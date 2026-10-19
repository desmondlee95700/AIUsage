import XCTest
@testable import AIUsage

final class QuotaTileTests: XCTestCase {
    func testCompactResetTextDropsOnlyTheResetsInPrefix() {
        XCTAssertEqual(QuotaTile.compactResetText("Resets in 1d 18h"), "1d 18h")
        XCTAssertEqual(QuotaTile.compactResetText("Resets soon"), "Resets soon")
        XCTAssertEqual(QuotaTile.compactResetText("Refreshed"), "Refreshed")
        XCTAssertEqual(QuotaTile.compactResetText("Fully refreshed"), "Fully refreshed")
    }
}
