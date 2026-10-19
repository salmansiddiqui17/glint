/// What Esc does in the overlay (FR-27, OQ-9): one stage per press.
public enum EscapeAction: Equatable, Sendable {
    /// While editing text: commit it and keep the Text tool.
    case commitText
    /// While a tool is active: leave the tool and keep the selection.
    case deselectTool
    /// Otherwise: cancel the capture.
    case cancelCapture

    public static func resolve(isEditingText: Bool, isToolActive: Bool) -> EscapeAction {
        if isEditingText { return .commitText }
        if isToolActive { return .deselectTool }
        return .cancelCapture
    }
}
