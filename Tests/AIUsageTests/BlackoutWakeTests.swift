import XCTest
@testable import AIUsage

final class BlackoutWakeTests: XCTestCase {
    func testNoWakeDuringGrace() {
        // Input just now, but Blackout only started half a second ago
        XCTAssertFalse(BlackoutWake.shouldWake(secondsSinceInput: 0, elapsed: 0.5, grace: 1))
        XCTAssertFalse(BlackoutWake.shouldWake(secondsSinceInput: 0, elapsed: 1, grace: 1))
        XCTAssertTrue(BlackoutWake.isInGrace(elapsed: 0.5, grace: 1))
        XCTAssertFalse(BlackoutWake.isInGrace(elapsed: 1.5, grace: 1))
    }

    func testInputDuringGraceDoesNotWakeLater() {
        // Last input was the starting click, 0.2s after start; 10s have passed
        XCTAssertFalse(BlackoutWake.shouldWake(secondsSinceInput: 9.8, elapsed: 10, grace: 1))
        // Input from before Blackout started
        XCTAssertFalse(BlackoutWake.shouldWake(secondsSinceInput: 30, elapsed: 10, grace: 1))
    }

    func testInputAfterGraceWakes() {
        XCTAssertTrue(BlackoutWake.shouldWake(secondsSinceInput: 0.1, elapsed: 10, grace: 1))
        XCTAssertTrue(BlackoutWake.shouldWake(secondsSinceInput: 8.9, elapsed: 10, grace: 1))
        XCTAssertTrue(BlackoutWake.shouldWake(secondsSinceInput: 0.1, elapsed: 1.2, grace: 1))
    }

    func testReclaimsFocusFromOrdinaryApps() {
        XCTAssertTrue(BlackoutWake.shouldReclaimFocus(activatedPID: 200, ownPID: 100, bundleID: "com.apple.Terminal"))
        XCTAssertTrue(BlackoutWake.shouldReclaimFocus(activatedPID: 200, ownPID: 100, bundleID: nil))
        XCTAssertTrue(BlackoutWake.shouldReclaimFocus(activatedPID: nil, ownPID: 100, bundleID: nil))
    }

    func testDoesNotReclaimFocusFromOwnActivation() {
        XCTAssertFalse(BlackoutWake.shouldReclaimFocus(activatedPID: 100, ownPID: 100, bundleID: "com.example.AIUsage"))
    }

    func testDoesNotReclaimFocusFromLockScreenOrScreenSaver() {
        XCTAssertFalse(BlackoutWake.shouldReclaimFocus(activatedPID: 200, ownPID: 100, bundleID: "com.apple.loginwindow"))
        XCTAssertFalse(BlackoutWake.shouldReclaimFocus(activatedPID: 200, ownPID: 100, bundleID: "com.apple.ScreenSaver.Engine"))
    }
}
