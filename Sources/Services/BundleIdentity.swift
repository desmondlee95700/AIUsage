import AppKit

/// Handles the move from the original bundle identifier (`com.antigravity.aiusage`, which borrowed
/// another product's namespace) to `io.github.desmondlee95700.aiusage`.
enum BundleIdentity {
    static let legacyIdentifier = "com.antigravity.aiusage"
    static let migratedKey = "migratedFromLegacyBundleIdentifier"

    // MARK: - Settings migration

    /// Copies settings saved under the legacy identifier into the current domain, once. Settings
    /// already saved under the current identifier win. The legacy domain is left in place so
    /// rolling back to an older version keeps its settings.
    static func migrateLegacyDefaults(defaults: UserDefaults = .standard) {
        guard let current = Bundle.main.bundleIdentifier, current != legacyIdentifier,
              !defaults.bool(forKey: migratedKey) else { return }
        if let legacy = defaults.persistentDomain(forName: legacyIdentifier) {
            let existing = defaults.persistentDomain(forName: current) ?? [:]
            defaults.setPersistentDomain(merge(legacy: legacy, into: existing), forName: current)
        }
        defaults.set(true, forKey: migratedKey)
    }

    /// Legacy values fill in keys the current domain doesn't have yet.
    static func merge(legacy: [String: Any], into current: [String: Any]) -> [String: Any] {
        current.merging(legacy) { currentValue, _ in currentValue }
    }

    // MARK: - Single instance

    /// Quits a copy still running under the legacy identifier (e.g. the previous version after an
    /// update), and returns false when another copy of this version is already running, in which
    /// case the caller should quit. Prevents two menu bar items, e.g. when both an old and a new
    /// login item launch the app.
    static func claimSingleInstance() -> Bool {
        let me = NSRunningApplication.current
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: legacyIdentifier) where app != me {
            app.terminate()
        }
        guard let current = Bundle.main.bundleIdentifier else { return true }
        return !NSRunningApplication.runningApplications(withBundleIdentifier: current).contains { $0 != me }
    }
}
