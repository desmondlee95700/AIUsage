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
        let fallbackPath = "/Users/dessy/Documents/sidehustle/AIUsage/Assets/AppIcon.png"
        if FileManager.default.fileExists(atPath: fallbackPath),
           let image = NSImage(contentsOfFile: fallbackPath) {
            return image
        }
        return nil
    }()
}
