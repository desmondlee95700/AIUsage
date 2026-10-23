import XCTest
@testable import AIUsage

final class UpdateDownloadTests: XCTestCase {
    private var dir: URL!
    private let url = URL(string: "https://github.com/desmondlee95700/AIUsage/releases/download/v9.9.9/AIUsage.dmg")!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeTemp(bytes: Int) throws -> URL {
        let file = dir.appendingPathComponent("download.tmp")
        try Data(repeating: 0, count: bytes).write(to: file)
        return file
    }

    private func response(_ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    func testMovesValidDownloadIntoPlace() throws {
        let temp = try makeTemp(bytes: 64)
        let dest = dir.appendingPathComponent("AIUsage-v9.9.9.dmg")
        // An older copy at the destination is replaced
        try Data([1]).write(to: dest)

        let failure = UpdateService.saveDownload(tempURL: temp, response: response(200), error: nil, expectedSize: 64, to: dest)

        XCTAssertNil(failure)
        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.path))
        XCTAssertEqual(try Data(contentsOf: dest).count, 64)
    }

    func testRejectsNonOKStatus() throws {
        let temp = try makeTemp(bytes: 64)
        let dest = dir.appendingPathComponent("AIUsage.dmg")

        let failure = UpdateService.saveDownload(tempURL: temp, response: response(404), error: nil, expectedSize: nil, to: dest)

        XCTAssertNotNil(failure)
        XCTAssertTrue(failure?.contains("404") == true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest.path))
    }

    func testRejectsSizeMismatch() throws {
        let temp = try makeTemp(bytes: 10)
        let dest = dir.appendingPathComponent("AIUsage.dmg")

        let failure = UpdateService.saveDownload(tempURL: temp, response: response(200), error: nil, expectedSize: 64, to: dest)

        XCTAssertNotNil(failure)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest.path))
    }

    func testReportsTransportError() {
        let dest = dir.appendingPathComponent("AIUsage.dmg")
        let failure = UpdateService.saveDownload(
            tempURL: nil, response: nil, error: URLError(.notConnectedToInternet), expectedSize: nil, to: dest
        )
        XCTAssertNotNil(failure)
    }

    func testRejectsChecksumMismatch() throws {
        let temp = try makeTemp(bytes: 64)
        let dest = dir.appendingPathComponent("AIUsage-v9.9.9.dmg")

        let failure = UpdateService.saveDownload(
            tempURL: temp, response: response(200), error: nil, expectedSize: 64,
            expectedSHA256: String(repeating: "0", count: 64), to: dest
        )

        XCTAssertNotNil(failure)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest.path))
    }

    func testAcceptsMatchingChecksum() throws {
        let temp = try makeTemp(bytes: 64)
        let dest = dir.appendingPathComponent("AIUsage-v9.9.9.dmg")
        // SHA-256 of 64 zero bytes
        let digest = "F5A5FD42D16A20302798EF6ED309979B43003D2320D9F0E8EA9831A92759FB4B"

        let failure = UpdateService.saveDownload(
            tempURL: temp, response: response(200), error: nil, expectedSize: 64,
            expectedSHA256: digest, to: dest
        )

        XCTAssertNil(failure)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.path))
    }

    func testReadsDigestFromShasumOutput() {
        let hex = String(repeating: "ab", count: 32)
        let sums = Data("\(String(repeating: "cd", count: 32))  AIUsage-v9.9.9.dmg\n\(hex) *AIUsage.dmg\n".utf8)

        XCTAssertEqual(UpdateService.sha256(for: "AIUsage.dmg", inChecksums: sums), hex)
        XCTAssertNil(UpdateService.sha256(for: "Other.dmg", inChecksums: sums))
        XCTAssertNil(UpdateService.sha256(for: "AIUsage.dmg", inChecksums: Data("nothex  AIUsage.dmg".utf8)))
    }
}
