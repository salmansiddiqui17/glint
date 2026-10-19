import CoreGraphics

/// How a vector annotation is painted: a stroked path, a filled path, or both (the arrow).
///
/// The live overlay (Core Animation shape layers) and the export renderer (Core Graphics) paint
/// the same shape, so what is drawn is what is exported.
/// `@unchecked Sendable` because `CGPath` isn't marked Sendable: the paths are built by
/// `AnnotationGeometry.shape(for:)` and never changed afterwards.
public struct VectorShape: @unchecked Sendable {
    public let stroke: CGPath?
    public let fill: CGPath?
    public let lineWidth: CGFloat
    public let lineCap: CGLineCap
    public let lineJoin: CGLineJoin
    public let color: RGBAColor
}

/// The arrow's parts (FR-31): a shaft and a filled triangular head at `tip`.
public struct ArrowGeometry: Equatable, Sendable {
    /// Head corners: the tip, then the two back corners.
    public let head: [CGPoint]
    /// The shaft, or nil when the arrow is shorter than its head.
    public let shaft: Segment?

    public struct Segment: Equatable, Sendable {
        public let start: CGPoint
        public let end: CGPoint
    }

    /// Head length 4·w + 15 pt.
    public static func headLength(width: CGFloat) -> CGFloat { 4 * width + 15 }
    /// The shaft stops 3·w + 15 pt short of the tip, inside the head.
    public static func shaftInset(width: CGFloat) -> CGFloat { 3 * width + 15 }
    /// Half the head's angle: 11.25°, so 22.5° in total.
    public static let halfAngle: CGFloat = .pi / 16

    /// Nil when `from` and `to` coincide (no direction).
    public init?(from: CGPoint, to tip: CGPoint, width: CGFloat) {
        let dx = tip.x - from.x, dy = tip.y - from.y
        let length = hypot(dx, dy)
        guard length > 0 else { return nil }
        let unit = CGPoint(x: dx / length, y: dy / length)
        let normal = CGPoint(x: -unit.y, y: unit.x)
        let headLength = Self.headLength(width: width)
        let halfBase = headLength * tan(Self.halfAngle)
        let base = CGPoint(x: tip.x - unit.x * headLength, y: tip.y - unit.y * headLength)
        head = [tip,
                CGPoint(x: base.x + normal.x * halfBase, y: base.y + normal.y * halfBase),
                CGPoint(x: base.x - normal.x * halfBase, y: base.y - normal.y * halfBase)]
        let inset = Self.shaftInset(width: width)
        shaft = length < headLength
            ? nil
            : Segment(start: from, end: CGPoint(x: tip.x - unit.x * inset, y: tip.y - unit.y * inset))
    }
}

public enum AnnotationGeometry {
    /// The paint for a vector annotation (FR-29 to FR-34), or nil for text and redactions, which
    /// are drawn as images.
    public static func shape(for annotation: Annotation) -> VectorShape? {
        switch annotation {
        case let .pencil(points, color, width):
            return freehand(points, color: color, width: width)
        case let .marker(points, color, width):
            return freehand(points, color: color.withAlpha(color.alpha * DrawingLimits.markerOpacity), width: width)
        case let .line(from, to, color, width):
            let path = CGMutablePath()
            path.move(to: from)
            path.addLine(to: to)
            return VectorShape(stroke: path, fill: nil, lineWidth: width, lineCap: .round, lineJoin: .round, color: color)
        case let .arrow(from, to, color, width):
            guard let arrow = ArrowGeometry(from: from, to: to, width: width) else { return nil }
            let head = CGMutablePath()
            head.addLines(between: arrow.head)
            head.closeSubpath()
            var shaft: CGMutablePath?
            if let line = arrow.shaft {
                shaft = CGMutablePath()
                shaft?.move(to: line.start)
                shaft?.addLine(to: line.end)
            }
            return VectorShape(stroke: shaft, fill: head, lineWidth: width, lineCap: .round, lineJoin: .round,
                               color: color)
        case let .ellipse(rect, color, width):
            return VectorShape(stroke: CGPath(ellipseIn: rect, transform: nil), fill: nil, lineWidth: width,
                               lineCap: .round, lineJoin: .round, color: color)
        case let .rectangle(rect, color, width):
            return VectorShape(stroke: CGPath(rect: rect, transform: nil), fill: nil, lineWidth: width,
                               lineCap: .butt, lineJoin: .miter, color: color)
        case .text, .redaction:
            return nil
        }
    }

    /// Pencil and marker strokes (FR-29, FR-34): round caps and joins. A single point (a click)
    /// is a dot as wide as the stroke. One path per stroke, so a translucent marker does not
    /// darken where it crosses itself.
    private static func freehand(_ points: [CGPoint], color: RGBAColor, width: CGFloat) -> VectorShape? {
        guard let first = points.first else { return nil }
        if points.count == 1 {
            let dot = CGRect(x: first.x - width / 2, y: first.y - width / 2, width: width, height: width)
            return VectorShape(stroke: nil, fill: CGPath(ellipseIn: dot, transform: nil), lineWidth: width,
                               lineCap: .round, lineJoin: .round, color: color)
        }
        let path = CGMutablePath()
        path.addLines(between: points)
        return VectorShape(stroke: path, fill: nil, lineWidth: width, lineCap: .round, lineJoin: .round, color: color)
    }
}
