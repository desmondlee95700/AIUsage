import XCTest
@testable import AIUsage

final class FreshnessTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testLabels() {
        XCTAssertEqual(Freshness.label(lastUpdated: nil, now: now), "Connecting…")
        XCTAssertEqual(Freshness.label(lastUpdated: now, now: now), "Updated just now")
        XCTAssertEqual(Freshness.label(lastUpdated: now.addingTimeInterval(-9), now: now), "Updated just now")
        XCTAssertEqual(Freshness.label(lastUpdated: now.addingTimeInterval(-45), now: now), "Updated 45s ago")
        XCTAssertEqual(Freshness.label(lastUpdated: now.addingTimeInterval(-185), now: now), "Updated 3m ago")
        XCTAssertEqual(Freshness.label(lastUpdated: now.addingTimeInterval(-7_300), now: now), "Updated 2h ago")
        // Clock skew never shows a negative age
        XCTAssertEqual(Freshness.label(lastUpdated: now.addingTimeInterval(30), now: now), "Updated just now")
    }

    func testStaleness() {
        XCTAssertFalse(Freshness.isStale(lastUpdated: nil, refreshInterval: 60, now: now))
        XCTAssertFalse(Freshness.isStale(lastUpdated: now.addingTimeInterval(-170), refreshInterval: 60, now: now))
        XCTAssertTrue(Freshness.isStale(lastUpdated: now.addingTimeInterval(-190), refreshInterval: 60, now: now))
        // Manual refresh: stale after 10 minutes
        XCTAssertFalse(Freshness.isStale(lastUpdated: now.addingTimeInterval(-590), refreshInterval: 0, now: now))
        XCTAssertTrue(Freshness.isStale(lastUpdated: now.addingTimeInterval(-610), refreshInterval: 0, now: now))
    }

    func testQuotaLevelsMatchAlertThresholds() {
        XCTAssertEqual(QuotaLevel(fraction: 0.39), .healthy)
        XCTAssertEqual(QuotaLevel(fraction: 0.31), .healthy)
        XCTAssertEqual(QuotaLevel(fraction: 0.30), .moderate)   // first alert fires at <= 30%
        XCTAssertEqual(QuotaLevel(fraction: 0.11), .moderate)
        XCTAssertEqual(QuotaLevel(fraction: 0.10), .critical)   // second alert fires at <= 10%
        XCTAssertFalse(QuotaLevel(fraction: 0.5).needsAttention)
        XCTAssertTrue(QuotaLevel(fraction: 0.2).needsAttention)
    }
}
