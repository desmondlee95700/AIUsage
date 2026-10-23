import Foundation

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
