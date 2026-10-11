import Foundation
import SwiftUI
import Combine

public class QuotaService: ObservableObject {
    public static let shared = QuotaService()
    
    // Installation Status
    @Published public var isGeminiInstalled: Bool = false
    @Published public var isCodexInstalled: Bool = false
    @Published public var isClaudeInstalled: Bool = false
    
    public var installedProviders: [AIProvider] {
        var list: [AIProvider] = []
        if isGeminiInstalled { list.append(.gemini) }
        if isCodexInstalled { list.append(.chatgpt) }
        if isClaudeInstalled { list.append(.claude) }
        return list
    }
    
    public var installedProvidersCount: Int {
        installedProviders.count
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
    
    // Local token activity (Claude Code / Codex CLI session logs)
    @Published public var claudeActivity: TokenActivitySummary? = nil
    @Published public var codexActivity: TokenActivitySummary? = nil
    
    // Codex Reset State
    @Published public var isConsumingReset: Bool = false
    @Published public var resetActionMessage: String? = nil
    @Published public var resetActionIsSuccess: Bool = false
    
    // Low Quota Alert Tracking (tracks 30% and 10% thresholds per provider upon active quota drop)
    private var alertTracker = QuotaAlertTracker()
    
    // MARK: - Selected Providers (Multi-Choice Provider Focus)
    @Published public var selectedProviders: Set<AIProvider> {
        didSet {
            let stringArray = selectedProviders.map { $0.rawValue }
            UserDefaults.standard.set(stringArray, forKey: "selectedProviders")
            if !selectedProviders.contains(.gemini) {
                isGeminiConnected = false
                discoveredServer = nil
            }
            if !selectedProviders.contains(.chatgpt) {
                isCodexConnected = false
            }
            if !selectedProviders.contains(.claude) {
                isClaudeConnected = false
            }
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
            refresh()
        }
    }
    
    public func selectOnlyProvider(_ provider: AIProvider) {
        selectedProviders = [provider]
        dualActiveProvider = provider
        refresh()
    }
    
    public func selectAllProviders() {
        var all = Set<AIProvider>()
        if isGeminiInstalled { all.insert(.gemini) }
        if isCodexInstalled { all.insert(.chatgpt) }
        if isClaudeInstalled { all.insert(.claude) }
        if !all.isEmpty {
            selectedProviders = all
            if !all.contains(dualActiveProvider), let first = selectedInstalledProviders.first {
                dualActiveProvider = first
            }
            refresh()
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
    
    // Active provider within Multi-Provider segmented view
    @Published public var dualActiveProvider: AIProvider = .gemini
    
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
    /// A refresh requested while another was in flight; replayed when that one finishes.
    /// The value is whether any of the dropped requests asked for forced discovery.
    private var pendingRefreshForceDiscovery: Bool?
    
    public init() {
        let geminiInst = ProcessDiscovery.isAntigravityInstalled
        let codexInst = CodexDiscovery.isCodexInstalled
        let claudeInst = ClaudeDiscovery.isClaudeInstalled
        self.isGeminiInstalled = geminiInst
        self.isCodexInstalled = codexInst
        self.isClaudeInstalled = claudeInst
    
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
        
        // Sets are unordered; pick in canonical order so the popover opens consistently
        if let first = AIProvider.allCases.first(where: { initialSelected.contains($0) }) {
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
        
        // 0 is a real value (.manual), so distinguish "never saved" from "saved as 0"
        if UserDefaults.standard.object(forKey: "refreshInterval") != nil {
            let savedInterval = UserDefaults.standard.integer(forKey: "refreshInterval")
            self.refreshInterval = RefreshInterval(rawValue: savedInterval) ?? .oneMinute
        } else {
            self.refreshInterval = .oneMinute
        }
        
        self.session = URLSession(configuration: .ephemeral, delegate: InsecureTrustDelegate.shared, delegateQueue: nil)
        
        restartTimer()
    }
    
    public func restartTimer() {
        timer?.invalidate()
        timer = nil
        
        guard refreshInterval.rawValue > 0 else { return }
        
        let interval = TimeInterval(refreshInterval.rawValue)
        // A tick right after a popover-open refresh would repeat the same work, so skip it
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.refreshIfStale(minAge: interval / 2)
        }
        // Lets macOS coalesce our wakeups with other timers
        timer?.tolerance = interval * 0.1
    }
    
    /// Refreshes unless the last refresh finished less than `minAge` seconds ago. Used for
    /// automatic triggers (timer ticks, popover opens); explicit user actions call `refresh`.
    public func refreshIfStale(minAge: TimeInterval = 15) {
        if let last = lastUpdated, Date().timeIntervalSince(last) < minAge { return }
        refresh()
    }
    
    public func refresh(forceDiscovery: Bool = false) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.refresh(forceDiscovery: forceDiscovery) }
            return
        }
        
        // Don't drop requests that arrive mid-refresh (e.g. a provider was just
        // enabled): queue one follow-up that runs when the current refresh ends.
        guard !isLoading else {
            pendingRefreshForceDiscovery = (pendingRefreshForceDiscovery ?? false) || forceDiscovery
            return
        }
        isLoading = true
        
        // Installation checks can spawn `ps` and walk app bundles, so keep them off the main thread
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let geminiInst = ProcessDiscovery.isAntigravityInstalled
            let codexInst = CodexDiscovery.isCodexInstalled
            let claudeInst = ClaudeDiscovery.isClaudeInstalled
            DispatchQueue.main.async {
                self?.performRefresh(
                    forceDiscovery: forceDiscovery,
                    geminiInst: geminiInst,
                    codexInst: codexInst,
                    claudeInst: claudeInst
                )
            }
        }
    }
    
    private func performRefresh(forceDiscovery: Bool, geminiInst: Bool, codexInst: Bool, claudeInst: Bool) {
        isGeminiInstalled = geminiInst
        isCodexInstalled = codexInst
        isClaudeInstalled = claudeInst
        
        let dispatchGroup = DispatchGroup()
        
        // 1. Refresh Gemini (Antigravity) if installed and selected
        if geminiInst && selectedProviders.contains(.gemini) {
            dispatchGroup.enter()
            refreshGemini(forceDiscovery: forceDiscovery) {
                dispatchGroup.leave()
            }
        } else {
            isGeminiConnected = false
            discoveredServer = nil
            if !geminiInst {
                geminiErrorMessage = "Antigravity is not installed."
            }
        }
        
        // 2. Refresh ChatGPT (Codex) if installed and selected
        if codexInst && selectedProviders.contains(.chatgpt) {
            dispatchGroup.enter()
            refreshCodex {
                dispatchGroup.leave()
            }
        } else {
            isCodexConnected = false
            if !codexInst {
                codexErrorMessage = "ChatGPT / Codex is not installed."
            }
        }
        
        // Token activity comes from local session logs, so it's independent of connection
        // state and doesn't hold up the refresh
        refreshTokenActivity(codex: codexInst && selectedProviders.contains(.chatgpt),
                             claude: claudeInst && selectedProviders.contains(.claude))
        
        // 3. Refresh Claude (Anthropic) if installed and selected
        if claudeInst && selectedProviders.contains(.claude) {
            dispatchGroup.enter()
            refreshClaude(forceRefresh: forceDiscovery) {
                dispatchGroup.leave()
            }
        } else {
            isClaudeConnected = false
            if !claudeInst {
                claudeErrorMessage = "Claude is not installed."
            }
        }
        
        dispatchGroup.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            self.isLoading = false
            self.lastUpdated = Date()
            self.updateMenuBarCallback?()
            self.checkLowQuotaNotifications()
            
            if let pendingForce = self.pendingRefreshForceDiscovery {
                self.pendingRefreshForceDiscovery = nil
                self.refresh(forceDiscovery: pendingForce)
            }
        }
    }
    
    // MARK: - Token Activity
    
    private func refreshTokenActivity(codex: Bool, claude: Bool) {
        if codex {
            TokenActivityService.shared.loadCodex { [weak self] summary in
                if self?.codexActivity != summary { self?.codexActivity = summary }
            }
        }
        if claude {
            TokenActivityService.shared.loadClaude { [weak self] summary in
                if self?.claudeActivity != summary { self?.claudeActivity = summary }
            }
        }
    }
    
    // MARK: - Low Quota Spending Alerts
    
    private func checkLowQuotaNotifications() {
        // 1. ChatGPT (OpenAI)
        if isCodexConnected && selectedProviders.contains(.chatgpt) {
            if let short = codex5hWindow {
                evaluateQuotaAlert(provider: "ChatGPT", windowName: "5-hour limit", keySuffix: "5h", remainingPercent: short.remainingPercent)
            } else if let active = codexActiveWindow {
                evaluateQuotaAlert(provider: "ChatGPT", windowName: active.windowDisplayName.lowercased(), keySuffix: "active", remainingPercent: active.remainingPercent)
            }
        }
        
        // 2. Antigravity (Google) — inspect all groups including Gemini Models and Claude/GPT models
        if isGeminiConnected && selectedProviders.contains(.gemini) {
            if let groups = quotaSummary?.groups, !groups.isEmpty {
                for group in groups {
                    let groupName = group.displayName
                    for bucket in group.buckets {
                        if let fraction = bucket.remainingFraction {
                            let pct = Int((fraction * 100.0).rounded())
                            let windowDesc = bucket.window ?? (bucket.bucketId.contains("5h") ? "5-hour limit" : "weekly limit")
                            let key = "\(groupName)-\(bucket.bucketId)"
                            evaluateQuotaAlert(
                                provider: "Antigravity",
                                windowName: "\(groupName) \(windowDesc)",
                                keySuffix: key,
                                remainingPercent: pct
                            )
                        }
                    }
                }
            } else {
                if let bucket5h = primary5hBucket {
                    evaluateQuotaAlert(provider: "Antigravity", windowName: "5-hour limit", keySuffix: "5h", remainingPercent: bucket5h.percentage)
                }
                if let bucketWeekly = primaryWeeklyBucket {
                    evaluateQuotaAlert(provider: "Antigravity", windowName: "weekly limit", keySuffix: "weekly", remainingPercent: bucketWeekly.percentage)
                }
            }
        }
        
        // 3. Claude (Anthropic)
        if isClaudeConnected && selectedProviders.contains(.claude) {
            if let fiveHour = claude5hPercentage {
                evaluateQuotaAlert(provider: "Claude", windowName: "5-hour limit", keySuffix: "5h", remainingPercent: fiveHour)
            }
            if let weekly = claudeWeeklyPercentage {
                evaluateQuotaAlert(provider: "Claude", windowName: "weekly limit", keySuffix: "weekly", remainingPercent: weekly)
            }
        }
        
        // Mark baselines as initialized so subsequent refreshes only alert upon active quota drop
        alertTracker.finishBaseline()
    }
    
    private func evaluateQuotaAlert(provider: String, windowName: String? = nil, keySuffix: String = "", remainingPercent: Int) {
        let alertKey = keySuffix.isEmpty ? provider : "\(provider)-\(keySuffix)"
        guard alertTracker.shouldAlert(key: alertKey, remainingPercent: remainingPercent) else { return }
        NotificationManager.shared.sendLowQuotaNotification(
            provider: provider,
            remainingQuota: "\(remainingPercent)%",
            window: windowName
        )
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
                // The cached server isn't health-checked before use, so a failure may just mean
                // Antigravity restarted on a new port. Rediscover once before reporting an error.
                if fetchedQuota == nil && !forceDiscovery {
                    ProcessDiscovery.invalidateCache()
                    self.refreshGemini(forceDiscovery: true, completion: completion)
                    return
                }
    
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
    
    private func refreshClaude(forceRefresh: Bool = false, completion: @escaping () -> Void) {
        let pollInterval = TimeInterval(refreshInterval.rawValue)
        ClaudeService.shared.fetch(forceRefresh: forceRefresh, pollInterval: pollInterval) { [weak self] result in
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
    
    // MARK: - Claude Helpers
    
    /// Menu bar percentage for Claude: the 5-hour window when reported, else the weekly one.
    public var claudePercentage: Int? {
        claude5hPercentage ?? claudeWeeklyPercentage
    }
    
    public var claudeWeeklyPercentage: Int? {
        guard let limits = claudeLimits, limits.hasWeeklyWindow else { return nil }
        return limits.weeklyRemainingPercent
    }
    
    public var claude5hPercentage: Int? {
        guard let limits = claudeLimits, limits.hasFiveHourWindow else { return nil }
        return limits.fiveHourRemainingPercent
    }
    
    // MARK: - Menu Bar Formatter Helpers
    
    /// Short status for a provider as shown in the menu bar and provider tabs: "42%", "Off", or a tier badge.
    public func badgeText(for provider: AIProvider) -> String {
        switch provider {
        case .gemini:
            return isGeminiConnected ? "\(geminiPercentage)%" : "Off"
        case .chatgpt:
            return isCodexConnected ? "\(codexRemainingPercentage)%" : "Off"
        case .claude:
            guard isClaudeConnected else { return "Off" }
            if let pct = claudePercentage {
                return "\(pct)%"
            }
            return claudeAccount?.tierBadge ?? "Free"
        }
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
                    var parts: [String] = []
                    if let fiveH = claude5hPercentage {
                        parts.append("5h: \(fiveH)% (\(limits.formattedFiveHourCountdown ?? "Full Quota"))")
                    }
                    if let weekly = claudeWeeklyPercentage {
                        parts.append("Weekly: \(weekly)% (\(limits.formattedWeeklyCountdown ?? "Full Quota"))")
                    }
                    lines.append("• Claude (Anthropic): \(parts.joined(separator: " · ")) (\(tier))")
                } else if claudeAccount?.canSeeUsageLimits == true {
                    lines.append("• Claude (Anthropic): Usage unavailable (\(tier))")
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
}
