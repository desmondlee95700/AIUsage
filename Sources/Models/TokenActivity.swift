import Foundation

/// Token counts for one request or an aggregate of many. Input is split so cache reads,
/// which are billed far below fresh input, never inflate the headline total.
public struct TokenUsage: Equatable, Sendable {
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

public struct DailyTokenActivity: Equatable, Identifiable, Sendable {
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

public struct TokenActivitySummary: Equatable, Sendable {
    /// Oldest first, one entry per day (zero-filled), ending today
    public let days: [DailyTokenActivity]
    /// Yesterday's usage up to the same time of day as now, so a partly-used today is compared fairly
    public let yesterdaySoFar: TokenUsage

    public init(days: [DailyTokenActivity], yesterdaySoFar: TokenUsage = TokenUsage()) {
        self.days = days
        self.yesterdaySoFar = yesterdaySoFar
    }

    public var today: TokenUsage { days.last?.usage ?? TokenUsage() }
    public var periodTotal: TokenUsage { days.reduce(TokenUsage()) { $0 + $1.usage } }
    public var peakDayTotal: Int { days.map(\.usage.total).max() ?? 0 }
    public var isEmpty: Bool { days.allSatisfy { $0.usage.total == 0 && $0.usage.cacheRead == 0 } }

    /// The most recent `count` days (ending today)
    public func lastDays(_ count: Int) -> TokenActivitySummary {
        TokenActivitySummary(days: Array(days.suffix(count)), yesterdaySoFar: yesterdaySoFar)
    }

    /// Today's tokens against yesterday at the same time, e.g. "↓45% vs yesterday" or "↑2.3× vs yesterday".
    /// Nil when yesterday had nothing by now, since any percentage would be meaningless.
    public var todayVsYesterday: String? {
        let current = today.total
        let baseline = yesterdaySoFar.total
        guard baseline > 0 else { return nil }
        let ratio = Double(current) / Double(baseline)
        if abs(ratio - 1) < 0.01 { return "Same as yesterday" }
        let percent = Int((abs(ratio - 1) * 100).rounded())
        // Big jumps read better as a multiple than as "+640%"; switch as soon as the percentage
        // would reach 100, so "↑100%" never shows next to "↑2.0×"
        if ratio > 1 && percent >= 100 { return String(format: "↑%.1f× vs yesterday", ratio) }
        return "\(ratio > 1 ? "↑" : "↓")\(percent)% vs yesterday"
    }
    
    /// Buckets per-request usage into local days, zero-filling the last `dayCount` days.
    public static func build(
        from entries: [(timestamp: Date, usage: TokenUsage)],
        dayCount: Int = 30,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> TokenActivitySummary {
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let sameTimeYesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        var buckets: [Date: TokenUsage] = [:]
        var yesterdaySoFar = TokenUsage()
        for entry in entries {
            buckets[calendar.startOfDay(for: entry.timestamp), default: TokenUsage()] += entry.usage
            if entry.timestamp >= yesterday && entry.timestamp <= sameTimeYesterday {
                yesterdaySoFar += entry.usage
            }
        }
        let days = (0..<dayCount).reversed().compactMap { offset -> DailyTokenActivity? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return DailyTokenActivity(day: day, usage: buckets[day] ?? TokenUsage())
        }
        return TokenActivitySummary(days: days, yesterdaySoFar: yesterdaySoFar)
    }

    public static func formatTokens(_ tokens: Int) -> String {
        let value = Double(tokens)
        if tokens >= 1_000_000_000 { return String(format: "%.1fB", value / 1_000_000_000) }
        if tokens >= 1_000_000 { return String(format: "%.1fM", value / 1_000_000) }
        if tokens >= 1_000 { return String(format: "%.1fK", value / 1_000) }
        return "\(tokens)"
    }
}
