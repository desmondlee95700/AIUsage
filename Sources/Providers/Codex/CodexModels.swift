import Foundation

// MARK: - Codex Models (ChatGPT.app)

public struct CodexAccountResponse: Codable, Sendable {
    public let account: CodexAccountInfo?
    public let requiresOpenaiAuth: Bool?
    public let workspaceRouting: CodexWorkspaceRouting?
}

public struct CodexAccountInfo: Codable, Sendable {
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

public struct CodexWorkspaceRouting: Codable, Sendable {
    public let chatgptAccountId: String?
    public let backendOrigin: String?
    public let accountRoutingOverride: String?
}

public struct CodexRateLimitsResponse: Codable, Sendable {
    public let accountId: String?
    public let ordinaryUsageAllowed: Bool?
    public let rateLimits: CodexRateLimitSnapshot?
    public let rateLimitsByLimitId: [String: CodexRateLimitSnapshot]?
    public let rateLimitResetCredits: CodexRateLimitResetCreditsSummary?
}

public struct CodexRateLimitSnapshot: Codable, Sendable {
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

public struct CodexRateLimitWindow: Codable, Sendable {
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

public struct CodexCreditsSnapshot: Codable, Sendable {
    public let hasCredits: Bool
    public let unlimited: Bool
    public let balance: String?
}

public struct CodexRateLimitResetCreditsSummary: Codable, Sendable {
    public let availableCount: Int
    public let credits: [CodexRateLimitResetCredit]?
}

public struct CodexRateLimitResetCredit: Codable, Identifiable, Sendable {
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
            (try? container.decodeIfPresent(String.self, forKey: key))
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

public struct CodexUsageResponse: Codable, Sendable {
    public let summary: CodexUsageSummary?
    public let dailyUsageBuckets: [CodexDailyUsageBucket]?
}

public struct CodexUsageSummary: Codable, Sendable {
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

public struct CodexDailyUsageBucket: Codable, Identifiable, Sendable {
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
