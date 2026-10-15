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

    func testModelLimitsKeepTheirOwnResetTimes() throws {
        let limits = try XCTUnwrap(parse("""
        {
          "seven_day": {"utilization": 10, "resets_at": "2026-10-14T00:00:00Z"},
          "seven_day_sonnet": {"utilization": 20, "resets_at": "2026-10-16T00:00:00Z"},
          "seven_day_opus": {"utilization": 75}
        }
        """))
        XCTAssertEqual(limits.sonnetRemainingPercent, 80)
        XCTAssertEqual(limits.opusRemainingPercent, 25)
        XCTAssertEqual(limits.modelResetTime(limits.sonnetResetTime), ClaudeService.parseDate("2026-10-16T00:00:00Z"))
        // Opus has no reset of its own, so it falls back to the all-models weekly reset
        XCTAssertNil(limits.opusResetTime)
        XCTAssertEqual(limits.modelResetTime(limits.opusResetTime), limits.weeklyResetTime)
    }

    func testOpusOnlyPayloadIsNotTreatedAsFreeTier() {
        XCTAssertNotNil(parse(#"{"five_hour": null, "seven_day": null, "seven_day_opus": {"utilization": 5}}"#))
    }

    func testDisabledExtraUsageIsNil() throws {
        let off = try XCTUnwrap(parse(#"{"five_hour": {"utilization": 1}, "extra_usage": {"is_enabled": false, "utilization": null}}"#))
        XCTAssertNil(off.extraUsagePercent)
        let offWithFigure = try XCTUnwrap(parse(#"{"five_hour": {"utilization": 1}, "extra_usage": {"is_enabled": false, "utilization": 0}}"#))
        XCTAssertNil(offWithFigure.extraUsagePercent)
        let on = try XCTUnwrap(parse(#"{"five_hour": {"utilization": 1}, "extra_usage": {"is_enabled": true, "utilization": 40}}"#))
        XCTAssertEqual(on.extraUsagePercent, 60)
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

    func testParseClaudeCodeCredentials() {
        // `security -w` output ends with a newline
        let json = #"{"claudeAiOauth":{"accessToken":"tok","refreshToken":"r","expiresAt":1791000000000}}"# + "\n"
        let token = ClaudeService.parseClaudeCodeCredentials(Data(json.utf8))
        XCTAssertEqual(token?.value, "tok")
        XCTAssertEqual(token?.expiresAt, Date(timeIntervalSince1970: 1_791_000_000))
        XCTAssertEqual(token?.isExpired(at: Date(timeIntervalSince1970: 1_790_999_999)), false)
        XCTAssertEqual(token?.isExpired(at: Date(timeIntervalSince1970: 1_791_000_000)), true)

        let noExpiry = ClaudeService.parseClaudeCodeCredentials(Data(#"{"claudeAiOauth":{"accessToken":"tok"}}"#.utf8))
        XCTAssertNil(noExpiry?.expiresAt)
        XCTAssertEqual(noExpiry?.isExpired(), false)

        XCTAssertNil(ClaudeService.parseClaudeCodeCredentials(Data(#"{"claudeAiOauth":{"accessToken":""}}"#.utf8)))
        XCTAssertNil(ClaudeService.parseClaudeCodeCredentials(Data("not json".utf8)))
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
