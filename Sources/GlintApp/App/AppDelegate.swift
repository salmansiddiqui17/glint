import AppKit
import GlintCore
import KeyboardShortcuts
import os

/// Wires the menu bar, hotkey, onboarding and capture together.
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings()
    private let windows = WindowPresenter()
    private var menuBar: MenuBarController?
    private var isSetUp = false
    private let logger = Logger(subsystem: GlintCore.bundleIdentifier, category: "app")
    private lazy var coordinator = CaptureCoordinator(
        settings: settings, exporter: Exporter(settings: settings),
        showOnboarding: { [weak self] in self?.showOnboarding() })

    public override init() { super.init() }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            // One instance only: wait out a relaunching predecessor, or hand over to a running copy.
            guard await SingleInstance.claim() else { return NSApp.terminate(nil) }
            setUp()
        }
    }

    private func setUp() {
        menuBar = MenuBarController(onCapture: { [weak self] in self?.coordinator.start() },
                                    onPreferences: { [weak self] in self?.showPreferences() },
                                    onAbout: { [weak self] in self?.showAbout() })
        KeyboardShortcuts.onKeyDown(for: .captureScreenshot) { [weak self] in
            self?.coordinator.start()
        }
        isSetUp = true
        if !settings.hasCompletedOnboarding {
            showOnboarding()
        }
    }

    /// Re-opening Glint while it runs starts a capture (FR-3).
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if isSetUp { coordinator.start() }
        return false
    }

    /// First run (FR-10), or a capture found Screen Recording off (FR-12).
    private func showOnboarding() {
        let isFirstRun = !settings.hasCompletedOnboarding
        windows.show("onboarding", title: isFirstRun ? "Welcome to Glint" : "Glint") {
            OnboardingView(isFirstRun: isFirstRun) { [weak self] launchAtLogin in
                guard let self else { return }
                if let launchAtLogin {
                    do {
                        try LoginItem.setEnabled(launchAtLogin)   // no-op if already in that state
                    } catch {
                        logger.error("launch at login: \(error.localizedDescription, privacy: .public)")
                    }
                }
                settings.hasCompletedOnboarding = true
                windows.close("onboarding")
            }
        }
    }

    private func showPreferences() {
        windows.show("preferences", title: "Glint Preferences") { PreferencesView() }
    }

    /// FR-5.
    private func showAbout() {
        windows.show("about", title: String(localized: "About Glint")) { AboutView() }
    }
}
