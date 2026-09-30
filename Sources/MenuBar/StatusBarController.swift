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
        
        service.onFocusModeChanged = { [weak self] in
            DispatchQueue.main.async {
                self?.updateStatusButton()
            }
        }
        
        // Initial refresh
        service.refresh()
    }
    
    private func setupPopover() {
        popover.behavior = .transient
        popover.animates = false
        popover.appearance = NSAppearance(named: .darkAqua)

        let hosting = NSHostingController(
            rootView: MainUsageView(service: service)
                .environmentObject(LiquidGlassObserver.shared)
        )


        // Make the hosting view itself fully transparent so the NSVisualEffectView
        // behind it can sample the real desktop wallpaper (same as Control Center).
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = NSColor.clear.cgColor

        // Embed a full-size NSVisualEffectView as the background layer.
        // This must be at the AppKit level — SwiftUI .background() alone cannot
        // pierce the opaque NSHostingView container.
        let effectView = NSVisualEffectView()
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.translatesAutoresizingMaskIntoConstraints = false

        // Insert effectView *behind* the hosting view inside a wrapper
        let wrapper = NSViewController()
        wrapper.addChild(hosting)
        wrapper.view = NSView()
        wrapper.view.wantsLayer = true
        wrapper.view.layer?.backgroundColor = NSColor.clear.cgColor

        wrapper.view.addSubview(effectView)
        wrapper.view.addSubview(hosting.view)

        effectView.translatesAutoresizingMaskIntoConstraints = false
        hosting.view.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: wrapper.view.leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: wrapper.view.trailingAnchor),
            effectView.topAnchor.constraint(equalTo: wrapper.view.topAnchor),
            effectView.bottomAnchor.constraint(equalTo: wrapper.view.bottomAnchor),

            hosting.view.leadingAnchor.constraint(equalTo: wrapper.view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: wrapper.view.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: wrapper.view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: wrapper.view.bottomAnchor),
        ])

        popover.contentViewController = wrapper
        updatePopoverSize(force: true)
    }
    
    public func updatePopoverSize(force: Bool = false) {
        guard let controller = popover.contentViewController else { return }
        // The hosting controller is a child of the wrapper; measure its fitting size.
        let measureView = controller.children.first?.view ?? controller.view
        measureView.layoutSubtreeIfNeeded()
        let targetHeight = ceil(measureView.fittingSize.height)
        guard targetHeight > 50 else { return }

        let currentHeight = popover.contentSize.height
        // Only resize if forced, initial load (currentHeight <= 0), or height delta > 10pt
        if force || currentHeight <= 0 || abs(currentHeight - targetHeight) > 10 {
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
        
        if service.displayMode == .iconOnly {
            let icon: NSImage
            switch service.providerFocusMode {
            case .gemini:
                icon = AppIconHelper.antigravityTemplate ?? NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)!
            case .chatgpt:
                icon = AppIconHelper.chatgptTemplate ?? NSImage(systemSymbolName: "circle.hexagongrid", accessibilityDescription: nil)!
            case .claude:
                icon = NSImage(systemSymbolName: "asterisk", accessibilityDescription: nil)!
            case .both:
                icon = AppIconHelper.dualTemplate ?? NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)!
            }
            icon.isTemplate = true
            return icon
        }
        
        switch service.providerFocusMode {
        case .gemini:
            return renderSingleProviderImage(provider: .gemini)
            
        case .chatgpt:
            return renderSingleProviderImage(provider: .chatgpt)
            
        case .claude:
            return renderSingleProviderImage(provider: .claude)
            
        case .both:
            let hasAG = service.isGeminiInstalled
            let hasCodex = service.isCodexInstalled
            
            // If neither is installed
            if !hasAG && !hasCodex {
                let icon = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)!
                icon.isTemplate = true
                return icon
            }
            
            // If only one is installed, don't show "Off" for the uninstalled tool
            if hasAG && !hasCodex {
                return renderSingleProviderImage(provider: .gemini)
            }
            if !hasAG && hasCodex {
                return renderSingleProviderImage(provider: .chatgpt)
            }
            
            // Both are installed: render Dual
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
        }
    }
    
    private func renderSingleProviderImage(provider: AIProvider) -> NSImage {
        let font = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black
        ]
        let iconSize: CGFloat = 14.0
        let height: CGFloat = 18.0
        
        let icon: NSImage?
        let textStr: String
        
        switch provider {
        case .gemini:
            icon = AppIconHelper.antigravityTemplate
            textStr = service.isGeminiConnected ? " \(service.geminiPercentage)%" : " Off"
        case .chatgpt:
            icon = AppIconHelper.chatgptTemplate
            textStr = service.isCodexConnected ? " \(service.codexRemainingPercentage)%" : " Off"
        case .claude:
            icon = NSImage(systemSymbolName: "asterisk", accessibilityDescription: nil)
            textStr = " Ready"
        }
        
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
        let titleItem = NSMenuItem(title: "AIUsage \(AppVersion.displayString)", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(NSMenuItem.separator())
        
        let bothInstalled = service.isGeminiInstalled && service.isCodexInstalled
        
        let selectedTitle: String = {
            if !service.isGeminiInstalled && !service.isCodexInstalled {
                return "None"
            }
            switch service.providerFocusMode {
            case .both:
                return "Both"
            case .gemini:
                return "Antigravity (Google)"
            case .chatgpt:
                return "ChatGPT (OpenAI)"
            case .claude:
                return "Claude (Anthropic)"
            }
        }()
        
        let selectedIcon: NSImage? = {
            switch service.providerFocusMode {
            case .both:
                return AppIconHelper.dualTemplate
            case .gemini:
                return AppIconHelper.antigravityTemplate
            case .chatgpt:
                return AppIconHelper.chatgptTemplate
            case .claude:
                return NSImage(systemSymbolName: "asterisk", accessibilityDescription: nil)
            }
        }()
        
        // Provider Focus Submenu (Both, Antigravity, ChatGPT)
        let focusMenu = NSMenu()
        if bothInstalled {
            let bothModeItem = NSMenuItem(title: "Both (Antigravity & ChatGPT)", action: #selector(switchToBothAction), keyEquivalent: "b")
            bothModeItem.image = AppIconHelper.dualTemplate
            bothModeItem.state = (service.providerFocusMode == .both) ? .on : .off
            bothModeItem.target = self
            focusMenu.addItem(bothModeItem)
        }
        
        if service.isGeminiInstalled {
            let geminiModeItem = NSMenuItem(title: "Antigravity (Google)", action: #selector(switchToGeminiAction), keyEquivalent: "1")
            geminiModeItem.image = AppIconHelper.antigravityTemplate
            geminiModeItem.state = (service.providerFocusMode == .gemini) ? .on : .off
            geminiModeItem.target = self
            focusMenu.addItem(geminiModeItem)
        }
        
        if service.isCodexInstalled {
            let chatgptModeItem = NSMenuItem(title: "ChatGPT (OpenAI)", action: #selector(switchToChatGPTAction), keyEquivalent: "2")
            chatgptModeItem.image = AppIconHelper.chatgptTemplate
            chatgptModeItem.state = (service.providerFocusMode == .chatgpt) ? .on : .off
            chatgptModeItem.target = self
            focusMenu.addItem(chatgptModeItem)
        }
        
        let focusSubItem = NSMenuItem(title: "Provider Focus (\(selectedTitle))", action: nil, keyEquivalent: "")
        focusSubItem.image = selectedIcon
        focusSubItem.submenu = focusMenu
        menu.addItem(focusSubItem)
        
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
        
        // App Launch Actions
        if service.isGeminiInstalled || service.isCodexInstalled {
            menu.addItem(NSMenuItem.separator())
            if service.isGeminiInstalled {
                let launchAGItem = NSMenuItem(title: "Launch Antigravity", action: #selector(launchAntigravityAction), keyEquivalent: "")
                launchAGItem.image = AppIconHelper.antigravityTemplate
                launchAGItem.target = self
                menu.addItem(launchAGItem)
            }
            if service.isCodexInstalled {
                let launchCGItem = NSMenuItem(title: "Launch ChatGPT", action: #selector(launchChatGPTAction), keyEquivalent: "")
                launchCGItem.image = AppIconHelper.chatgptTemplate
                launchCGItem.target = self
                menu.addItem(launchCGItem)
            }
        }
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit AIUsage", action: #selector(quitAction), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = nil // Restore normal click behavior
    }
    
    @objc private func launchAntigravityAction() {
        ProcessDiscovery.launchAntigravityApp()
    }
    
    @objc private func launchChatGPTAction() {
        CodexDiscovery.launchChatGPTApp()
    }
    
    @objc private func switchToBothAction() {
        service.setFocusMode(.both)
    }
    
    @objc private func switchToGeminiAction() {
        service.setFocusMode(.gemini)
    }
    
    @objc private func switchToChatGPTAction() {
        service.setFocusMode(.chatgpt)
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
