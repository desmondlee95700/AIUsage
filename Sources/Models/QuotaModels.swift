import Foundation

// MARK: - AI Provider Enum

public enum AIProvider: String, CaseIterable, Codable, Identifiable {
    case gemini = "gemini"
    case chatgpt = "chatgpt"
    case claude = "claude"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .gemini: return "Antigravity"
        case .chatgpt: return "ChatGPT"
        case .claude: return "Claude"
        }
    }
    
    public var fullName: String {
        switch self {
        case .gemini: return "Antigravity (Google)"
        case .chatgpt: return "ChatGPT (OpenAI)"
        case .claude: return "Claude (Anthropic)"
        }
    }
    
    public var subtitle: String {
        switch self {
        case .gemini: return "Google"
        case .chatgpt: return "OpenAI"
        case .claude: return "Anthropic"
        }
    }
}

// MARK: - Quota Summary Models (Gemini / Antigravity)

public struct QuotaSummaryResponse: Codable {
    public let response: QuotaSummaryData?
}

public struct QuotaSummaryData: Codable {
    public let groups: [QuotaGroup]?
    public let description: String?
    
    /// The group shown in the menu bar: the Gemini models when present, else the first group.
    var primaryGroup: QuotaGroup? {
        groups?.first { $0.displayName.contains("Gemini") } ?? groups?.first
    }
    
    /// The primary group's weekly bucket, matched by window, id or name.
    public var primaryWeeklyBucket: QuotaBucket? {
        primaryGroup?.buckets.first { bucket in
            let window = bucket.window?.lowercased() ?? ""
            let id = bucket.bucketId.lowercased()
            let name = bucket.displayName.lowercased()
            return window == "weekly" || window.contains("week") || id.contains("weekly") || name.contains("week")
        }
    }
    
    /// The primary group's 5-hour bucket, falling back to its first non-weekly bucket.
    public var primary5hBucket: QuotaBucket? {
        let group = primaryGroup
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

    /// The bucket shown in the menu bar: of the primary group's 5-hour and weekly buckets, the one
    /// with the least quota left. Buckets without a reported fraction are skipped, so this is nil
    /// rather than a misleading 0% when there's no data.
    public var bindingBucket: QuotaBucket? {
        [primary5hBucket, primaryWeeklyBucket]
            .compactMap { $0 }
            .filter { $0.remainingFraction != nil }
            .min { ($0.remainingFraction ?? 1) < ($1.remainingFraction ?? 1) }
    }
}

public struct QuotaGroup: Codable, Identifiable {
    public var id: String { displayName }
    public let displayName: String
    public let description: String?
    public let buckets: [QuotaBucket]
}

public struct QuotaBucket: Codable, Identifiable {
    public var id: String { bucketId }
    public let bucketId: String
    public let displayName: String
    public let description: String?
    public let window: String?
    public let remainingFraction: Double?
    public let resetTime: String?
    
    public var percentage: Int {
        guard let fraction = remainingFraction else { return 0 }
        return Int((fraction * 100.0).rounded())
    }
    
    public var formattedPercentage: String {
        guard let fraction = remainingFraction else { return "N/A" }
        let pct = fraction * 100.0
        if pct.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(pct))%"
        } else {
            return String(format: "%.1f%%", pct)
        }
    }
    
    /// Live countdown from the reset time. The server's description is static text, so it's only
    /// used when there's no timestamp to count down to.
    public var formattedResetCountdown: String? {
        if let target = resetDate {
            return DateParsing.countdown(until: target).map { "Resets in \($0)" } ?? "Resets soon"
        }
        if let desc = description, !desc.isEmpty {
            return desc
        }
        return nil
    }
    
    public var resetDate: Date? {
        resetTime.flatMap(DateParsing.iso8601)
    }
}

// MARK: - User Status Models (Gemini / Antigravity)

public struct UserStatusResponse: Codable {
    public let userStatus: UserStatusData?
}

