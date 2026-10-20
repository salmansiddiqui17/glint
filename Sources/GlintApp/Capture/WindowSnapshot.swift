import AppKit
import GlintCore

/// Other apps' windows at the moment a capture was triggered, for window snapping (FR-16). It is
/// taken before the screen is captured, so a window that moves afterwards still snaps where the
/// frozen image shows it.
struct WindowSnapshot {
    /// Snappable window frames, front to back, in global display coordinates (top-left origin).
    let frames: [CGRect]
    /// The main display's height, to convert AppKit display frames into the same coordinates.
    let mainDisplayHeight: CGFloat

    @MainActor
    static func current() -> WindowSnapshot {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        return WindowSnapshot(
            frames: WindowList.snapFrames(in: info, excludingProcess: Int(ProcessInfo.processInfo.processIdentifier)),
            mainDisplayHeight: NSScreen.screens.first?.frame.height ?? 0)
    }

    /// The snap targets on the display whose AppKit frame is `display`.
    func targets(for display: CGRect) -> SnapTargets {
        SnapTargets(windows: frames,
                    display: SnapTargets.globalFrame(ofDisplay: display, mainDisplayHeight: mainDisplayHeight))
    }
}
