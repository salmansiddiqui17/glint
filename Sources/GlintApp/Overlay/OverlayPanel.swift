import AppKit

/// Borderless full-display window for one display (FR-17): above the menu bar, Dock and
/// full-screen apps, on every Space.
final class OverlayPanel: NSPanel {
    /// - Parameter frame: the display's frame in global points, as snapshotted at capture time.
    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        // No acceptsMouseMovedEvents: the overlay view's tracking area already delivers mouse
        // moves, and both together delivered each one twice.
        animationBehavior = .none
        setFrame(frame, display: false)
    }

    override var canBecomeKey: Bool { true }
}
