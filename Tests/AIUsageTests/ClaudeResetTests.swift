import XCTest
@testable import AIUsage

final class ClaudeResetTests: XCTestCase {
    /// Shape of a real `?cedar_ember=1` usage response (ids and labels replaced).
    private let payload = """
    {
      "five_hour": {"utilization": 8, "resets_at": "2026-11-11T16:20:00.018368+00:00"},
      "seven_day": {"utilization": 49, "resets_at": "2026-11-14T17:00:00.018385+00:00"},
      "limits": [
        {"kind": "session", "group": "session", "percent": 8, "scope": null},
        {"kind": "weekly_all", "group": "weekly", "percent": 49, "scope": null},
        {"kind": "weekly_scoped", "group": "weekly", "percent": 11, "scope": {"model": {"display_name": "Fable", "id": null}, "surface": null}}
      ],
      "cedar_ember": {
        "eligible": true,
        "at_limit": false,
        "next_grant_id": "grant_model",
        "grants": [
          {"id": "grant_full", "label": "One full limit reset", "resets_left": 1, "resets_total": 1,
           "ends_at": "2099-12-10T22:00:00+00:00", "clears": ["five_hour", "seven_day", "seven_day_overage_included"],
           "gives_back_weekly": false, "paused": false, "usable_now": true, "unavailable_reason": null, "type": "full"},
          {"id": "grant_model", "label": "Launch week reset", "resets_left": 1, "resets_total": 1,
           "ends_at": "2099-11-17T07:59:00+00:00", "clears": ["five_hour", "seven_day_overage_included"],
           "gives_back_weekly": true, "paused": false, "usable_now": true, "unavailable_reason": null, "type": "full"},
          {"id": "grant_used", "label": "Used", "resets_left": 0, "resets_total": 1, "clears": ["five_hour"],
           "usable_now": false, "unavailable_reason": "unavailable"},
          {"id": "Bad Id!", "resets_left": 1, "clears": ["five_hour"], "usable_now": true}
        ]
      }
    }
    """

    func testParsesGrantsAndScopedModel() throws {
        let limits = try XCTUnwrap(ClaudeService.parseUsageLimits(Data(payload.utf8)))
        XCTAssertEqual(limits.scopedModelName, "Fable")
        // The malformed id is dropped, as Claude Code drops it
        XCTAssertEqual(limits.resetGrants.map(\.id), ["grant_full", "grant_model", "grant_used"])

        let available = limits.availableResets()
        XCTAssertEqual(available.map(\.id), ["grant_model", "grant_full"], "used-up resets are hidden, soonest expiry first")

        let full = try XCTUnwrap(available.last)
        XCTAssertTrue(full.isFullReset)
        XCTAssertEqual(full.title(scopedModel: "Fable"), "Full reset")
        XCTAssertNil(full.unavailableMessage)

        let model = try XCTUnwrap(available.first)
        XCTAssertFalse(model.isFullReset)
        XCTAssertTrue(model.givesBackWeekly)
        XCTAssertEqual(model.title(scopedModel: "Fable"), "Fable reset")
        XCTAssertTrue(model.summary(scopedModel: "Fable").contains("Your week doesn't reset"))
    }

    func testExpiredResetsAreHidden() {
        let limits = ClaudeUsageLimits(
            fiveHourRemainingPercent: 50, fiveHourUsedPercent: 50,
            weeklyRemainingPercent: 50, weeklyUsedPercent: 50,
            resetGrants: [ClaudeResetGrant(id: "old", expiresAt: Date(timeIntervalSinceNow: -60))]
        )
        XCTAssertTrue(limits.availableResets().isEmpty)
    }

    func testIneligibleOrMissingBlockHasNoGrants() {
        XCTAssertTrue(ClaudeService.parseResetGrants(nil).isEmpty)
        XCTAssertTrue(ClaudeService.parseResetGrants(["eligible": false, "grants": [["id": "a", "resets_left": 1]]]).isEmpty)
    }

    func testUnavailableGrantExplainsWhy() {
        let grants = ClaudeService.parseResetGrants([
            "eligible": true,
            "grants": [
                ["id": "a", "resets_left": 1, "usable_now": false, "unavailable_reason": "blocked_seven_day"],
                ["id": "b", "resets_left": 1, "usable_now": true, "paused": true]
            ]
        ])
        XCTAssertEqual(grants[0].unavailableMessage, "Usable once your weekly limit resets")
        XCTAssertFalse(grants[1].usableNow, "a paused reset can't be used")
        XCTAssertEqual(grants[1].unavailableMessage, "Not available right now")
    }

    func testRequestBodyMatchesClaudeCode() throws {
        let body = try XCTUnwrap(ClaudeService.resetRequestBody(grantId: "grant_full", requestId: "req-1"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(json, ["program": "cedar_ember", "grant_id": "grant_full", "request_id": "req-1"])
    }

    func testGrantIdValidation() {
        XCTAssertTrue(ClaudeService.isValidGrantId("abc_123-x"))
        XCTAssertFalse(ClaudeService.isValidGrantId("../usage"))
        XCTAssertFalse(ClaudeService.isValidGrantId(""))
        XCTAssertFalse(ClaudeService.isValidGrantId(String(repeating: "a", count: 41)))
    }

    func testParsesResetOutcomes() {
        func outcome(_ json: String) -> ClaudeService.ResetOutcome? {
            ClaudeService.parseResetOutcome(Data(json.utf8))
        }
        XCTAssertEqual(outcome(#"{"result": "reset", "resets_left": 0, "cleared": ["five_hour"]}"#), .reset(resetsLeft: 0))
        XCTAssertEqual(outcome(#"{"result": "already_used"}"#), .alreadyUsed)
        XCTAssertEqual(outcome(#"{"result": "not_limited"}"#), .notLimited)
        XCTAssertEqual(outcome(#"{"result": "ineligible"}"#), .ineligible)
        XCTAssertEqual(outcome(#"{"result": "something_new"}"#), .unavailable)
        XCTAssertEqual(outcome(#"{"result": "cooldown", "cooldown_until": "2026-11-12T00:00:00Z"}"#),
                       .cooldown(until: ClaudeService.parseDate("2026-11-12T00:00:00Z")))
        XCTAssertTrue(outcome(#"{"result": "reset"}"#)?.isSuccess == true)
        XCTAssertNil(outcome("not json"))
    }
}
