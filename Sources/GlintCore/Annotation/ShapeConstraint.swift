import CoreGraphics

/// ⇧-constrained drawing (FR-56).
public enum ShapeConstraint {
    private static let diagonal = (0.5 as CGFloat).squareRoot()
    /// The eight 45° directions in order of increasing `atan2(dy, dx)`, starting at +x: clockwise
    /// on screen, because y grows downward.
    private static let directions: [CGPoint] = [
        CGPoint(x: 1, y: 0), CGPoint(x: diagonal, y: diagonal), CGPoint(x: 0, y: 1),
        CGPoint(x: -diagonal, y: diagonal), CGPoint(x: -1, y: 0), CGPoint(x: -diagonal, y: -diagonal),
        CGPoint(x: 0, y: -1), CGPoint(x: diagonal, y: -diagonal),
    ]

    /// Lines and arrows: `end` turned to the nearest 45° step around `start`, keeping its distance.
    /// On a diagonal the x and y offsets are equal, to floating-point rounding.
    public static func angleSnapped(from start: CGPoint, to end: CGPoint) -> CGPoint {
        let dx = end.x - start.x, dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 0 else { return end }
        let step = Int((atan2(dy, dx) / (.pi / 4)).rounded())
        let direction = directions[(step % 8 + 8) % 8]
        return CGPoint(x: start.x + length * direction.x, y: start.y + length * direction.y)
    }

    /// Rectangles, ellipses and redactions: `end` moved so the box from `start` is square, using
    /// the larger of the two drag distances and keeping the drag's direction.
    public static func squared(from start: CGPoint, to end: CGPoint) -> CGPoint {
        let dx = end.x - start.x, dy = end.y - start.y
        let side = max(abs(dx), abs(dy))
        return CGPoint(x: start.x + (dx < 0 ? -side : side), y: start.y + (dy < 0 ? -side : side))
    }
}
