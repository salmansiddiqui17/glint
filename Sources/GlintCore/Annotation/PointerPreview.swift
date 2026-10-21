import CoreGraphics

/// What follows the pointer while a drawing tool is active, in display-local points with a
/// top-left origin, so the size of what a drag will make shows before dragging.
public enum PointerPreview: Equatable, Sendable {
    /// The brush (FR-38): a circle as wide as the stroke, inscribed in this square.
    case brush(CGRect)
    /// The Redact band (FR-36, OQ-20): a thin bar as tall as the band a sweep makes.
    case band(CGRect)

    /// The Redact bar's width in points.
    public static let bandBarWidth: CGFloat = 2

    /// The preview for `tool` at `point`, or nil for none.
    /// - Parameters:
    ///   - drafting: a drag is drawing a shape. The brush stays on, even over a toolbar; the
    ///     Redact bar hides, because the dashed draft outline shows the redaction instead.
    ///   - overToolbars: the pointer is over the toolbar or the tools palette.
    public init?(tool: Tool?, at point: CGPoint, strokeWidth: CGFloat, drafting: Bool, overToolbars: Bool) {
        if tool?.showsBrushPreview == true, drafting || !overToolbars {
            self = .brush(CGRect(x: point.x - strokeWidth / 2, y: point.y - strokeWidth / 2,
                                 width: strokeWidth, height: strokeWidth))
        } else if tool == .redact, !drafting, !overToolbars {
            let height = DrawingLimits.redactionBandFactor * strokeWidth
            self = .band(CGRect(x: point.x - Self.bandBarWidth / 2, y: point.y - height / 2,
                                width: Self.bandBarWidth, height: height))
        } else {
            return nil
        }
    }
}
