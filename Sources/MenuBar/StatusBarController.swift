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
            
        case .activeProvider:
            var provider = service.activeProvider
            if !service.isGeminiInstalled && service.isCodexInstalled {
                provider = .chatgpt
            } else if service.isGeminiInstalled && !service.isCodexInstalled {
                provider = .gemini
            }
            return renderSingleProviderImage(provider: provider)
            
        case .weekly:
            guard service.isGeminiInstalled else {
                return renderSingleProviderImage(provider: .chatgpt)
            }
            return renderSingleProviderImage(provider: .gemini)
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
        
        let isGemini = provider == .gemini
        let icon = isGemini ? AppIconHelper.antigravityTemplate : AppIconHelper.chatgptTemplate
        let textStr = isGemini
            ? (service.isGeminiConnected ? " \(service.geminiPercentage)%" : " Off")
            : (service.isCodexConnected ? " \(service.codexRemainingPercentage)%" : " Off")
        
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
        let titleItem = NSMenuItem(title: "AIUsage", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(NSMenuItem.separator())
        
        let bothInstalled = service.isGeminiInstalled && service.isCodexInstalled
        
        // Provider Selection (shows what is selected from Menu Bar Display)
        let providerSectionTitle = NSMenuItem(title: "Provider Selection", action: nil, keyEquivalent: "")
        providerSectionTitle.isEnabled = false
        menu.addItem(providerSectionTitle)
        
        let selectedTitle: String = {
            if !service.isGeminiInstalled && !service.isCodexInstalled {
                return "No AI Models Installed"
            }
            if service.displayMode == .dual {
                return "Dual (Antigravity & ChatGPT)"
            } else if service.activeProvider == .gemini {
                return "Antigravity (Gemini)"
            } else {
                return "ChatGPT (Codex)"
            }
        }()
        
        let selectedIcon: NSImage? = {
            if service.displayMode == .dual {
                return AppIconHelper.dualTemplate
            } else if service.activeProvider == .gemini {
                return AppIconHelper.antigravityTemplate
            } else {
                return AppIconHelper.chatgptTemplate
            }
        }()
        
        let currentItem = NSMenuItem(title: selectedTitle, action: nil, keyEquivalent: "")
        currentItem.image = selectedIcon
        currentItem.state = .on
        currentItem.isEnabled = false
        menu.addItem(currentItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Menu Bar Display Submenu (consists strictly of: Dual, Antigravity, ChatGPT)
        let displayMenu = NSMenu()
        if bothInstalled {
            let dualModeItem = NSMenuItem(title: "Dual (Antigravity & ChatGPT)", action: #selector(switchToDualAction), keyEquivalent: "d")
            dualModeItem.image = AppIconHelper.dualTemplate
            dualModeItem.state = (service.displayMode == .dual) ? .on : .off
            dualModeItem.target = self
            displayMenu.addItem(dualModeItem)
        }
        
        if service.isGeminiInstalled {
            let geminiModeItem = NSMenuItem(title: "Antigravity (Gemini)", action: #selector(switchToGeminiAction), keyEquivalent: "1")
            geminiModeItem.image = AppIconHelper.antigravityTemplate
            let isSelected = (service.displayMode == .activeProvider || service.displayMode == .weekly) && service.activeProvider == .gemini
            geminiModeItem.state = isSelected ? .on : .off
            geminiModeItem.target = self
            displayMenu.addItem(geminiModeItem)
        }
        
        if service.isCodexInstalled {
            let chatgptModeItem = NSMenuItem(title: "ChatGPT (Codex)", action: #selector(switchToChatGPTAction), keyEquivalent: "2")
            chatgptModeItem.image = AppIconHelper.chatgptTemplate
            let isSelected = (service.displayMode == .activeProvider) && service.activeProvider == .chatgpt
            chatgptModeItem.state = isSelected ? .on : .off
            chatgptModeItem.target = self
            displayMenu.addItem(chatgptModeItem)
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
    
    @objc private func switchToDualAction() {
        service.displayMode = .dual
    }
    
    @objc private func switchToGeminiAction() {
        service.activeProvider = .gemini
        service.displayMode = .activeProvider
    }
    
    @objc private func switchToChatGPTAction() {
        service.activeProvider = .chatgpt
        service.displayMode = .activeProvider
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
