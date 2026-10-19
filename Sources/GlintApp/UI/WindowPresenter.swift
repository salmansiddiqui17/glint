import AppKit
import SwiftUI

/// Shows one SwiftUI window per identifier, front and focused (FR-1 AC3). Closed windows are
/// dropped, so their views (and any permission polling) end and the next show starts fresh
/// (NFR-5, NFR-7).
@MainActor
final class WindowPresenter: NSObject, NSWindowDelegate {
    private var windows: [String: NSWindow] = [:]

    func show(_ id: String, title: String, @ViewBuilder content: () -> some View) {
        if let window = windows[id] { return bringToFront(window) }
        let controller = NSHostingController(rootView: content())
        let window = NSWindow(contentViewController: controller)
        window.title = title
        window.styleMask = [.titled, .closable]
        // A grouped Form scrolls, so it reports no height of its own and the window would open as
        // a bare title bar; size the window to fit the content instead.
        window.setContentSize(controller.view.fittingSize)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        windows[id] = window
        bringToFront(window)
    }

    func close(_ id: String) {
        windows[id]?.close()
    }

    private func bringToFront(_ window: NSWindow) {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()   // visible even if macOS declines the activation (hotkey path)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let id = windows.first(where: { $0.value === window })?.key else { return }
        windows[id] = nil
        // Tear the SwiftUI view down now rather than whenever AppKit frees the window.
        Task { window.contentViewController = nil }
    }
}
