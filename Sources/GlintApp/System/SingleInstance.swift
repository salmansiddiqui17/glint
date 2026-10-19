import AppKit
import GlintCore

/// Keeps exactly one Glint running, so there is one status item and one hotkey handler.
///
/// Two instances can otherwise overlap: during `ScreenRecordingPermission.relaunch()`, or when the
/// /Applications copy and a build-folder copy (same bundle ID) are both opened. Launch arguments
/// can't carry a hand-over (the sandbox drops them), so the rule is: the **older** instance wins.
@MainActor
enum SingleInstance {
    /// Returns `true` when this instance should continue starting up.
    ///
    /// Waits up to `timeout` for every older Glint to exit (the relaunch case: the predecessor is
    /// quitting). If one is still running after that, sends it a reopen event (FR-3: that starts a
    /// capture) and returns `false` so the caller can quit. Younger instances are ignored; they
    /// defer to this one in turn, so two copies started together still leave exactly one.
    static func claim(timeout: Duration = .seconds(5)) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while true {
            let older = olderInstances()
            if older.isEmpty { return true }
            if ContinuousClock.now >= deadline {
                if let url = older.first?.bundleURL {
                    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
                }
                return false
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    /// Other running Glint processes that come before this one in launch order.
    private static func olderInstances() -> [NSRunningApplication] {
        let me = NSRunningApplication.current
        return NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0.processIdentifier != me.processIdentifier && !$0.isTerminated && order($0) < order(me) }
            .sorted { order($0) < order($1) }
    }

    /// One ordering key for every process, so all instances agree on who is older.
    private static func order(_ app: NSRunningApplication) -> LaunchOrder {
        LaunchOrder(launchDate: app.launchDate, processID: app.processIdentifier)
    }
}
