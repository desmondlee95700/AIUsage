import Foundation

/// Shared, cached date formatters. Formatters are expensive to create, and these were previously
/// rebuilt on every call (several times per refresh and per countdown re-render). Both formatter
/// types are thread-safe for parsing and formatting as long as their options aren't mutated.
enum DateParsing {
    // ISO8601DateFormatter is thread-safe once configured, but not marked Sendable
    nonisolated(unsafe) private static let iso8601Fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    // ISO8601DateFormatter is thread-safe once configured, but not marked Sendable

    nonisolated(unsafe) private static let iso8601Whole = ISO8601DateFormatter()

    /// Parses ISO 8601 timestamps with or without fractional seconds.
    static func iso8601(_ string: String) -> Date? {
        iso8601Fractional.date(from: string) ?? iso8601Whole.date(from: string)
    }

    /// Exact date for tooltips behind relative countdowns, in the user's locale ("Mon 12 Oct, 9:08 AM").
    private static let exactDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE d MMM jmm")
        return formatter
    }()

    static func exact(_ date: Date) -> String {
        exactDate.string(from: date)
    }

    /// Time left until `date` as "2d 3h", "4h 12m", "16m" or "<1m"; nil once it has passed.
    /// Every reset and expiry countdown uses this, so all providers read the same way.
    static func countdown(until date: Date, now: Date = Date()) -> String? {
        let seconds = Int(date.timeIntervalSince(now))
        guard seconds > 0 else { return nil }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3600
        let minutes = (seconds % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return minutes > 0 ? "\(minutes)m" : "<1m"
    }
}
