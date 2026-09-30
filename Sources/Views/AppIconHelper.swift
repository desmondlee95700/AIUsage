//
//  AppIconHelper.swift
//  AIUsage
//

import Cocoa
import SwiftUI

public enum AppIconHelper {
    public static var appIconImage: NSImage? = {
        if let image = NSImage(named: "AppIcon") {
            return image
        }
        if let path = Bundle.main.path(forResource: "AppIcon", ofType: "png"),
           let image = NSImage(contentsOfFile: path) {
            return image
        }
        if let path = Bundle.main.path(forResource: "AppIcon", ofType: "icns"),
           let image = NSImage(contentsOfFile: path) {
            return image
        }
        
        // Portable dev fallback relative to this source file
        let currentFile = URL(fileURLWithPath: #filePath)
        let projectRoot = currentFile
            .deletingLastPathComponent() // Views
            .deletingLastPathComponent() // Sources
            .deletingLastPathComponent() // Project root
        let assetPath = projectRoot.appendingPathComponent("Assets/AppIcon.png").path
        if FileManager.default.fileExists(atPath: assetPath),
           let image = NSImage(contentsOfFile: assetPath) {
            return image
        }
        return nil
    }()
}
