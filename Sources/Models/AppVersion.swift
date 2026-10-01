//
//  AppVersion.swift
//  AIUsage
//

import Foundation

public enum AppVersion {
    /// Semantic marketing version string (e.g. "2.0.0")
    public static var current: String {
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
           !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return version
        }
        return "2.0.0"
    }

    /// Internal build version number (e.g. "11")
    public static var build: String {
        if let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String,
           !build.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return build
        }
        return "11"
    }

    /// Display string with version prefix (e.g. "v2.0.0")
    public static var displayString: String {
        "v\(current)"
    }
}