public struct UserStatusData: Codable {
    public let name: String?
    public let email: String?
    public let userTier: UserTier?
    public let planStatus: PlanStatus?
}

public struct UserTier: Codable {
    public let id: String?
    public let name: String?
    public let description: String?
    public let upgradeSubscriptionUri: String?
    public let upgradeSubscriptionText: String?
}

public struct PlanStatus: Codable {
    public let availablePromptCredits: Int?
    public let availableFlowCredits: Int?
}

// MARK: - Codex Models (ChatGPT.app)

public struct CodexAccountResponse: Codable {
    public let account: CodexAccountInfo?
    public let requiresOpenaiAuth: Bool?
    public let workspaceRouting: CodexWorkspaceRouting?
}

public struct CodexAccountInfo: Codable {
    public let type: String?
    public let email: String?
    public let planType: String?
    
    public var formattedPlan: String {
        guard let plan = planType else { return "ChatGPT" }
        switch plan.lowercased() {
        case "free": return "ChatGPT Free"
        case "plus": return "ChatGPT Plus"
        case "pro": return "ChatGPT Pro"
        case "team": return "ChatGPT Team"
        case "business": return "ChatGPT Business"
        case "enterprise": return "ChatGPT Enterprise"
        default: return "ChatGPT (\(plan.capitalized))"
        }
    }
}

public struct CodexWorkspaceRouting: Codable {
    public let chatgptAccountId: String?
    public let backendOrigin: String?
    public let accountRoutingOverride: String?
}

public struct CodexRateLimitsResponse: Codable {
    public let accountId: String?
    public let ordinaryUsageAllowed: Bool?
    public let rateLimits: CodexRateLimitSnapshot?
    public let rateLimitsByLimitId: [String: CodexRateLimitSnapshot]?
    public let rateLimitResetCredits: CodexRateLimitResetCreditsSummary?
}

public struct CodexRateLimitSnapshot: Codable {
    public let limitId: String?
    public let limitName: String?
    public let normalModelSlug: String?
    public let primary: CodexRateLimitWindow?
    public let secondary: CodexRateLimitWindow?
    public let credits: CodexCreditsSnapshot?
    public let planType: String?
    public let spendControlReached: Bool?
    
    /// Weekly limit window (typically 6-10 days, e.g. 10,080 mins / 7 days for ChatGPT Plus)
    public var weeklyWindow: CodexRateLimitWindow? {
        if let p = primary, let mins = p.windowDurationMins, mins >= 6 * 1440 && mins <= 10 * 1440 {
            return p
        }
        if let s = secondary, let mins = s.windowDurationMins, mins >= 6 * 1440 && mins <= 10 * 1440 {
            return s
        }
        return nil
    }
    
    /// Short rolling burst window (typically <= 24 hours, e.g. 5-hour / 300 mins)
    public var rollingShortWindow: CodexRateLimitWindow? {
        if let p = primary, let mins = p.windowDurationMins, mins <= 24 * 60 {
            return p
        }
        if let s = secondary, let mins = s.windowDurationMins, mins <= 24 * 60 {
            return s
        }
        return nil
    }
    
    /// The headline window for alerts and the tooltip: the 5-hour rolling limit, then weekly, then whatever is reported.
    public var activeWindow: CodexRateLimitWindow? {
        rollingShortWindow ?? weeklyWindow ?? primary ?? secondary
    }

    /// The window shown in the menu bar: whichever has the least quota left, since that's the one that
    /// blocks you first. A full 5-hour window with an exhausted weekly limit is still exhausted.
    /// Ties go to the shorter window, which resets sooner.
    public var bindingWindow: CodexRateLimitWindow? {
        [primary, secondary].compactMap { $0 }.min { a, b in
            if a.remainingPercent != b.remainingPercent {
                return a.remainingPercent < b.remainingPercent
            }
            return (a.windowDurationMins ?? .max) < (b.windowDurationMins ?? .max)
        }
    }
    
