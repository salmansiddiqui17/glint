import AppKit
import CoreGraphics

/// Screen Recording (TCC) permission helpers (FR-10, FR-11, FR-12).
///
/// `isGranted` can be stale for the life of the process: macOS often reports a new grant only
/// after a relaunch. Callers must also treat capture failures as "permission missing" (FR-12).
@MainActor
enum ScreenRecordingPermission {
    static var isGranted: Bool { CGPreflightScreenCaptureAccess() }

    /// Asks macOS for access. It shows the system prompt while the user hasn't decided, which
    /// includes after the permission was reset or the app's signature changed, and is silent
    /// otherwise. Either way it lists Glint in System Settings.
    ///
    /// It never opens System Settings itself. `CGRequestScreenCaptureAccess()` returns false
    /// both while its prompt is showing and when access was already declined, so Glint can't
    /// tell whether a prompt appeared, and opening Settings as well could show both at once.
    /// The Screen Recording row offers a separate "Open Settings…" button instead.
    static func request(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: SettingsKey.hasRequestedScreenRecording)
        _ = CGRequestScreenCaptureAccess()
    }

    static func openSystemSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension",
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) { return }
        }
    }

    /// Starts a new instance, which waits for this older one to exit (see `SingleInstance`), then
    /// quits. macOS often applies a new grant only after a restart. If the new instance can't be
    /// launched, this one keeps running.
    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { app, error in
            Task { @MainActor in
                guard app != nil, error == nil else { return NSSound.beep() }
                NSApp.terminate(nil)
            }
        }
    }
}
