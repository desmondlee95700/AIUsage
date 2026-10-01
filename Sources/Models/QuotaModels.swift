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
    
    public var symbolIcon: String {
        switch self {
        case .gemini: return "sparkles"
        case .chatgpt: return "circle.hexagongrid"
        case .claude: return "asterisk"
        }
    }
    
    public var badgeGlyph: String {
        switch self {
        case .gemini: return "✦"
        case .chatgpt: return "✷"
        case .claude: return "✽"
        }
    }
}

// MARK: - Provider Focus Mode (Syncs Popover & Menu Bar)

public enum ProviderFocusMode: String, CaseIterable, Codable, Identifiable {
    case gemini = "gemini"
    case chatgpt = "chatgpt"
    case claude = "claude"
    case both = "both"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .gemini: return "Antigravity (Google)"
        case .chatgpt: return "ChatGPT (OpenAI)"
        case .claude: return "Claude (Anthropic)"
        case .both: return "All Providers"
        }
    }
    
    public var shortName: String {
        switch self {
        case .gemini: return "Antigravity"
        case .chatgpt: return "ChatGPT"
        case .claude: return "Claude"
        case .both: return "All"
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
    
    public var formattedResetCountdown: String? {
        if let desc = description, !desc.isEmpty {
            return desc
        }
        guard let resetTime = resetTime else { return nil }
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var targetDate = formatter.date(from: resetTime)
        if targetDate == nil {
            formatter.formatOptions = [.withInternetDateTime]
            targetDate = formatter.date(from: resetTime)
        }
        
        guard let target = targetDate else { return nil }
        let diff = target.timeIntervalSince(Date())
        if diff <= 0 {
            return "Refreshes soon"
        }
        
        let hours = Int(diff) / 3600
        let minutes = (Int(diff) % 3600) / 60
        let days = hours / 24
        let remainingHours = hours % 24
        
        if days > 0 {
            return "Fully refreshes in \(days)d \(remainingHours)h"
        } else if hours > 0 {
            return "Fully refreshes in \(hours)h \(minutes)m"
        } else {
            return "Fully refreshes in \(minutes)m"
        }
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
        guard let timestamp = resetsAt else { return nil }
        let resetDate = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let diff = resetDate.timeIntervalSince(Date())
        if diff <= 0 {
            return "Refreshes soon"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d MMM yyyy 'at' h:mm a"
        return "Resets \(formatter.string(from: resetDate))"
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
        self.creditId = try? container.decodeIfPresent(String.self, forKey: .creditId)
            ?? container.decodeIfPresent(String.self, forKey: .creditIdSnake)
            ?? container.decodeIfPresent(String.self, forKey: .id)
        self.resetType = try? container.decodeIfPresent(String.self, forKey: .resetType)
            ?? container.decodeIfPresent(String.self, forKey: .resetTypeSnake)
        self.status = try? container.decodeIfPresent(String.self, forKey: .status)
        
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
                let isoFormatter = ISO8601DateFormatter()
                if let d = isoFormatter.date(from: str) {
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
            return "Resets Available"
        }
        let lower = rt.lowercased().replacingOccurrences(of: "_", with: "")
        if lower == "codexratelimits" || lower == "codexratelimit" || lower == "codex" || lower == "ratelimits" {
            return "Resets Available"
        }
        return rt
    }
    
    public var formattedExpiration: String {
        guard let exp = expiresAt else { return "Ready to use" }
        let date = Date(timeIntervalSince1970: TimeInterval(exp))
        let now = Date()
        let diff = date.timeIntervalSince(now)
        if diff <= 0 {
            return "Expired"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d MMM yyyy 'at' h:mm a"
        let dateStr = formatter.string(from: date)
        return "Resets \(dateStr)"
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
    case dual = "Dual (Antigravity & ChatGPT)"
    case activeProvider = "Active Provider Only"
    case weekly = "Antigravity Weekly Only"
    case iconOnly = "Icon Only"
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

public struct ClaudeAccountInfo: Codable, Equatable {
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
        guard let type = organizationType?.lowercased() else {
            return "Claude Free"
        }
        switch type {
        case "claude_pro", "pro":
            return "Claude Pro"
        case "claude_max", "max":
            return "Claude Max"
        case "raven":
            return "Claude Team"
        case "enterprise":
            return "Claude Enterprise"
        case "free":
            return "Claude Free"
        default:
            return "Claude (\(type.capitalized))"
        }
    }
    
    public var tierBadge: String {
        guard let type = organizationType?.lowercased() else {
            return "Free"
        }
        switch type {
        case "claude_pro", "pro": return "Pro"
        case "claude_max", "max": return "Max"
        case "raven": return "Team"
        case "enterprise": return "Enterprise"
        default: return "Free"
        }
    }
    
    /// Checks which Claude tier has access to dedicated usage limits tracking
    public var canSeeUsageLimits: Bool {
        guard let type = organizationType?.lowercased() else { return false }
        return type == "claude_pro" || type == "pro" || type == "raven" || type == "claude_max" || type == "enterprise"
    }
    
    public var tierDescription: String {
        if canSeeUsageLimits {
            return "Includes dedicated 5-hour rolling session and weekly model quota tracking."
        } else {
            return "Free tier has dynamic server-capacity cooldowns. Upgrade to Claude Pro for full quota limits."
        }
    }
}

public struct ClaudeUsageLimits: Codable, Equatable {
    public let fiveHourRemainingPercent: Int
    public let fiveHourUsedPercent: Int
    public let fiveHourResetTime: Date?
    
    public let weeklyRemainingPercent: Int
    public let weeklyUsedPercent: Int
    public let weeklyResetTime: Date?
    
    public let sonnetRemainingPercent: Int?
    public let opusRemainingPercent: Int?
    public let extraUsagePercent: Int?
    
    public let lastUpdated: Date?
    
    public init(
        fiveHourRemainingPercent: Int,
        fiveHourUsedPercent: Int,
        fiveHourResetTime: Date? = nil,
        weeklyRemainingPercent: Int,
        weeklyUsedPercent: Int,
        weeklyResetTime: Date? = nil,
        sonnetRemainingPercent: Int? = nil,
        opusRemainingPercent: Int? = nil,
        extraUsagePercent: Int? = nil,
        lastUpdated: Date? = nil
    ) {
        self.fiveHourRemainingPercent = fiveHourRemainingPercent
        self.fiveHourUsedPercent = fiveHourUsedPercent
        self.fiveHourResetTime = fiveHourResetTime
        self.weeklyRemainingPercent = weeklyRemainingPercent
        self.weeklyUsedPercent = weeklyUsedPercent
        self.weeklyResetTime = weeklyResetTime
        self.sonnetRemainingPercent = sonnetRemainingPercent
        self.opusRemainingPercent = opusRemainingPercent
        self.extraUsagePercent = extraUsagePercent
        self.lastUpdated = lastUpdated
    }
    
    public var formattedFiveHourCountdown: String? {
        guard let reset = fiveHourResetTime else { return "Rolling 5h window" }
        let diff = reset.timeIntervalSince(Date())
        if diff <= 0 { return "Fully refreshed" }
        let hours = Int(diff) / 3600
        let minutes = (Int(diff) % 3600) / 60
        if hours > 0 {
            return "Resets in \(hours)h \(minutes)m"
        } else {
            return "Resets in \(minutes)m"
        }
    }
    
    public var formattedWeeklyCountdown: String? {
        guard let reset = weeklyResetTime else { return "Weekly reset" }
        let diff = reset.timeIntervalSince(Date())
        if diff <= 0 { return "Refreshed" }
        let days = Int(diff) / 86400
        let hours = (Int(diff) % 86400) / 3600
        if days > 0 {
            return "Resets in \(days)d \(hours)h"
        } else {
            return "Resets in \(hours)h"
        }
    }
}
