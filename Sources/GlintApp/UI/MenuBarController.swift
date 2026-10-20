import AppKit
import KeyboardShortcuts

/// The status-bar item and its menu (FR-1, FR-2). Left and right click both open the menu.
@MainActor
final class MenuBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let onCapture: () -> Void
    private let onPreferences: () -> Void
    private let onAbout: () -> Void

    init(onCapture: @escaping () -> Void, onPreferences: @escaping () -> Void, onAbout: @escaping () -> Void) {
        self.onCapture = onCapture
        self.onPreferences = onPreferences
        self.onAbout = onAbout
        super.init()
        let image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Glint")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.autosaveName = "Glint"   // keeps its place if the user ⌘-drags it

        let menu = NSMenu()
        let take = NSMenuItem(title: String(localized: "Take Screenshot"), action: #selector(takeScreenshot),
                              keyEquivalent: "")
        take.setShortcut(for: .captureScreenshot)   // shows the live hotkey; blank when disabled
        menu.addItem(take)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: String(localized: "Preferences…"), action: #selector(preferences),
                                keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: String(localized: "About Glint"), action: #selector(about), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: String(localized: "Quit Glint"), action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
    }

    @objc private func takeScreenshot() {
        // Runs after the menu has closed; the menu belongs to Glint, so capture excludes it anyway.
        DispatchQueue.main.async { self.onCapture() }
    }

    @objc private func preferences() { onPreferences() }

    @objc private func about() { onAbout() }

    @objc private func quit() { NSApp.terminate(nil) }
}
