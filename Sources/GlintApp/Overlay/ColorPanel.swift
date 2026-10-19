import AppKit
import GlintCore

/// The macOS colour panel, raised above the overlay (FR-37). System panels normally open at a
/// level far below the screen-saver-level overlay, where they would be hidden.
@MainActor
final class ColorPanel: NSObject {
    private var onChange: ((RGBAColor) -> Void)?

    /// Opens the panel showing `color`, next to `anchor` (a rect in global screen coordinates),
    /// and reports every change as the user drags. The panel takes keyboard focus only when one
    /// of its text fields is clicked, so Esc and the ⌘ shortcuts keep working in the overlay.
    func show(_ color: RGBAColor, near anchor: CGRect, onChange: @escaping (RGBAColor) -> Void) {
        let panel = NSColorPanel.shared
        self.onChange = nil                      // setting the colour below must not echo back
        panel.showsAlpha = false
        panel.isContinuous = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.color = NSColor(cgColor: color.cgColor) ?? .red
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) {
            panel.setFrameOrigin(Self.origin(for: panel.frame.size, beside: anchor, in: screen.visibleFrame))
        }
        self.onChange = onChange
        panel.orderFrontRegardless()
    }

    /// Right of `anchor`, else left of it, top-aligned with it, and kept inside `visible` (global,
    /// bottom-left coordinates).
    private static func origin(for size: CGSize, beside anchor: CGRect, in visible: CGRect) -> CGPoint {
        let gap: CGFloat = 8
        let right = anchor.maxX + gap, left = anchor.minX - gap - size.width
        let x = right + size.width <= visible.maxX ? right : left >= visible.minX ? left : visible.maxX - size.width
        return CGPoint(x: min(max(x, visible.minX), visible.maxX - size.width),
                       y: min(max(anchor.maxY - size.height, visible.minY), visible.maxY - size.height))
    }

    /// Closes the panel and stops reporting changes (FR-27: cancelling closes the colour panel).
    func close() {
        onChange = nil
        guard NSColorPanel.sharedColorPanelExists else { return }
        let panel = NSColorPanel.shared
        panel.setTarget(nil)
        panel.setAction(nil)
        panel.orderOut(nil)
    }

    /// Colours with no RGB equivalent (an image pattern) are ignored.
    @objc private func colorChanged(_ sender: NSColorPanel) {
        guard let color = RGBAColor(sender.color.cgColor) else { return }
        onChange?(color.withAlpha(1))
    }
}
