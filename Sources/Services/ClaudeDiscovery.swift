import Foundation
import AppKit

public struct ClaudeDiscovery {
    private static let claudeBundleIdentifiers = [
        "com.anthropic.claudefordesktop",
        "com.anthropic.claude"
    ]
    
    public static var isClaudeAppInstalled: Bool {
        for bundleId in claudeBundleIdentifiers {
            if NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) != nil {
                return true
            }
        }
        let fileManager = FileManager.default
        let standardPaths = [
            "/Applications/Claude.app",
            "\(NSHomeDirectory())/Applications/Claude.app"
        ]
        return standardPaths.contains { fileManager.fileExists(atPath: $0) }
    }
    
    public static var hasClaudeData: Bool {
        let fileManager = FileManager.default
        let home = NSHomeDirectory()
        return fileManager.fileExists(atPath: "\(home)/.claude.json") ||
               fileManager.fileExists(atPath: "\(home)/Library/Application Support/Claude")
    }
    
    public static var isClaudeInstalled: Bool {
        isClaudeAppInstalled || hasClaudeData
    }
    
    public static func launchClaudeApp() {
        for bundleId in claudeBundleIdentifiers {
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                NSWorkspace.shared.openApplication(at: appURL, configuration: config, completionHandler: nil)
                return
            }
        }
        
        let fileManager = FileManager.default
        let standardPaths = [
            "/Applications/Claude.app",
            "\(NSHomeDirectory())/Applications/Claude.app"
        ]
        
        for path in standardPaths {
            if fileManager.fileExists(atPath: path) {
                let url = URL(fileURLWithPath: path)
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                NSWorkspace.shared.openApplication(at: url, configuration: config, completionHandler: nil)
                return
            }
        }
        
        // Fallback to web if desktop app is not installed
        if let webURL = URL(string: "https://claude.ai") {
            NSWorkspace.shared.open(webURL)
        }
    }
}
