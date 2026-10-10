import XCTest
@testable import AIUsage

final class QuotaAlertTrackerTests: XCTestCase {
    private func trackerAfterBaseline(_ readings: [String: Int] = [:]) -> QuotaAlertTracker {
        var tracker = QuotaAlertTracker()
        for (key, percent) in readings {
            XCTAssertFalse(tracker.shouldAlert(key: key, remainingPercent: percent))
        }
        tracker.finishBaseline()
        return tracker
    }

    func testBaselineReadingsNeverAlert() {
        var tracker = QuotaAlertTracker()
        XCTAssertFalse(tracker.shouldAlert(key: "a", remainingPercent: 5))
        XCTAssertFalse(tracker.shouldAlert(key: "b", remainingPercent: 25))
    }

    func testAlreadyLowAtLaunchDoesNotAlertOnFurtherDrop() {
        var tracker = trackerAfterBaseline(["a": 25])
        // 30% was acknowledged at launch, so dropping within the band stays quiet
        XCTAssertFalse(tracker.shouldAlert(key: "a", remainingPercent: 20))
        // ...but crossing 10% is a new threshold
        XCTAssertTrue(tracker.shouldAlert(key: "a", remainingPercent: 9))
    }

    func testDropBelowThirtyAlertsOnce() {
        var tracker = trackerAfterBaseline(["a": 80])
        XCTAssertFalse(tracker.shouldAlert(key: "a", remainingPercent: 50))
        XCTAssertTrue(tracker.shouldAlert(key: "a", remainingPercent: 30))
        XCTAssertFalse(tracker.shouldAlert(key: "a", remainingPercent: 20))
    }

    func testRapidDropBelowTenAlertsOnceForBothThresholds() {
        var tracker = trackerAfterBaseline(["a": 80])
        XCTAssertTrue(tracker.shouldAlert(key: "a", remainingPercent: 8))
        XCTAssertFalse(tracker.shouldAlert(key: "a", remainingPercent: 5))
    }

    func testNoAlertWithoutActiveDrop() {
        var tracker = trackerAfterBaseline(["a": 25])
        // Unchanged or rising quota means the tool is idle
        XCTAssertFalse(tracker.shouldAlert(key: "a", remainingPercent: 25))
        XCTAssertFalse(tracker.shouldAlert(key: "a", remainingPercent: 28))
    }

    func testFirstReadingAfterBaselineDoesNotAlert() {
        // A provider that connects after launch has no previous reading to compare against
        var tracker = trackerAfterBaseline()
        XCTAssertFalse(tracker.shouldAlert(key: "late", remainingPercent: 5))
    }

    func testRecoveryAboveThirtyRearmsThresholds() {
        var tracker = trackerAfterBaseline(["a": 80])
        XCTAssertTrue(tracker.shouldAlert(key: "a", remainingPercent: 25))
        XCTAssertFalse(tracker.shouldAlert(key: "a", remainingPercent: 100)) // window reset
        XCTAssertTrue(tracker.shouldAlert(key: "a", remainingPercent: 29))
    }

    func testTenPercentRearmsAfterPartialRecovery() {
        var tracker = trackerAfterBaseline(["a": 80])
        XCTAssertTrue(tracker.shouldAlert(key: "a", remainingPercent: 8))
        XCTAssertFalse(tracker.shouldAlert(key: "a", remainingPercent: 28)) // partial recovery
        XCTAssertFalse(tracker.shouldAlert(key: "a", remainingPercent: 25)) // drop within band re-arms 10%
        XCTAssertTrue(tracker.shouldAlert(key: "a", remainingPercent: 9))
    }

    func testKeysAreTrackedIndependently() {
        var tracker = trackerAfterBaseline(["a": 80, "b": 80])
        XCTAssertTrue(tracker.shouldAlert(key: "a", remainingPercent: 20))
        XCTAssertTrue(tracker.shouldAlert(key: "b", remainingPercent: 20))
    }

    func testNegativeReadingsAreIgnored() {
        var tracker = trackerAfterBaseline(["a": 80])
        XCTAssertFalse(tracker.shouldAlert(key: "a", remainingPercent: -1))
        XCTAssertTrue(tracker.shouldAlert(key: "a", remainingPercent: 20))
    }
}
