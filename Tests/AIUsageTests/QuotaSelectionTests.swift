import XCTest
@testable import AIUsage

/// Covers which quota window each provider surfaces in the menu bar, tooltip and alerts.
final class QuotaSelectionTests: XCTestCase {
    // MARK: - Antigravity buckets

    private func bucket(_ id: String, name: String, window: String? = nil, fraction: Double? = 0.5) -> QuotaBucket {
        QuotaBucket(bucketId: id, displayName: name, description: nil, window: window, remainingFraction: fraction, resetTime: nil)
    }

    private func summary(_ groups: [(String, [QuotaBucket])]) -> QuotaSummaryData {
        QuotaSummaryData(
            groups: groups.map { QuotaGroup(displayName: $0.0, description: nil, buckets: $0.1) },
            description: nil
        )
    }

    func testPrefersGeminiGroupOverFirstGroup() {
        let data = summary([
            ("Claude & GPT Models", [bucket("other-5h", name: "5h Limit", window: "5h", fraction: 0.1)]),
            ("Gemini Models", [bucket("gemini-5h", name: "5h Limit", window: "5h", fraction: 0.9)])
        ])
        XCTAssertEqual(data.primary5hBucket?.bucketId, "gemini-5h")
    }

    func testFallsBackToFirstGroupWithoutGemini() {
        let data = summary([
            ("Claude & GPT Models", [bucket("other-5h", name: "5h Limit", window: "5h")]),
            ("Image Models", [bucket("image-5h", name: "5h Limit", window: "5h")])
        ])
        XCTAssertEqual(data.primary5hBucket?.bucketId, "other-5h")
    }

    func testMatchesFiveHourAndWeeklyBucketsByWindowIdOrName() {
        let byWindow = summary([("Gemini", [
            bucket("a", name: "Weekly", window: "WEEKLY"),
            bucket("b", name: "Short", window: "5h")
        ])])
        XCTAssertEqual(byWindow.primary5hBucket?.bucketId, "b")
        XCTAssertEqual(byWindow.primaryWeeklyBucket?.bucketId, "a")

        let byId = summary([("Gemini", [bucket("quota_weekly", name: "A"), bucket("quota_5h", name: "B")])])
        XCTAssertEqual(byId.primary5hBucket?.bucketId, "quota_5h")
        XCTAssertEqual(byId.primaryWeeklyBucket?.bucketId, "quota_weekly")

        let byName = summary([("Gemini", [bucket("x", name: "Per Week"), bucket("y", name: "5-Hour Window")])])
        XCTAssertEqual(byName.primary5hBucket?.bucketId, "y")
        XCTAssertEqual(byName.primaryWeeklyBucket?.bucketId, "x")
    }

    func testFiveHourFallsBackToFirstNonWeeklyBucket() {
        let data = summary([("Gemini", [
            bucket("quota_weekly", name: "Weekly", window: "weekly"),
            bucket("daily", name: "Daily", window: "daily")
        ])])
        XCTAssertEqual(data.primary5hBucket?.bucketId, "daily")
    }

    func testOnlyWeeklyBucketHasNoFiveHourBucket() {
        let data = summary([("Gemini", [bucket("quota_weekly", name: "Weekly", window: "weekly")])])
        XCTAssertNil(data.primary5hBucket)
        XCTAssertEqual(data.primaryWeeklyBucket?.bucketId, "quota_weekly")
    }

    func testNoGroups() {
        let data = QuotaSummaryData(groups: nil, description: nil)
        XCTAssertNil(data.primary5hBucket)
        XCTAssertNil(data.primaryWeeklyBucket)
    }

    func testBindingBucketIsTheLowerOfFiveHourAndWeekly() {
        let weeklyLow = summary([("Gemini", [
            bucket("g-5h", name: "5h", window: "5h", fraction: 1.0),
            bucket("g-weekly", name: "Weekly", window: "weekly", fraction: 0.04)
        ])])
        XCTAssertEqual(weeklyLow.bindingBucket?.bucketId, "g-weekly")

        let fiveHourLow = summary([("Gemini", [
            bucket("g-5h", name: "5h", window: "5h", fraction: 0.2),
            bucket("g-weekly", name: "Weekly", window: "weekly", fraction: 0.9)
        ])])
        XCTAssertEqual(fiveHourLow.bindingBucket?.bucketId, "g-5h")
    }

    func testBindingBucketSkipsBucketsWithoutData() {
        let partial = summary([("Gemini", [
            bucket("g-5h", name: "5h", window: "5h", fraction: nil),
            bucket("g-weekly", name: "Weekly", window: "weekly", fraction: 0.7)
        ])])
        XCTAssertEqual(partial.bindingBucket?.bucketId, "g-weekly")

        let none = summary([("Gemini", [bucket("g-5h", name: "5h", window: "5h", fraction: nil)])])
        XCTAssertNil(none.bindingBucket)
    }

    func testBucketPercentageRounds() {
        XCTAssertEqual(bucket("a", name: "A", fraction: 0.456).percentage, 46)
        XCTAssertEqual(bucket("a", name: "A", fraction: nil).percentage, 0)
    }

    // MARK: - Codex active window

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