    /// All active rate limit windows, ordered with shorter rolling window first followed by weekly/longer window
    public var allWindows: [(title: String, window: CodexRateLimitWindow)] {
        var list: [(title: String, window: CodexRateLimitWindow)] = []
        if let p = primary, let s = secondary {
            let pMins = p.windowDurationMins ?? 0
            let sMins = s.windowDurationMins ?? 0
            
            let first = pMins <= sMins ? p : s
            let second = pMins <= sMins ? s : p
            
            let firstTitle = first.windowDisplayName
            var secondTitle = second.windowDisplayName
            if firstTitle == secondTitle {
                secondTitle = "Extended Limit"
            }
            list.append((title: firstTitle, window: first))
            list.append((title: secondTitle, window: second))
        } else if let p = primary {
            list.append((title: p.windowDisplayName, window: p))
        } else if let s = secondary {
            list.append((title: s.windowDisplayName, window: s))
        }
        return list
    }
}

public struct CodexRateLimitWindow: Codable {
    public let usedPercent: Int
    public let windowDurationMins: Int?
    public let resetsAt: Int? // Unix timestamp (seconds)
    
    public var remainingPercent: Int {
        return max(0, min(100, 100 - usedPercent))
    }
    
    public var remainingFraction: Double {
        return Double(remainingPercent) / 100.0
    }
    
    public var windowDisplayName: String {
        guard let mins = windowDurationMins else { return "Model Quota" }
        let days = mins / 1440
        let hours = mins / 60
        
        if days >= 6 && days <= 8 {
            return "Weekly Limit"
        } else if days >= 28 && days <= 31 {
            return "Monthly Limit (30-Day)"
        } else if days > 1 {
            return "\(days)-Day Limit"
        } else if hours > 0 {
            return "Rolling \(hours)-Hour Limit"
        } else {
            return "\(mins)-Minute Limit"
        }
    }
    
    public var formattedDuration: String {
        guard let mins = windowDurationMins else { return "Rolling window" }
        let days = mins / 1440
        let hours = (mins % 1440) / 60
        if days >= 6 && days <= 8 {
            return "7d window"
        } else if days > 0 {
            return "\(days)d window"
        } else if hours > 0 {
            return "\(hours)h window"
        } else {
            return "\(mins)m window"
        }
    }
    
    public var formattedResetCountdown: String? {
        guard let resetDate = resetDate else { return nil }
        return DateParsing.countdown(until: resetDate).map { "Resets in \($0)" } ?? "Resets soon"
    }
    
    public var resetDate: Date? {
        resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }
}

public struct CodexCreditsSnapshot: Codable {
    public let hasCredits: Bool
    public let unlimited: Bool
    public let balance: String?
}

public struct CodexRateLimitResetCreditsSummary: Codable {
    public let availableCount: Int
    public let credits: [CodexRateLimitResetCredit]?
}

public struct CodexRateLimitResetCredit: Codable, Identifiable {
    public var id: String {
        creditId ?? "\(resetType ?? "reset")-\(expiresAt ?? 0)"
    }
    
    public let creditId: String?
    public let resetType: String?
    public let status: String?
    public let grantedAt: Int?
    public let expiresAt: Int?
    
    enum CodingKeys: String, CodingKey {
        case creditId = "creditId"
        case creditIdSnake = "credit_id"
        case id = "id"
        case resetType = "resetType"
        case resetTypeSnake = "reset_type"
        case status = "status"
        case grantedAt = "grantedAt"
        case grantedAtSnake = "granted_at"
        case expiresAt = "expiresAt"
        case expiresAtSnake = "expires_at"
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Each key is tried on its own so a type mismatch on one doesn't discard the fallbacks
        func string(_ key: CodingKeys) -> String? {
            (try? container.decodeIfPresent(String.self, forKey: key)) ?? nil
        }
        self.creditId = string(.creditId) ?? string(.creditIdSnake) ?? string(.id)
        self.resetType = string(.resetType) ?? string(.resetTypeSnake)
        self.status = string(.status)
        
