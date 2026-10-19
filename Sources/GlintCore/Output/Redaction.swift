import CoreGraphics
import CoreImage

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

    /// `image` obscured over its whole area, at the same pixel size and in the same colour space.
    ///
    /// Edges are extended before filtering, so every output pixel is opaque and comes only from
    /// the filter: nothing of the original shows through. Pixelate blocks start at the image's
    /// top-left corner and each block is one flat colour, so the original cannot be recovered.
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
        return context.createCGImage(output, from: extent, format: deep ? .RGBAh : .RGBA8, colorSpace: space,
                                     deferred: false)
    }
}
