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
    
    // Installation Status
    @Published public var isGeminiInstalled: Bool = false
    @Published public var isCodexInstalled: Bool = false
    
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
        case .claude: return false
        }
    }
    
    public var errorMessage: String? {
        switch activeProvider {
        case .gemini: return geminiErrorMessage
        case .chatgpt: return codexErrorMessage
        case .claude: return "Claude (Anthropic) support coming soon."
        }
    }
    
    // Codex Reset State
    @Published public var isConsumingReset: Bool = false
    @Published public var resetActionMessage: String? = nil
    @Published public var resetActionIsSuccess: Bool = false
    
    // Provider Focus Mode (Syncs Popover & Menu Bar)
    @Published public var providerFocusMode: ProviderFocusMode {
        didSet {
            UserDefaults.standard.set(providerFocusMode.rawValue, forKey: "providerFocusMode")
            updateMenuBarCallback?()
        }
    }
    
    // Active provider within Multi-Provider (Both) view
    @Published public var dualActiveProvider: AIProvider = .gemini
    
    public func cycleDualActiveProvider() {
        let activeProviders: [AIProvider] = {
            var list: [AIProvider] = []
            if isGeminiInstalled { list.append(.gemini) }
            if isCodexInstalled { list.append(.chatgpt) }
            return list
        }()
        guard !activeProviders.isEmpty else { return }
        if let index = activeProviders.firstIndex(of: dualActiveProvider) {
            let nextIndex = (index + 1) % activeProviders.count
            dualActiveProvider = activeProviders[nextIndex]
        } else {
            dualActiveProvider = activeProviders[0]
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
    public var onFocusModeChanged: (() -> Void)?
    
    private var timer: Timer?
    private let session: URLSession
    
    public init() {
        let geminiInst = ProcessDiscovery.isAntigravityInstalled
        let codexInst = CodexDiscovery.isCodexInstalled
        self.isGeminiInstalled = geminiInst
        self.isCodexInstalled = codexInst
        
        let savedProvider = UserDefaults.standard.string(forKey: "activeProvider")
        var provider = AIProvider(rawValue: savedProvider ?? "") ?? .gemini
        if !geminiInst && codexInst {
            provider = .chatgpt
        } else if geminiInst && !codexInst {
            provider = .gemini
        }
        self.activeProvider = provider
        
        let savedMode = UserDefaults.standard.string(forKey: "menuBarDisplayMode")
        var mode: MenuBarDisplayMode
        if savedMode == "Dual: ✦ Gemini · ✷ ChatGPT" || savedMode == "Dual (Antigravity & ChatGPT)" {
            mode = .dual
        } else if savedMode == "Active Provider Quota" || savedMode == "Active Provider Only" {
            mode = .activeProvider
        } else if savedMode == "Gemini Weekly Only" || savedMode == "Antigravity Weekly Only" {
            mode = .weekly
        } else {
            mode = MenuBarDisplayMode(rawValue: savedMode ?? "") ?? .dual
        }
        if mode == .dual && (!geminiInst || !codexInst) {
            mode = .activeProvider
        }
        self.displayMode = mode
        
        let savedFocus = UserDefaults.standard.string(forKey: "providerFocusMode")
        var focus: ProviderFocusMode
        if let f = ProviderFocusMode(rawValue: savedFocus ?? "") {
            focus = f
        } else {
            if mode == .dual {
                focus = .both
            } else if provider == .chatgpt {
                focus = .chatgpt
            } else {
                focus = .gemini
            }
        }
        if focus == .both && (!geminiInst || !codexInst) {
            focus = codexInst ? .chatgpt : .gemini
        }
        self.providerFocusMode = focus
        
        let savedInterval = UserDefaults.standard.integer(forKey: "refreshInterval")
        self.refreshInterval = RefreshInterval(rawValue: savedInterval == 0 ? 60 : savedInterval) ?? .oneMinute
        
        self.session = URLSession(configuration: .ephemeral, delegate: InsecureTrustDelegate.shared, delegateQueue: nil)
        
        restartTimer()
    }
    
    public func setFocusMode(_ mode: ProviderFocusMode) {
        self.providerFocusMode = mode
        switch mode {
        case .gemini:
            self.activeProvider = .gemini
            self.displayMode = .activeProvider
            self.dualActiveProvider = .gemini
        case .chatgpt:
            self.activeProvider = .chatgpt
            self.displayMode = .activeProvider
            self.dualActiveProvider = .chatgpt
        case .claude:
            self.activeProvider = .claude
            self.displayMode = .activeProvider
            self.dualActiveProvider = .claude
        case .both:
            self.displayMode = .dual
        }
        updateMenuBarCallback?()
        onFocusModeChanged?()
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
        
        let geminiInst = ProcessDiscovery.isAntigravityInstalled
        let codexInst = CodexDiscovery.isCodexInstalled
        
        DispatchQueue.main.async {
            self.isLoading = true
            self.isGeminiInstalled = geminiInst
            self.isCodexInstalled = codexInst
        }
        
        let dispatchGroup = DispatchGroup()
        
        // 1. Refresh Gemini (Antigravity) if installed
        if geminiInst {
            dispatchGroup.enter()
            refreshGemini(forceDiscovery: forceDiscovery) {
                dispatchGroup.leave()
            }
        } else {
            DispatchQueue.main.async {
                self.isGeminiConnected = false
                self.discoveredServer = nil
                self.geminiErrorMessage = "Antigravity is not installed."
            }
        }
        
        // 2. Refresh ChatGPT (Codex) if installed
        if codexInst {
            dispatchGroup.enter()
            refreshCodex {
                dispatchGroup.leave()
            }
        } else {
            DispatchQueue.main.async {
                self.isCodexConnected = false
                self.codexErrorMessage = "ChatGPT / Codex is not installed."
            }
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
    
    public func consumeCodexReset(completion: ((Bool, String) -> Void)? = nil) {
        guard !isConsumingReset else { return }
        isConsumingReset = true
        resetActionMessage = nil
        
        CodexService.shared.consumeResetCredit { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isConsumingReset = false
                
                switch result {
                case .success(let outcome):
                    self.resetActionIsSuccess = outcome.isSuccess
                    self.resetActionMessage = outcome.userMessage
                    if outcome.isSuccess {
                        self.refreshCodex {
                            self.updateMenuBarCallback?()
                        }
                    }
                    completion?(outcome.isSuccess, outcome.userMessage)
                case .failure(let error):
                    self.resetActionIsSuccess = false
                    self.resetActionMessage = error.localizedDescription
                    completion?(false, error.localizedDescription)
                }
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
        return group?.buckets.first { bucket in
            let window = bucket.window?.lowercased() ?? ""
            let id = bucket.bucketId.lowercased()
            let name = bucket.displayName.lowercased()
            return window == "weekly" || window.contains("week") || id.contains("weekly") || name.contains("week")
        }
    }
    
    public var primary5hBucket: QuotaBucket? {
        guard let groups = quotaSummary?.groups else { return nil }
        let group = groups.first { $0.displayName.contains("Gemini") } ?? groups.first
        return group?.buckets.first { bucket in
            let window = bucket.window?.lowercased() ?? ""
            let id = bucket.bucketId.lowercased()
            let name = bucket.displayName.lowercased()
            return window == "5h" ||
                   window.contains("5h") ||
                   id.contains("5h") ||
                   name.contains("5h") ||
                   name.contains("5 hour") ||
                   name.contains("5-hour") ||
                   window.contains("hour")
        } ?? group?.buckets.first { $0.window != "weekly" && !$0.bucketId.contains("weekly") }
    }
    
    /// Returns Antigravity quota percentage (prioritizes 5-hour limit on the menu bar)
    public var geminiPercentage: Int {
        (primary5hBucket ?? primaryWeeklyBucket)?.percentage ?? 0
    }
    
    public var geminiWeeklyPercentage: Int {
        primaryWeeklyBucket?.percentage ?? 0
    }
    
    public var gemini5hPercentage: Int {
        primary5hBucket?.percentage ?? geminiPercentage
    }
    
    public var codexSnapshot: CodexRateLimitSnapshot? {
        codexRateLimits?.rateLimits
    }
    
    public var codexPrimaryWindow: CodexRateLimitWindow? {
        codexSnapshot?.primary
    }
    
    public var codexSecondaryWindow: CodexRateLimitWindow? {
        codexSnapshot?.secondary
    }
    
    public var codexWeeklyWindow: CodexRateLimitWindow? {
        codexSnapshot?.weeklyWindow
    }
    
    public var codex5hWindow: CodexRateLimitWindow? {
        codexSnapshot?.rollingShortWindow
    }
    
    /// The active window for menu bar display (prioritizes 5h rolling limit, then weekly limit, then primary)
    public var codexActiveWindow: CodexRateLimitWindow? {
        if let short = codex5hWindow {
            return short
        }
        if let weekly = codexWeeklyWindow {
            return weekly
        }
        return codexPrimaryWindow ?? codexSecondaryWindow
    }
    
    public var codexRemainingPercentage: Int {
        codexActiveWindow?.remainingPercent ?? 0
    }
    
    public var codexWeeklyPercentage: Int? {
        codexWeeklyWindow?.remainingPercent
    }
    
    public var codex5hPercentage: Int? {
        codex5hWindow?.remainingPercent
    }
    
    public var codexUsedPercentage: Int {
        codexActiveWindow?.usedPercent ?? 0
    }
    
    // MARK: - Menu Bar Formatter Helpers
    
    public var menuBarTitle: String {
        let geminiStr = isGeminiConnected ? "\(geminiPercentage)%" : "Offline"
        let codexStr = isCodexConnected ? "\(codexRemainingPercentage)%" : "Offline"
        
        switch displayMode {
        case .dual:
            if !isGeminiInstalled && !isCodexInstalled {
                return " No AI Tools"
            }
            if isGeminiInstalled && !isCodexInstalled {
                return isGeminiConnected ? " \(geminiStr)" : " Offline"
            }
            if !isGeminiInstalled && isCodexInstalled {
                return isCodexConnected ? " \(codexStr)" : " Offline"
            }
            if !isGeminiConnected && !isCodexConnected {
                return " Offline"
            }
            return " \(geminiStr) · \(codexStr)"
            
        case .activeProvider:
            switch activeProvider {
            case .gemini:
                guard isGeminiInstalled else { return isCodexConnected ? " \(codexStr)" : " Offline" }
                return isGeminiConnected ? " \(geminiPercentage)%" : " Offline"
            case .chatgpt:
                guard isCodexInstalled else { return isGeminiConnected ? " \(geminiStr)" : " Offline" }
                return isCodexConnected ? " \(codexRemainingPercentage)%" : " Offline"
            case .claude:
                return " Claude"
            }
            
        case .weekly:
            return isGeminiConnected ? " \(geminiPercentage)%" : " Antigravity Offline"
            
        case .iconOnly:
            return ""
        }
    }
    
    public var menuBarTooltip: String {
        var lines: [String] = ["AIUsage \(AppVersion.displayString) — AI Model Quota Tracker"]
        
        let showGemini = (providerFocusMode == .gemini || providerFocusMode == .both) && isGeminiInstalled
        let showCodex = (providerFocusMode == .chatgpt || providerFocusMode == .both) && isCodexInstalled
        
        if showGemini {
            if isGeminiConnected {
                let tier = userStatus?.userTier?.name ?? "Connected"
                let bucket = primary5hBucket ?? primaryWeeklyBucket
                let reset = bucket?.formattedResetCountdown ?? "Active"
                let windowDesc = (primary5hBucket != nil) ? "5h limit" : "Weekly"
                lines.append("• Antigravity (Google): \(geminiPercentage)% (\(windowDesc)) remaining (\(tier)) · \(reset)")
            } else {
                lines.append("• Antigravity (Google): Offline (Launch Antigravity)")
            }
        }
        
        if showCodex {
            if isCodexConnected {
                let plan = codexAccount?.formattedPlan ?? "Connected"
                if let short = codex5hWindow, let weekly = codexWeeklyWindow {
                    let shortReset = short.formattedResetCountdown ?? "Active"
                    let weeklyReset = weekly.formattedResetCountdown ?? "Active"
                    lines.append("• ChatGPT (OpenAI): 5h: \(short.remainingPercent)% (\(shortReset)) · Weekly: \(weekly.remainingPercent)% (\(weeklyReset)) (\(plan))")
                } else if let active = codexActiveWindow {
                    let reset = active.formattedResetCountdown ?? "Active"
                    let desc = active.windowDisplayName
                    lines.append("• ChatGPT (OpenAI): \(active.remainingPercent)% (\(desc)) remaining (\(plan)) · \(reset)")
                } else {
                    lines.append("• ChatGPT (OpenAI): \(codexRemainingPercentage)% remaining (\(plan))")
                }
            } else {
                lines.append("• ChatGPT (OpenAI): Offline (Launch ChatGPT.app)")
            }
        }
        
        if !isGeminiInstalled && !isCodexInstalled {
            lines.append("• No supported AI models installed")
        } else {
            lines.append("Click to switch views or right-click for quick actions")
        }
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
