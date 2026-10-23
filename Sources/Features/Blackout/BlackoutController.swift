import AppKit
import IOKit.pwr_mgt

/// Blackout: covers every display in black so an agent can keep working behind it, and ends
/// on the first key press, click, scroll or mouse move.
///
/// - The overlay windows sit above the menu bar, Dock and notifications, and take key focus so
///   the waking key press or click lands on them instead of the app behind (a stray Return
///   must not answer a prompt in the agent's terminal).
/// - Waking is detected from the HID system's idle time, which counts only hardware input, so it
///   works even if another app takes focus. Events reaching the overlay wake it at once.
/// - Once the overlay has faded in, the display is put to sleep, since black pixels on an LCD
///   still glow from the backlight. Waking shows the lock screen when Lock Screen settings ask
///   for a password after the display turns off; the overlay stays up underneath until then.
/// - System idle sleep is held off so the agent keeps running while the display is off.
@MainActor
public final class BlackoutController {
    public static let shared = BlackoutController()

    /// Called just before the overlay appears, so the popover can close first.
    public var willStart: (() -> Void)?

    public private(set) var isActive = false

    private var windows: [NSWindow] = []
    private var startedAt = Date()
    private var pollTimer: Timer?
    private var eventMonitor: Any?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var sleepAssertion: IOPMAssertionID = 0
    private var displaySleepWork: DispatchWorkItem?

    /// Hardware events that wake. Queried one by one rather than via kCGAnyInputEventType, which
    /// also counts key and button releases: releasing a held shortcut key or mouse button after the
    /// grace period isn't new input (the local event monitor ignores releases for the same reason).
    private static let wakeEventTypes: [CGEventType] = [
        .keyDown, .flagsChanged, .mouseMoved, .scrollWheel,
        .leftMouseDown, .rightMouseDown, .otherMouseDown,
        .leftMouseDragged, .rightMouseDragged, .otherMouseDragged
    ]

    /// The app that was frontmost when Blackout started, so focus can go back to it on waking
    private var previousApp: NSRunningApplication?

    private init() {}

    public func start() {
        guard !isActive else { return }
        isActive = true
        willStart?()
        startedAt = Date()

        // This accessory app has no windows of its own, so after waking, keystrokes would go
        // nowhere unless activation is handed back
        let frontmost = NSWorkspace.shared.frontmostApplication
        previousApp = frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : frontmost

        holdOffSystemSleep()
        showWindows()
        installEventMonitor()
        observeSystemEvents()

        // Polls only while active; HID idle time has no change notification
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkForInput() }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer

