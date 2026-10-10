import XCTest
@testable import AIUsage

final class ClaudeParsingTests: XCTestCase {
    private func parse(_ json: String) -> ClaudeUsageLimits? {
        ClaudeService.parseUsageLimits(Data(json.utf8))
    }

    func testParsesFullPayload() throws {
        let limits = try XCTUnwrap(parse("""
        {
          "five_hour": {"utilization": 42.4, "resets_at": "2026-10-10T15:00:00.000Z"},
          "seven_day": {"utilization": 10, "resets_at": "2026-10-14T00:00:00Z"},
          "seven_day_sonnet": {"utilization": 99.6},
          "seven_day_opus": null,
          "extra_usage": {"utilization": 5}
        }
        """))
        XCTAssertEqual(limits.fiveHourRemainingPercent, 58)
        XCTAssertEqual(limits.fiveHourUsedPercent, 42)
        XCTAssertEqual(limits.weeklyRemainingPercent, 90)
        XCTAssertEqual(limits.sonnetRemainingPercent, 0)
        XCTAssertNil(limits.opusRemainingPercent)
        XCTAssertEqual(limits.extraUsagePercent, 95)
        XCTAssertTrue(limits.hasFiveHourWindow)
        XCTAssertTrue(limits.hasWeeklyWindow)
        XCTAssertNotNil(limits.fiveHourResetTime)
        XCTAssertNotNil(limits.weeklyResetTime)
    }

    func testFreeTierNullLimitsReturnNil() {
        XCTAssertNil(parse(#"{"five_hour": null, "seven_day": null, "seven_day_sonnet": null}"#))
    }

    func testMissingFiveHourWindowIsFlagged() throws {
        let limits = try XCTUnwrap(parse(#"{"seven_day": {"utilization": 30}}"#))
        XCTAssertFalse(limits.hasFiveHourWindow)
        XCTAssertTrue(limits.hasWeeklyWindow)
        XCTAssertEqual(limits.weeklyRemainingPercent, 70)
    }

    func testUtilizationIsClamped() throws {
        let limits = try XCTUnwrap(parse(#"{"five_hour": {"utilization": 130}, "seven_day": {"utilization": -5}}"#))
        XCTAssertEqual(limits.fiveHourRemainingPercent, 0)
        XCTAssertEqual(limits.weeklyRemainingPercent, 100)
    }

    func testInvalidJSONReturnsNil() {
        XCTAssertNil(parse("not json"))
        XCTAssertNil(ClaudeService.parseUsageLimits(nil))
    }

    func testParseDateFormats() {
        let expected = Date(timeIntervalSince1970: 1_791_000_000)
        XCTAssertEqual(ClaudeService.parseDate("2026-10-03T04:00:00Z"), expected)
        XCTAssertEqual(ClaudeService.parseDate("2026-10-03T04:00:00.000Z"), expected)
        XCTAssertEqual(ClaudeService.parseDate(1_791_000_000.0), expected)
        // Millisecond timestamps are detected by magnitude
        XCTAssertEqual(ClaudeService.parseDate(1_791_000_000_000.0), expected)
        XCTAssertNil(ClaudeService.parseDate(""))
        XCTAssertNil(ClaudeService.parseDate(nil))
        XCTAssertNil(ClaudeService.parseDate("yesterday"))
    }

    func testTierMapping() {
        XCTAssertEqual(ClaudeAccountInfo(organizationType: "claude_pro").tierBadge, "Pro")
        XCTAssertEqual(ClaudeAccountInfo(organizationType: "claude_max").formattedTier, "Claude Max")
        XCTAssertEqual(ClaudeAccountInfo(organizationType: "raven").formattedTier, "Claude Team")
        XCTAssertEqual(ClaudeAccountInfo(organizationType: nil).tierBadge, "Free")
        XCTAssertTrue(ClaudeAccountInfo(organizationType: "claude_max").canSeeUsageLimits)
        XCTAssertFalse(ClaudeAccountInfo(organizationType: "claude_free").canSeeUsageLimits)
    }
}
