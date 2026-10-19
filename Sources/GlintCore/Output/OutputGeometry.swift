import CoreGraphics

/// A size in whole pixels.
public struct PixelSize: Equatable, Hashable, Sendable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

/// Converts a selection in points into source-image pixels and output size (FR-25, FR-42, FR-45).
///
/// The badge and the exporter both go through these functions with the frozen image's size, so the
/// numbers on the badge are always the exported image's pixel size (FR-42 AC).
public enum OutputGeometry {
    /// The selection in the frozen image's pixel space (top-left origin). Each edge is rounded to a
    /// whole pixel on its own, then clipped to the image, so adjacent selections share pixel edges.
    public static func pixelRect(for selection: CGRect, scale: CGFloat, imageSize: PixelSize) -> CGRect {
        precondition(scale > 0, "backing scale must be positive")
        func edge(_ value: CGFloat, limit: Int) -> CGFloat {
            min(max((value * scale).rounded(), 0), CGFloat(limit))
        }
        let minX = edge(selection.minX, limit: imageSize.width), maxX = edge(selection.maxX, limit: imageSize.width)
        let minY = edge(selection.minY, limit: imageSize.height), maxY = edge(selection.maxY, limit: imageSize.height)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Pixel size of the exported image: the native pixel rect, or with `standardResolution` that
    /// size divided by the scale and rounded. Can be zero for a degenerate selection; callers treat
    /// zero as "nothing to export".
    public static func outputPixelSize(for selection: CGRect, scale: CGFloat, imageSize: PixelSize,
                                       standardResolution: Bool) -> PixelSize {
        let pixels = pixelRect(for: selection, scale: scale, imageSize: imageSize)
        guard standardResolution, scale > 1 else {
            return PixelSize(width: Int(pixels.width), height: Int(pixels.height))
        }
        return PixelSize(width: Int((pixels.width / scale).rounded()), height: Int((pixels.height / scale).rounded()))
    }

    /// Text for the size badge, e.g. "600 × 400".
    public static func badgeText(_ size: PixelSize) -> String {
        "\(size.width) × \(size.height)"
    }

    /// Resolution metadata for an exported image: 72 dpi per point, so a native Retina image opens at
    /// its on-screen size (72 × scale); 72 dpi when the output is already 1×.
    public static func dpi(scale: CGFloat, standardResolution: Bool) -> CGFloat {
        standardResolution ? 72 : 72 * scale
    }
}