    func testCodexActiveWindowPrefersFiveHourThenWeekly() {
        let fiveHour = window(used: 40, mins: 300)
        let weekly = window(used: 10, mins: 10_080)
        let monthly = window(used: 5, mins: 43_200)

        XCTAssertEqual(snapshot(primary: weekly, secondary: fiveHour).activeWindow?.windowDurationMins, 300)
        XCTAssertEqual(snapshot(primary: monthly, secondary: weekly).activeWindow?.windowDurationMins, 10_080)
        // Neither 5-hour nor weekly: primary, then secondary
        XCTAssertEqual(snapshot(primary: monthly, secondary: nil).activeWindow?.windowDurationMins, 43_200)
        XCTAssertEqual(snapshot(primary: nil, secondary: monthly).activeWindow?.windowDurationMins, 43_200)
        XCTAssertNil(snapshot(primary: nil, secondary: nil).activeWindow)
    }

    func testCodexBindingWindowIsTheLowest() {
        let fiveHour = window(used: 0, mins: 300)
        let weekly = window(used: 96, mins: 10_080)
        XCTAssertEqual(snapshot(primary: fiveHour, secondary: weekly).bindingWindow?.windowDurationMins, 10_080)
        XCTAssertEqual(snapshot(primary: window(used: 70, mins: 300), secondary: window(used: 20, mins: 10_080))
            .bindingWindow?.windowDurationMins, 300)
        XCTAssertNil(snapshot(primary: nil, secondary: nil).bindingWindow)
    }

    func testCodexBindingWindowTieGoesToShorterWindow() {
        let tie = snapshot(primary: window(used: 50, mins: 10_080), secondary: window(used: 50, mins: 300))
        XCTAssertEqual(tie.bindingWindow?.windowDurationMins, 300)
    }

    // MARK: - Claude limits

    private func limits(fiveHour: Int, weekly: Int, hasFiveHour: Bool = true, hasWeekly: Bool = true) -> ClaudeUsageLimits {
        ClaudeUsageLimits(
            fiveHourRemainingPercent: fiveHour, fiveHourUsedPercent: 100 - fiveHour,
            weeklyRemainingPercent: weekly, weeklyUsedPercent: 100 - weekly,
            hasFiveHourWindow: hasFiveHour, hasWeeklyWindow: hasWeekly
        )
    }

    func testClaudeMenuBarPercentIsTheLowerWindow() {
        XCTAssertEqual(limits(fiveHour: 30, weekly: 80).menuBarPercent, 30)
        XCTAssertEqual(limits(fiveHour: 100, weekly: 4).menuBarPercent, 4)
        XCTAssertEqual(limits(fiveHour: 100, weekly: 80, hasFiveHour: false).menuBarPercent, 80)
        // An unreported window's placeholder never wins
        XCTAssertEqual(limits(fiveHour: 0, weekly: 80, hasFiveHour: false).menuBarPercent, 80)
        XCTAssertNil(limits(fiveHour: 100, weekly: 100, hasFiveHour: false, hasWeekly: false).menuBarPercent)
    }

    func testClaudeWeeklyBinding() {
        XCTAssertTrue(limits(fiveHour: 100, weekly: 4).isWeeklyBinding)
        XCTAssertFalse(limits(fiveHour: 30, weekly: 80).isWeeklyBinding)
        // Ties read as the 5-hour window
        XCTAssertFalse(limits(fiveHour: 50, weekly: 50).isWeeklyBinding)
        XCTAssertTrue(limits(fiveHour: 100, weekly: 80, hasFiveHour: false).isWeeklyBinding)
        XCTAssertFalse(limits(fiveHour: 100, weekly: 0, hasWeekly: false).isWeeklyBinding)
    }

    func testClaudeUnreportedWindowsAreNil() {
        let onlyWeekly = limits(fiveHour: 100, weekly: 60, hasFiveHour: false)
        XCTAssertNil(onlyWeekly.fiveHourPercent)
        XCTAssertEqual(onlyWeekly.weeklyPercent, 60)
    }

    // MARK: - Claude tiers

    func testPaidTiersCanSeeUsageLimitsAndMatchBadge() {
        let paid = ["claude_pro": "Pro", "pro": "Pro", "claude_max": "Max", "max": "Max",
                    "raven": "Team", "enterprise": "Enterprise", "CLAUDE_PRO": "Pro",
                    "claude_max_20x": "Max", "claude_team": "Team", "claude_enterprise": "Enterprise"]
        for (type, badge) in paid {
            let account = ClaudeAccountInfo(organizationType: type)
            XCTAssertEqual(account.tierBadge, badge, type)
            XCTAssertTrue(account.canSeeUsageLimits, type)
        }
    }

    func testUnknownPaidTierShowsItsOwnNameAndLimits() {
        let account = ClaudeAccountInfo(organizationType: "claude_something_new")
        XCTAssertEqual(account.tierBadge, "Something New")
        XCTAssertEqual(account.formattedTier, "Claude Something New")
        XCTAssertTrue(account.canSeeUsageLimits)
    }

    func testFreeTiersCannotSeeUsageLimits() {
        for type in ["free", "claude_free", "none", "", nil] as [String?] {
            let account = ClaudeAccountInfo(organizationType: type)
            XCTAssertEqual(account.tierBadge, "Free", type ?? "nil")
            XCTAssertFalse(account.canSeeUsageLimits, type ?? "nil")
        }
    }
}
