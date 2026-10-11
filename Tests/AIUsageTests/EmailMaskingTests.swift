import XCTest
@testable import AIUsage

final class EmailMaskingTests: XCTestCase {
    func testMasksNameAndKeepsDomain() {
        XCTAssertEqual(EmailMasking.mask("d3smond95@gmail.com"), "d3•••@gmail.com")
        XCTAssertEqual(EmailMasking.mask("ab@example.com"), "a•••@example.com")
        // A one-letter name never reveals the whole name
        XCTAssertEqual(EmailMasking.mask("a@example.com"), "•••@example.com")
    }

    func testNonEmailValues() {
        XCTAssertEqual(EmailMasking.mask("Organization"), "Or•••")
        XCTAssertEqual(EmailMasking.mask("ab"), "ab")
    }
}
