import Foundation
import AppKit

public struct CodexDiscovery {
    private static let chatGPTBundleIdentifiers = [
        "com.openai.codex",
        "com.openai.chat"
    ]

    public static func findCodexBinary() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let fileManager = FileManager.default

        // ChatGPT has moved the bundled runtime between releases. Resolve the
        // installed bundle first, then check both known layouts and finally
        // look for an executable named "codex" inside its Resources folder.
        for appURL in chatGPTApplicationURLs() {
            let knownPaths = [
                appURL.appendingPathComponent("Contents/Resources/codex"),
                appURL.appendingPathComponent("Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"),
                appURL.appendingPathComponent("Contents/Resources/codex-cli/bin/codex"),
                appURL.appendingPathComponent("Contents/Resources/codex-cli/codex")
            ]

            for url in knownPaths where fileManager.isExecutableFile(atPath: url.path) {
                return url.path
            }

            let resourcesURL = appURL.appendingPathComponent("Contents/Resources", isDirectory: true)
            if let enumerator = fileManager.enumerator(
                at: resourcesURL,
                includingPropertiesForKeys: [.isRegularFileKey, .isExecutableKey],
                options: [.skipsHiddenFiles]
            ) {
                for case let url as URL in enumerator where url.lastPathComponent == "codex" {
                    if fileManager.isExecutableFile(atPath: url.path) {
                        return url.path
                    }
                }
            }
        }

        // Also support a standalone Codex CLI installation.
        let standalonePaths = [
            "\(home)/.codex/bin/codex",
            "/usr/local/bin/codex",
            "/opt/homebrew/bin/codex"
        ]
        for path in standalonePaths where fileManager.isExecutableFile(atPath: path) {
            return path
        }

        return nil
    }

    private static func chatGPTApplicationURLs() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var urls = [
            URL(fileURLWithPath: "/Applications/ChatGPT.app"),
            home.appendingPathComponent("Applications/ChatGPT.app")
        ]

        for bundleIdentifier in chatGPTBundleIdentifiers {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                urls.append(url)
            }
        }

        var seen = Set<String>()
        return urls.filter { url in
            let path = url.standardizedFileURL.path
            guard seen.insert(path).inserted else { return false }
            return FileManager.default.fileExists(atPath: path)
        }
    }
    
    public static var hasCodexAuth: Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let authPath = "\(home)/.codex/auth.json"
        return FileManager.default.fileExists(atPath: authPath)
    }
    
    public static var isChatGPTAppInstalled: Bool {
        !chatGPTApplicationURLs().isEmpty
    }
    
    public static var isCodexInstalled: Bool {
        // A ChatGPT app or auth file alone is not sufficient: CodexService
        // needs an executable runtime it can launch with `app-server`.
        findCodexBinary() != nil
    }
    
    public static func launchChatGPTApp() {
        for appURL in chatGPTApplicationURLs() {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: appURL, configuration: config, completionHandler: nil)
            return
        }
        
        // Fallback to web if desktop app is not installed
        if let webURL = URL(string: "https://chatgpt.com") {
            NSWorkspace.shared.open(webURL)
        }
    }
}
