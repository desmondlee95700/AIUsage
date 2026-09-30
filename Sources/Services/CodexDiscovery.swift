import Foundation
import AppKit

public struct CodexDiscovery {
    public static func findCodexBinary() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidatePaths = [
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex",
            "\(home)/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "\(home)/.codex/bin/codex",
            "/usr/local/bin/codex",
            "/opt/homebrew/bin/codex"
        ]
        
        for path in candidatePaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }
    
    public static var hasCodexAuth: Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let authPath = "\(home)/.codex/auth.json"
        return FileManager.default.fileExists(atPath: authPath)
    }
    
    public static var isChatGPTAppInstalled: Bool {
        let defaultAppPath = "/Applications/ChatGPT.app"
        let userAppPath = "\(FileManager.default.homeDirectoryForCurrentUser.path)/Applications/ChatGPT.app"
        return FileManager.default.fileExists(atPath: defaultAppPath) || FileManager.default.fileExists(atPath: userAppPath)
    }
    
    public static var isCodexInstalled: Bool {
        if findCodexBinary() != nil || isChatGPTAppInstalled || hasCodexAuth {
            return true
        }
        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") != nil {
            return true
        }
        return false
    }
}