        if let ts = try? container.decodeIfPresent(Int.self, forKey: .grantedAt) {
            self.grantedAt = ts
        } else if let tsSnake = try? container.decodeIfPresent(Int.self, forKey: .grantedAtSnake) {
            self.grantedAt = tsSnake
        } else if let str = try? container.decodeIfPresent(String.self, forKey: .grantedAt), let val = Int(str) {
            self.grantedAt = val
        } else {
            self.grantedAt = nil
        }
        
        if let ts = try? container.decodeIfPresent(Int.self, forKey: .expiresAt) {
            self.expiresAt = ts
        } else if let tsSnake = try? container.decodeIfPresent(Int.self, forKey: .expiresAtSnake) {
            self.expiresAt = tsSnake
        } else if let str = try? container.decodeIfPresent(String.self, forKey: .expiresAt) {
            if let val = Int(str) {
                self.expiresAt = val
            } else {
                if let d = DateParsing.iso8601(str) {
                    self.expiresAt = Int(d.timeIntervalSince1970)
                } else {
                    self.expiresAt = nil
                }
            }
        } else {
            self.expiresAt = nil
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(creditId, forKey: .creditId)
        try container.encodeIfPresent(resetType, forKey: .resetType)
        try container.encodeIfPresent(status, forKey: .status)
        try container.encodeIfPresent(grantedAt, forKey: .grantedAt)
        try container.encodeIfPresent(expiresAt, forKey: .expiresAt)
    }
    
    public var formattedResetType: String {
        guard let rt = resetType, !rt.isEmpty else {
            return "Rate limit reset"
        }
        let lower = rt.lowercased().replacingOccurrences(of: "_", with: "")
        if lower == "codexratelimits" || lower == "codexratelimit" || lower == "codex" || lower == "ratelimits" {
            return "Rate limit reset"
        }
        return rt
    }
    
    public var formattedExpiration: String {
        guard let exp = expiresAt else { return "Ready to use" }
        let date = Date(timeIntervalSince1970: TimeInterval(exp))
        return DateParsing.countdown(until: date).map { "Expires in \($0)" } ?? "Expired"
    }
}

public struct CodexUsageResponse: Codable {
    public let summary: CodexUsageSummary?
    public let dailyUsageBuckets: [CodexDailyUsageBucket]?
}

public struct CodexUsageSummary: Codable {
    public let lifetimeTokens: Int?
    public let peakDailyTokens: Int?
    public let longestStreakDays: Int?
    public let currentStreakDays: Int?
    public let longestRunningTurnSec: Int?
    
    public var formattedLifetimeTokens: String {
        guard let tokens = lifetimeTokens else { return "0" }
        if tokens >= 1_000_000 {
            return String(format: "%.1fM", Double(tokens) / 1_000_000.0)
        } else if tokens >= 1_000 {
            return String(format: "%.1fK", Double(tokens) / 1_000.0)
        }
        return "\(tokens)"
    }
    
    public var formattedPeakTokens: String {
        guard let tokens = peakDailyTokens else { return "0" }
        if tokens >= 1_000_000 {
            return String(format: "%.1fM", Double(tokens) / 1_000_000.0)
        } else if tokens >= 1_000 {
            return String(format: "%.1fK", Double(tokens) / 1_000.0)
        }
        return "\(tokens)"
    }
}

public struct CodexDailyUsageBucket: Codable, Identifiable {
    public var id: String { startDate }
    public let startDate: String
    public let tokens: Int
    
    public var formattedTokens: String {
        if tokens >= 1_000_000 {
            return String(format: "%.1fM", Double(tokens) / 1_000_000.0)
        } else if tokens >= 1_000 {
            return String(format: "%.1fK", Double(tokens) / 1_000.0)
        }
        return "\(tokens)"
    }
}

// MARK: - App Preferences

public enum MenuBarDisplayMode: String, CaseIterable, Codable {
    /// Each selected provider's icon and lowest remaining limit
    case percentages = "Percentages"
    /// Provider icons only, for a quieter or more private menu bar
    case iconOnly = "Icon Only"
    
