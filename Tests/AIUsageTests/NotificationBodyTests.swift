import XCTest
@testable import AIUsage

final class NotificationBodyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_791_000_000)

    func testIncludesWindowAndResetTime() {
        let body = NotificationManager.lowQuotaBody(
            provider: "ChatGPT", remainingQuota: "25%", window: "5-hour limit",
            resetDate: now.addingTimeInterval(2 * 3600 + 10 * 60), now: now
        )
        XCTAssertEqual(body, "25% of your 5-hour limit left on ChatGPT. Resets in 2h 10m.")
    }

    func testOmitsResetWhenUnknownOrPast() {
        XCTAssertEqual(
            NotificationManager.lowQuotaBody(provider: "Claude", remainingQuota: "8%", window: "weekly limit", resetDate: nil, now: now),
            "8% of your weekly limit left on Claude."
        )
        XCTAssertEqual(
            NotificationManager.lowQuotaBody(provider: "Claude", remainingQuota: "8%", window: nil, resetDate: now.addingTimeInterval(-60), now: now),
            "8% quota left on Claude."
        )
    }
}
