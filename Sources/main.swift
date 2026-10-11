import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard BundleIdentity.claimSingleInstance() else {
            NSApp.terminate(nil)
            return
        }
        // Before anything reads settings (QuotaService.shared reads them on first use)
        BundleIdentity.migrateLegacyDefaults()
        
        // Ensure menu bar accessory mode (no Dock icon)
        NSApp.setActivationPolicy(.accessory)
        
        // Set application icon
        if let icon = AppIconHelper.appIconImage {
            NSApp.applicationIconImage = icon
        }
        
        // Initialize status bar item and controller
        statusBarController = StatusBarController(service: .shared)
        
        // Request user notification permissions for low-quota spending alerts, unless they're turned off
        if QuotaService.shared.alertMode != .off {
            NotificationManager.shared.requestAuthorization()
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