        // After the fade and the grace period, so the starting click can't wake the display again
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.sleepDisplay() }
        }
        displaySleepWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + BlackoutWake.grace + 0.2, execute: work)
    }

    public func stop() {
        guard isActive else { return }
        isActive = false

        pollTimer?.invalidate()
        pollTimer = nil
        displaySleepWork?.cancel()
        displaySleepWork = nil
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        for (center, observer) in observers {
            center.removeObserver(observer)
        }
        observers.removeAll()
        releaseSleepAssertion()
        hideWindows()
        restorePreviousApp()
    }

    // MARK: - Overlay

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private func showWindows() {
        windows = NSScreen.screens.map(makeWindow(for:))

        for window in windows {
            window.orderFrontRegardless()
        }
        focusOverlay()
        NSCursor.setHiddenUntilMouseMoves(true)

        if reduceMotion {
            windows.forEach { $0.alphaValue = 1 }
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.6
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                windows.forEach { $0.animator().alphaValue = 1 }
            }
        }
    }

    private func makeWindow(for screen: NSScreen) -> NSWindow {
        // Non-activating, so the overlay takes key focus even when macOS 14's cooperative
        // activation refuses to bring this accessory app forward
        let window = BlackoutWindow(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.becomesKeyOnlyIfNeeded = false
        window.setFrame(screen.frame, display: false)
        window.backgroundColor = .black
        window.isOpaque = true
        window.hasShadow = false
        window.alphaValue = 0
        // Above the menu bar, Dock, notification banners and full-screen apps
        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.acceptsMouseMovedEvents = true
        window.ignoresMouseEvents = false
        window.animationBehavior = .none
        return window
    }

    private func hideWindows() {
        let closing = windows
        windows = []
        guard !reduceMotion else {
            closing.forEach { $0.orderOut(nil) }
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            closing.forEach { $0.animator().alphaValue = 0 }
        }, completionHandler: {
            // AppKit calls this on the main thread
            MainActor.assumeIsolated { closing.forEach { $0.orderOut(nil) } }
        })
    }

    /// Gives key focus to the overlay under the mouse, where a click would land, so the waking
    /// key press lands on it instead of the app behind. Activation is best effort (macOS 14 may
    /// refuse it); the non-activating panel becomes key either way.
    private func focusOverlay() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        let mouse = NSEvent.mouseLocation
        (windows.first { $0.frame.contains(mouse) } ?? windows.first)?.makeKeyAndOrderFront(nil)
    }

    /// Hands activation back to the app that was frontmost before Blackout, if it's still running.
    private func restorePreviousApp() {
        defer { previousApp = nil }
        guard let app = previousApp, !app.isTerminated else { return }
        if #available(macOS 14.0, *) {
            // Cooperative activation: this app must yield before the other can be activated
            NSApp.yieldActivation(to: app)
            app.activate()
        } else {
            app.activate(options: [])
        }
    }

    // MARK: - Waking

    private func checkForInput() {
        guard isActive else { return }
        let secondsSinceInput = Self.wakeEventTypes
            .map { CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: $0) }
            .min() ?? .infinity
        if BlackoutWake.shouldWake(secondsSinceInput: secondsSinceInput, elapsed: Date().timeIntervalSince(startedAt)) {
            stop()
        }
    }

    /// Swallows every input event that reaches the app while Blackout is up, waking once past the
    /// grace period. Without this, the waking key press would beep or reach a menu shortcut.
    private func installEventMonitor() {
        let mask: NSEvent.EventTypeMask = [
            .keyDown, .keyUp, .flagsChanged, .mouseMoved, .scrollWheel,
            .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp,
            .leftMouseDragged, .rightMouseDragged, .otherMouseDragged
        ]
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self, self.isActive else { return event }
            let elapsed = Date().timeIntervalSince(self.startedAt)
            // Key releases and button-ups finish the gesture that started Blackout
            let isRelease = [.keyUp, .leftMouseUp, .rightMouseUp, .otherMouseUp].contains(event.type)
            if !isRelease && !BlackoutWake.isInGrace(elapsed: elapsed) {
                self.stop()
            }
            return nil
        }
    }

    private func observeSystemEvents() {
        let center = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter

        // A display was connected, disconnected or rearranged: cover the new layout
        observers.append((center, center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.rebuildWindows() }
        }))

        // Another app took focus: take it back so keys still reach the overlay. Watches every
        // activation, since this app may never have been active to resign. The lock screen and
        // screen saver are left alone, or reclaiming focus would fight the password field
        observers.append((workspace, workspace.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard BlackoutWake.shouldReclaimFocus(
                activatedPID: app?.processIdentifier,
                ownPID: ProcessInfo.processInfo.processIdentifier,
                bundleID: app?.bundleIdentifier
            ) else { return }
            Task { @MainActor in
                guard let self, self.isActive else { return }
                self.focusOverlay()
            }
        }))

        // Back from system sleep (lid opened) or a user switch: the user is back
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append((workspace, workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.stop() }
            }))
        }
    }

    private func rebuildWindows() {
        guard isActive else { return }
        windows.forEach { $0.orderOut(nil) }
        windows = NSScreen.screens.map(makeWindow(for:))
        for window in windows {
            window.alphaValue = 1
            window.orderFrontRegardless()
        }
        focusOverlay()
    }

    // MARK: - Power

    private func holdOffSystemSleep() {
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "AIUsage Blackout: keeping the Mac awake while an agent works" as CFString,
            &sleepAssertion
        )
        if result != kIOReturnSuccess {
            sleepAssertion = 0
        }
    }

    /// Turns the backlight off; any hardware input turns it back on. `pmset displaysleepnow`
    /// needs no privileges and works on both Intel and Apple silicon.
    private func sleepDisplay() {
        guard isActive else { return }
        let pmset = Process()
        pmset.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        pmset.arguments = ["displaysleepnow"]
        pmset.terminationHandler = { process in
            if process.terminationStatus != 0 {
                NSLog("AIUsage: pmset displaysleepnow exited with status %d", process.terminationStatus)
            }
        }
        do {
            try pmset.run()
        } catch {
            // NSLog rather than print: a menu bar app's stdout goes nowhere, but this shows in Console
            NSLog("AIUsage: couldn't sleep the display: %@", error.localizedDescription)
        }
    }

    private func releaseSleepAssertion() {
        guard sleepAssertion != 0 else { return }
        IOPMAssertionRelease(sleepAssertion)
        sleepAssertion = 0
    }
}

/// Borderless windows can't become key by default; the overlay needs to, to receive the waking keys.
private final class BlackoutWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
