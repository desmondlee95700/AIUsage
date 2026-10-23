import Foundation

// MARK: - Quota Summary Models (Gemini / Antigravity)

public struct QuotaSummaryResponse: Codable, Sendable {
    public let response: QuotaSummaryData?
}

public struct QuotaSummaryData: Codable, Sendable {
    public let groups: [QuotaGroup]?
    public let description: String?
    
    /// The group shown in the menu bar: the Gemini models when present, else the first group.
    var primaryGroup: QuotaGroup? {
        groups?.first { $0.displayName.contains("Gemini") } ?? groups?.first
    }
    
    /// The primary group's weekly bucket, matched by window, id or name.
    public var primaryWeeklyBucket: QuotaBucket? {
        primaryGroup?.buckets.first(where: \.isWeekly)
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
        } ?? group?.buckets.first { !$0.isWeekly }
    }

    /// The bucket shown in the menu bar: of the primary group's 5-hour and weekly buckets, the one
    /// with the least quota left. Buckets without a reported fraction are skipped, so this is nil
    /// rather than a misleading 0% when there's no data.
    public var bindingBucket: QuotaBucket? {
        [primary5hBucket, primaryWeeklyBucket].compactMap { $0 }.lowestRemaining
    }
}

extension Sequence where Element == QuotaBucket {
    /// The bucket with the least quota left, skipping buckets that report no fraction.
    public var lowestRemaining: QuotaBucket? {
        filter { $0.remainingFraction != nil }
            .min { ($0.remainingFraction ?? 1) < ($1.remainingFraction ?? 1) }
    }
}

public struct QuotaGroup: Codable, Identifiable, Sendable {
    public var id: String { displayName }
    public let displayName: String
    public let description: String?
    public let buckets: [QuotaBucket]
}

public struct QuotaBucket: Codable, Identifiable, Sendable {
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
    
    /// Weekly window, matched case-insensitively by window, id or name. Shared by the weekly
    /// lookup and the 5-hour fallback so the two can never pick the same bucket.
    public var isWeekly: Bool {
        let window = self.window?.lowercased() ?? ""
        return window.contains("week") || bucketId.lowercased().contains("weekly") || displayName.lowercased().contains("week")
    }
}

// MARK: - User Status Models (Gemini / Antigravity)

public struct UserStatusResponse: Codable, Sendable {
    public let userStatus: UserStatusData?
}

public struct UserStatusData: Codable, Sendable {
    public let name: String?
    public let email: String?
    public let userTier: UserTier?
    public let planStatus: PlanStatus?
}

public struct UserTier: Codable, Sendable {
    public let id: String?
    public let name: String?
    public let description: String?
    public let upgradeSubscriptionUri: String?
    public let upgradeSubscriptionText: String?
}

public struct PlanStatus: Codable, Sendable {
    public let availablePromptCredits: Int?
    public let availableFlowCredits: Int?
}
