//
//  AppIconHelper.swift
//  AIUsage
//

import Cocoa
import SwiftUI

public enum AppIconHelper {
    private static func loadAsset(named name: String, ofType ext: String) -> NSImage? {
        // Try Bundle resources
        if let image = NSImage(named: name) {
            return image
        }
        if let path = Bundle.main.path(forResource: name, ofType: ext),
           let image = NSImage(contentsOfFile: path) {
            return image
        }
        
        // Portable dev fallback relative to source location
        let currentFile = URL(fileURLWithPath: #filePath)
        let projectRoot = currentFile
            .deletingLastPathComponent() // Views
            .deletingLastPathComponent() // Sources
            .deletingLastPathComponent() // Project root
        let assetPath = projectRoot.appendingPathComponent("Assets/\(name).\(ext)").path
        if FileManager.default.fileExists(atPath: assetPath),
           let image = NSImage(contentsOfFile: assetPath) {
            return image
        }
        return nil
    }
    
    public static var appIconImage: NSImage? = {
        guard let image = loadAsset(named: "AppIcon", ofType: "png") ?? loadAsset(named: "AppIcon", ofType: "icns") else { return nil }
        image.size = NSSize(width: 32, height: 32)
        return image
    }()
    
    public static var antigravityIcon: NSImage? = {
        guard let image = loadAsset(named: "AntigravityIcon", ofType: "png") ?? appIconImage else { return nil }
        image.size = NSSize(width: 32, height: 32)
        return image
    }()
    
    public static var chatgptIcon: NSImage? = {
        guard let image = loadAsset(named: "ChatGPTIcon", ofType: "png") else { return nil }
        image.size = NSSize(width: 32, height: 32)
        return image
    }()
    
    public static var claudeIcon: NSImage? = {
        guard let image = loadAsset(named: "ClaudeIcon", ofType: "png") else { return nil }
        image.size = NSSize(width: 32, height: 32)
        return image
    }()
    
    public static var antigravityTemplate: NSImage? = {
        if let image = loadAsset(named: "AntigravityTemplate@2x", ofType: "png") ?? loadAsset(named: "AntigravityTemplate", ofType: "png") {
            image.size = NSSize(width: 14, height: 14)
            image.isTemplate = true
            return image
        }
        return nil
    }()
    
    public static var chatgptTemplate: NSImage? = {
        if let image = loadAsset(named: "ChatGPTTemplate@2x", ofType: "png") ?? loadAsset(named: "ChatGPTTemplate", ofType: "png") {
            image.size = NSSize(width: 14, height: 14)
            image.isTemplate = true
            return image
        }
        return nil
    }()
    
    public static var claudeTemplate: NSImage? = {
        if let image = loadAsset(named: "ClaudeTemplate@2x", ofType: "png") ?? loadAsset(named: "ClaudeTemplate", ofType: "png") {
            image.size = NSSize(width: 14, height: 14)
            image.isTemplate = true
            return image
        }
        return nil
    }()
    
    public static var dualTemplate: NSImage? = {
        let size = NSSize(width: 32, height: 14)
        let img = NSImage(size: size, flipped: false) { rect in
            if let ag = antigravityTemplate {
                ag.draw(in: NSRect(x: 0, y: 0, width: 14, height: 14), from: .zero, operation: .sourceOver, fraction: 1.0)
            }
            if let cg = chatgptTemplate {
                cg.draw(in: NSRect(x: 18, y: 0, width: 14, height: 14), from: .zero, operation: .sourceOver, fraction: 1.0)
            }
            return true
        }
        img.isTemplate = true
        return img
    }()
}
