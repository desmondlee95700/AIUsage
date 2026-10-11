import XCTest
@testable import AIUsage

final class VersionComparisonTests: XCTestCase {
    func testPlainTextReleaseNotes() {
        let body = """
        ## 🐛 Fixes

        - **release:** handle pre-release versions in updater and release script
        - refresh, notification, parsing and threading bugs; remove dead code


        **Full changelog:** https://github.com/desmondlee95700/AIUsage/compare/v2.1.2...v2.1.3
        """
        XCTAssertEqual(
            UpdateService.plainTextReleaseNotes(body),
            "🐛 Fixes\n\n• release: handle pre-release versions in updater and release script\n• refresh, notification, parsing and threading bugs; remove dead code"
        )
        let truncated = UpdateService.plainTextReleaseNotes("- one\n- two\n- three", maxLength: 12)
        XCTAssertEqual(truncated, "• one\n• two\n…")
    }

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

    func testPrereleaseOrdering() {
        // A release outranks its own pre-releases...
        XCTAssertTrue(UpdateService.isVersion("v2.1.3", greaterThan: "2.1.3-rc.1"))
        XCTAssertFalse(UpdateService.isVersion("v2.1.3-rc.1", greaterThan: "2.1.3"))
        // ...but a pre-release still outranks the previous release, so rc testers aren't offered a downgrade
        XCTAssertTrue(UpdateService.isVersion("2.1.3-rc.1", greaterThan: "2.1.2"))
        XCTAssertFalse(UpdateService.isVersion("v2.1.2", greaterThan: "2.1.3-rc.1"))
        // Pre-release identifiers follow semver precedence
        XCTAssertTrue(UpdateService.isVersion("2.1.3-rc.2", greaterThan: "2.1.3-rc.1"))
        XCTAssertTrue(UpdateService.isVersion("2.1.3-rc.10", greaterThan: "2.1.3-rc.9"))
        XCTAssertTrue(UpdateService.isVersion("2.1.3-rc.1", greaterThan: "2.1.3-beta.5"))
        XCTAssertTrue(UpdateService.isVersion("2.1.3-rc.1", greaterThan: "2.1.3-rc"))
        XCTAssertFalse(UpdateService.isVersion("2.1.3-rc.1", greaterThan: "2.1.3-rc.1"))
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

    func testResetCountdownUsesDescriptionOnlyWithoutTimestamp() {
        XCTAssertEqual(bucket(fraction: 1, description: "Resets Monday").formattedResetCountdown, "Resets Monday")
        // A timestamp gives a live countdown, which beats static server text
        let future = ISO8601DateFormatter().string(from: Date().addingTimeInterval(3 * 3600 + 90))
        XCTAssertEqual(bucket(fraction: 1, description: "Resets Monday", resetTime: future).formattedResetCountdown, "Resets in 3h 1m")
    }

    func testMenuBarDisplayModeMigration() {
        XCTAssertEqual(MenuBarDisplayMode(savedValue: "Icon Only"), .iconOnly)
        for old in ["Dual (Antigravity & ChatGPT)", "Active Provider Only", "Antigravity Weekly Only", "Percentages", nil] as [String?] {
            XCTAssertEqual(MenuBarDisplayMode(savedValue: old), .percentages, old ?? "nil")
        }
    }

    func testResetCountdownFromTimestamp() {
        XCTAssertEqual(bucket(fraction: 1, resetTime: "2000-01-01T00:00:00Z").formattedResetCountdown, "Resets soon")
        XCTAssertNil(bucket(fraction: 1, resetTime: "not a date").formattedResetCountdown)

        let future = ISO8601DateFormatter().string(from: Date().addingTimeInterval(2 * 86400 + 3 * 3600 + 60))
        XCTAssertEqual(bucket(fraction: 1, resetTime: future).formattedResetCountdown, "Resets in 2d 3h")
    }
}
