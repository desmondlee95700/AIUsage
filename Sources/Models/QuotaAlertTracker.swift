import Foundation

/// Decides when a low-quota alert should fire, tracking the 30% and 10% thresholds per quota window.
///
/// Alerts only fire when quota actively drops past a threshold. Quota that is already low when the
/// app launches is acknowledged silently, and thresholds re-arm once quota recovers above 30%.
public struct QuotaAlertTracker {
    private var alertedThresholds: [String: Set<Int>] = [:]
    private var lastKnownPercentages: [String: Int] = [:]
    private var hasInitializedBaselines = false

    public init() {}

    /// Ends the silent baseline pass. Call after the first full round of readings.
    public mutating func finishBaseline() {
        hasInitializedBaselines = true
    }

    /// Records a reading for `key` and returns whether an alert should be sent for it.
    public mutating func shouldAlert(key: String, remainingPercent: Int) -> Bool {
        guard remainingPercent >= 0 else { return false }

        let previousPercent = lastKnownPercentages[key]

        // 1. Initial baseline establishment on startup:
        // Record current levels silently. If a tool already has low quota on launch, mark it as acknowledged
        // so an idle tool with stale low quota NEVER fires a notification out of the blue.
        if !hasInitializedBaselines {
            lastKnownPercentages[key] = remainingPercent
            var initialFired: Set<Int> = []
            if remainingPercent <= 10 {
                initialFired.insert(10)
                initialFired.insert(30)
            } else if remainingPercent <= 30 {
                initialFired.insert(30)
            }
            if !initialFired.isEmpty {
                alertedThresholds[key] = initialFired
            }
            return false
        }

        // 2. Always record current percentage
        lastKnownPercentages[key] = remainingPercent

        // 3. REQUIRE ACTIVE DROP:
        // A low quota alert MUST only trigger when quota ACTUALLY DECREASES (active usage occurred)!
        // If remainingPercent >= prev, the tool is idle (no usage occurred) or has reset/recovered.
        guard let prev = previousPercent, remainingPercent < prev else {
            // Quota has recovered or reset (> 30%)
            if remainingPercent > 30 {
                alertedThresholds[key] = []
            }
            return false
        }

        var fired = alertedThresholds[key] ?? []
        var shouldAlert = false

        // Threshold 1: <= 10% (Critical warning)
        if remainingPercent <= 10 {
            if !fired.contains(10) {
                shouldAlert = true
                fired.insert(10)
                fired.insert(30) // Mark 30% as also triggered if it dropped rapidly
            }
        }
        // Threshold 2: <= 30% (Early warning)
        else if remainingPercent <= 30 {
            if !fired.contains(30) {
                shouldAlert = true
                fired.insert(30)
            }
            // If quota is between 11% and 30%, rearm 10% in case it drops further
            fired.remove(10)
        }

        alertedThresholds[key] = fired
        return shouldAlert
    }
}
