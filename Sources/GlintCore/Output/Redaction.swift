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

    /// Mosaic block size or blur radius, in pixels: max(8, 4·w) for stroke width w.
    public static func strength(strokeWidth: CGFloat) -> CGFloat {
        max(8, 4 * strokeWidth)
    }

    /// `image` obscured over its whole area, in the same colour space.
    ///
    /// Edges are extended before filtering, so every output pixel is opaque and comes only from
    /// the filter: nothing of the original shows through.
    /// - Blur returns an image of the same pixel size.
    /// - Pixelate returns **one pixel per block** (NFR-6): `ceil(width / strength)` ×
    ///   `ceil(height / strength)` pixels. Blocks start at the image's top-left corner, so the last
    ///   column and row may be partial; `blockRect` says where the image goes when drawn. Each
    ///   block is one flat colour, so the original cannot be recovered.
    public static func obscure(_ image: CGImage, style: RedactionStyle, strength: CGFloat) -> CGImage? {
        let input = CIImage(cgImage: image)
        let extent = input.extent
        let filtered: CIImage? = switch style {
        case .pixelate:
            CIFilter(name: "CIPixellate", parameters: [
                kCIInputImageKey: input.clampedToExtent(),
                kCIInputScaleKey: strength,
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
        return style == .pixelate ? onePixelPerBlock(obscured, block: Int(strength.rounded())) : obscured
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
    /// A patch with one pixel per block (pixelate) covers whole blocks of `strength` pixels from
    /// the frame's top-left corner, so it can reach past the frame's right and bottom edges; draw
    /// it there without smoothing, clipped to `frame`. A full-size patch (blur) is drawn at `frame`.
    public static func blockRect(for patch: CGImage, frame: CGRect, scale: CGFloat, strength: CGFloat) -> CGRect {
        let fullSize = patch.width == Int((frame.width * scale).rounded())
            && patch.height == Int((frame.height * scale).rounded())
        guard !fullSize else { return frame }
        return CGRect(x: frame.minX, y: frame.minY, width: CGFloat(patch.width) * strength / scale,
                      height: CGFloat(patch.height) * strength / scale)
    }
}
