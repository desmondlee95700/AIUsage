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
    
    /// Semantic version comparison, including pre-release suffixes (`2.1.3-rc.1 < 2.1.3`).
    public static func isVersion(_ v1: String, greaterThan v2: String) -> Bool {
        let (core1, pre1) = splitVersion(v1)
        let (core2, pre2) = splitVersion(v2)

        let maxCount = max(core1.count, core2.count)
        for i in 0..<maxCount {
            let p1 = i < core1.count ? core1[i] : 0
            let p2 = i < core2.count ? core2[i] : 0
            if p1 > p2 { return true }
            if p1 < p2 { return false }
        }

        // Same core version: a release outranks any of its pre-releases
        switch (pre1, pre2) {
        case (nil, nil), (nil, _?): return pre2 != nil
        case (_?, nil): return false
        case let (a?, b?): return isPrerelease(a, greaterThan: b)
        }
    }

    /// Splits "v2.1.3-rc.1" into numeric core [2, 1, 3] and pre-release identifiers ["rc", "1"].
    private static func splitVersion(_ version: String) -> (core: [Int], prerelease: [String]?) {
        let clean = version.trimmingCharacters(in: CharacterSet(charactersIn: "vV \t\n\r"))
        let pieces = clean.split(separator: "-", maxSplits: 1)
        let core = (pieces.first ?? "").split(separator: ".").compactMap { Int($0) }
        let prerelease = pieces.count > 1 ? pieces[1].split(separator: ".").map(String.init) : nil
        return (core, prerelease)
    }

    /// Semver precedence for pre-release identifiers: numeric compare numerically and rank
    /// below alphanumeric ones; a shorter list ranks lower when all shared identifiers match.
    private static func isPrerelease(_ a: [String], greaterThan b: [String]) -> Bool {
        for (x, y) in zip(a, b) where x != y {
            switch (Int(x), Int(y)) {
            case let (nx?, ny?): return nx > ny
            case (nil, _?): return true
            case (_?, nil): return false
            case (nil, nil): return x > y
            }
        }
        return a.count > b.count
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
                    // Background checks stay quiet for a version the user chose to skip;
                    // the header badge and menu item still offer it.
                    if isUserInitiated || self.skippedVersion != release.tagName {
                        self.promptUpdate(release, allowSkip: !isUserInitiated)
                    }
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
    
    private var skippedVersion: String? {
        get { UserDefaults.standard.string(forKey: "skippedUpdateVersion") }
        set { UserDefaults.standard.set(newValue, forKey: "skippedUpdateVersion") }
    }
    
    /// Runs an alert in front of other apps. As a menu bar (accessory) app we aren't
    /// active by default, so without this the alert can open behind other windows.
    private func runFrontmost(_ alert: NSAlert) -> NSApplication.ModalResponse {
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal()
    }
    
    /// Converts the Markdown release body into plain text for NSAlert, which can't render
    /// Markdown: headings and emphasis markers are stripped, list items become bullets, and
    /// the "Full changelog" link is dropped since "View Release Notes" opens the release page.
    static func plainTextReleaseNotes(_ markdown: String, maxLength: Int = 450) -> String {
        var lines: [String] = []
        for rawLine in markdown.components(separatedBy: .newlines) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.lowercased().contains("full changelog") { continue }
            
            while line.hasPrefix("#") { line.removeFirst() }
            line = line.replacingOccurrences(of: "**", with: "")
                .replacingOccurrences(of: "__", with: "")
                .replacingOccurrences(of: "`", with: "")
                .trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                line = "• " + line.dropFirst(2)
            }
            
            // Collapse runs of blank lines
            if line.isEmpty && (lines.last?.isEmpty ?? true) { continue }
            lines.append(line)
        }
        while lines.last?.isEmpty == true { lines.removeLast() }
        
        // Truncate on a line boundary so a bullet is never cut mid-sentence
        var result = ""
        for line in lines {
            let candidate = result.isEmpty ? line : result + "\n" + line
            if candidate.count > maxLength {
                return result.isEmpty ? String(line.prefix(maxLength)) + "…" : result + "\n…"
            }
            result = candidate
        }
        return result
    }
    
    public func promptUpdate(_ release: GitHubRelease, allowSkip: Bool = false) {
        let alert = NSAlert()
        alert.messageText = "A New Version of AIUsage is Available!"
        
        var informativeText = "AIUsage \(release.tagName) is now available (you have \(AppVersion.displayString)).\n"
        if let notes = release.body, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let summary = Self.plainTextReleaseNotes(notes)
            if !summary.isEmpty {
                informativeText += "\nWhat's New:\n\(summary)\n"
            }
        }
        alert.informativeText = informativeText
        alert.alertStyle = .informational
        
        if let icon = AppIconHelper.appIconImage {
            alert.icon = icon
        }
        
        alert.addButton(withTitle: "Download & Install")
        alert.addButton(withTitle: "View Release Notes")
        alert.addButton(withTitle: "Later")
        if allowSkip {
            alert.addButton(withTitle: "Skip This Version")
        }
        let skipResponse = NSApplication.ModalResponse(rawValue: NSApplication.ModalResponse.alertThirdButtonReturn.rawValue + 1)
        
        let response = runFrontmost(alert)
        switch response {
        case .alertFirstButtonReturn:
            downloadAndInstallUpdate(release)
        case .alertSecondButtonReturn:
            if let url = URL(string: release.htmlUrl) {
                NSWorkspace.shared.open(url)
            }
        case skipResponse:
            skippedVersion = release.tagName
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
                    _ = self.runFrontmost(completionAlert)
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
        _ = runFrontmost(alert)
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
        _ = runFrontmost(alert)
    }
}
