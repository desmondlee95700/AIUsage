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
    
    public func sendLowQuotaNotification(provider: String, remainingQuota: String, window: String? = nil) {
        let center = UNUserNotificationCenter.current()
        
        center.getNotificationSettings { [weak self] settings in
            if settings.authorizationStatus == .denied {
                // When permission is denied, open Notification settings for the user
                DispatchQueue.main.async {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                        NSWorkspace.shared.open(url)
                    }
                }
                return
            }
            
            if settings.authorizationStatus == .notDetermined {
                self?.requestAuthorization { granted in
                    if granted {
                        self?.postNotification(provider: provider, remainingQuota: remainingQuota, window: window)
                    }
                }
                return
            }
            
            self?.postNotification(provider: provider, remainingQuota: remainingQuota, window: window)
        }
    }
    
    private func postNotification(provider: String, remainingQuota: String, window: String? = nil) {
        let content = UNMutableNotificationContent()
        content.title = "\(provider) Quota Alert"
        if let window = window, !window.isEmpty {
            content.body = "You have \(remainingQuota) quota remaining (\(window)) on \(provider)."
        } else {
            content.body = "You have \(remainingQuota) quota remaining on \(provider)."
        }
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