    public var title: String {
        switch self {
        case .percentages: return "Show Percentages"
        case .iconOnly: return "Icon Only"
        }
    }
    
    /// Reads a saved preference. Values from older versions (the dual, active-provider and
    /// weekly-only modes, which all showed percentages) map to `.percentages`.
    public init(savedValue: String?) {
        self = savedValue == MenuBarDisplayMode.iconOnly.rawValue ? .iconOnly : .percentages
    }
}

public enum RefreshInterval: Int, CaseIterable, Codable {
    case thirtySeconds = 30
    case oneMinute = 60
    case twoMinutes = 120
    case fiveMinutes = 300
    case manual = 0
    
    public var title: String {
        switch self {
        case .thirtySeconds: return "Every 30 seconds"
        case .oneMinute: return "Every 1 minute"
        case .twoMinutes: return "Every 2 minutes"
        case .fiveMinutes: return "Every 5 minutes"
        case .manual: return "Manual only"
        }
    }
}

// MARK: - Claude Models (Anthropic)

public struct ClaudeAccountInfo: Codable, Equatable, Sendable {
    public let accountUuid: String?
    public let emailAddress: String?
    public let displayName: String?
    public let organizationUuid: String?
    public let organizationType: String?
    public let billingType: String?
    public let hasExtraUsageEnabled: Bool?
    public let organizationRateLimitTier: String?
    public let subscriptionCreatedAt: String?
    
    public init(
        accountUuid: String? = nil,
        emailAddress: String? = nil,
        displayName: String? = nil,
        organizationUuid: String? = nil,
        organizationType: String? = nil,
        billingType: String? = nil,
        hasExtraUsageEnabled: Bool? = nil,
        organizationRateLimitTier: String? = nil,
        subscriptionCreatedAt: String? = nil
    ) {
        self.accountUuid = accountUuid
        self.emailAddress = emailAddress
        self.displayName = displayName
        self.organizationUuid = organizationUuid
        self.organizationType = organizationType
        self.billingType = billingType
        self.hasExtraUsageEnabled = hasExtraUsageEnabled
        self.organizationRateLimitTier = organizationRateLimitTier
        self.subscriptionCreatedAt = subscriptionCreatedAt
    }
    
    public var formattedTier: String {
        "Claude \(tierBadge)"
    }

    /// Plan values that mean no subscription, with any "claude_" prefix removed.
    private static let freePlanNames: Set<String> = ["free", "none"]

    /// Short plan name: "Pro", "Max", "Team", "Enterprise" or "Free". Plan strings differ between
    /// claude.ai and Claude Code and gain variants over time (e.g. "claude_max_20x"), so known plans
    /// match by keyword and any other non-free value shows under its own name. Treating unknown
    /// values as Free would hide a paying user's limits behind an upgrade prompt.
    public var tierBadge: String {
        guard var name = organizationType?.lowercased(), !name.isEmpty else { return "Free" }
        if name.hasPrefix("claude_") { name.removeFirst("claude_".count) }
        if Self.freePlanNames.contains(name) { return "Free" }
        if name.contains("enterprise") { return "Enterprise" }
        if name.contains("max") { return "Max" }
        if name.contains("team") || name == "raven" { return "Team" }
        if name.contains("pro") { return "Pro" }
        return name.replacingOccurrences(of: "_", with: " ").capitalized
    }

    /// Paid tiers have 5-hour and weekly usage limits to track. Derived from `tierBadge` so the
    /// two never disagree about which plan values are paid.
    public var canSeeUsageLimits: Bool {
        tierBadge != "Free"
    }
}

public struct ClaudeUsageLimits: Codable, Equatable, Sendable {
    public let fiveHourRemainingPercent: Int
    public let fiveHourUsedPercent: Int
    public let fiveHourResetTime: Date?
    
    public let weeklyRemainingPercent: Int
    public let weeklyUsedPercent: Int
    public let weeklyResetTime: Date?
    
