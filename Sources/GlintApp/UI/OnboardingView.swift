import KeyboardShortcuts
import SwiftUI

/// The welcome window (FR-10): what Glint does, the hotkey, Screen Recording and launch at login.
/// Shown again when a capture finds Screen Recording off (FR-12); then it explains that instead
/// and leaves launch at login alone, so the user's later choice in Preferences stands.
struct OnboardingView: View {
    let isFirstRun: Bool
    /// Receives the launch-at-login choice on the first run, nil afterwards.
    let onDone: (_ launchAtLogin: Bool?) -> Void
    @State private var launchAtLogin = true

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
            }
            HStack {
                Spacer()
                Button("Done") { onDone(isFirstRun ? launchAtLogin : nil) }
                    .keyboardShortcut(.defaultAction)
                    .help("Closes this window.")
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}
