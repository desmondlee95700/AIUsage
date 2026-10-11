import Foundation
import SwiftUI
import Combine

/// Owns all provider state shown in the UI. Main-actor isolated: published state only changes on
/// the main thread, and blocking work (subprocesses, discovery) runs off it via `runBlocking`.
@MainActor
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
    
    // Local token activity (Claude Code / Codex session logs, desktop app and CLI)
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
            Task { @MainActor in
                self?.refreshIfStale(minAge: interval / 2)
            }
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
        // Don't drop requests that arrive mid-refresh (e.g. a provider was just
        // enabled): queue one follow-up that runs when the current refresh ends.
        guard !isLoading else {
            pendingRefreshForceDiscovery = (pendingRefreshForceDiscovery ?? false) || forceDiscovery
            return
        }
        isLoading = true
        
        Task {
            await performRefresh(forceDiscovery: forceDiscovery)
        }
    }
    
    private func performRefresh(forceDiscovery: Bool) async {
        // Installation checks can spawn `ps` and walk app bundles, so keep them off the main thread
        let (geminiInst, codexInst, claudeInst) = await runBlocking {
            (ProcessDiscovery.isAntigravityInstalled, CodexDiscovery.isCodexInstalled, ClaudeDiscovery.isClaudeInstalled)
        }
        isGeminiInstalled = geminiInst
        isCodexInstalled = codexInst
        isClaudeInstalled = claudeInst
        
        let geminiActive = geminiInst && selectedProviders.contains(.gemini)
        let codexActive = codexInst && selectedProviders.contains(.chatgpt)
        let claudeActive = claudeInst && selectedProviders.contains(.claude)
        
        if !geminiActive {
            isGeminiConnected = false
            discoveredServer = nil
            if !geminiInst {
                geminiErrorMessage = "Antigravity is not installed."
            }
        }
        if !codexActive {
            isCodexConnected = false
            if !codexInst {
                codexErrorMessage = "ChatGPT / Codex is not installed."
            }
        }
        if !claudeActive {
            isClaudeConnected = false
            if !claudeInst {
                claudeErrorMessage = "Claude is not installed."
            }
        }
        
        // Token activity comes from local session logs, so it's independent of connection
        // state and doesn't hold up the refresh
        refreshTokenActivity(codex: codexActive, claude: claudeActive)
        
        // Providers are independent, so fetch them concurrently. Each child hops back to the
        // main actor to publish its results.
        await withTaskGroup(of: Void.self) { group in
            if geminiActive {
                group.addTask { await self.refreshGemini(forceDiscovery: forceDiscovery) }
            }
            if codexActive {
                group.addTask { await self.refreshCodex() }
            }
            if claudeActive {
                group.addTask { await self.refreshClaude(forceRefresh: forceDiscovery) }
            }
        }
        
        isLoading = false
        lastUpdated = Date()
        updateMenuBarCallback?()
        checkLowQuotaNotifications()
        
        if let pendingForce = pendingRefreshForceDiscovery {
            pendingRefreshForceDiscovery = nil
            refresh(forceDiscovery: pendingForce)
        }
    }
    
    // MARK: - Token Activity
    
    private func refreshTokenActivity(codex: Bool, claude: Bool) {
        if codex {
            Task {
                let summary = await TokenActivityService.shared.loadCodex()
                if codexActivity != summary { codexActivity = summary }
            }
        }
        if claude {
            Task {
                let summary = await TokenActivityService.shared.loadClaude()
                if claudeActivity != summary { claudeActivity = summary }
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
    
    private func refreshGemini(forceDiscovery: Bool) async {
        guard let server = await runBlocking({ ProcessDiscovery.discover(forceRefresh: forceDiscovery) }) else {
            isGeminiConnected = false
            discoveredServer = nil
            geminiErrorMessage = "Antigravity is not running. Launch Antigravity to monitor Gemini quotas."
            return
        }
        
        // The user tier is optional extra detail, so its failure doesn't fail the refresh
        async let status: UserStatusResponse? = try? antigravityCall("GetUserStatus", server: server)
        do {
            let summary: QuotaSummaryResponse = try await antigravityCall("RetrieveUserQuotaSummary", server: server)
            guard let quota = summary.response else { throw URLError(.cannotParseResponse) }
            isGeminiConnected = true
            discoveredServer = server
            quotaSummary = quota
            userStatus = await status?.userStatus
            geminiErrorMessage = nil
        } catch {
            // The cached server isn't health-checked before use, so a failure may just mean
            // Antigravity restarted on a new port. Rediscover once before reporting an error.
            if !forceDiscovery {
                ProcessDiscovery.invalidateCache()
                await refreshGemini(forceDiscovery: true)
                return
            }
            isGeminiConnected = false
            geminiErrorMessage = error.localizedDescription
        }
    }
    
    // MARK: - Codex / ChatGPT Refresh Pipeline
    
    private func refreshCodex() async {
        do {
            let payload = try await CodexService.shared.fetch()
            isCodexConnected = true
            codexRateLimits = payload.rateLimits
            codexAccount = payload.account
            codexUsage = payload.usage
            codexErrorMessage = nil
        } catch {
            isCodexConnected = false
            codexErrorMessage = error.localizedDescription
        }
    }
    
    // MARK: - Claude / Anthropic Refresh Pipeline
    
    private func refreshClaude(forceRefresh: Bool = false) async {
        let pollInterval = TimeInterval(refreshInterval.rawValue)
        do {
            let payload = try await ClaudeService.shared.fetch(forceRefresh: forceRefresh, pollInterval: pollInterval)
            isClaudeConnected = true
            claudeAccount = payload.account
            claudeLimits = payload.limits
            claudeErrorMessage = nil
        } catch {
            isClaudeConnected = false
            claudeErrorMessage = error.localizedDescription
        }
    }
    
    public func consumeCodexReset(completion: ((Bool, String) -> Void)? = nil) {
        guard !isConsumingReset else { return }
        isConsumingReset = true
        resetActionMessage = nil
        
        Task {
            do {
                let outcome = try await CodexService.shared.consumeResetCredit()
                isConsumingReset = false
                resetActionIsSuccess = outcome.isSuccess
                resetActionMessage = outcome.userMessage
                completion?(outcome.isSuccess, outcome.userMessage)
                if outcome.isSuccess {
                    await refreshCodex()
                    updateMenuBarCallback?()
                }
            } catch {
                isConsumingReset = false
                resetActionIsSuccess = false
                resetActionMessage = error.localizedDescription
                completion?(false, error.localizedDescription)
            }
        }
    }
    
    // MARK: - Antigravity Connect-RPC
    
    /// POSTs an empty request to a LanguageServerService method on the local Antigravity server.
    private func antigravityCall<T: Decodable>(_ method: String, server: DiscoveredServer) async throws -> T {
        guard let url = URL(string: "https://127.0.0.1:\(server.port)/exa.language_server_pb.LanguageServerService/\(method)") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(server.csrfToken, forHTTPHeaderField: "X-Codeium-Csrf-Token")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.httpBody = Data("{}".utf8)
        request.timeoutInterval = 4.0
        
        let (data, _) = try await session.data(for: request)
        return try JSONDecoder().decode(T.self, from: data)
    }
    
    // MARK: - Computed Properties for Helpers
    
    public var primaryWeeklyBucket: QuotaBucket? {
        quotaSummary?.primaryWeeklyBucket
    }
    
    public var primary5hBucket: QuotaBucket? {
        quotaSummary?.primary5hBucket
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
        codexSnapshot?.activeWindow
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
        claudeLimits?.menuBarPercent
    }
    
    public var claudeWeeklyPercentage: Int? {
        claudeLimits?.weeklyPercent
    }
    
    public var claude5hPercentage: Int? {
        claudeLimits?.fiveHourPercent
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
