import Foundation

/// The twin micro-bars beside a provider's menu bar figure: 5-hour limit on top, weekly below.
/// Only drawn when a provider reports both, since a single bar would repeat the number beside it.
public struct MenuBarMeter: Equatable {
    /// Remaining fraction of each window, clamped to 0...1
    public let fiveHour: Double
    public let weekly: Double

    public init?(fiveHour: Double?, weekly: Double?) {
        guard let fiveHour, let weekly else { return nil }
        self.fiveHour = min(max(fiveHour, 0), 1)
        self.weekly = min(max(weekly, 0), 1)
    }

    /// Whether the weekly bar is the one the menu bar figure comes from. Ties go to the 5-hour
    /// window, matching how each provider picks its figure.
    public var isWeeklyBinding: Bool { weekly < fiveHour }
}
