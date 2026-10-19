import CoreGraphics

/// Converts between GlintCore's top-left-origin points and AppKit's bottom-left-origin view and
/// layer coordinates, for a space `height` points tall.
///
/// The flip is its own inverse, so the same call converts in either direction.
public struct FlippedCoordinates: Equatable, Sendable {
    public let height: CGFloat

    public init(height: CGFloat) {
        self.height = height
    }

    public func point(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: height - point.y)
    }

    /// The flipped rect, standardized (non-negative width and height).
    public func rect(_ rect: CGRect) -> CGRect {
        let rect = rect.standardized
        return CGRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
    }
}
