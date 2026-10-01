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
    @Published public var isClaudeInstalled: Bool = false
    
    public var installedProvidersCount: Int {
        var count = 0
        if isGeminiInstalled { count += 1 }
        if isCodexInstalled { count += 1 }
        if isClaudeInstalled { count += 1 }
        return count
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
    
    // Claude / Anthropic State
    @Published public var isClaudeConnected: Bool = false
    @Published public var claudeAccount: ClaudeAccountInfo? = nil
    @Published public var claudeLimits: ClaudeUsageLimits? = nil
    @Published public var claudeErrorMessage: String? = nil
    
    // Backward compatibility property for isConnected (checks current provider)
    public var isConnected: Bool {
        switch activeProvider {
        case .gemini: return isGeminiConnected
        case .chatgpt: return isCodexConnected
        case .claude: return isClaudeConnected
        }
    }
    
    public var errorMessage: String? {
        switch activeProvider {
        case .gemini: return geminiErrorMessage
        case .chatgpt: return codexErrorMessage
        case .claude: return claudeErrorMessage
        }
    }
    
    // Codex Reset State
    @Published public var isConsumingReset: Bool = false
    @Published public var resetActionMessage: String? = nil
    @Published public var resetActionIsSuccess: Bool = false
    
    // Low Quota Spending Alert Tracking (tracks 30% and 10% thresholds per provider)
    private var alertedThresholds: [String: Set<Int>] = [:]
    
    // MARK: - Selected Providers (Multi-Choice Provider Focus)
    @Published public var selectedProviders: Set<AIProvider> {
        didSet {
            let stringArray = selectedProviders.map { $0.rawValue }
            UserDefaults.standard.set(stringArray, forKey: "selectedProviders")
            updateMenuBarCallback?()
            onFocusModeChanged?()
        }
    }
    
    public var selectedInstalledProviders: [AIProvider] {
        var list: [AIProvider] = []
        if isGeminiInstalled && selectedProviders.contains(.gemini) { list.append(.gemini) }
        if isCodexInstalled && selectedProviders.contains(.chatgpt) { list.append(.chatgpt) }
        if isClaudeInstalled && selectedProviders.contains(.claude) { list.append(.claude) }
        return list
    }
    
    public var selectedProvidersCount: Int {
        selectedInstalledProviders.count
    }
    
    public var isAllProvidersSelected: Bool {
        let installed = installedProvidersCount
        return installed > 0 && selectedInstalledProviders.count == installed
    }
    
    public func isProviderSelected(_ provider: AIProvider) -> Bool {
        selectedProviders.contains(provider)
    }
    
    public func toggleProviderSelection(_ provider: AIProvider) {
        if selectedProviders.contains(provider) {
            // Keep at least one provider selected
            if selectedInstalledProviders.count > 1 {
                selectedProviders.remove(provider)
                if dualActiveProvider == provider, let first = selectedInstalledProviders.first {
                    dualActiveProvider = first
                }
            }
        } else {
            selectedProviders.insert(provider)
            dualActiveProvider = provider
        }
    }
    
    public func selectOnlyProvider(_ provider: AIProvider) {
        selectedProviders = [provider]
        dualActiveProvider = provider
    }
    
    public func selectAllProviders() {
        var all = Set<AIProvider>()
        if isGeminiInstalled { all.insert(.gemini) }
        if isCodexInstalled { all.insert(.chatgpt) }
        if isClaudeInstalled { all.insert(.claude) }
        if !all.isEmpty {
            selectedProviders = all
        }
    }
    
    public func isProviderConnected(_ provider: AIProvider) -> Bool {
        switch provider {
        case .gemini: return isGeminiConnected
        case .chatgpt: return isCodexConnected
        case .claude: return isClaudeConnected
        }
    }
    
    public var selectedProvidersSummary: String {
        let list = selectedInstalledProviders
        if list.isEmpty { return "None" }
        if list.count == installedProvidersCount && installedProvidersCount > 1 {
            return "All Providers"
        }
        if list.count == 1 {
            return list[0].fullName
        }
        return list.map { $0.displayName }.joined(separator: " · ")
    }
    
    // Provider Focus Mode compatibility bridge
    public var providerFocusMode: ProviderFocusMode {
        get {
            if isAllProvidersSelected {
                return .both
            }
            if selectedInstalledProviders.count == 1, let single = selectedInstalledProviders.first {
                switch single {
                case .gemini: return .gemini
                case .chatgpt: return .chatgpt
                case .claude: return .claude
                }
            }
            return .both
        }
        set {
            switch newValue {
            case .both: selectAllProviders()
            case .gemini: selectOnlyProvider(.gemini)
            case .chatgpt: selectOnlyProvider(.chatgpt)
            case .claude: selectOnlyProvider(.claude)
            }
        }
    }
    
    // Active provider within Multi-Provider segmented view
    @Published public var dualActiveProvider: AIProvider = .gemini
    
    public func cycleDualActiveProvider() {
        let activeProviders = selectedInstalledProviders
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
        let claudeInst = ClaudeDiscovery.isClaudeInstalled
        self.isGeminiInstalled = geminiInst
        self.isCodexInstalled = codexInst
        self.isClaudeInstalled = claudeInst
        
        let savedProvider = UserDefaults.standard.string(forKey: "activeProvider")
        var provider = AIProvider(rawValue: savedProvider ?? "") ?? .gemini
        if provider == .gemini && !geminiInst {
            if codexInst { provider = .chatgpt }
            else if claudeInst { provider = .claude }
        } else if provider == .chatgpt && !codexInst {
            if geminiInst { provider = .gemini }
            else if claudeInst { provider = .claude }
        } else if provider == .claude && !claudeInst {
            if geminiInst { provider = .gemini }
            else if codexInst { provider = .chatgpt }
        }
        self.activeProvider = provider
        
        // Multi-choice selected providers initialization
        var initialSelected = Set<AIProvider>()
        if let savedArray = UserDefaults.standard.stringArray(forKey: "selectedProviders"), !savedArray.isEmpty {
            for raw in savedArray {
                if let p = AIProvider(rawValue: raw) {
                    if (p == .gemini && geminiInst) ||
                       (p == .chatgpt && codexInst) ||
                       (p == .claude && claudeInst) {
                        initialSelected.insert(p)
                    }
                }
            }
        } else {
            let savedFocus = UserDefaults.standard.string(forKey: "providerFocusMode")
            if savedFocus == "gemini" && geminiInst {
                initialSelected.insert(.gemini)
            } else if savedFocus == "chatgpt" && codexInst {
                initialSelected.insert(.chatgpt)
            } else if savedFocus == "claude" && claudeInst {
                initialSelected.insert(.claude)
            }
        }
        if initialSelected.isEmpty {
            if geminiInst { initialSelected.insert(.gemini) }
            if codexInst { initialSelected.insert(.chatgpt) }
            if claudeInst { initialSelected.insert(.claude) }
        }
        self.selectedProviders = initialSelected
        
        if let first = initialSelected.first {
            self.dualActiveProvider = first
        }
        
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
        let totalInstalled = (geminiInst ? 1 : 0) + (codexInst ? 1 : 0) + (claudeInst ? 1 : 0)
        if mode == .dual && totalInstalled < 2 {
            mode = .activeProvider
        }
        self.displayMode = mode
        
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
        let claudeInst = ClaudeDiscovery.isClaudeInstalled
        
        DispatchQueue.main.async {
            self.isLoading = true
            self.isGeminiInstalled = geminiInst
            self.isCodexInstalled = codexInst
            self.isClaudeInstalled = claudeInst
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
        
        // 3. Refresh Claude (Anthropic) if installed
        if claudeInst {
            dispatchGroup.enter()
            refreshClaude {
                dispatchGroup.leave()
            }
        } else {
            DispatchQueue.main.async {
                self.isClaudeConnected = false
                self.claudeErrorMessage = "Claude is not installed."
            }
        }
        
        dispatchGroup.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            self.isLoading = false
            self.lastUpdated = Date()
            self.updateMenuBarCallback?()
            self.checkLowQuotaNotifications()
        }
    }
    
    // MARK: - Low Quota Spending Alerts
    
    private func checkLowQuotaNotifications() {
        // 1. ChatGPT (OpenAI)
        if isCodexConnected {
            if let remaining = codex5hPercentage ?? (codexActiveWindow != nil ? codexRemainingPercentage : nil) {
                evaluateQuotaAlert(provider: "ChatGPT", remainingPercent: remaining)
            }
        }
        
        // 2. Antigravity (Google)
        if isGeminiConnected {
            let remaining = primary5hBucket?.percentage ?? primaryWeeklyBucket?.percentage ?? geminiPercentage
            evaluateQuotaAlert(provider: "Antigravity", remainingPercent: remaining)
        }
        
        // 3. Claude (Anthropic)
        if isClaudeConnected {
            // Only alert when numerical quota limits are available (Pro / Team tiers)
            if let remaining = claude5hPercentage ?? claudeWeeklyPercentage {
                evaluateQuotaAlert(provider: "Claude", remainingPercent: remaining)
            }
        }
    }
    
    private func evaluateQuotaAlert(provider: String, remainingPercent: Int) {
        guard remainingPercent >= 0 else { return }
        
        var fired = alertedThresholds[provider] ?? []
        
        // Threshold 1: <= 10% (Critical warning)
        if remainingPercent <= 10 {
            if !fired.contains(10) {
                NotificationManager.shared.sendLowQuotaNotification(
                    provider: provider,
                    remainingQuota: "\(remainingPercent)%"
                )
                fired.insert(10)
                fired.insert(30) // Mark 30% as also triggered if it dropped rapidly
                alertedThresholds[provider] = fired
            }
        }
        // Threshold 2: <= 30% (Early warning)
        else if remainingPercent <= 30 {
            if !fired.contains(30) {
                NotificationManager.shared.sendLowQuotaNotification(
                    provider: provider,
                    remainingQuota: "\(remainingPercent)%"
                )
                fired.insert(30)
                alertedThresholds[provider] = fired
            }
            // If quota is between 11% and 30%, rearm 10% in case it drops further
            if fired.contains(10) {
                fired.remove(10)
                alertedThresholds[provider] = fired
            }
        }
        // Quota has recovered or reset (> 30%)
        else {
            // Rearm both 30% and 10% alerts for next cycle
            if !fired.isEmpty {
                alertedThresholds[provider] = []
            }
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
    
    // MARK: - Claude / Anthropic Refresh Pipeline
    
    private func refreshClaude(completion: @escaping () -> Void) {
        ClaudeService.shared.usagePollInterval = TimeInterval(refreshInterval.rawValue)
        ClaudeService.shared.fetch { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else {
                    completion()
                    return
                }
                switch result {
                case .success(let payload):
                    self.isClaudeConnected = true
                    self.claudeAccount = payload.account
                    self.claudeLimits = payload.limits
                    self.claudeErrorMessage = nil
                case .failure(let err):
                    self.isClaudeConnected = false
                    self.claudeErrorMessage = err.localizedDescription
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
    
    // MARK: - Claude Helpers
    
    public var claudePercentage: Int? {
        claudeLimits?.fiveHourRemainingPercent ?? claudeLimits?.weeklyRemainingPercent
    }
    
    public var claudeWeeklyPercentage: Int? {
        claudeLimits?.weeklyRemainingPercent
    }
    
    public var claude5hPercentage: Int? {
        claudeLimits?.fiveHourRemainingPercent
    }
    
    // MARK: - Menu Bar Formatter Helpers
    
    public var menuBarTitle: String {
        let providers = selectedInstalledProviders
        guard !providers.isEmpty else { return " No AI Tools" }
        
        if displayMode == .iconOnly { return "" }
        
        var parts: [String] = []
        for p in providers {
            switch p {
            case .gemini:
                parts.append(isGeminiConnected ? "\(geminiPercentage)%" : "Off")
            case .chatgpt:
                parts.append(isCodexConnected ? "\(codexRemainingPercentage)%" : "Off")
            case .claude:
                if isClaudeConnected {
                    parts.append(claudePercentage != nil ? "\(claudePercentage!)%" : (claudeAccount?.tierBadge ?? "Free"))
                } else {
                    parts.append("Off")
                }
            }
        }
        return " " + parts.joined(separator: " · ")
    }
    
    public var menuBarTooltip: String {
        var lines: [String] = ["AIUsage \(AppVersion.displayString) — AI Model Quota Tracker"]
        
        let providers = selectedInstalledProviders
        
        if providers.contains(.gemini) {
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
        
        if providers.contains(.chatgpt) {
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
        
        if providers.contains(.claude) {
            if isClaudeConnected {
                let tier = claudeAccount?.formattedTier ?? "Connected"
                if let limits = claudeLimits {
                    let fiveH = limits.formattedFiveHourCountdown ?? "Full Quota"
                    let weekly = limits.formattedWeeklyCountdown ?? "Full Quota"
                    lines.append("• Claude (Anthropic): 5h: \(limits.fiveHourRemainingPercent)% (\(fiveH)) · Weekly: \(limits.weeklyRemainingPercent)% (\(weekly)) (\(tier))")
                } else {
                    lines.append("• Claude (Anthropic): Dynamic Free Tier (\(tier))")
                }
            } else {
                lines.append("• Claude (Anthropic): Offline (Launch Claude.app)")
            }
        }
        
        if providers.isEmpty {
            lines.append("• No AI providers selected")
        } else {
            lines.append("Click to switch views or right-click for quick actions")
        }
        return lines.joined(separator: "\n")
    }
    
    public var statusTintColor: NSColor {
        let activePercentages: [Int] = selectedInstalledProviders.compactMap { provider in
            switch provider {
            case .gemini: return isGeminiConnected ? geminiPercentage : nil
            case .chatgpt: return isCodexConnected ? codexRemainingPercentage : nil
            case .claude: return isClaudeConnected ? (claudePercentage ?? 100) : nil
            }
        }
        
        guard let minPct = activePercentages.min() else {
            return .secondaryLabelColor
        }
        
        if minPct >= 50 {
            return NSColor(red: 0.13, green: 0.77, blue: 0.36, alpha: 1.0) // Green #22c55e
        } else if minPct >= 20 {
            return NSColor(red: 0.96, green: 0.62, blue: 0.04, alpha: 1.0) // Orange #f59e0b
        } else {
            return NSColor(red: 0.94, green: 0.27, blue: 0.27, alpha: 1.0) // Red #ef4444
        }
    }
}
