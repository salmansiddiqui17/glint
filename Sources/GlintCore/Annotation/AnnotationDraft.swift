import CoreGraphics

/// An annotation being drawn by a drag (FR-29 to FR-34, FR-36), with the ⇧ constraint (FR-56).
///
/// Points are display-local, top-left origin; the caller clamps them to the display.
public struct AnnotationDraft: Equatable, Sendable {
    public let tool: Tool
    public let start: CGPoint
    private let style: DrawingStyle
    private let bounds: CGRect
    private let scale: CGFloat
    /// The pencil and marker path: pointer positions at least one device pixel apart, so a long
    /// stroke doesn't pile up points the display can't show.
    private var points: [CGPoint]
    private var current: CGPoint
    private var constrained = false

    /// - Parameters:
    ///   - tool: any tool except `.text`, which places a text box instead.
    ///   - bounds: the display; constrained shapes and redactions are kept inside it.
    ///   - scale: device pixels per point; redactions are snapped to whole pixels.
    public init(tool: Tool, start: CGPoint, style: DrawingStyle, bounds: CGRect, scale: CGFloat) {
        precondition(tool != .text, "the text tool places a text box, not a draft")
        precondition(scale > 0, "backing scale must be positive")
        self.tool = tool
        self.start = start
        self.style = style
        self.bounds = bounds
        self.scale = scale
        points = [start]
        current = start
    }

    /// The pointer moved. `constrained` is whether ⇧ is held.
    public mutating func drag(to point: CGPoint, constrained: Bool) {
        if let last = points.last, hypot(point.x - last.x, point.y - last.y) >= 1 / scale { points.append(point) }
        current = point
        self.constrained = constrained
    }

    /// ⇧ was pressed or released without the pointer moving: the shape updates live (FR-56).
    public mutating func setConstrained(_ constrained: Bool) {
        self.constrained = constrained
    }

    /// The annotation as drawn so far, or nil while the drag is too small to draw anything. A
    /// drag that ends with nil adds nothing and no undo step. A pencil or marker click is a dot.
    public var annotation: Annotation? {
        switch tool {
        case .pencil:
            return .pencil(points: stroke, color: style.color, width: style.strokeWidth)
        case .marker:
            return .marker(points: stroke, color: style.color, width: style.strokeWidth)
        case .line, .arrow:
            let end = constrained ? onDisplay(ShapeConstraint.angleSnapped(from: start, to: current)) : current
            guard hypot(end.x - start.x, end.y - start.y) >= 1 else { return nil }
            return tool == .line
                ? .line(from: start, to: end, color: style.color, width: style.strokeWidth)
                : .arrow(from: start, to: end, color: style.color, width: style.strokeWidth)
        case .ellipse, .rectangle:
            guard let rect = box() else { return nil }
            return tool == .ellipse
                ? .ellipse(rect, color: style.color, width: style.strokeWidth)
                : .rectangle(rect, color: style.color, width: style.strokeWidth)
        case .redact:
            // Whole pixels, so the live preview and the export obscure exactly the same pixels.
            guard let rect = (constrained ? box() : band())?.intersection(bounds), !rect.isNull else { return nil }
            let snapped = constrained ? squareOnPixels(rect) : PixelSnapping.aligned(rect, scale: scale)
            guard (snapped.width * scale).rounded() >= 1, (snapped.height * scale).rounded() >= 1 else { return nil }
            return .redaction(snapped, style: style.redactionStyle, width: style.strokeWidth)
        case .text:
            return nil
        }
    }

    /// The kept points, ending exactly at the pointer.
    private var stroke: [CGPoint] {
        current == points.last ? points : points + [current]
    }

    /// The dragged box (square when constrained), or nil when it is under 1 pt in either direction.
    private func box() -> CGRect? {
        let end = constrained ? squaredEnd() : current
        let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                          width: abs(end.x - start.x), height: abs(end.y - start.y))
        return rect.width >= 1 && rect.height >= 1 ? rect : nil
    }

    /// The dragged redaction box, at least a band of `redactionBandFactor` stroke widths thick
    /// across the drag, so a sweep along a line of text covers it (FR-36, OQ-20). The band is
    /// centred on the drag and shifted back onto the display rather than cut, unless the display
    /// is smaller. Nil while the drag is within the drag threshold, so a click or a jiggle adds
    /// nothing.
    private func band() -> CGRect? {
        let width = abs(current.x - start.x), height = abs(current.y - start.y)
        guard max(width, height) > SelectionEditor.dragThreshold else { return nil }
        let thickness = DrawingLimits.redactionBandFactor * style.strokeWidth
        func across(_ low: CGFloat, _ high: CGFloat, _ minimum: CGFloat, _ maximum: CGFloat) -> CGFloat {
            max(min((low + high - thickness) / 2, maximum - thickness), minimum)
        }
        var rect = CGRect(x: min(start.x, current.x), y: min(start.y, current.y), width: width, height: height)
        if width >= height, height < thickness {
            rect.origin.y = across(start.y, current.y, bounds.minY, bounds.maxY)
            rect.size.height = thickness
        } else if height > width, width < thickness {
            rect.origin.x = across(start.x, current.x, bounds.minX, bounds.maxX)
            rect.size.width = thickness
        }
        return rect
    }

    /// The far corner of the ⇧ square. A drag straight along one axis gives no direction on the
    /// other, so the square opens towards the side with more room; at the right or bottom edge it
    /// would otherwise have none.
    private func squaredEnd() -> CGPoint {
        var end = ShapeConstraint.squared(from: start, to: current)
        if current.x == start.x, bounds.maxX - start.x < start.x - bounds.minX { end.x = 2 * start.x - end.x }
        if current.y == start.y, bounds.maxY - start.y < start.y - bounds.minY { end.y = 2 * start.y - end.y }
        return onDisplay(end)
    }

    /// A constrained end pulled back towards `start` along the same direction until it is on the
    /// display. The pointer is clamped, but turning it to 45° or squaring the box can reach past
    /// the edge; shortening keeps the angle and the square.
    private func onDisplay(_ end: CGPoint) -> CGPoint {
        let dx = end.x - start.x, dy = end.y - start.y
        var fraction: CGFloat = 1
        if dx > 0 { fraction = min(fraction, (bounds.maxX - start.x) / dx) }
        if dx < 0 { fraction = min(fraction, (bounds.minX - start.x) / dx) }
        if dy > 0 { fraction = min(fraction, (bounds.maxY - start.y) / dy) }
        if dy < 0 { fraction = min(fraction, (bounds.minY - start.y) / dy) }
        fraction = max(fraction, 0)
        return CGPoint(x: start.x + dx * fraction, y: start.y + dy * fraction)
    }

    /// A square in points snapped to whole pixels as a square: the corner and the side are
    /// rounded, then the side is kept on the display (whose edges are whole pixels).
    private func squareOnPixels(_ square: CGRect) -> CGRect {
        func snap(_ value: CGFloat) -> CGFloat { (value * scale).rounded() / scale }
        let x = snap(square.minX), y = snap(square.minY)
        let side = min(snap(square.width), bounds.maxX - x, bounds.maxY - y)
        return CGRect(x: x, y: y, width: side, height: side)
    }
}
