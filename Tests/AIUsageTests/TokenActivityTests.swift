import XCTest
@testable import AIUsage

final class TokenActivityTests: XCTestCase {
    private func data(_ lines: [String]) -> Data {
        Data(lines.joined(separator: "\n").utf8)
    }
    
    func testClaudeLogDedupesRepeatedMessageLines() {
        let usage = #"{"input_tokens":10,"cache_creation_input_tokens":200,"cache_read_input_tokens":3000,"output_tokens":40}"#
        let log = data([
            #"{"type":"user","timestamp":"2026-10-10T08:00:00.000Z","message":{"content":"hi"}}"#,
            #"{"type":"assistant","requestId":"req_1","timestamp":"2026-10-10T08:00:01.000Z","message":{"id":"msg_1","usage":\#(usage)}}"#,
            #"{"type":"assistant","requestId":"req_1","timestamp":"2026-10-10T08:00:02.000Z","message":{"id":"msg_1","usage":\#(usage)}}"#,
            "not json",
        ])
        let entries = TokenActivityService.parseClaudeLog(log)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(Set(entries.compactMap(\.key)).count, 1, "repeated lines share one dedupe key")
        XCTAssertEqual(entries[0].usage, TokenUsage(input: 10, cacheRead: 3000, cacheWrite: 200, output: 40))
        XCTAssertEqual(entries[0].usage.total, 250)
    }
    
    func testCodexLogSkipsRepeatedTurnsAndSplitsCachedInput() {
        func event(_ ts: String, running: Int, input: Int, cached: Int, output: Int) -> String {
            #"{"timestamp":"\#(ts)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":\#(running)},"last_token_usage":{"input_tokens":\#(input),"cached_input_tokens":\#(cached),"output_tokens":\#(output)}}}}"#
        }
        let log = data([
            #"{"timestamp":"2026-10-01T00:00:00Z","type":"event_msg","payload":{"type":"token_count","info":null}}"#,
            event("2026-10-01T00:00:01Z", running: 1100, input: 1000, cached: 600, output: 100),
            event("2026-10-01T00:00:02Z", running: 1100, input: 1000, cached: 600, output: 100),
            event("2026-10-01T00:00:03Z", running: 2300, input: 1150, cached: 1000, output: 50),
        ])
        let entries = TokenActivityService.parseCodexLog(log)
        XCTAssertEqual(entries.map(\.usage), [
            TokenUsage(input: 400, cacheRead: 600, output: 100),
            TokenUsage(input: 150, cacheRead: 1000, output: 50),
        ])
    }
    
    func testSummaryBucketsByLocalDayAndZeroFills() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Singapore")!
        let now = TokenActivityService.parseTimestamp("2026-10-10T04:00:00Z")! // 12:00 local
        let entries: [(timestamp: Date, usage: TokenUsage)] = [
            // 2026-10-09 17:00 UTC is already 10 Oct locally
            (TokenActivityService.parseTimestamp("2026-10-09T17:00:00Z")!, TokenUsage(input: 5, output: 5)),
            (TokenActivityService.parseTimestamp("2026-10-10T01:00:00Z")!, TokenUsage(output: 10)),
            (TokenActivityService.parseTimestamp("2026-10-08T01:00:00Z")!, TokenUsage(cacheRead: 99, output: 7)),
        ]
        let summary = TokenActivitySummary.build(from: entries, dayCount: 7, now: now, calendar: calendar)
        XCTAssertEqual(summary.days.count, 7)
        XCTAssertEqual(summary.today.total, 20)
        XCTAssertEqual(summary.days[5].usage.total, 0)
        XCTAssertEqual(summary.days[4].usage, TokenUsage(cacheRead: 99, output: 7))
        XCTAssertEqual(summary.periodTotal.total, 27)
        XCTAssertEqual(summary.peakDayTotal, 20)
    }
    
    func testLastDaysKeepsMostRecentDays() {
        let now = Date()
        let summary = TokenActivitySummary.build(
            from: [(now, TokenUsage(output: 5)), (now.addingTimeInterval(-20 * 86_400), TokenUsage(output: 100))],
            dayCount: 30,
            now: now
        )
        let week = summary.lastDays(7)
        XCTAssertEqual(week.days.count, 7)
        XCTAssertEqual(week.days.last, summary.days.last)
        XCTAssertEqual(week.periodTotal.total, 5)
        XCTAssertEqual(summary.lastDays(TokenActivityRange.month.rawValue).periodTotal.total, 105)
    }
    
    func testFormatTokens() {
        XCTAssertEqual(TokenActivitySummary.formatTokens(950), "950")
        XCTAssertEqual(TokenActivitySummary.formatTokens(144_583), "144.6K")
        XCTAssertEqual(TokenActivitySummary.formatTokens(4_159_117), "4.2M")
    }
}
