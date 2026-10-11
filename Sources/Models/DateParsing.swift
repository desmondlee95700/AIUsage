import Foundation

/// Shared, cached date formatters. Formatters are expensive to create, and these were previously
/// rebuilt on every call (several times per refresh and per countdown re-render). Both formatter
/// types are thread-safe for parsing and formatting as long as their options aren't mutated.
enum DateParsing {
    private static let iso8601Fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601Whole = ISO8601DateFormatter()

    /// Parses ISO 8601 timestamps with or without fractional seconds.
    static func iso8601(_ string: String) -> Date? {
        iso8601Fractional.date(from: string) ?? iso8601Whole.date(from: string)
    }

    /// "3 Oct 2026 at 4:00 PM", used for Codex reset and credit expiry dates.
    static let resetDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d MMM yyyy 'at' h:mm a"
        return formatter
    }()
}
