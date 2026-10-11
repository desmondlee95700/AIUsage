import Foundation
import ServiceManagement

/// Registers AIUsage as a login item via `SMAppService` (macOS 13+). The system owns the
/// state, so it's always read live: the user can also toggle it in System Settings.
public enum LaunchAtLogin {
    public static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// The user must allow the login item in System Settings > General > Login Items.
    public static var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    /// Turns the login item on or off. Throws when registration fails, e.g. when running
    /// outside an app bundle (`swift run`) or from a translocated download.
    public static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    public static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
