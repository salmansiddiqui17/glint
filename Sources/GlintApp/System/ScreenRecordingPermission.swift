import AppKit
import CoreGraphics

/// Screen Recording (TCC) permission helpers (FR-10, FR-11, FR-12).
///
/// `isGranted` can be stale for the life of the process: macOS often reports a new grant only
/// after a relaunch. Callers must also treat capture failures as "permission missing" (FR-12).
@MainActor
enum ScreenRecordingPermission {
    static var isGranted: Bool { CGPreflightScreenCaptureAccess() }

    /// First call: shows the system prompt. Later calls (macOS no longer prompts once the user has
    /// decided): request again, which is silent then but re-lists Glint in System Settings after a
    /// `tccutil reset`, and open the Screen Recording pane.
    ///
    /// `CGRequestScreenCaptureAccess()` returns false while its prompt is still pending, so its
    /// result can't tell "prompted now" from "already declined"; a stored flag does. Accepted
    /// trade-off: after a `tccutil reset`, a later click may show the prompt and Settings together.
    static func request(defaults: UserDefaults = .standard) {
        let alreadyAsked = defaults.bool(forKey: SettingsKey.hasRequestedScreenRecording)
        defaults.set(true, forKey: SettingsKey.hasRequestedScreenRecording)
        if CGRequestScreenCaptureAccess() { return }
        if alreadyAsked { openSystemSettings() }
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
