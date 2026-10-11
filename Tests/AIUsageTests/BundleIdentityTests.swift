import XCTest
@testable import AIUsage

final class BundleIdentityTests: XCTestCase {
    func testLegacySettingsFillMissingKeys() {
        let merged = BundleIdentity.merge(
            legacy: ["refreshInterval": 300, "selectedProviders": ["claude"]],
            into: ["menuBarDisplayMode": "Icon Only"]
        )
        XCTAssertEqual(merged["refreshInterval"] as? Int, 300)
        XCTAssertEqual(merged["selectedProviders"] as? [String], ["claude"])
        XCTAssertEqual(merged["menuBarDisplayMode"] as? String, "Icon Only")
    }

    func testCurrentSettingsWinOverLegacy() {
        let merged = BundleIdentity.merge(legacy: ["refreshInterval": 300], into: ["refreshInterval": 60])
        XCTAssertEqual(merged["refreshInterval"] as? Int, 60)
    }

    func testUpdateURLPolicy() {
        let trusted = [
            "https://github.com/desmondlee95700/AIUsage/releases/download/v2.4.0/AIUsage.dmg",
            "https://github.com/desmondlee95700/AIUsage/releases/tag/v2.4.0"
        ]
        for string in trusted {
            XCTAssertTrue(UpdateService.isTrustedReleaseURL(URL(string: string)!), string)
        }
        let untrusted = [
            "http://github.com/desmondlee95700/AIUsage/releases/download/v2.4.0/AIUsage.dmg",
            "https://github.com/someone-else/AIUsage/releases/download/v2.4.0/AIUsage.dmg",
            "https://github.com/desmondlee95700/AIUsage/archive/main.zip",
            "https://evil.example.com/desmondlee95700/AIUsage/releases/download/v2.4.0/AIUsage.dmg"
        ]
        for string in untrusted {
            XCTAssertFalse(UpdateService.isTrustedReleaseURL(URL(string: string)!), string)
        }

        XCTAssertTrue(UpdateService.isAllowedHost(URL(string: "https://release-assets.githubusercontent.com/x")!))
        XCTAssertFalse(UpdateService.isAllowedHost(URL(string: "http://release-assets.githubusercontent.com/x")!))
        XCTAssertFalse(UpdateService.isAllowedHost(URL(string: "https://objects.example.com/x")!))
    }
}
