import CoreGraphics
import CoreImage
import Foundation

/// Pixelate and blur for the Redact tool (FR-36).
public enum Redaction {
    /// Core Image contexts are thread-safe and costly to create, so one is shared.
    private static let context = CIContext(options: [.cacheIntermediates: false])

    /// Frees the memory Core Image keeps between renders. Called when a capture ends, so it goes
    /// with the frozen images (NFR-6).
    public static func releaseCaches() {
        context.clearCaches()
    }

    /// The least share of a redaction's shorter side that one block or the blur radius spans.
    /// Measured with Vision on the export (OQ-19): at 0.1 pixelate still let "hunt" be read from
    /// 96 pt text at 2×, and at 0.15 it was garbled; at 0.2 neither style left anything. Blur
    /// alone was safe at 0.1, but one factor keeps the two styles equally strong.
    static let sizeFactor: CGFloat = 0.2

    /// Mosaic block size or blur radius, in whole pixels, for a redaction drawn with stroke width
    /// w over `frame` (display points, as `Renderer.patchFrame` gives it) at `scale` pixels per
    /// point: max(8, 4·w, k·s), where s is the frame's shorter side in pixels and k is
    /// `sizeFactor` (FR-36, OQ-19).
    /// Large text stays legible through a fixed strength, so larger redactions are obscured more
    /// strongly. One over a line of UI text (up to 40 px tall) keeps max(8, 4·w). Measured at the
    /// capture's own scale, so 1× and Retina hide the same share of the content, and the 1×
    /// export reuses the overlay's patch.
    public static func strength(strokeWidth: CGFloat, frame: CGRect, scale: CGFloat) -> CGFloat {
        let shorterSide = (min(frame.width, frame.height) * scale).rounded()
        return CGFloat(blockSize(strength: max(8, 4 * strokeWidth, sizeFactor * shorterSide)))
    }

    /// A pixelate block's side in whole pixels, for `strength`. The patch is made and drawn with
    /// this one number, so a fractional strength can't draw the patch short of its frame and leave
    /// an unredacted strip along the right and bottom edges (FR-36).
    static func blockSize(strength: CGFloat) -> Int {
        Int(strength.rounded())
    }

    /// `image` obscured over its whole area, in the same colour space.
    ///
    /// Edges are extended before filtering, so every output pixel is opaque and comes only from
    /// the filter: nothing of the original shows through.
    /// - Blur returns an image of the same pixel size.
    /// - Pixelate returns **one pixel per block** (NFR-6) of `blockSize(strength:)` pixels:
    ///   `ceil(width / block)` × `ceil(height / block)` pixels. Blocks start at the image's
    ///   top-left corner, so the last column and row may be partial; `blockRect` says where the image goes when drawn. Each
    ///   block is one flat colour, so the original cannot be recovered.
    public static func obscure(_ image: CGImage, style: RedactionStyle, strength: CGFloat) -> CGImage? {
        let input = CIImage(cgImage: image)
        let extent = input.extent
        let block = blockSize(strength: strength)
        let filtered: CIImage? = switch style {
        case .pixelate:
            CIFilter(name: "CIPixellate", parameters: [
                kCIInputImageKey: input.clampedToExtent(),
                kCIInputScaleKey: block,
                kCIInputCenterKey: CIVector(x: extent.minX, y: extent.maxY),   // grid from the top-left corner
            ])?.outputImage
        case .blur:
            CIFilter(name: "CIGaussianBlur", parameters: [
                kCIInputImageKey: input.clampedToExtent(),
                kCIInputRadiusKey: strength,
            ])?.outputImage
        }
        guard let output = filtered?.cropped(to: extent) else { return nil }
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let deep = image.bitsPerComponent > 8 || CGColorSpaceUsesExtendedRange(space)
        // Rendered now, not deferred: a deferred image re-runs the filter every time it is drawn
        // (and keeps the unredacted source alive to do so).
        guard let obscured = context.createCGImage(output, from: extent, format: deep ? .RGBAh : .RGBA8,
                                                   colorSpace: space, deferred: false) else { return nil }
        return style == .pixelate ? onePixelPerBlock(obscured, block: block) : obscured
    }

    /// A flat, opaque grey in place of `image`, whatever the style: what text recognition sees
    /// of a redaction, so nothing under it can be read (FR-46). Like pixelate it has one pixel
    /// per block (NFR-6) and is drawn at `blockRect`, so it covers the whole frame.
    static func solid(_ image: CGImage, style: RedactionStyle, strength: CGFloat) -> CGImage? {
        let block = blockSize(strength: strength)
        guard block > 1, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: (image.width + block - 1) / block,
                                      height: (image.height + block - 1) / block, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.setFillColor(gray: 0.5, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: context.width, height: context.height))
        return context.makeImage()
    }

    /// The top-left pixel of each `block` × `block` block of `image`, which for a pixellated
    /// image is that block's colour: 1/block² of the memory (NFR-6). Exact, byte for byte.
    /// Nil (fail closed) for pixels that aren't a whole number of bytes, which it can't copy.
    static func onePixelPerBlock(_ image: CGImage, block: Int) -> CGImage? {
        let bytesPerPixel = image.bitsPerPixel / 8
        guard block > 1, image.bitsPerPixel % 8 == 0, let space = image.colorSpace,
              let data = image.dataProvider?.data, let source = CFDataGetBytePtr(data) else { return nil }
        let columns = (image.width + block - 1) / block, rows = (image.height + block - 1) / block
        var blocks = Data(count: columns * rows * bytesPerPixel)
        blocks.withUnsafeMutableBytes { target in
            for row in 0..<rows {
                for column in 0..<columns {
                    let from = source + row * block * image.bytesPerRow + column * block * bytesPerPixel
                    let to = target.baseAddress! + (row * columns + column) * bytesPerPixel
                    to.copyMemory(from: from, byteCount: bytesPerPixel)
                }
            }
        }
        guard let provider = CGDataProvider(data: blocks as CFData) else { return nil }
        return CGImage(width: columns, height: rows, bitsPerComponent: image.bitsPerComponent,
                       bitsPerPixel: image.bitsPerPixel, bytesPerRow: columns * bytesPerPixel, space: space,
                       bitmapInfo: image.bitmapInfo, provider: provider, decode: nil, shouldInterpolate: false,
                       intent: image.renderingIntent)
    }

    /// Where a redaction's patch is drawn, in display points, for a patch whose area is `frame`.
    /// A patch with one pixel per block (pixelate) covers whole blocks of `blockSize(strength:)`
    /// pixels from the frame's top-left corner, so it can reach past the frame's right and bottom
    /// edges; draw it there without smoothing, clipped to `frame`. A full-size patch (blur) is
    /// drawn at `frame`.
    public static func blockRect(for patch: CGImage, frame: CGRect, scale: CGFloat, strength: CGFloat) -> CGRect {
        let fullSize = patch.width == Int((frame.width * scale).rounded())
            && patch.height == Int((frame.height * scale).rounded())
        guard !fullSize else { return frame }
        let block = CGFloat(blockSize(strength: strength))
        return CGRect(x: frame.minX, y: frame.minY, width: CGFloat(patch.width) * block / scale,
                      height: CGFloat(patch.height) * block / scale)
    }
}
