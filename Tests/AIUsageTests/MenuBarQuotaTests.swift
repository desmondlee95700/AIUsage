import XCTest
@testable import AIUsage

final class MenuBarQuotaTests: XCTestCase {
    @MainActor
    func testCodexBothCapsAndWeeklyOnly() async throws {
        let service = QuotaService()
        service.isCodexConnected = true
        service.codexRateLimits = try JSONDecoder().decode(CodexRateLimitsResponse.self, from: Data(#"{"rateLimits":{"primary":{"usedPercent":47,"windowDurationMins":300},"secondary":{"usedPercent":10,"windowDurationMins":10080}}}"#.utf8))
        XCTAssertEqual(service.menuBarQuotaLines(for: .chatgpt), ["53%", "90%"])
        service.codexRateLimits = try JSONDecoder().decode(CodexRateLimitsResponse.self, from: Data(#"{"rateLimits":{"primary":{"usedPercent":10,"windowDurationMins":10080}}}"#.utf8))
        XCTAssertEqual(service.menuBarQuotaLines(for: .chatgpt), ["90%"])
        XCTAssertEqual(service.menuBarQuotaLines(for: .chatgpt, includeWindowLabels: true), ["90% wk"])
        service.isCodexConnected = false
        XCTAssertEqual(service.menuBarQuotaLines(for: .chatgpt), ["Off"])
    }

    @MainActor
    func testClaudeMissingCapsAreHidden() async throws {
        let service = QuotaService()
        service.isClaudeConnected = true
        service.claudeLimits = ClaudeService.parseUsageLimits(Data(#"{"five_hour":{"utilization":47},"seven_day":{"utilization":10}}"#.utf8))
        XCTAssertEqual(service.menuBarQuotaLines(for: .claude), ["53%", "90%"])
        service.claudeLimits = ClaudeService.parseUsageLimits(Data(#"{"five_hour":null,"seven_day":{"utilization":10}}"#.utf8))
        XCTAssertEqual(service.menuBarQuotaLines(for: .claude), ["90%"])
        service.claudeLimits = nil
        XCTAssertEqual(service.menuBarQuotaLines(for: .claude), ["–"])
    }

    @MainActor
    func testAntigravityWeeklyOnlyDoesNotDuplicateCap() async throws {
        let service = QuotaService()
        service.isGeminiConnected = true
        service.quotaSummary = try JSONDecoder().decode(QuotaSummaryData.self, from: Data(#"{"groups":[{"displayName":"Gemini","buckets":[{"bucketId":"week","displayName":"Weekly","window":"WEEKLY","remainingFraction":0.9}]}]}"#.utf8))
        XCTAssertEqual(service.menuBarQuotaLines(for: .gemini), ["90%"])
        let bothCaps = #"{"groups":[{"displayName":"Gemini","buckets":["#
            + #"{"bucketId":"5h","displayName":"5-hour","window":"5h","remainingFraction":0.53},"#
            + #"{"bucketId":"weekly","displayName":"Weekly","window":"weekly","remainingFraction":0.9}]}]}"#
        service.quotaSummary = try JSONDecoder().decode(QuotaSummaryData.self, from: Data(bothCaps.utf8))
        XCTAssertEqual(service.menuBarQuotaLines(for: .gemini), ["53%", "90%"])
    }
}
