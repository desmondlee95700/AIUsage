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
}
