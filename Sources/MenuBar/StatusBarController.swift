import Cocoa
import SwiftUI

@MainActor
public class StatusBarController {
    private var statusItem: NSStatusItem
    private var popover: NSPopover
    private var service: QuotaService
    private var eventMonitor: Any?
    /// Horizontal extent of each provider's section within the rendered menu bar image
    /// (image coordinates), used to open the popover on the provider that was clicked.
    private var providerSegments: [(provider: AIProvider, range: ClosedRange<CGFloat>)] = []
    
    public init(service: QuotaService) {
        self.service = service
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        
        setupPopover()
        setupStatusButton()
        
        // Both sides are on the main actor, so no dispatch hop is needed
        service.updateMenuBarCallback = { [weak self] in
            self?.updateStatusButton()
        }
        
        // Blackout starts from the popover too; close it so it isn't left open behind the overlay
        BlackoutController.shared.willStart = { [weak self] in
            self?.hidePopover(nil)
        }
        
        // Initial refresh
        service.refresh()
        
        // Quotas go stale over sleep and Antigravity may come back on a new port, so
        // rediscover after wake. The short delay lets Wi-Fi reconnect first.
        // The controller lives for the app's lifetime, so the observer is never removed.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                self?.service.refresh(forceDiscovery: true)
                // The periodic timer doesn't tick during sleep, so check on wake too
                UpdateService.shared.checkForUpdates(isUserInitiated: false)
            }
        }
        
        // Background update checks: soon after launch, then periodically
        UpdateService.shared.startAutomaticChecks()
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
            hosting.view.bottomAnchor.constraint(equalTo: wrapper.view.bottomAnchor)
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
        button.setAccessibilityLabel((["AIUsage"] + service.selectedInstalledProviders.map { provider in
            "\(provider.rawValue): " + service.menuBarQuotaLines(for: provider, includeWindowLabels: true).joined(separator: ", ")
        }).joined(separator: "; "))
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
        
        let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold)
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = 10
        paragraph.maximumLineHeight = 10
        let textAttrs: [NSAttributedString.Key: Any] = [
            .paragraphStyle: paragraph,
            .font: font,
            .foregroundColor: NSColor.black
        ]
        let secondaryAttrs: [NSAttributedString.Key: Any] = [
            .paragraphStyle: paragraph,
            .font: font,
            .foregroundColor: NSColor(white: 0, alpha: 0.45)
        ]
        
        let iconSize: CGFloat = 14.0
        let height: CGFloat = 22.0
        
        // Critical quota gets a warning glyph; the image stays a template so it follows the menu bar's appearance
        let warningSize: CGFloat = 11.0
        let warningGlyph = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 9.5, weight: .bold))
        
        // Align each progress bar with its percentage; the 5-hour row is above the weekly row.
        let meterLead: CGFloat = 3.0
        let meterBarWidth: CGFloat = 18.0
        let meterBarHeight: CGFloat = 3.0
        let lineHeight: CGFloat = 10.0
        
        struct ProviderRenderItem {
            let provider: AIProvider
            let icon: NSImage?
            let lines: [NSAttributedString]
            let percentages: [Int?]
            /// Disconnected or without data: drawn faded so live figures stand out
            let isDimmed: Bool
            let isCritical: Bool
            var iconWidth: CGFloat { icon != nil ? 14.0 : 0 }
            var textWidth: CGFloat { lines.map { $0.size().width }.max() ?? 0 }
        }
        let items = providers.map { provider in
            let percent = service.menuBarPercentage(for: provider)
            let isDimmed = !service.isProviderConnected(provider) || (percent == nil && provider != .claude)
            let lines = service.menuBarQuotaLines(for: provider)
            return ProviderRenderItem(
                provider: provider,
                icon: AppIconHelper.template(for: provider),
                lines: lines.map { NSAttributedString(string: " " + $0, attributes: isDimmed ? secondaryAttrs : textAttrs) },
                percentages: lines.map { $0.hasSuffix("%") ? Int($0.dropLast()) : nil },
                isDimmed: isDimmed,
                isCritical: percent.map { QuotaLevel(fraction: Double($0) / 100.0) == .critical } ?? false
            )
        }
        func meterWidth(_ item: ProviderRenderItem) -> CGFloat {
            item.percentages.contains { $0 != nil } ? meterLead + meterBarWidth : 0
        }
        func warningWidth(_ item: ProviderRenderItem) -> CGFloat {
            item.isCritical && warningGlyph != nil ? warningSize + 2 : 0
        }
        
        let sepText = NSAttributedString(string: "  ·  ", attributes: secondaryAttrs)
        let sepWidth = sepText.size().width
        
        var totalWidth: CGFloat = items.reduce(0) { $0 + $1.iconWidth + meterWidth($1) + warningWidth($1) + $1.textWidth }
        totalWidth += sepWidth * CGFloat(items.count - 1)
        totalWidth = ceil(totalWidth)
        
        // Record each provider's horizontal span; the separator is split evenly between neighbours.
        var segX: CGFloat = 0
        for (idx, item) in items.enumerated() {
            let start = idx == 0 ? 0 : segX - sepWidth / 2
            segX += item.iconWidth + meterWidth(item) + warningWidth(item) + item.textWidth
            let end = idx == items.count - 1 ? totalWidth : segX + sepWidth / 2
            providerSegments.append((item.provider, start...end))
            segX += sepWidth
        }
        
        let img = NSImage(size: NSSize(width: totalWidth, height: height), flipped: false) { _ in
            var x: CGFloat = 0
            let iconY: CGFloat = (height - iconSize) / 2
            
            for (idx, item) in items.enumerated() {
                let textY = (height - CGFloat(item.lines.count) * lineHeight) / 2
                
                if let ic = item.icon {
                    ic.draw(in: NSRect(x: x, y: iconY, width: iconSize, height: iconSize), from: .zero, operation: .sourceOver, fraction: item.isDimmed ? 0.45 : 1.0)
                    x += iconSize
                }
                if item.isCritical, let glyph = warningGlyph {
                    let glyphHeight = warningSize * glyph.size.height / max(glyph.size.width, 1)
                    glyph.draw(in: NSRect(x: x + 2, y: (height - glyphHeight) / 2, width: warningSize, height: glyphHeight),
                               from: .zero, operation: .sourceOver, fraction: 1.0)
                    x += warningSize + 2
                }
                for (lineIndex, line) in item.lines.enumerated() {
                    let y = textY + CGFloat(item.lines.count - lineIndex - 1) * lineHeight
                    line.draw(at: NSPoint(x: x, y: y))
                    if let percentage = item.percentages[lineIndex] {
                        let track = NSRect(x: x + item.textWidth + meterLead,
                                           y: y + (lineHeight - meterBarHeight) / 2,
                                           width: meterBarWidth, height: meterBarHeight)
                        let radius = meterBarHeight / 2
                        let path = NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius)
                        NSColor(white: 0, alpha: 0.22).setFill()
                        path.fill()
                        NSGraphicsContext.saveGraphicsState()
                        path.addClip()
                        NSColor.black.setFill()
                        NSRect(x: track.minX, y: track.minY,
                               width: meterBarWidth * CGFloat(max(0, min(100, percentage))) / 100,
                               height: track.height).fill()
                        NSGraphicsContext.restoreGraphicsState()
                    }
                }
                x += item.textWidth + meterWidth(item)
                
                if idx < items.count - 1 {
                    sepText.draw(at: NSPoint(x: x, y: (height - sepText.size().height) / 2))
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
            // Re-read notification permission first, so the alerts submenu reflects any change made
            // in System Settings since it was last read
            NotificationManager.shared.refreshPermission { [weak self] in
                self?.showContextMenu(button)
            }
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
        // Refresh quotas when the popover opens, unless that just happened
        service.refreshIfStale()
        // Pick up notification permission changes made in System Settings
        NotificationManager.shared.refreshPermission()
        
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
        
        // Actions: Refresh All
        let refreshItem = NSMenuItem(title: "Refresh All Now", action: #selector(refreshAction), keyEquivalent: "r")
        refreshItem.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh All Now")
        refreshItem.target = self
        menu.addItem(refreshItem)
        
        let blackoutItem = NSMenuItem(title: "Blackout", action: #selector(blackoutAction), keyEquivalent: "b")
        blackoutItem.image = NSImage(systemSymbolName: "moon.fill", accessibilityDescription: "Blackout")
        blackoutItem.toolTip = "Turn the screen black while an agent keeps working. Any key or mouse move wakes it."
        blackoutItem.target = self
        menu.addItem(blackoutItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Data: how often numbers refresh and when you're told they're low
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
        
        menu.addItem(makeAlertsItem())
        
        menu.addItem(NSMenuItem.separator())
        
        // Appearance: what the menu bar and popover show
        menu.addItem(makeDisplayModeItem())
        let hideEmailItem = NSMenuItem(title: "Hide Email Addresses", action: #selector(toggleHideEmailsAction), keyEquivalent: "")
        hideEmailItem.image = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: "Hide Email Addresses")
        hideEmailItem.state = UserDefaults.standard.bool(forKey: EmailMasking.defaultsKey) ? .on : .off
        hideEmailItem.target = self
        menu.addItem(hideEmailItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // App
        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLoginAction), keyEquivalent: "")
        loginItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: "Launch at Login")
        // Pending approval in System Settings shows as mixed until the user allows it
        loginItem.state = LaunchAtLogin.isEnabled ? .on : (LaunchAtLogin.requiresApproval ? .mixed : .off)
        loginItem.target = self
        menu.addItem(loginItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Maintenance: Check for Updates
        let updateTitle: String = {
            if let update = UpdateService.shared.availableUpdate {
                return "Update to \(update.tagName)…"
            }
            return "Check for Updates…"
        }()
        let updateItem = NSMenuItem(title: updateTitle, action: #selector(checkForUpdatesAction), keyEquivalent: "u")
        updateItem.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: "Check for Updates")
        updateItem.target = self
        menu.addItem(updateItem)
        
        // Quit
        let quitItem = NSMenuItem(title: "Quit AIUsage", action: #selector(quitAction), keyEquivalent: "q")
        quitItem.image = NSImage(systemSymbolName: "rectangle.portrait.and.arrow.right", accessibilityDescription: "Quit AIUsage")
        quitItem.target = self
        menu.addItem(quitItem)
        
        // Pop the menu up directly under the status item. The previous approach (assign
        // statusItem.menu, then performClick) re-sends the button's action on recent macOS, which
        // reopened this menu recursively and froze the app on right-click.
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY + 5), in: button)
    }
    
    // MARK: - Context Menu Builders
    
    /// "Menu Bar" submenu: Show Percentages / Icon Only
    private func makeDisplayModeItem() -> NSMenuItem {
        let displayMenu = NSMenu()
        for mode in MenuBarDisplayMode.allCases {
            let item = NSMenuItem(title: mode.title, action: #selector(changeDisplayModeAction(_:)), keyEquivalent: "")
            item.representedObject = mode.rawValue
            item.state = service.displayMode == mode ? .on : .off
            item.target = self
            displayMenu.addItem(item)
        }
        let displaySubItem = NSMenuItem(title: "Menu Bar", action: nil, keyEquivalent: "")
        displaySubItem.image = NSImage(systemSymbolName: "menubar.rectangle", accessibilityDescription: "Menu Bar")
        displaySubItem.submenu = displayMenu
        return displaySubItem
    }
    
    /// "Low-Quota Alerts" submenu: alert thresholds, then live notification permission and the one action that fixes it
    private func makeAlertsItem() -> NSMenuItem {
        let alertsMenu = NSMenu()
        for mode in LowQuotaAlertMode.allCases {
            let item = NSMenuItem(title: mode.title, action: #selector(changeAlertModeAction(_:)), keyEquivalent: "")
            item.representedObject = mode.rawValue
            item.state = service.alertMode == mode ? .on : .off
            item.target = self
            alertsMenu.addItem(item)
        }
        alertsMenu.addItem(NSMenuItem.separator())
        
        let statusItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        alertsMenu.addItem(statusItem)
        switch NotificationManager.shared.permission {
        case .authorized:
            statusItem.title = "Notifications: On"
        case .notDetermined, .unknown:
            statusItem.title = "Notifications: Not Set Up"
            let item = NSMenuItem(title: "Turn On Notifications", action: #selector(turnOnNotificationsAction), keyEquivalent: "")
            item.target = self
            alertsMenu.addItem(item)
        case .denied:
            statusItem.title = "Notifications: Blocked"
            let item = NSMenuItem(title: "Open Notification Settings…", action: #selector(openNotificationSettingsAction), keyEquivalent: "")
            item.target = self
            alertsMenu.addItem(item)
        }
        
        let alertsSubItem = NSMenuItem(title: "Low-Quota Alerts", action: nil, keyEquivalent: "")
        alertsSubItem.image = NSImage(systemSymbolName: "bell.badge", accessibilityDescription: "Low-Quota Alerts")
        alertsSubItem.submenu = alertsMenu
        return alertsSubItem
    }
    
    @objc private func checkForUpdatesAction() {
        UpdateService.shared.checkForUpdates(isUserInitiated: true)
    }
    
    @objc private func changeRefreshIntervalAction(_ sender: NSMenuItem) {
        if let interval = sender.representedObject as? RefreshInterval {
            service.refreshInterval = interval
        }
    }
    
    @objc private func toggleLaunchAtLoginAction() {
        LaunchAtLogin.toggle()
    }
    
    @objc private func changeDisplayModeAction(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let mode = MenuBarDisplayMode(rawValue: raw) {
            service.displayMode = mode
        }
    }
    
    @objc private func changeAlertModeAction(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let mode = LowQuotaAlertMode(rawValue: raw) {
            service.alertMode = mode
        }
    }
    
    @objc private func turnOnNotificationsAction() {
        service.turnOnAlerts()
    }
    
    @objc private func openNotificationSettingsAction() {
        NotificationManager.openNotificationSettings()
    }
    
    @objc private func toggleHideEmailsAction() {
        let defaults = UserDefaults.standard
        defaults.set(!defaults.bool(forKey: EmailMasking.defaultsKey), forKey: EmailMasking.defaultsKey)
    }
    
    @objc private func blackoutAction() {
        // Let the menu finish closing before the overlay takes focus
        DispatchQueue.main.async {
            BlackoutController.shared.start()
        }
    }
    
    @objc private func refreshAction() {
        service.refresh(forceDiscovery: true)
    }
    
    @objc private func quitAction() {
        NSApplication.shared.terminate(nil)
    }
}
