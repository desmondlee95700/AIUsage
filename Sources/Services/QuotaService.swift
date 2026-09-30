import Foundation
import SwiftUI
import Combine

public class QuotaService: ObservableObject {
    public static let shared = QuotaService()
    
    // Active Provider Selection
    @Published public var activeProvider: AIProvider {
        didSet {
            UserDefaults.standard.set(activeProvider.rawValue, forKey: "activeProvider")
            updateMenuBarCallback?()
        }
    }
    
    // General Status
    @Published public var isLoading: Bool = false
    @Published public var lastUpdated: Date? = nil
    
    // Gemini / Antigravity State
    @Published public var isGeminiConnected: Bool = false
    @Published public var quotaSummary: QuotaSummaryData? = nil
    @Published public var userStatus: UserStatusData? = nil
    @Published public var geminiErrorMessage: String? = nil
    @Published public var discoveredServer: DiscoveredServer? = nil
    
    // ChatGPT / Codex State
    @Published public var isCodexConnected: Bool = false
    @Published public var codexRateLimits: CodexRateLimitsResponse? = nil
    @Published public var codexAccount: CodexAccountInfo? = nil
    @Published public var codexUsage: CodexUsageSummary? = nil
    @Published public var codexErrorMessage: String? = nil
    
    // Backward compatibility property for isConnected (checks current provider)
    public var isConnected: Bool {
        switch activeProvider {
        case .gemini: return isGeminiConnected
        case .chatgpt: return isCodexConnected
        }
    }
    
    public var errorMessage: String? {
        switch activeProvider {
        case .gemini: return geminiErrorMessage
        case .chatgpt: return codexErrorMessage
        }
    }
    
    // User preferences
    @Published public var displayMode: MenuBarDisplayMode {
        didSet {
            UserDefaults.standard.set(displayMode.rawValue, forKey: "menuBarDisplayMode")
            updateMenuBarCallback?()
        }
    }
    
    @Published public var refreshInterval: RefreshInterval {
        didSet {
            UserDefaults.standard.set(refreshInterval.rawValue, forKey: "refreshInterval")
            restartTimer()
        }
    }
    
    public var updateMenuBarCallback: (() -> Void)?
    
    private var timer: Timer?
    private let session: URLSession
    
    public init() {
        let savedProvider = UserDefaults.standard.string(forKey: "activeProvider")
        self.activeProvider = AIProvider(rawValue: savedProvider ?? "") ?? .gemini
        
        let savedMode = UserDefaults.standard.string(forKey: "menuBarDisplayMode")
        self.displayMode = MenuBarDisplayMode(rawValue: savedMode ?? "") ?? .dual
        
        let savedInterval = UserDefaults.standard.integer(forKey: "refreshInterval")
        self.refreshInterval = RefreshInterval(rawValue: savedInterval == 0 ? 60 : savedInterval) ?? .oneMinute
        
        self.session = URLSession(configuration: .ephemeral, delegate: InsecureTrustDelegate.shared, delegateQueue: nil)
        
        restartTimer()
    }
    
    public func restartTimer() {
        timer?.invalidate()
        timer = nil
        
        guard refreshInterval.rawValue > 0 else { return }
        
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(refreshInterval.rawValue), repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }
    
