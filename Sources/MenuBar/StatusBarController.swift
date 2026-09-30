import Cocoa
import SwiftUI

public class StatusBarController {
    private var statusItem: NSStatusItem
    private var popover: NSPopover
    private var service: QuotaService
    private var eventMonitor: Any?
    
    public init(service: QuotaService = .shared) {
        self.service = service
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        
        setupPopover()
        setupStatusButton()
        
        service.updateMenuBarCallback = { [weak self] in
            DispatchQueue.main.async {
                self?.updateStatusButton()
            }
        }
        
        // Initial refresh
        service.refresh()
    }
    
    private func setupPopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .darkAqua)
        let hosting = NSHostingController(rootView: MainUsageView(service: service))
        popover.contentViewController = hosting
        updatePopoverSize(force: true)
    }
    
    public func updatePopoverSize(force: Bool = false) {
        guard let controller = popover.contentViewController else { return }
        controller.view.layoutSubtreeIfNeeded()
        let targetHeight = ceil(controller.view.fittingSize.height)
        guard targetHeight > 50 else { return }
        
        let currentHeight = popover.contentSize.height
        // Only resize if forced, initial load (currentHeight <= 0), or height delta > 25pt
        if force || currentHeight <= 0 || abs(currentHeight - targetHeight) > 25 {
            popover.contentSize = NSSize(width: 380, height: targetHeight)
        }
    }
    
    private func setupStatusButton() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        
        updateStatusButton()
    }
    
    public func updateStatusButton() {
        guard let button = statusItem.button else { return }
        
        let renderedImage = renderMenuBarImage()
        button.image = renderedImage
        button.imagePosition = .imageOnly
        button.title = ""
        button.attributedTitle = NSAttributedString()
        button.toolTip = service.menuBarTooltip
    }
    
    // MARK: - Template Menu Bar Image Generator
    
    private func renderMenuBarImage() -> NSImage {
        let font = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black
        ]
        let secondaryAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(white: 0, alpha: 0.45)
        ]
        
        let iconSize: CGFloat = 14.0
        let height: CGFloat = 18.0
        
        switch service.displayMode {
        case .iconOnly:
            let icon = (service.activeProvider == .gemini ? AppIconHelper.antigravityTemplate : AppIconHelper.chatgptTemplate)
                ?? NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)!
            icon.isTemplate = true
            return icon
            
        case .dual:
            let geminiStr = service.isGeminiConnected ? " \(service.geminiPercentage)%" : " Off"
            let chatgptStr = service.isCodexConnected ? " \(service.codexRemainingPercentage)%" : " Off"
            
            let agText = NSAttributedString(string: geminiStr, attributes: textAttrs)
            let sepText = NSAttributedString(string: "  ·  ", attributes: secondaryAttrs)
            let cgText = NSAttributedString(string: chatgptStr, attributes: textAttrs)
            
            let agImg = AppIconHelper.antigravityTemplate
            let cgImg = AppIconHelper.chatgptTemplate
            
            let agWidth = (agImg != nil ? iconSize : 0) + agText.size().width
            let sepWidth = sepText.size().width
            let cgWidth = (cgImg != nil ? iconSize : 0) + cgText.size().width
            let totalWidth = ceil(agWidth + sepWidth + cgWidth)
            
            let img = NSImage(size: NSSize(width: totalWidth, height: height), flipped: false) { rect in
                var x: CGFloat = 0
                let iconY: CGFloat = (height - iconSize) / 2
                let textY: CGFloat = (height - agText.size().height) / 2
                
                // 1. Antigravity Icon
                if let ag = agImg {
                    ag.draw(in: NSRect(x: x, y: iconY, width: iconSize, height: iconSize), from: .zero, operation: .sourceOver, fraction: 1.0)
                    x += iconSize
                }
                // 2. Gemini Text
                agText.draw(at: NSPoint(x: x, y: textY))
                x += agText.size().width
                
                // 3. Separator
                sepText.draw(at: NSPoint(x: x, y: textY))
                x += sepText.size().width
                
                // 4. ChatGPT Icon
                if let cg = cgImg {
                    cg.draw(in: NSRect(x: x, y: iconY, width: iconSize, height: iconSize), from: .zero, operation: .sourceOver, fraction: 1.0)
                    x += iconSize
                }
                // 5. ChatGPT Text
                cgText.draw(at: NSPoint(x: x, y: textY))
                
                return true
            }
            img.isTemplate = true
            return img
            
        case .activeProvider:
            let isGemini = service.activeProvider == .gemini
            let icon = isGemini ? AppIconHelper.antigravityTemplate : AppIconHelper.chatgptTemplate
            let textStr = isGemini
                ? (service.isGeminiConnected ? " \(service.geminiPercentage)%" : " Offline")
                : (service.isCodexConnected ? " \(service.codexRemainingPercentage)%" : " Offline")
            
            let text = NSAttributedString(string: textStr, attributes: textAttrs)
            let totalWidth = ceil((icon != nil ? iconSize : 0) + text.size().width)
            
            let img = NSImage(size: NSSize(width: totalWidth, height: height), flipped: false) { rect in
                var x: CGFloat = 0
                let iconY: CGFloat = (height - iconSize) / 2
                let textY: CGFloat = (height - text.size().height) / 2
                
                if let ic = icon {
                    ic.draw(in: NSRect(x: x, y: iconY, width: iconSize, height: iconSize), from: .zero, operation: .sourceOver, fraction: 1.0)
                    x += iconSize
                }
                text.draw(at: NSPoint(x: x, y: textY))
                return true
            }
            img.isTemplate = true
            return img
            
        case .weekly:
            let icon = AppIconHelper.antigravityTemplate
            let textStr = service.isGeminiConnected ? " \(service.geminiPercentage)%" : " Offline"
            let text = NSAttributedString(string: textStr, attributes: textAttrs)
            let totalWidth = ceil((icon != nil ? iconSize : 0) + text.size().width)
            
            let img = NSImage(size: NSSize(width: totalWidth, height: height), flipped: false) { rect in
                var x: CGFloat = 0
                let iconY: CGFloat = (height - iconSize) / 2
                let textY: CGFloat = (height - text.size().height) / 2
                
                if let ic = icon {
                    ic.draw(in: NSRect(x: x, y: iconY, width: iconSize, height: iconSize), from: .zero, operation: .sourceOver, fraction: 1.0)
                    x += iconSize
                }
                text.draw(at: NSPoint(x: x, y: textY))
                return true
            }
            img.isTemplate = true
            return img
        }
    }
    
    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showContextMenu(button)
            return
        }
        
        if popover.isShown {
            hidePopover(sender)
        } else {
            showPopover(button)
        }
    }
    
    private func showPopover(_ button: NSStatusBarButton) {
        // Refresh quotas automatically when popover is opened
        service.refresh()
        
        updatePopoverSize(force: false)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        if let window = popover.contentViewController?.view.window {
            window.isOpaque = false
            window.backgroundColor = .clear
            window.makeKey()
        }
    }
    
    private func hidePopover(_ sender: AnyObject?) {
        popover.performClose(sender)
    }
    
    private func showContextMenu(_ button: NSStatusBarButton) {
        let menu = NSMenu()
        
        // Header
        let titleItem = NSMenuItem(title: "AIUsage", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(NSMenuItem.separator())
        
        // Provider Selection
        let geminiItem = NSMenuItem(title: "Gemini (Antigravity)", action: #selector(switchToGeminiAction), keyEquivalent: "1")
        if let agImg = AppIconHelper.antigravityTemplate {
            geminiItem.image = agImg
        }
        geminiItem.state = service.activeProvider == .gemini ? .on : .off
        geminiItem.target = self
        menu.addItem(geminiItem)
        
        let chatgptItem = NSMenuItem(title: "ChatGPT (Codex)", action: #selector(switchToChatGPTAction), keyEquivalent: "2")
        if let cgImg = AppIconHelper.chatgptTemplate {
            chatgptItem.image = cgImg
        }
        chatgptItem.state = service.activeProvider == .chatgpt ? .on : .off
        chatgptItem.target = self
        menu.addItem(chatgptItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Display Mode Submenu
        let displayMenu = NSMenu()
        for mode in MenuBarDisplayMode.allCases {
            let item = NSMenuItem(title: mode.rawValue, action: #selector(changeDisplayModeAction(_:)), keyEquivalent: "")
            item.representedObject = mode
            item.state = service.displayMode == mode ? .on : .off
            item.target = self
            displayMenu.addItem(item)
        }
        let displaySubItem = NSMenuItem(title: "Menu Bar Display", action: nil, keyEquivalent: "")
        displaySubItem.submenu = displayMenu
        menu.addItem(displaySubItem)
        
        // Refresh Interval Submenu
        let intervalMenu = NSMenu()
        for interval in RefreshInterval.allCases {
            let item = NSMenuItem(title: interval.title, action: #selector(changeRefreshIntervalAction(_:)), keyEquivalent: "")
            item.representedObject = interval
            item.state = service.refreshInterval == interval ? .on : .off
            item.target = self
            intervalMenu.addItem(item)
        }
        let intervalSubItem = NSMenuItem(title: "Refresh Interval", action: nil, keyEquivalent: "")
        intervalSubItem.submenu = intervalMenu
        menu.addItem(intervalSubItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Actions
        let refreshItem = NSMenuItem(title: "Refresh All Now", action: #selector(refreshAction), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit AIUsage", action: #selector(quitAction), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = nil // Restore normal click behavior
    }
    
    @objc private func switchToGeminiAction() {
        service.activeProvider = .gemini
    }
    
    @objc private func switchToChatGPTAction() {
        service.activeProvider = .chatgpt
    }
    
    @objc private func changeDisplayModeAction(_ sender: NSMenuItem) {
        if let mode = sender.representedObject as? MenuBarDisplayMode {
            service.displayMode = mode
        }
    }
    
    @objc private func changeRefreshIntervalAction(_ sender: NSMenuItem) {
        if let interval = sender.representedObject as? RefreshInterval {
            service.refreshInterval = interval
        }
    }
    
    @objc private func refreshAction() {
        service.refresh(forceDiscovery: true)
    }
    
    @objc private func quitAction() {
        NSApplication.shared.terminate(nil)
    }
}
