import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure menu bar accessory mode (no Dock icon)
        NSApp.setActivationPolicy(.accessory)
        
        // Set application icon
        if let icon = AppIconHelper.appIconImage {
            NSApp.applicationIconImage = icon
        }
        
        // Initialize status bar item and controller
        statusBarController = StatusBarController()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
