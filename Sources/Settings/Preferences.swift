import Foundation

public enum MenuBarDisplayMode: String, CaseIterable, Codable {
    public static let storageKey = "menuBarDisplayMode"
    
    /// Each selected provider's icon and lowest remaining limit
    case percentages = "Percentages"
    /// Provider icons only, for a quieter or more private menu bar
    case iconOnly = "Icon Only"
    
    public var title: String {
        switch self {
        case .percentages: return "Show Percentages"
        case .iconOnly: return "Icon Only"
        }
    }
    
    /// Reads a saved preference. Values from older versions (the dual, active-provider and
    /// weekly-only modes, which all showed percentages) map to `.percentages`.
    public init(savedValue: String?) {
        self = savedValue == MenuBarDisplayMode.iconOnly.rawValue ? .iconOnly : .percentages
    }
}

/// Which low-quota notifications to send. Thresholds match the gauge colours (amber at 30%, red at 10%).
public enum LowQuotaAlertMode: String, CaseIterable, Codable {
    case all = "all"
    case criticalOnly = "critical"
    case off = "off"
    
    public static let storageKey = "lowQuotaAlertMode"
    
    public var title: String {
        switch self {
        case .all: return "At 30% and 10%"
        case .criticalOnly: return "At 10% Only"
        case .off: return "Off"
        }
    }
    
    /// Whether crossing `threshold` (30 or 10) should send a notification
    public func allows(threshold: Int) -> Bool {
        switch self {
        case .all: return true
        case .criticalOnly: return threshold <= 10
        case .off: return false
        }
    }
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
