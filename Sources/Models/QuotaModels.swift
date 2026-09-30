import Foundation

// MARK: - Quota Summary Models

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

// MARK: - User Status Models

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

// MARK: - App Preferences

public enum MenuBarDisplayMode: String, CaseIterable, Codable {
    case weekly = "Weekly Quota (e.g. 71%)"
    case weeklyAnd5h = "Weekly & 5h (e.g. 71% · 100%)"
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
