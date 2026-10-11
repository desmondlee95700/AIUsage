import Foundation
import UserNotifications
import Cocoa

/// Whether macOS lets AIUsage show notifications, as last read from Notification Center.
public enum NotificationPermission: Equatable {
    case unknown        // not read yet
    case notDetermined  // never asked
    case denied
    case authorized
}

public class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    public static let shared = NotificationManager()
    
    /// Drives the first-run card and the status line in the alerts menus. Refreshed when the
    /// popover opens, so a change made in System Settings shows up the next time it's opened.
    @Published public private(set) var permission: NotificationPermission = .unknown
    
    /// Never prompts: permission is asked for when the user turns alerts on from the first-run
    /// card or the alerts menu, so the macOS prompt arrives when they're expecting it.
    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        refreshPermission()
    }
    
    public func refreshPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            let permission: NotificationPermission
            switch settings.authorizationStatus {
            case .notDetermined: permission = .notDetermined
            case .denied: permission = .denied
            default: permission = .authorized
            }
            DispatchQueue.main.async {
                if self?.permission != permission { self?.permission = permission }
            }
        }
    }
    
    public func requestAuthorization(completion: ((Bool) -> Void)? = nil) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, error in
            // NSLog rather than print: a menu bar app's stdout goes nowhere, but this shows in Console
            if let error = error {
                NSLog("AIUsage: notification authorization error: %@", error.localizedDescription)
            } else if !granted {
                NSLog("AIUsage: notification permission not granted")
            }
            self?.refreshPermission()
            completion?(granted)
        }
    }
    
    /// Opens AIUsage's page in System Settings › Notifications, for users who declined the prompt.
    public static func openNotificationSettings() {
        let bundleId = Bundle.main.bundleIdentifier ?? ""
        let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(bundleId)")
            ?? URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!
        NSWorkspace.shared.open(url)
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
