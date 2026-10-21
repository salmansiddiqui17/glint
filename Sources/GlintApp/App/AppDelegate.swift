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
    /// The text recognition warm-up while it runs (OQ-18).
    private var warmUp: Task<Void, Never>?
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
        warmUpTextRecognitionIfNeeded(after: .seconds(5))
    }

    /// On the first launch of each build and macOS version, recognises a small generated image so
    /// macOS prepares Vision's text model before the first Copy Text (FR-46, OQ-18). Only while
    /// Copy Text is turned on: otherwise Glint never runs Vision (OQ-22). At launch it starts after
    /// `delay`, so launch, the hotkey and the menu never wait for it; turning Copy Text on starts it
    /// at once. It runs at utility priority, not background: XPC passes the priority on to the
    /// Neural Engine compile, which background would confine to the efficiency cores and throttle.
    private func warmUpTextRecognitionIfNeeded(after delay: Duration = .zero) {
        // One at a time: turning Copy Text off and on again doesn't start another.
        guard warmUp == nil, settings.copyTextEnabled else { return }
        let build = Self.buildKey()
        guard TextRecognitionWarmUp.isNeeded(isEnabled: settings.copyTextEnabled,
                                             warmedUpBuild: settings.textRecognitionWarmedUpBuild,
                                             currentBuild: build) else { return }
        warmUp = Task {
            defer { warmUp = nil }
            try? await Task.sleep(for: delay)
            guard settings.copyTextEnabled else { return }   // turned off while waiting
            let started = ContinuousClock.now
            do {
                try await Task.detached(priority: .utility) { try await TextRecognition.warmUp() }.value
                logger.notice("text recognition warmed up in \(milliseconds(since: started)) ms")
                TextRecognitionReadiness.hasFinished = true   // the next Copy Text keeps the usual limit
                if let build { settings.textRecognitionWarmedUpBuild = build }
            } catch {
                logger.error("text recognition warm-up failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// This build's warm-up key: the version and build, plus the executable's modification date,
    /// since every local build is 0.1.0 (1), and the macOS version with its build. Nil if the date
    /// can't be read, so it warms up each launch.
    private static func buildKey() -> String? {
        let modified = try? Bundle.main.executableURL?.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate
        return TextRecognitionWarmUp.buildKey(
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?",
            build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?",
            executableModified: modified,
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString)
    }

    /// Re-opening Glint while it runs starts a capture (FR-3).
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if isSetUp { coordinator.start() }
        return false
    }

    /// First run (FR-10), or a capture found Screen Recording off (FR-12).
    private func showOnboarding() {
        let isFirstRun = !settings.hasCompletedOnboarding
        windows.show("onboarding", title: isFirstRun ? String(localized: "Welcome to Glint") : "Glint") {
            OnboardingView(isFirstRun: isFirstRun) { [weak self] choices in
                guard let self else { return }
                if let choices {
                    do {
                        try LoginItem.setEnabled(choices.launchAtLogin)   // no-op if already in that state
                    } catch {
                        logger.error("launch at login: \(error.localizedDescription, privacy: .public)")
                    }
                    if let copyTextEnabled = choices.copyTextEnabled {
                        settings.copyTextEnabled = copyTextEnabled
                        warmUpTextRecognitionIfNeeded()   // at once, if Copy Text was turned on (OQ-22)
                    }
                }
                settings.hasCompletedOnboarding = true
                windows.close("onboarding")
            }
        }
    }

    private func showPreferences() {
        windows.show("preferences", title: String(localized: "Glint Preferences")) {
            // Turning Copy Text on warms up at once, not at the next launch (OQ-22).
            PreferencesView(onTurnOnCopyText: { [weak self] in self?.warmUpTextRecognitionIfNeeded() })
        }
    }

    /// FR-5.
    private func showAbout() {
        windows.show("about", title: String(localized: "About Glint")) { AboutView() }
    }
}
