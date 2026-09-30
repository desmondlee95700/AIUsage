//
//  AppVersion.swift
//  AIUsage
//

import Foundation

public enum AppVersion {
    /// Semantic marketing version string (e.g. "1.1.8")
    public static var current: String {
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
           !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return version
        }
        return "1.1.8"
    }

    /// Internal build version number (e.g. "9")
    public static var build: String {
        if let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String,
           !build.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return build
        }
        return "9"
    }

    /// Display string with version prefix (e.g. "v1.1.8")
    public static var displayString: String {
        "v\(current)"
    }
}