    public let sonnetRemainingPercent: Int?
    public let sonnetResetTime: Date?
    public let opusRemainingPercent: Int?
    public let opusResetTime: Date?
    /// Remaining share of the monthly extra-usage cap; nil when extra usage is off or unreported.
    public let extraUsagePercent: Int?
    
    /// Whether the server reported each window. When false, the matching percentages are placeholders.
    public let hasFiveHourWindow: Bool
    public let hasWeeklyWindow: Bool
    
    public let lastUpdated: Date?
    
    public init(
        fiveHourRemainingPercent: Int,
        fiveHourUsedPercent: Int,
        fiveHourResetTime: Date? = nil,
        weeklyRemainingPercent: Int,
        weeklyUsedPercent: Int,
        weeklyResetTime: Date? = nil,
        sonnetRemainingPercent: Int? = nil,
        sonnetResetTime: Date? = nil,
        opusRemainingPercent: Int? = nil,
        opusResetTime: Date? = nil,
        extraUsagePercent: Int? = nil,
        hasFiveHourWindow: Bool = true,
        hasWeeklyWindow: Bool = true,
        lastUpdated: Date? = nil
    ) {
        self.fiveHourRemainingPercent = fiveHourRemainingPercent
        self.fiveHourUsedPercent = fiveHourUsedPercent
        self.fiveHourResetTime = fiveHourResetTime
        self.weeklyRemainingPercent = weeklyRemainingPercent
        self.weeklyUsedPercent = weeklyUsedPercent
        self.weeklyResetTime = weeklyResetTime
        self.sonnetRemainingPercent = sonnetRemainingPercent
        self.sonnetResetTime = sonnetResetTime
        self.opusRemainingPercent = opusRemainingPercent
        self.opusResetTime = opusResetTime
        self.extraUsagePercent = extraUsagePercent
        self.hasFiveHourWindow = hasFiveHourWindow
        self.hasWeeklyWindow = hasWeeklyWindow
        self.lastUpdated = lastUpdated
    }
    
    /// Remaining 5-hour percentage, or nil when the server didn't report that window.
    public var fiveHourPercent: Int? {
        hasFiveHourWindow ? fiveHourRemainingPercent : nil
    }
    
    /// Remaining weekly percentage, or nil when the server didn't report that window.
    public var weeklyPercent: Int? {
        hasWeeklyWindow ? weeklyRemainingPercent : nil
    }
    
    /// Menu bar percentage: the lower of the 5-hour and weekly windows, since running out of either
    /// blocks you. Model-specific weekly limits (Sonnet, Opus) are left out as they only block one model.
    public var menuBarPercent: Int? {
        [fiveHourPercent, weeklyPercent].compactMap { $0 }.min()
    }

    /// Whether the weekly window, rather than the 5-hour one, is the figure in the menu bar.
    public var isWeeklyBinding: Bool {
        guard let weekly = weeklyPercent else { return false }
        return weekly < (fiveHourPercent ?? 101)
    }
    
    public var formattedFiveHourCountdown: String? {
        guard let reset = fiveHourResetTime else { return "Rolling 5h window" }
        return DateParsing.countdown(until: reset).map { "Resets in \($0)" } ?? "Fully refreshed"
    }
    
    public var formattedWeeklyCountdown: String? {
        guard let reset = weeklyResetTime else { return "Weekly reset" }
        return DateParsing.countdown(until: reset).map { "Resets in \($0)" } ?? "Refreshed"
    }
    
    /// Reset time for a model-specific weekly limit (Sonnet, Opus). These run on their own
    /// schedule, so the all-models weekly reset is only a fallback when the server omits one.
    public func modelResetTime(_ reset: Date?) -> Date? {
        reset ?? weeklyResetTime
    }
    
    public func formattedModelCountdown(_ reset: Date?) -> String? {
        guard let reset = modelResetTime(reset) else { return "Weekly reset" }
        return DateParsing.countdown(until: reset).map { "Resets in \($0)" } ?? "Refreshed"
    }
}
