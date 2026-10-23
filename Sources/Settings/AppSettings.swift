import Foundation

/// UserDefaults keys for app preferences. The preference enums keep their own `storageKey`;
/// these are the settings stored as plain values.
enum AppSettings {
    static let selectedProvidersKey = "selectedProviders"
    static let refreshIntervalKey = "refreshInterval"
    /// Single-provider focus from before multi-select, read once to migrate it
    static let legacyProviderFocusModeKey = "providerFocusMode"
    static let skippedUpdateVersionKey = "skippedUpdateVersion"
}
