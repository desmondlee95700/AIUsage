import XCTest
@testable import AIUsage

final class VersionComparisonTests: XCTestCase {
    func testIsVersionGreaterThan() {
        XCTAssertTrue(UpdateService.isVersion("v2.1.3", greaterThan: "2.1.2"))
        XCTAssertTrue(UpdateService.isVersion("2.10.0", greaterThan: "2.9.9"))
        XCTAssertTrue(UpdateService.isVersion("3", greaterThan: "2.99"))
        XCTAssertTrue(UpdateService.isVersion("2.1.0.1", greaterThan: "2.1"))
        XCTAssertFalse(UpdateService.isVersion("v2.1.2", greaterThan: "2.1.2"))
        XCTAssertFalse(UpdateService.isVersion("2.1", greaterThan: "2.1.0"))
        XCTAssertFalse(UpdateService.isVersion("2.0.9", greaterThan: "2.1.0"))
        XCTAssertFalse(UpdateService.isVersion(" V2.1.2\n", greaterThan: "2.1.2"))
    }
}

final class QuotaBucketTests: XCTestCase {
    private func bucket(fraction: Double?, description: String? = nil, resetTime: String? = nil) -> QuotaBucket {
        QuotaBucket(
            bucketId: "b", displayName: "B", description: description,
            window: nil, remainingFraction: fraction, resetTime: resetTime
        )
    }

    func testPercentageFormatting() {
        XCTAssertEqual(bucket(fraction: 0.5).percentage, 50)
        XCTAssertEqual(bucket(fraction: 0.5).formattedPercentage, "50%")
        XCTAssertEqual(bucket(fraction: 0.1234).formattedPercentage, "12.3%")
        XCTAssertEqual(bucket(fraction: 0.996).percentage, 100)
        XCTAssertEqual(bucket(fraction: nil).percentage, 0)
        XCTAssertEqual(bucket(fraction: nil).formattedPercentage, "N/A")
    }

    func testResetCountdownPrefersServerDescription() {
        XCTAssertEqual(bucket(fraction: 1, description: "Resets Monday").formattedResetCountdown, "Resets Monday")
    }

    func testResetCountdownFromTimestamp() {
        XCTAssertEqual(bucket(fraction: 1, resetTime: "2000-01-01T00:00:00Z").formattedResetCountdown, "Refreshes soon")
        XCTAssertNil(bucket(fraction: 1, resetTime: "not a date").formattedResetCountdown)

        let future = ISO8601DateFormatter().string(from: Date().addingTimeInterval(2 * 86400 + 3 * 3600 + 60))
        XCTAssertEqual(bucket(fraction: 1, resetTime: future).formattedResetCountdown, "Fully refreshes in 2d 3h")
    }
}
