import Foundation

/// Token counts for one request or an aggregate of many. Input is split so cache reads,
/// which are billed far below fresh input, never inflate the headline total.
public struct TokenUsage: Equatable {
    public var input: Int = 0        // fresh, uncached input
    public var cacheRead: Int = 0
    public var cacheWrite: Int = 0
    public var output: Int = 0

    public init(input: Int = 0, cacheRead: Int = 0, cacheWrite: Int = 0, output: Int = 0) {
        self.input = input
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
        self.output = output
    }

    /// Tokens processed excluding cache reads
    public var total: Int { input + cacheWrite + output }

    public static func + (lhs: TokenUsage, rhs: TokenUsage) -> TokenUsage {
        TokenUsage(
            input: lhs.input + rhs.input,
            cacheRead: lhs.cacheRead + rhs.cacheRead,
            cacheWrite: lhs.cacheWrite + rhs.cacheWrite,
            output: lhs.output + rhs.output
        )
    }

    public static func += (lhs: inout TokenUsage, rhs: TokenUsage) {
        lhs = lhs + rhs
    }
}

public struct DailyTokenActivity: Equatable, Identifiable {
    /// Start of the local calendar day
    public let day: Date
    public let usage: TokenUsage
    public var id: Date { day }
}

/// Periods the activity card can show; logs are always loaded for the longest one.
public enum TokenActivityRange: Int, CaseIterable, Identifiable {
    case week = 7
    case fortnight = 14
    case month = 30
    
    public var id: Int { rawValue }
    public var shortLabel: String { "\(rawValue)D" }
    
    public static let storageKey = "tokenActivityRangeDays"
    public static var longest: TokenActivityRange { .month }
}

public struct TokenActivitySummary: Equatable {
    /// Oldest first, one entry per day (zero-filled), ending today
    public let days: [DailyTokenActivity]

    public var today: TokenUsage { days.last?.usage ?? TokenUsage() }
    public var periodTotal: TokenUsage { days.reduce(TokenUsage()) { $0 + $1.usage } }
    public var peakDayTotal: Int { days.map(\.usage.total).max() ?? 0 }
    public var isEmpty: Bool { days.allSatisfy { $0.usage.total == 0 && $0.usage.cacheRead == 0 } }

    /// The most recent `count` days (ending today)
    public func lastDays(_ count: Int) -> TokenActivitySummary {
        TokenActivitySummary(days: Array(days.suffix(count)))
    }
    
    /// Buckets per-request usage into local days, zero-filling the last `dayCount` days.
    public static func build(
        from entries: [(timestamp: Date, usage: TokenUsage)],
        dayCount: Int = 30,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> TokenActivitySummary {
        let today = calendar.startOfDay(for: now)
        var buckets: [Date: TokenUsage] = [:]
        for entry in entries {
            buckets[calendar.startOfDay(for: entry.timestamp), default: TokenUsage()] += entry.usage
        }
        let days = (0..<dayCount).reversed().compactMap { offset -> DailyTokenActivity? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return DailyTokenActivity(day: day, usage: buckets[day] ?? TokenUsage())
        }
        return TokenActivitySummary(days: days)
    }

    public static func formatTokens(_ tokens: Int) -> String {
        let value = Double(tokens)
        if tokens >= 1_000_000_000 { return String(format: "%.1fB", value / 1_000_000_000) }
        if tokens >= 1_000_000 { return String(format: "%.1fM", value / 1_000_000) }
        if tokens >= 1_000 { return String(format: "%.1fK", value / 1_000) }
        return "\(tokens)"
    }
}
