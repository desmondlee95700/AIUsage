import Foundation

/// When Blackout should end, decided from how long ago the last hardware input arrived.
public enum BlackoutWake {
    /// Input in the first moment after starting is ignored, so the click that started Blackout
    /// and the hand still settling on the trackpad don't end it straight away.
    public static let grace: TimeInterval = 1.0

    /// True once keyboard, mouse or trackpad input has arrived after the grace period.
    /// `secondsSinceInput` is the time since the last hardware event; `elapsed` is the time
    /// since Blackout started.
    public static func shouldWake(secondsSinceInput: TimeInterval, elapsed: TimeInterval, grace: TimeInterval = grace) -> Bool {
        !isInGrace(elapsed: elapsed, grace: grace) && secondsSinceInput < elapsed - grace
    }

    /// True while events should be swallowed without waking.
    public static func isInGrace(elapsed: TimeInterval, grace: TimeInterval = grace) -> Bool {
        elapsed <= grace
    }

    /// Bundle IDs of the lock screen and screen saver, which take focus when the display wakes.
    private static let systemOwnedBundleIDs: Set<String> = [
        "com.apple.loginwindow",
        "com.apple.ScreenSaver.Engine"
    ]

    /// True when another app's activation should be answered by re-focusing the overlay. Our own
    /// activation is ignored, as is the lock screen or screen saver: fighting them for focus can
    /// steal it from the password field.
    public static func shouldReclaimFocus(activatedPID: pid_t?, ownPID: pid_t, bundleID: String?) -> Bool {
        if activatedPID == ownPID { return false }
        if let bundleID, systemOwnedBundleIDs.contains(bundleID) { return false }
        return true
    }
}
