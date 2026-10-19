import SwiftUI

/// Screen Recording status with Grant / Relaunch buttons (FR-10, FR-11). Polls only while visible (NFR-7).
struct ScreenRecordingRow: View {
    @State private var granted = ScreenRecordingPermission.isGranted
    /// Set by `ScreenRecordingPermission.request()`, so Relaunch is offered in every window once asked.
    @AppStorage(SettingsKey.hasRequestedScreenRecording) private var requested = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(granted ? "Screen Recording: Granted" : "Screen Recording: Not granted",
                      systemImage: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(granted ? .green : .red)
                Spacer()
                if !granted {
                    Button("Grant Access…") { ScreenRecordingPermission.request() }
                        .help("Asks macOS for Screen Recording access, or opens System Settings.")
                    if requested {
                        Button("Relaunch") { ScreenRecordingPermission.relaunch() }
                            .help("Restarts Glint so macOS applies the new permission.")
                    }
                }
            }
            if !granted && requested {
                Text("After allowing Glint in System Settings, click Relaunch if this still says Not granted.")
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
