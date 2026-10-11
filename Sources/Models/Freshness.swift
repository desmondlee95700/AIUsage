import Foundation

/// How current the popover's numbers are, shown in the header in place of a bare "Live" status.
public enum Freshness {
    /// "Updated just now", "Updated 45s ago", "Updated 3m ago", "Updated 2h ago", or
    /// "Connecting…" before the first refresh has finished.
    public static func label(lastUpdated: Date?, now: Date = Date()) -> String {
        guard let lastUpdated = lastUpdated else { return "Connecting…" }
        let age = max(0, Int(now.timeIntervalSince(lastUpdated)))
        switch age {
        case ..<10: return "Updated just now"
        case ..<60: return "Updated \(age)s ago"
        case ..<3600: return "Updated \(age / 60)m ago"
        default: return "Updated \(age / 3600)h ago"
        }
    }

    /// True once the data has missed a few automatic refreshes. With manual refresh
    /// (`refreshInterval` 0) numbers count as stale after 10 minutes.
    public static func isStale(lastUpdated: Date?, refreshInterval: TimeInterval, now: Date = Date()) -> Bool {
        guard let lastUpdated = lastUpdated else { return false }
        let limit = refreshInterval > 0 ? refreshInterval * 3 : 600
        return now.timeIntervalSince(lastUpdated) > limit
    }
}
