import AppKit
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

    /// Flips the login item from a menu. Opens Login Items when macOS needs the user's approval,
    /// and explains failures (e.g. running from outside /Applications) in an alert.
    @MainActor
    public static func toggle() {
        let enable = !isEnabled
        do {
            try setEnabled(enable)
            if enable && requiresApproval {
                openSystemSettings()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = enable ? "Couldn't Enable Launch at Login" : "Couldn't Disable Launch at Login"
            alert.informativeText = "\(error.localizedDescription)\n\nMake sure AIUsage is in your Applications folder, or change it in System Settings > General > Login Items."
            alert.alertStyle = .warning
            if let icon = AppIconHelper.appIconImage {
                alert.icon = icon
            }
            alert.addButton(withTitle: "Open Login Items")
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn {
                openSystemSettings()
            }
        }
    }
}
