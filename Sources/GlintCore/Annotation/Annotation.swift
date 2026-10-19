import CoreGraphics

/// The drawing tools in the tools palette, top to bottom (FR-28).
public enum Tool: String, CaseIterable, Sendable {
    case pencil, line, arrow, ellipse, rectangle, marker, text, redact

    /// Whether the pointer shows the brush preview circle (FR-38): every tool that strokes a path.
    public var showsBrushPreview: Bool {
        switch self {
        case .pencil, .line, .arrow, .ellipse, .rectangle, .marker: true
        case .text, .redact: false
        }
    }
}

/// How a redaction obscures what is beneath it (FR-36, FR-47).
public enum RedactionStyle: String, CaseIterable, Sendable {
    case pixelate, blur

    public var displayName: String {
        switch self {
        case .pixelate: "Pixelate"
        case .blur: "Blur"
        }
    }
}

/// A committed text box (FR-35). `origin` is the top-left of the first line's line box.
public struct TextAnnotation: Equatable, Sendable {
    public var origin: CGPoint
    public var string: String
    public var fontSize: CGFloat
    public var color: RGBAColor

    public init(origin: CGPoint, string: String, fontSize: CGFloat, color: RGBAColor) {
        self.origin = origin
        self.string = string
        self.fontSize = fontSize
        self.color = color
    }
}

/// One annotation, kept as an object rather than pixels (FR-40), in display-local points with a
/// top-left origin, so it stays put when the selection moves.
public enum Annotation: Equatable, Sendable {
    case pencil(points: [CGPoint], color: RGBAColor, width: CGFloat)
    case marker(points: [CGPoint], color: RGBAColor, width: CGFloat)
    case line(from: CGPoint, to: CGPoint, color: RGBAColor, width: CGFloat)
    case arrow(from: CGPoint, to: CGPoint, color: RGBAColor, width: CGFloat)
    case ellipse(CGRect, color: RGBAColor, width: CGFloat)
    case rectangle(CGRect, color: RGBAColor, width: CGFloat)
    case text(TextAnnotation)
    /// `width` is the stroke width when it was drawn, which sets the effect's strength.
    case redaction(CGRect, style: RedactionStyle, width: CGFloat)
}

/// The current colour, widths and redaction style, shared by every display (FR-37, FR-38).
/// The widths are always whole points within `DrawingLimits`, however they are set.
public struct DrawingStyle: Equatable, Sendable {
    public var color: RGBAColor
    public var strokeWidth: CGFloat {
        didSet { strokeWidth = DrawingLimits.strokeWidth(strokeWidth, steppedBy: 0) }
    }
    public var fontSize: CGFloat {
        didSet { fontSize = DrawingLimits.fontSize(fontSize, steppedBy: 0) }
    }
    public var redactionStyle: RedactionStyle

    public init(color: RGBAColor = .red, strokeWidth: CGFloat = DrawingLimits.defaultStrokeWidth,
                fontSize: CGFloat = DrawingLimits.defaultFontSize, redactionStyle: RedactionStyle = .pixelate) {
        self.color = color
        self.strokeWidth = DrawingLimits.strokeWidth(strokeWidth, steppedBy: 0)
        self.fontSize = DrawingLimits.fontSize(fontSize, steppedBy: 0)
        self.redactionStyle = redactionStyle
    }
}

/// Ranges, defaults and steps for stroke width (FR-38) and text size (FR-35).
public enum DrawingLimits {
    public static let strokeWidths: ClosedRange<CGFloat> = 3...50
    public static let defaultStrokeWidth: CGFloat = 3
    public static let fontSizes: ClosedRange<CGFloat> = 10...250
    public static let defaultFontSize: CGFloat = 24
    /// The marker's opacity (FR-34).
    public static let markerOpacity: CGFloat = 0.3

    /// `width` rounded to a whole point, moved by `steps` and kept in range; a non-finite width
    /// becomes the default. With zero steps this just tidies a stored or computed value.
    public static func strokeWidth(_ width: CGFloat, steppedBy steps: Int) -> CGFloat {
        clamp(width, steps, strokeWidths, fallback: defaultStrokeWidth)
    }

    /// `size` rounded to a whole point, moved by `steps` and kept in range; a non-finite size
    /// becomes the default.
    public static func fontSize(_ size: CGFloat, steppedBy steps: Int) -> CGFloat {
        clamp(size, steps, fontSizes, fallback: defaultFontSize)
    }

    private static func clamp(_ value: CGFloat, _ steps: Int, _ range: ClosedRange<CGFloat>,
                              fallback: CGFloat) -> CGFloat {
        let base = value.isFinite ? value.rounded() : fallback
        return min(max(base + CGFloat(steps), range.lowerBound), range.upperBound)
    }
}
