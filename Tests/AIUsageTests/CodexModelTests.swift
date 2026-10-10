import XCTest
@testable import AIUsage

final class CodexModelTests: XCTestCase {
    private func window(used: Int, mins: Int?) -> CodexRateLimitWindow {
        CodexRateLimitWindow(usedPercent: used, windowDurationMins: mins, resetsAt: nil)
    }

    private func snapshot(primary: CodexRateLimitWindow?, secondary: CodexRateLimitWindow?) -> CodexRateLimitSnapshot {
        CodexRateLimitSnapshot(
            limitId: nil, limitName: nil, normalModelSlug: nil,
            primary: primary, secondary: secondary,
            credits: nil, planType: nil, spendControlReached: nil
        )
    }

    // MARK: - Window classification

    func testClassifiesFiveHourAndWeeklyWindowsRegardlessOfSlot() {
        let fiveHour = window(used: 40, mins: 300)
        let weekly = window(used: 10, mins: 10_080)

        for snap in [snapshot(primary: fiveHour, secondary: weekly), snapshot(primary: weekly, secondary: fiveHour)] {
            XCTAssertEqual(snap.rollingShortWindow?.windowDurationMins, 300)
            XCTAssertEqual(snap.weeklyWindow?.windowDurationMins, 10_080)
            // Shorter window is always listed first
            XCTAssertEqual(snap.allWindows.map(\.title), ["Rolling 5-Hour Limit", "Weekly Limit"])
        }
    }

    func testDuplicateWindowTitlesAreDisambiguated() {
        let snap = snapshot(primary: window(used: 0, mins: 10_080), secondary: window(used: 0, mins: 10_080))
        XCTAssertEqual(snap.allWindows.map(\.title), ["Weekly Limit", "Extended Limit"])
    }

    func testSingleWindow() {
        let snap = snapshot(primary: nil, secondary: window(used: 0, mins: 43_200))
        XCTAssertEqual(snap.allWindows.map(\.title), ["Monthly Limit (30-Day)"])
        XCTAssertNil(snap.weeklyWindow)
        XCTAssertNil(snap.rollingShortWindow)
    }

    func testWindowDisplayNames() {
        XCTAssertEqual(window(used: 0, mins: nil).windowDisplayName, "Model Quota")
        XCTAssertEqual(window(used: 0, mins: 45).windowDisplayName, "45-Minute Limit")
        XCTAssertEqual(window(used: 0, mins: 300).windowDisplayName, "Rolling 5-Hour Limit")
        XCTAssertEqual(window(used: 0, mins: 3 * 1440).windowDisplayName, "3-Day Limit")
        XCTAssertEqual(window(used: 0, mins: 10_080).windowDisplayName, "Weekly Limit")
    }

    func testRemainingPercentIsClamped() {
        XCTAssertEqual(window(used: 25, mins: nil).remainingPercent, 75)
        XCTAssertEqual(window(used: 150, mins: nil).remainingPercent, 0)
        XCTAssertEqual(window(used: -10, mins: nil).remainingPercent, 100)
    }

    // MARK: - Decoding

    func testDecodesRateLimitsResponse() throws {
        let json = """
        {
          "rateLimits": {
            "primary": {"usedPercent": 12, "windowDurationMins": 300, "resetsAt": 1791000000},
            "secondary": {"usedPercent": 3, "windowDurationMins": 10080}
          },
          "rateLimitResetCredits": {"availableCount": 1, "credits": []}
        }
        """
        let decoded = try JSONDecoder().decode(CodexRateLimitsResponse.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.rateLimits?.rollingShortWindow?.remainingPercent, 88)
        XCTAssertEqual(decoded.rateLimits?.weeklyWindow?.remainingPercent, 97)
        XCTAssertEqual(decoded.rateLimitResetCredits?.availableCount, 1)
    }

    func testResetCreditDecodesCamelAndSnakeCase() throws {
        let camel = try JSONDecoder().decode(CodexRateLimitResetCredit.self, from: Data(
            #"{"creditId": "c1", "resetType": "codex_rate_limits", "expiresAt": 1791000000}"#.utf8))
        XCTAssertEqual(camel.creditId, "c1")
        XCTAssertEqual(camel.expiresAt, 1_791_000_000)
        XCTAssertEqual(camel.formattedResetType, "Resets Available")

        let snake = try JSONDecoder().decode(CodexRateLimitResetCredit.self, from: Data(
            #"{"credit_id": "c2", "reset_type": "custom", "expires_at": 1791000000}"#.utf8))
        XCTAssertEqual(snake.creditId, "c2")
        XCTAssertEqual(snake.resetType, "custom")
        XCTAssertEqual(snake.expiresAt, 1_791_000_000)
    }

    func testResetCreditFallsBackWhenPrimaryKeyHasWrongType() throws {
        // A non-string creditId must not discard the snake_case fallback
        let credit = try JSONDecoder().decode(CodexRateLimitResetCredit.self, from: Data(
            #"{"creditId": 42, "credit_id": "c3"}"#.utf8))
        XCTAssertEqual(credit.creditId, "c3")
    }

    func testResetCreditParsesStringTimestamps() throws {
        let numeric = try JSONDecoder().decode(CodexRateLimitResetCredit.self, from: Data(
            #"{"expiresAt": "1791000000"}"#.utf8))
        XCTAssertEqual(numeric.expiresAt, 1_791_000_000)

        let iso = try JSONDecoder().decode(CodexRateLimitResetCredit.self, from: Data(
            #"{"expiresAt": "2026-10-03T04:00:00Z"}"#.utf8))
        XCTAssertEqual(iso.expiresAt, 1_791_000_000)
    }

    // MARK: - app-server output framing

    func testTakeLinesKeepsPartialLineAndHandlesSplitUTF8() {
        let stream = Data("{\"email\":\"jösé@example.com\"}\n{\"id\":4}\npartial".utf8)
        var buffer = Data()
        var lines: [String] = []
        // Feed one byte at a time so multi-byte characters straddle reads
        for byte in stream {
            buffer.append(byte)
            lines += CodexService.takeLines(from: &buffer).map { String(decoding: $0, as: UTF8.self) }
        }
        XCTAssertEqual(lines, ["{\"email\":\"jösé@example.com\"}", "{\"id\":4}"])
        XCTAssertEqual(String(decoding: buffer, as: UTF8.self), "partial")
    }
}
