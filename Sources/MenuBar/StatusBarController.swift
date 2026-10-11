import Cocoa
import SwiftUI

public class StatusBarController {
    private var statusItem: NSStatusItem
    private var popover: NSPopover
    private var service: QuotaService
    private var eventMonitor: Any?
    private var wakeObserver: NSObjectProtocol?
    /// Horizontal extent of each provider's section within the rendered menu bar image
    /// (image coordinates), used to open the popover on the provider that was clicked.
    private var providerSegments: [(provider: AIProvider, range: ClosedRange<CGFloat>)] = []
    
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
        
        // Quotas go stale over sleep and Antigravity may come back on a new port, so
        // rediscover after wake. The short delay lets Wi-Fi reconnect first.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                self?.service.refresh(forceDiscovery: true)
            }
        }
        
        // Background check for updates (silent)
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            UpdateService.shared.checkForUpdates(isUserInitiated: false)
        }
    }
    
    deinit {
        if let wakeObserver = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
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
    
    private func renderMenuBarImage() -> NSImage {
        let providers = service.selectedInstalledProviders
        providerSegments = []
        
        if providers.isEmpty {
            let icon = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)!
            icon.isTemplate = true
            return icon
        }
        
        if service.displayMode == .iconOnly {
            let icon = AppIconHelper.combinedTemplate(for: providers)
                ?? NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)!
            icon.isTemplate = true
            return icon
        }
        
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
        
        struct ProviderRenderItem {
            let provider: AIProvider
            let icon: NSImage?
            let text: NSAttributedString
            var iconWidth: CGFloat { icon != nil ? 14.0 : 0 }
            var textWidth: CGFloat { text.size().width }
        }
        let items = providers.map { provider in
            ProviderRenderItem(
                provider: provider,
                icon: AppIconHelper.template(for: provider),
                text: NSAttributedString(string: " " + service.badgeText(for: provider), attributes: textAttrs)
            )
        }
        
        let sepText = NSAttributedString(string: "  ·  ", attributes: secondaryAttrs)
        let sepWidth = sepText.size().width
        
        var totalWidth: CGFloat = items.reduce(0) { $0 + $1.iconWidth + $1.textWidth }
        totalWidth += sepWidth * CGFloat(items.count - 1)
        totalWidth = ceil(totalWidth)
        
        // Record each provider's horizontal span; the separator is split evenly between neighbours.
        var segX: CGFloat = 0
        for (idx, item) in items.enumerated() {
            let start = idx == 0 ? 0 : segX - sepWidth / 2
            segX += item.iconWidth + item.textWidth
            let end = idx == items.count - 1 ? totalWidth : segX + sepWidth / 2
            providerSegments.append((item.provider, start...end))
            segX += sepWidth
        }
        
        let img = NSImage(size: NSSize(width: totalWidth, height: height), flipped: false) { _ in
            var x: CGFloat = 0
            let iconY: CGFloat = (height - iconSize) / 2
            
            for (idx, item) in items.enumerated() {
                let textY: CGFloat = (height - item.text.size().height) / 2
                
                if let ic = item.icon {
                    ic.draw(in: NSRect(x: x, y: iconY, width: iconSize, height: iconSize), from: .zero, operation: .sourceOver, fraction: 1.0)
                    x += iconSize
                }
                item.text.draw(at: NSPoint(x: x, y: textY))
                x += item.textWidth
                
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
            if let provider = providerAtClick(event, in: button) {
                service.dualActiveProvider = provider
            }
            showPopover(button)
        }
    }
    
    /// Maps a click on the status button to the provider section under the cursor.
    private func providerAtClick(_ event: NSEvent?, in button: NSStatusBarButton) -> AIProvider? {
        guard providerSegments.count > 1, let event, let imageWidth = button.image?.size.width else { return nil }
        let localX = button.convert(event.locationInWindow, from: nil).x
        // The image is centered within the button.
        let imageX = localX - (button.bounds.width - imageWidth) / 2
        return providerSegments.first(where: { $0.range.contains(imageX) })?.provider
            ?? (imageX < 0 ? providerSegments.first?.provider : providerSegments.last?.provider)
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
        
        let selectedFocusIcon = AppIconHelper.combinedTemplate(for: service.selectedInstalledProviders)
        
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
        intervalSubItem.image = NSImage(systemSymbolName: "timer", accessibilityDescription: "Refresh Interval")
        intervalSubItem.submenu = intervalMenu
        menu.addItem(intervalSubItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Actions: Refresh All
        let refreshItem = NSMenuItem(title: "Refresh All Now", action: #selector(refreshAction), keyEquivalent: "r")
        refreshItem.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh All Now")
        refreshItem.target = self
        menu.addItem(refreshItem)
        
        // Actions: Launch App Submenu (bundled together)
        if service.isGeminiInstalled || service.isCodexInstalled || service.isClaudeInstalled {
            let launchMenu = NSMenu()
            if service.isGeminiInstalled {
                let item = NSMenuItem(title: "Antigravity", action: #selector(launchAntigravityAction), keyEquivalent: "")
                item.image = AppIconHelper.antigravityTemplate
                item.target = self
                launchMenu.addItem(item)
            }
            if service.isCodexInstalled {
                let item = NSMenuItem(title: "ChatGPT", action: #selector(launchChatGPTAction), keyEquivalent: "")
                item.image = AppIconHelper.chatgptTemplate
                item.target = self
                launchMenu.addItem(item)
            }
            if service.isClaudeInstalled {
                let item = NSMenuItem(title: "Claude", action: #selector(launchClaudeAction), keyEquivalent: "")
                item.image = AppIconHelper.claudeTemplate
                item.target = self
                launchMenu.addItem(item)
            }
            
            let launchSubItem = NSMenuItem(title: "Launch App", action: nil, keyEquivalent: "")
            launchSubItem.image = NSImage(systemSymbolName: "arrow.up.forward.app", accessibilityDescription: "Launch App")
            launchSubItem.submenu = launchMenu
            menu.addItem(launchSubItem)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // Maintenance: Check for Updates
        let updateTitle: String = {
            if let update = UpdateService.shared.availableUpdate {
                return "Update to \(update.tagName)..."
            }
            return "Check for Updates..."
        }()
        let updateItem = NSMenuItem(title: updateTitle, action: #selector(checkForUpdatesAction), keyEquivalent: "u")
        updateItem.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: "Check for Updates")
        updateItem.target = self
        menu.addItem(updateItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit
        let quitItem = NSMenuItem(title: "Quit AIUsage", action: #selector(quitAction), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = nil // Restore normal click behavior
    }
    
    @objc private func checkForUpdatesAction() {
        UpdateService.shared.checkForUpdates(isUserInitiated: true)
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