    public func refresh(forceDiscovery: Bool = false) {
        guard !isLoading else { return }
        
        DispatchQueue.main.async {
            self.isLoading = true
        }
        
        let dispatchGroup = DispatchGroup()
        
        // 1. Refresh Gemini (Antigravity)
        dispatchGroup.enter()
        refreshGemini(forceDiscovery: forceDiscovery) {
            dispatchGroup.leave()
        }
        
        // 2. Refresh ChatGPT (Codex)
        dispatchGroup.enter()
        refreshCodex {
            dispatchGroup.leave()
        }
        
        dispatchGroup.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            self.isLoading = false
            self.lastUpdated = Date()
            self.updateMenuBarCallback?()
        }
    }
    
    // MARK: - Gemini Refresh Pipeline
    
    private func refreshGemini(forceDiscovery: Bool, completion: @escaping () -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                completion()
                return
            }
            
            guard let server = ProcessDiscovery.discover(forceRefresh: forceDiscovery) else {
                DispatchQueue.main.async {
                    self.isGeminiConnected = false
                    self.discoveredServer = nil
                    self.geminiErrorMessage = "Antigravity is not running. Launch Antigravity to monitor Gemini quotas."
                }
                completion()
                return
            }
            
            let group = DispatchGroup()
            var fetchedQuota: QuotaSummaryData?
            var fetchedStatus: UserStatusData?
            var quotaError: Error?
            
            group.enter()
            self.fetchQuotaSummary(server: server) { result in
                switch result {
                case .success(let data):
                    fetchedQuota = data
                case .failure(let err):
                    quotaError = err
                }
                group.leave()
            }
            
            group.enter()
            self.fetchUserStatus(server: server) { result in
                switch result {
                case .success(let data):
                    fetchedStatus = data
                case .failure:
                    break
                }
                group.leave()
            }
            
            group.notify(queue: .main) {
                if let quota = fetchedQuota {
                    self.isGeminiConnected = true
                    self.discoveredServer = server
                    self.quotaSummary = quota
                    self.userStatus = fetchedStatus
                    self.geminiErrorMessage = nil
                } else {
                    self.isGeminiConnected = false
                    self.geminiErrorMessage = quotaError?.localizedDescription ?? "Failed to fetch model quota from Antigravity."
                }
                completion()
            }
        }
    }
    
    // MARK: - Codex / ChatGPT Refresh Pipeline
    
    private func refreshCodex(completion: @escaping () -> Void) {
        CodexService.shared.fetch { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else {
                    completion()
                    return
                }
                switch result {
                case .success(let payload):
                    self.isCodexConnected = true
                    self.codexRateLimits = payload.rateLimits
                    self.codexAccount = payload.account
                    self.codexUsage = payload.usage
                    self.codexErrorMessage = nil
                case .failure(let err):
                    self.isCodexConnected = false
                    self.codexErrorMessage = err.localizedDescription
                }
                completion()
            }
        }
    }
    
    // MARK: - Gemini HTTP Calls
    
    private func fetchQuotaSummary(server: DiscoveredServer, completion: @escaping (Result<QuotaSummaryData, Error>) -> Void) {
        guard let url = URL(string: "https://127.0.0.1:\(server.port)/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary") else {
            completion(.failure(URLError(.badURL)))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(server.csrfToken, forHTTPHeaderField: "X-Codeium-Csrf-Token")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.httpBody = Data("{}".utf8)
        request.timeoutInterval = 4.0
        
        session.dataTask(with: request) { data, _, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data else {
                completion(.failure(URLError(.zeroByteResource)))
                return
            }
            do {
                let decoded = try JSONDecoder().decode(QuotaSummaryResponse.self, from: data)
                if let quotaData = decoded.response {
                    completion(.success(quotaData))
                } else {
                    completion(.failure(URLError(.cannotParseResponse)))
                }
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
    
    private func fetchUserStatus(server: DiscoveredServer, completion: @escaping (Result<UserStatusData, Error>) -> Void) {
        guard let url = URL(string: "https://127.0.0.1:\(server.port)/exa.language_server_pb.LanguageServerService/GetUserStatus") else {
            completion(.failure(URLError(.badURL)))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(server.csrfToken, forHTTPHeaderField: "X-Codeium-Csrf-Token")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.httpBody = Data("{}".utf8)
        request.timeoutInterval = 4.0
        
        session.dataTask(with: request) { data, _, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data else {
                completion(.failure(URLError(.zeroByteResource)))
                return
            }
            do {
                let decoded = try JSONDecoder().decode(UserStatusResponse.self, from: data)
                if let status = decoded.userStatus {
                    completion(.success(status))
                } else {
                    completion(.failure(URLError(.cannotParseResponse)))
                }
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
    
    // MARK: - Computed Properties for Helpers
    
    public var primaryWeeklyBucket: QuotaBucket? {
        guard let groups = quotaSummary?.groups else { return nil }
        let group = groups.first { $0.displayName.contains("Gemini") } ?? groups.first
        return group?.buckets.first { $0.window == "weekly" || $0.bucketId.contains("weekly") }
    }
    
    public var primary5hBucket: QuotaBucket? {
        guard let groups = quotaSummary?.groups else { return nil }
        let group = groups.first { $0.displayName.contains("Gemini") } ?? groups.first
        return group?.buckets.first { $0.window == "5h" || $0.bucketId.contains("5h") }
    }
    
    public var geminiPercentage: Int {
        primaryWeeklyBucket?.percentage ?? 0
    }
    
    public var codexPrimaryWindow: CodexRateLimitWindow? {
        codexRateLimits?.rateLimits?.primary
    }
    
    public var codexRemainingPercentage: Int {
        codexPrimaryWindow?.remainingPercent ?? 0
    }
    
    public var codexUsedPercentage: Int {
        codexPrimaryWindow?.usedPercent ?? 0
    }
    
    // MARK: - Menu Bar Formatter Helpers
    
    public var menuBarTitle: String {
        let geminiStr = isGeminiConnected ? "\(geminiPercentage)%" : "Offline"
        let codexStr = isCodexConnected ? "\(codexRemainingPercentage)%" : "Offline"
        
        switch displayMode {
        case .dual:
            if !isGeminiConnected && !isCodexConnected {
                return " Offline"
            }
            return " ✦ \(geminiStr) · ✷ \(codexStr)"
            
        case .activeProvider:
            switch activeProvider {
            case .gemini:
                return isGeminiConnected ? " ✦ \(geminiPercentage)%" : " ✦ Offline"
            case .chatgpt:
                return isCodexConnected ? " ✷ \(codexRemainingPercentage)%" : " ✷ Offline"
            }
            
        case .weekly:
            return isGeminiConnected ? " \(geminiPercentage)%" : " Antigravity Offline"
            
        case .iconOnly:
            return ""
        }
    }
    
    public var menuBarTooltip: String {
        var lines: [String] = ["AIUsage — AI Model Quota Tracker"]
        
        if isGeminiConnected {
            let tier = userStatus?.userTier?.name ?? "Connected"
            let reset = primaryWeeklyBucket?.formattedResetCountdown ?? "Active"
            lines.append("• ✦ Gemini: \(geminiPercentage)% remaining (\(tier)) · \(reset)")
        } else {
            lines.append("• ✦ Gemini: Offline (Launch Antigravity)")
        }
        
        if isCodexConnected {
            let plan = codexAccount?.formattedPlan ?? "Connected"
            let reset = codexPrimaryWindow?.formattedResetCountdown ?? "Active"
            lines.append("• ✷ ChatGPT: \(codexRemainingPercentage)% remaining (\(plan)) · \(reset)")
        } else {
            lines.append("• ✷ ChatGPT: Offline (Launch ChatGPT.app)")
        }
        
        lines.append("Click to switch views or right-click for quick actions")
        return lines.joined(separator: "\n")
    }
    
    public var statusTintColor: NSColor {
        // Evaluate the active provider or lowest remaining percentage
        let activePercent = activeProvider == .gemini ? (isGeminiConnected ? geminiPercentage : nil) : (isCodexConnected ? codexRemainingPercentage : nil)
        
        guard let pct = activePercent else {
            return .secondaryLabelColor
        }
        
        if pct >= 50 {
            return NSColor(red: 0.13, green: 0.77, blue: 0.36, alpha: 1.0) // Green #22c55e
        } else if pct >= 20 {
            return NSColor(red: 0.96, green: 0.62, blue: 0.04, alpha: 1.0) // Orange #f59e0b
        } else {
            return NSColor(red: 0.94, green: 0.27, blue: 0.27, alpha: 1.0) // Red #ef4444
        }
    }
}
