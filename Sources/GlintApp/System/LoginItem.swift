import ServiceManagement

/// Launch at login via SMAppService (FR-13). The system is the source of truth, so the user
/// turning it off (or not approving it) in System Settings is reflected here.
@MainActor
enum LoginItem {
    static var status: SMAppService.Status { SMAppService.mainApp.status }

    /// Registers or unregisters; asking for the state it is already in does nothing.
    static func setEnabled(_ enabled: Bool) throws {
        switch (enabled, status) {
        case (true, .enabled), (true, .requiresApproval), (false, .notRegistered), (false, .notFound):
            return
        case (true, _):
            try SMAppService.mainApp.register()
        case (false, _):
            try SMAppService.mainApp.unregister()
        }
    }

    /// For `.requiresApproval`: System Settings › General › Login Items.
    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
