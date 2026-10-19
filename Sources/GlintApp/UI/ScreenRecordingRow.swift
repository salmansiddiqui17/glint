import SwiftUI

/// Screen Recording status with Grant, Open Settings and Relaunch buttons (FR-10, FR-11). Polls
/// only while visible (NFR-7).
struct ScreenRecordingRow: View {
    @State private var granted = ScreenRecordingPermission.isGranted
    /// Set by `ScreenRecordingPermission.request()`, so Relaunch is offered in every window once asked.
    @AppStorage(SettingsKey.hasRequestedScreenRecording) private var requested = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(granted ? "Screen Recording: Granted" : "Screen Recording: Not granted",
                  systemImage: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(granted ? .green : .red)
            if !granted {
                HStack {
                    Button("Grant Access…") { ScreenRecordingPermission.request() }
                        .help("Asks macOS for Screen Recording access.")
                    Button("Open Settings…") { ScreenRecordingPermission.openSystemSettings() }
                        .help("Opens Privacy & Security › Screen & System Audio Recording.")
                    if requested {
                        Button("Relaunch") { ScreenRecordingPermission.relaunch() }
                            .help("Restarts Glint so macOS applies the new permission.")
                    }
                }
                Text(requested
                     ? "If no prompt appears, click Open Settings and turn Glint on. If it's already on but this still says Not granted, remove Glint with −, click Grant Access again, then Relaunch."
                     : "Click Grant Access, then allow Glint when macOS asks.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task {
            while !Task.isCancelled {
                granted = ScreenRecordingPermission.isGranted
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}
