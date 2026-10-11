import Foundation
import UserNotifications
import Cocoa

public class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    public static let shared = NotificationManager()
    
    /// Permission is requested by the app at launch (unless alerts are off) or on first use,
    /// not here, so merely touching `shared` never prompts.
    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }
    
    public func requestAuthorization(completion: ((Bool) -> Void)? = nil) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            // NSLog rather than print: a menu bar app's stdout goes nowhere, but this shows in Console
            if let error = error {
                NSLog("AIUsage: notification authorization error: %@", error.localizedDescription)
            } else if !granted {
                NSLog("AIUsage: notification permission not granted")
            }
            completion?(granted)
        }
    }
    
    // MARK: - Test Notification
    
    /// Posts a sample alert so the user can check notifications work. Asks for permission if it
    /// hasn't been decided yet; if notifications are blocked, explains and offers System Settings.
    public func sendTestNotification() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                self?.requestAuthorization { granted in
                    if granted {
                        self?.postTestNotification()
                    } else {
                        Self.showNotificationsBlockedAlert()
                    }
                }
            case .denied:
                Self.showNotificationsBlockedAlert()
            default:
                if settings.alertSetting == .disabled {
                    // Allowed, but banners are off, so a test would land silently in Notification Center
                    Self.showNotificationsBlockedAlert(bannersOnly: true)
                }
                self?.postTestNotification()
            }
        }
    }
    
    private func postTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "AIUsage Test Alert"
        content.body = "Notifications are working. You'll get alerts like this when a limit runs low."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "test-\(Int(Date().timeIntervalSince1970))", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                NSLog("AIUsage: failed to deliver test notification: %@", error.localizedDescription)
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Test Notification Failed"
                    alert.informativeText = error.localizedDescription
                    NSApp.activate(ignoringOtherApps: true)
                    alert.runModal()
                }
            }
        }
    }
    
    private static func showNotificationsBlockedAlert(bannersOnly: Bool = false) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            if bannersOnly {
                alert.messageText = "AIUsage Banners Are Off"
                alert.informativeText = "Notifications are allowed but set to not show banners, so low-quota alerts only appear in Notification Center. Turn on banners for AIUsage in System Settings to see them as they arrive."
            } else {
                alert.messageText = "Notifications Are Off for AIUsage"
                alert.informativeText = "Low-quota alerts can't be shown until you allow notifications for AIUsage in System Settings."
            }
            alert.addButton(withTitle: "Open Notification Settings")
            alert.addButton(withTitle: "Not Now")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn {
                let bundleId = Bundle.main.bundleIdentifier ?? ""
                let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(bundleId)")
                    ?? URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    public func sendLowQuotaNotification(provider: String, remainingQuota: String, window: String? = nil, resetDate: Date? = nil) {
        let center = UNUserNotificationCenter.current()
        
        center.getNotificationSettings { [weak self] settings in
            // This runs from background quota checks, so respect a denial silently
            // rather than popping open System Settings unprompted.
            if settings.authorizationStatus == .denied {
                return
            }
            
            if settings.authorizationStatus == .notDetermined {
                self?.requestAuthorization { granted in
                    if granted {
                        self?.postNotification(provider: provider, remainingQuota: remainingQuota, window: window, resetDate: resetDate)
                    }
                }
                return
            }
            
            self?.postNotification(provider: provider, remainingQuota: remainingQuota, window: window, resetDate: resetDate)
        }
    }
    
    private func postNotification(provider: String, remainingQuota: String, window: String? = nil, resetDate: Date? = nil) {
        let content = UNMutableNotificationContent()
        content.title = "\(provider) Quota Alert"
        content.body = Self.lowQuotaBody(provider: provider, remainingQuota: remainingQuota, window: window, resetDate: resetDate)
        content.sound = .default
        
        let iconName: String = {
            switch provider.lowercased() {
            case "chatgpt": return "ChatGPTIcon"
            case "antigravity": return "AntigravityIcon"
            case "claude": return "ClaudeIcon"
            default: return "AppIcon"
            }
        }()
        
        if let iconURL = Bundle.main.url(forResource: iconName, withExtension: "png") ?? Bundle.main.url(forResource: "AppIcon", withExtension: "png") {
            let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            let tempFile = tempDir.appendingPathComponent("notif_\(iconName).png")
            try? FileManager.default.removeItem(at: tempFile)
            if (try? FileManager.default.copyItem(at: iconURL, to: tempFile)) != nil {
                if let attachment = try? UNNotificationAttachment(identifier: "icon", url: tempFile, options: nil) {
                    content.attachments = [attachment]
                }
            }
        }
        
        let identifier = "low-quota-\(provider.lowercased())-\(Int(Date().timeIntervalSince1970))"
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                NSLog("AIUsage: failed to deliver notification: %@", error.localizedDescription)
            }
        }
    }
    
    /// "25% of your 5-hour limit left on ChatGPT. Resets in 2h 10m." The reset time is the
    /// next thing you'd want to know, so it's included whenever the provider reports one.
    static func lowQuotaBody(provider: String, remainingQuota: String, window: String?, resetDate: Date?, now: Date = Date()) -> String {
        var body: String
        if let window = window, !window.isEmpty {
            body = "\(remainingQuota) of your \(window) left on \(provider)."
        } else {
            body = "\(remainingQuota) quota left on \(provider)."
        }
        if let resetDate = resetDate, let countdown = DateParsing.countdown(until: resetDate, now: now) {
            body += " Resets in \(countdown)."
        }
        return body
    }
    
    // Present banner directly even when app is active
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if #available(macOS 11.0, *) {
            completionHandler([.banner, .sound, .list, .badge])
        } else {
            completionHandler([.alert, .sound])
        }
    }
}
