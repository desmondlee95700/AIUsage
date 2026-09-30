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
                self?.updatePopoverSize()
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
        updatePopoverSize()
    }
    
    private func updatePopoverSize() {
        guard let controller = popover.contentViewController else { return }
        controller.view.layoutSubtreeIfNeeded()
        let targetSize = controller.view.fittingSize
        if targetSize.height > 0 {
            popover.contentSize = NSSize(width: 380, height: targetSize.height)
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
        
        // Setup icon
        let iconName = service.isConnected ? "sparkles" : "sparkle"
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        if let image = NSImage(systemSymbolName: iconName, accessibilityDescription: "Model Quota")?.withSymbolConfiguration(config) {
            image.isTemplate = true
            button.image = image
            button.imagePosition = .imageLeading
        }
        
        // Setup text title
        let titleText = service.menuBarTitle
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ]
        button.attributedTitle = NSAttributedString(string: titleText, attributes: attributes)
        
        if service.isConnected {
            let emailInfo = service.userStatus?.email.map { " (\($0))" } ?? ""
            let pct = service.primaryWeeklyBucket?.formattedPercentage ?? "N/A"
            button.toolTip = "AIUsage\(emailInfo): \(pct) remaining\nClick to view full breakdown"
        } else {
            button.toolTip = "AIUsage (Offline)\nClick to reconnect"
        }
    }
    
    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            // Show quick context menu on right click
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
        // Refresh quota automatically when popover is opened
        service.refresh()
        
        updatePopoverSize()
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
        menu.addItem(NSMenuItem(title: "AIUsage", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Refresh Now", action: #selector(refreshAction), keyEquivalent: "r"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit AIUsage", action: #selector(quitAction), keyEquivalent: "q"))
        
        for item in menu.items {
            item.target = self
        }
        
        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = nil // Restore normal click behavior
    }
    
    @objc private func refreshAction() {
        service.refresh(forceDiscovery: true)
    }
    
    @objc private func quitAction() {
        NSApplication.shared.terminate(nil)
    }
}
