import Foundation
import Cocoa

public struct GitHubReleaseAsset: Codable {
    public let name: String
    public let browserDownloadUrl: String
    public let size: Int?
    
    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadUrl = "browser_download_url"
        case size
    }
}

public struct GitHubRelease: Codable {
    public let tagName: String
    public let name: String?
    public let body: String?
    public let htmlUrl: String
    public let publishedAt: String?
    public let assets: [GitHubReleaseAsset]
    
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlUrl = "html_url"
        case publishedAt = "published_at"
        case assets
    }
    
    public var dmgAsset: GitHubReleaseAsset? {
        assets.first { $0.name.lowercased() == "aiusage.dmg" } ??
        assets.first { $0.name.lowercased().hasSuffix(".dmg") }
    }
}

public final class UpdateService: ObservableObject {
    public static let shared = UpdateService()
    
    private let repoOwner = "desmondlee95700"
    private let repoName = "AIUsage"
    
    @Published public var isChecking: Bool = false
    @Published public var isDownloading: Bool = false
    @Published public var availableUpdate: GitHubRelease? = nil
    @Published public var downloadErrorMessage: String? = nil
    
    private let session: URLSession
    
    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10.0
        config.timeoutIntervalForResource = 300.0
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Version Comparison
    
    public static func isVersion(_ v1: String, greaterThan v2: String) -> Bool {
        let clean1 = v1.trimmingCharacters(in: CharacterSet(charactersIn: "vV \t\n\r"))
        let clean2 = v2.trimmingCharacters(in: CharacterSet(charactersIn: "vV \t\n\r"))
        
        let parts1 = clean1.split(separator: ".").compactMap { Int($0) }
        let parts2 = clean2.split(separator: ".").compactMap { Int($0) }
        
        let maxCount = max(parts1.count, parts2.count)
        for i in 0..<maxCount {
            let p1 = i < parts1.count ? parts1[i] : 0
            let p2 = i < parts2.count ? parts2[i] : 0
            if p1 > p2 { return true }
            if p1 < p2 { return false }
        }
        return false
    }
    
    // MARK: - Check for Updates
    
    public func checkForUpdates(isUserInitiated: Bool = false) {
        guard !isChecking else { return }
        isChecking = true
        
        guard let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest") else {
            isChecking = false
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("AIUsage-Updater/\(AppVersion.current)", forHTTPHeaderField: "User-Agent")
        
        session.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isChecking = false
                
                if let error = error {
                    if isUserInitiated {
                        self.showErrorAlert(message: "Could not connect to GitHub to check for updates: \(error.localizedDescription)")
                    }
                    return
                }
                
                guard let data = data,
                      let release = try? JSONDecoder().decode(GitHubRelease.self, from: data) else {
                    if isUserInitiated {
                        self.showErrorAlert(message: "Failed to parse release information from GitHub.")
                    }
                    return
                }
                
                let currentVer = AppVersion.current
                if Self.isVersion(release.tagName, greaterThan: currentVer) {
                    self.availableUpdate = release
                    self.promptUpdate(release)
                } else {
                    self.availableUpdate = nil
                    if isUserInitiated {
                        self.showUpToDateAlert()
                    }
                }
            }
        }.resume()
    }
    
    // MARK: - Update Presentation Dialog
    
    public func promptUpdate(_ release: GitHubRelease) {
        let alert = NSAlert()
        alert.messageText = "A New Version of AIUsage is Available!"
        
        var informativeText = "AIUsage \(release.tagName) is now available (you have \(AppVersion.displayString)).\n"
        if let notes = release.body, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let truncated = notes.count > 450 ? String(notes.prefix(450)) + "..." : notes
            informativeText += "\nWhat's New:\n\(truncated)\n"
        }
        alert.informativeText = informativeText
        alert.alertStyle = .informational
        
        if let icon = AppIconHelper.appIconImage {
            alert.icon = icon
        }
        
        alert.addButton(withTitle: "Download & Install")
        alert.addButton(withTitle: "View Release Notes")
        alert.addButton(withTitle: "Later")
        
        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            downloadAndInstallUpdate(release)
        case .alertSecondButtonReturn:
            if let url = URL(string: release.htmlUrl) {
                NSWorkspace.shared.open(url)
            }
        default:
            break
        }
    }
    
    // MARK: - Download and Open DMG
    
    public func downloadAndInstallUpdate(_ release: GitHubRelease) {
        guard let asset = release.dmgAsset,
              let downloadURL = URL(string: asset.browserDownloadUrl) else {
            // Fallback to opening release page in browser
            if let pageURL = URL(string: release.htmlUrl) {
                NSWorkspace.shared.open(pageURL)
            }
            return
        }
        
        isDownloading = true
        downloadErrorMessage = nil
        
        let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let destinationURL = downloadsDir.appendingPathComponent("AIUsage-\(release.tagName).dmg")
        
        let task = session.downloadTask(with: downloadURL) { [weak self] tempURL, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isDownloading = false
                
                if let error = error {
                    self.downloadErrorMessage = error.localizedDescription
                    self.showErrorAlert(message: "Failed to download update: \(error.localizedDescription)")
                    return
                }
                
                guard let tempURL = tempURL else {
                    self.showErrorAlert(message: "Downloaded update file not found.")
                    return
                }
                
                do {
                    if FileManager.default.fileExists(atPath: destinationURL.path) {
                        try FileManager.default.removeItem(at: destinationURL)
                    }
                    try FileManager.default.moveItem(at: tempURL, to: destinationURL)
                    
                    // Open the downloaded DMG directly in Finder
                    NSWorkspace.shared.open(destinationURL)
                    
                    let completionAlert = NSAlert()
                    completionAlert.messageText = "Update Download Complete!"
                    completionAlert.informativeText = "The installer (AIUsage-\(release.tagName).dmg) has been opened from your Downloads folder. Drag AIUsage into Applications to finish updating."
                    completionAlert.alertStyle = .informational
                    if let icon = AppIconHelper.appIconImage {
                        completionAlert.icon = icon
                    }
                    completionAlert.addButton(withTitle: "OK")
                    completionAlert.runModal()
                } catch {
                    self.showErrorAlert(message: "Could not save DMG installer: \(error.localizedDescription)")
                }
            }
        }
        task.resume()
    }
    
    private func showUpToDateAlert() {
        let alert = NSAlert()
        alert.messageText = "You're Up to Date!"
        alert.informativeText = "AIUsage \(AppVersion.displayString) is currently the newest version available."
        alert.alertStyle = .informational
        if let icon = AppIconHelper.appIconImage {
            alert.icon = icon
        }
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    private func showErrorAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = "Update Check Failed"
        alert.informativeText = message
        alert.alertStyle = .warning
        if let icon = AppIconHelper.appIconImage {
            alert.icon = icon
        }
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
