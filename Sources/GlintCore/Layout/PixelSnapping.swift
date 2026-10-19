import CoreGraphics

/// Rounds geometry to device pixels so 1 pt lines and text stay crisp at fractional positions.
///
/// Works in display-local points with a top-left origin, rounding each edge the same way
/// `OutputGeometry.pixelRect` does, so the drawn selection and the exported crop always agree.
public enum PixelSnapping {
    /// `rect` with each edge rounded to the nearest device pixel.
    public static func aligned(_ rect: CGRect, scale: CGFloat) -> CGRect {
        func snap(_ value: CGFloat) -> CGFloat { (value * scale).rounded() / scale }
        let minX = snap(rect.minX), minY = snap(rect.minY)
        return CGRect(x: minX, y: minY, width: snap(rect.maxX) - minX, height: snap(rect.maxY) - minY)
    }

    /// The four bands of `bounds` around `hole` (above, below, left, right), for a veil drawn as
    /// plain rectangles. Without a hole, the first band is the whole of `bounds`.
    public static func veilBands(around hole: CGRect?, in bounds: CGRect) -> [CGRect] {
        guard let hole = hole?.intersection(bounds), !hole.isNull else {
            return [bounds, .zero, .zero, .zero]
        }
        return [
            CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: hole.minY - bounds.minY),
            CGRect(x: bounds.minX, y: hole.maxY, width: bounds.width, height: bounds.maxY - hole.maxY),
            CGRect(x: bounds.minX, y: hole.minY, width: hole.minX - bounds.minX, height: hole.height),
            CGRect(x: hole.maxX, y: hole.minY, width: bounds.maxX - hole.maxX, height: hole.height),
        ]
    }
}
