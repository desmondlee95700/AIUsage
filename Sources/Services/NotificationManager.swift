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

/// Main-actor isolated: `permission` drives SwiftUI, so it only ever changes on the main thread.
/// Notification Center is called through its async APIs, which hop off and back automatically.
@MainActor
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
    
    /// Re-reads the permission from Notification Center; `completion` runs once `permission` is current.
    public func refreshPermission(completion: (() -> Void)? = nil) {
        Task {
            await updatePermission()
            completion?()
        }
    }
    
    private func updatePermission() async {
        let status = await Self.authorizationStatus()
        let current: NotificationPermission
        switch status {
        case .notDetermined: current = .notDetermined
        case .denied: current = .denied
        default: current = .authorized
        }
        if permission != current { permission = current }
    }
    
    public func requestAuthorization(completion: ((Bool) -> Void)? = nil) {
        Task {
            let granted: Bool
            do {
                granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
                // NSLog rather than print: a menu bar app's stdout goes nowhere, but this shows in Console
                if !granted { NSLog("AIUsage: notification permission not granted") }
            } catch {
                NSLog("AIUsage: notification authorization error: %@", error.localizedDescription)
                granted = false
            }
            await updatePermission()
            completion?(granted)
        }
    }
    
    /// Opens AIUsage's page in System Settings › Notifications, for users who declined the prompt.
    public nonisolated static func openNotificationSettings() {
        let bundleId = Bundle.main.bundleIdentifier ?? ""
        let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(bundleId)")
            ?? URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!
        NSWorkspace.shared.open(url)
    }
    
    /// Reads the status off the main actor: older SDKs don't mark UNNotificationSettings Sendable,
    /// so only the status enum crosses back.
    private nonisolated static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
    
    public func sendLowQuotaNotification(provider: String, remainingQuota: String, window: String? = nil, resetDate: Date? = nil) {
        Task {
            switch await Self.authorizationStatus() {
            case .denied:
                // This runs from background quota checks, so respect a denial silently
                // rather than popping open System Settings unprompted.
                return
            case .notDetermined:
                requestAuthorization { [weak self] granted in
                    if granted {
                        self?.postNotification(provider: provider, remainingQuota: remainingQuota, window: window, resetDate: resetDate)
                    }
                }
            default:
                postNotification(provider: provider, remainingQuota: remainingQuota, window: window, resetDate: resetDate)
            }
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
        
        Task {
            do {
                try await UNUserNotificationCenter.current().add(request)
            } catch {
                NSLog("AIUsage: failed to deliver notification: %@", error.localizedDescription)
            }
        }
    }
    
    /// "25% of your 5-hour limit left on ChatGPT. Resets in 2h 10m." The reset time is the
    /// next thing you'd want to know, so it's included whenever the provider reports one.
    nonisolated static func lowQuotaBody(provider: String, remainingQuota: String, window: String?, resetDate: Date?, now: Date = Date()) -> String {
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
    
    // Present banner directly even when app is active. Called by Notification Center on its own
    // queue and touches no state, so it's exempt from main-actor isolation.
    public nonisolated func userNotificationCenter(
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
