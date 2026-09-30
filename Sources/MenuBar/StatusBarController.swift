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
        
        let providers = service.selectedInstalledProviders
        
        if providers.isEmpty {
            let icon = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)!
            icon.isTemplate = true
            return icon
        }
        
        if service.displayMode == .iconOnly {
            let icon: NSImage
            if providers.count == 1 {
                switch providers[0] {
                case .gemini:
                    icon = AppIconHelper.antigravityTemplate ?? NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)!
                case .chatgpt:
                    icon = AppIconHelper.chatgptTemplate ?? NSImage(systemSymbolName: "circle.hexagongrid", accessibilityDescription: nil)!
                case .claude:
                    icon = AppIconHelper.claudeTemplate ?? NSImage(systemSymbolName: "asterisk", accessibilityDescription: nil)!
                }
            } else {
                icon = AppIconHelper.dualTemplate ?? NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)!
            }
            icon.isTemplate = true
            return icon
        }
        
        if providers.count == 1 {
            return renderSingleProviderImage(provider: providers[0])
        }
        
        struct ProviderRenderItem {
            let icon: NSImage?
            let text: String
        }
        var items: [ProviderRenderItem] = []
        for p in providers {
            switch p {
            case .gemini:
                items.append(ProviderRenderItem(
                    icon: AppIconHelper.antigravityTemplate,
                    text: service.isGeminiConnected ? " \(service.geminiPercentage)%" : " Off"
                ))
            case .chatgpt:
                items.append(ProviderRenderItem(
                    icon: AppIconHelper.chatgptTemplate,
                    text: service.isCodexConnected ? " \(service.codexRemainingPercentage)%" : " Off"
                ))
            case .claude:
                let claudeText: String = {
                    guard service.isClaudeConnected else { return " Off" }
                    if let pct = service.claudePercentage {
                        return " \(pct)%"
                    } else {
                        return " Free"
                    }
                }()
                items.append(ProviderRenderItem(
                    icon: AppIconHelper.claudeTemplate,
                    text: claudeText
                ))
            }
        }
        
        let sepText = NSAttributedString(string: "  ·  ", attributes: secondaryAttrs)
        let sepWidth = sepText.size().width
        
        var totalWidth: CGFloat = 0
        var itemWidths: [(iconWidth: CGFloat, textWidth: CGFloat, textAttr: NSAttributedString)] = []
        
        for (idx, item) in items.enumerated() {
            let textAttr = NSAttributedString(string: item.text, attributes: textAttrs)
            let iconW: CGFloat = item.icon != nil ? iconSize : 0
            let textW: CGFloat = textAttr.size().width
            itemWidths.append((iconW, textW, textAttr))
            totalWidth += iconW + textW
            if idx < items.count - 1 {
                totalWidth += sepWidth
            }
        }
        totalWidth = ceil(totalWidth)
        
        let img = NSImage(size: NSSize(width: totalWidth, height: height), flipped: false) { rect in
            var x: CGFloat = 0
            let iconY: CGFloat = (height - iconSize) / 2
            
            for (idx, item) in items.enumerated() {
                let w = itemWidths[idx]
                let textY: CGFloat = (height - w.textAttr.size().height) / 2
                
                if let ic = item.icon {
                    ic.draw(in: NSRect(x: x, y: iconY, width: iconSize, height: iconSize), from: .zero, operation: .sourceOver, fraction: 1.0)
                    x += iconSize
                }
                w.textAttr.draw(at: NSPoint(x: x, y: textY))
                x += w.textWidth
                
                if idx < items.count - 1 {
                    sepText.draw(at: NSPoint(x: x, y: textY))
                    x += sepWidth
                }
            }
            return true
        }
        img.isTemplate = true
        return img
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
            icon = AppIconHelper.claudeTemplate
            if service.isClaudeConnected {
                textStr = service.claudePercentage != nil ? " \(service.claudePercentage!)%" : " Free"
            } else {
                textStr = " Off"
            }
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
        
        let selectedFocusIcon: NSImage? = {
            let selected = service.selectedInstalledProviders
            if selected.count == 1 {
                switch selected[0] {
                case .gemini: return AppIconHelper.antigravityTemplate
                case .chatgpt: return AppIconHelper.chatgptTemplate
                case .claude: return AppIconHelper.claudeTemplate
                }
            }
            return AppIconHelper.dualTemplate
        }()
        
        // Provider Focus Submenu (Multi-Choice with persistent selection that doesn't close)
        let focusMenu = NSMenu()
        let customFocusItem = NSMenuItem()
        
        let hostingView = NSHostingView(
            rootView: ProviderFocusSubmenuView(service: service, onDismiss: { [weak menu] in
                menu?.cancelTracking()
            })
        )
        let fitting = hostingView.fittingSize
        let calculatedHeight: CGFloat = {
            let rowCount = (service.installedProvidersCount > 1 ? 1 : 0) + service.installedProvidersCount
            return CGFloat(40 + rowCount * 28 + 36)
        }()
        hostingView.frame = NSRect(x: 0, y: 0, width: 240, height: max(fitting.height, calculatedHeight))
        customFocusItem.view = hostingView
        focusMenu.addItem(customFocusItem)
        
        let focusSubItem = NSMenuItem(title: "Provider Focus (\(service.selectedProvidersSummary))", action: nil, keyEquivalent: "")
        focusSubItem.image = selectedFocusIcon
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
        if service.isGeminiInstalled || service.isCodexInstalled || service.isClaudeInstalled {
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
            if service.isClaudeInstalled {
                let launchClaudeItem = NSMenuItem(title: "Launch Claude", action: #selector(launchClaudeAction), keyEquivalent: "")
                launchClaudeItem.image = AppIconHelper.claudeTemplate
                launchClaudeItem.target = self
                menu.addItem(launchClaudeItem)
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
    
    @objc private func launchClaudeAction() {
        ClaudeDiscovery.launchClaudeApp()
    }
    
    @objc private func selectAllProvidersAction() {
        service.selectAllProviders()
        updateStatusButton()
    }
    
    @objc private func toggleGeminiAction(_ sender: NSMenuItem) {
        if NSEvent.modifierFlags.contains(.option) {
            service.selectOnlyProvider(.gemini)
        } else {
            service.toggleProviderSelection(.gemini)
        }
        updateStatusButton()
    }
    
    @objc private func toggleChatGPTAction(_ sender: NSMenuItem) {
        if NSEvent.modifierFlags.contains(.option) {
            service.selectOnlyProvider(.chatgpt)
        } else {
            service.toggleProviderSelection(.chatgpt)
        }
        updateStatusButton()
    }
    
    @objc private func toggleClaudeAction(_ sender: NSMenuItem) {
        if NSEvent.modifierFlags.contains(.option) {
            service.selectOnlyProvider(.claude)
        } else {
            service.toggleProviderSelection(.claude)
        }
        updateStatusButton()
    }
    
    @objc private func switchToBothAction() {
        service.selectAllProviders()
        updateStatusButton()
    }
    
    @objc private func switchToGeminiAction() {
        service.selectOnlyProvider(.gemini)
        updateStatusButton()
    }
    
    @objc private func switchToChatGPTAction() {
        service.selectOnlyProvider(.chatgpt)
        updateStatusButton()
    }
    
    @objc private func switchToClaudeAction() {
        service.selectOnlyProvider(.claude)
        updateStatusButton()
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
