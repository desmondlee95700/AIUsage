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

    /// Free limit resets the account can still use (claude.ai's "Limit resets").
    public let resetGrants: [ClaudeResetGrant]
    /// Model with its own weekly allowance ("Fable"), named in reset descriptions.
    public let scopedModelName: String?

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
        resetGrants: [ClaudeResetGrant] = [],
        scopedModelName: String? = nil,
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
        self.resetGrants = resetGrants
        self.scopedModelName = scopedModelName
        self.lastUpdated = lastUpdated
    }

    /// Resets that are left and haven't expired, soonest expiry first.
    public func availableResets(now: Date = Date()) -> [ClaudeResetGrant] {
        resetGrants
            .filter { $0.resetsLeft > 0 && ($0.expiresAt.map { $0 > now } ?? true) }
            .sorted { ($0.expiresAt ?? .distantFuture) < ($1.expiresAt ?? .distantFuture) }
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

/// A free limit reset from claude.ai's "Limit resets" list, reported in the usage payload's
/// `cedar_ember` block when it's requested with `?cedar_ember=1`.
public struct ClaudeResetGrant: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    /// Server description, e.g. "One full limit reset (November 2026)".
    public let label: String
    public let resetsLeft: Int
    public let expiresAt: Date?
    /// Limits this reset refills: "five_hour", "seven_day", "seven_day_overage_included" (the model allowance).
    public let clears: [String]
    /// Returns what the scoped model used to the weekly limit, without resetting the whole week.
    public let givesBackWeekly: Bool
    public let usableNow: Bool
    /// Why it can't be used now, e.g. "cooldown", "blocked_seven_day", "needs_limit".
    public let unavailableReason: String?
    
    public init(
        id: String,
        label: String = "",
        resetsLeft: Int = 1,
        expiresAt: Date? = nil,
        clears: [String] = [],
        givesBackWeekly: Bool = false,
        usableNow: Bool = true,
        unavailableReason: String? = nil
    ) {
        self.id = id
        self.label = label
        self.resetsLeft = resetsLeft
        self.expiresAt = expiresAt
        self.clears = clears
        self.givesBackWeekly = givesBackWeekly
        self.usableNow = usableNow
        self.unavailableReason = unavailableReason
    }
    
    /// Refills the weekly limit as well as the 5-hour one.
    public var isFullReset: Bool {
        clears.contains("seven_day")
    }
    
    public func title(scopedModel: String?) -> String {
        if isFullReset { return "Full reset" }
        if givesBackWeekly || clears.contains("seven_day_overage_included") {
            return "\(scopedModel ?? "Model") reset"
        }
        return clears == ["five_hour"] ? "5-hour reset" : "Limit reset"
    }
    
    /// What using it does, in a sentence.
    public func summary(scopedModel: String?) -> String {
        if isFullReset { return "Refills your 5-hour and weekly limits." }
        let model = scopedModel ?? "model"
        if givesBackWeekly {
            return "Refills your 5-hour limit and \(model) allowance, and returns what \(model) used of your weekly limit. Your week doesn't reset."
        }
        if clears.contains("seven_day_overage_included") {
            return "Refills your 5-hour limit and \(model) allowance."
        }
        return "Refills your 5-hour limit."
    }
    
    public var formattedExpiration: String {
        guard let expiresAt = expiresAt else { return "No expiry" }
        return DateParsing.countdown(until: expiresAt).map { "Expires in \($0)" } ?? "Expired"
    }
    
    /// Why the reset can't be used right now, or nil when it can.
    public var unavailableMessage: String? {
        guard !usableNow else { return nil }
        switch unavailableReason {
        case "cooldown": return "Cooling down after a recent reset"
        case "blocked_five_hour": return "Usable once your 5-hour limit resets"
        case "blocked_seven_day": return "Usable once your weekly limit resets"
        case "blocked_opus": return "Usable once your Opus limit resets"
        case "blocked_sonnet": return "Usable once your Sonnet limit resets"
        case "needs_limit": return "Usable once you hit a limit"
        case "cannot_clear": return "Nothing for it to refill right now"
        default: return "Not available right now"
        }
    }
}
