import GlintCore

/// The tool and drawing style shared by every display during one capture (FR-28, FR-37, FR-38).
///
/// The tool starts unselected with each capture. Colour, stroke width and text size are saved as
/// they change, so they carry over to the next capture and launch.
@MainActor
final class DrawingState {
    private let settings: AppSettings
    /// Called after any change, so every display can redraw its palette and preview.
    var onChange: (() -> Void)?

    var tool: Tool? {
        didSet { if tool != oldValue { onChange?() } }
    }

    var style: DrawingStyle {
        didSet {
            guard style != oldValue else { return }
            settings.drawingStyle = style
            onChange?()
        }
    }

    init(settings: AppSettings) {
        self.settings = settings
        style = settings.drawingStyle
    }
}
