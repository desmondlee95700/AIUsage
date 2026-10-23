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
        
        // Read notification permission for the alerts card and menus. Nothing is requested here:
        // a prompt at launch arrives unannounced and is easily missed, so the user turns alerts on
        // from the popover's first-run card or the alerts menu instead.
        NotificationManager.shared.refreshPermission()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
