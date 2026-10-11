import Foundation
import UserNotifications
import Cocoa

public class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    public static let shared = NotificationManager()
    
    private override init() {
        super.init()
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        requestAuthorization()
    }
    
    public func requestAuthorization(completion: ((Bool) -> Void)? = nil) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification authorization error: \(error.localizedDescription)")
            }
            completion?(granted)
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
                print("Failed to deliver notification: \(error.localizedDescription)")
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
