import KeyboardShortcuts
import SwiftUI

/// The welcome window (FR-10): what Glint does, the hotkey, Screen Recording, launch at login and
/// Copy Text. Shown again when a capture finds Screen Recording off (FR-12); then it explains that
/// instead and leaves both choices alone, so the user's later choices in Preferences stand.
struct OnboardingView: View {
    /// What the first run asks, applied when the user clicks Done.
    struct Choices {
        let launchAtLogin: Bool
        /// The Copy Text checkbox, or nil if left as it started, so turning Copy Text on in
        /// Preferences while this window is open isn't undone.
        let copyTextEnabled: Bool?
    }

    let isFirstRun: Bool
    /// Receives the choices on the first run, nil afterwards.
    let onDone: (Choices?) -> Void
    @State private var launchAtLogin = true
    @State private var copyTextEnabled = SettingsDefault.copyTextEnabled   // unchecked (OQ-22)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "camera.viewfinder").font(.system(size: 40))
                    .accessibilityHidden(true)
                Text(isFirstRun ? String(localized: "Welcome to Glint") : String(localized: "Screen Recording is off"))
                    .font(.title.bold())
            }
            Text(isFirstRun
                 ? String(localized: "Glint captures part of your screen so you can annotate it, then copy or save it. Everything stays on this Mac.")
                 : String(localized: "Glint needs Screen Recording access to capture your screen. It isn't allowed right now, or macOS is asking again."))
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("Capture shortcut:")
                Text(KeyboardShortcuts.getShortcut(for: .captureScreenshot)?.description ?? String(localized: "None"))
                    .font(.body.monospaced().bold())
            }
            ScreenRecordingRow()
            if isFirstRun {
                Toggle("Launch Glint at login", isOn: $launchAtLogin)
                    .help("Starts Glint when you log in, so the shortcut always works.")
                Toggle("Copy text from screenshots (on-device)", isOn: $copyTextEnabled)
                    .help("Adds Copy Text (⌘O), which reads the text in a selection with on-device text recognition. You can change this in Preferences.")
            }
            HStack {
                Spacer()
                Button("Done") {
                    let copyText = copyTextEnabled == SettingsDefault.copyTextEnabled ? nil : copyTextEnabled
                    onDone(isFirstRun ? Choices(launchAtLogin: launchAtLogin, copyTextEnabled: copyText) : nil)
                }
                .keyboardShortcut(.defaultAction)
                .help("Closes this window.")
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}
