import SwiftUI

public struct MainUsageView: View {
    @ObservedObject var service: QuotaService
    @ObservedObject private var updateService = UpdateService.shared
    @State private var spinAngle: Double = 0.0
    @State private var isShowingProviderFocusPopover: Bool = false
    @Namespace private var switcherNamespace
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var glassObserver: LiquidGlassObserver
    @AppStorage(EmailMasking.defaultsKey) private var hideEmails = false
    @ObservedObject private var notifications = NotificationManager.shared

    public init(service: QuotaService) {
        self.service = service
    }

    public var body: some View {
        let glassIntensity = reduceTransparency ? 0.0 : glassObserver.intensity

        VStack(spacing: 0) {
            // Header Bar
            headerBar

            specularDivider

            // Multi-Provider Flipping Switcher (ONLY shown when > 1 provider is selected)
            if service.selectedInstalledProviders.count > 1 {
                multiProviderSwitcherBar
            }

            // Fixed-Height Content Container (ZERO height shift, ZERO flicker)
            ZStack(alignment: .top) {
                if service.selectedInstalledProviders.isEmpty {
                    noToolsInstalledView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if service.selectedInstalledProviders.count == 1 {
                    OverflowScrollView {
                        alertsNotice
                        switch service.selectedInstalledProviders[0] {
                        case .gemini:
                            geminiView
                        case .chatgpt:
                            chatgptView
                        case .claude:
                            claudeView
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                } else {
                    dualFlippingContentView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity)
                }
            }
            .frame(height: contentHeight)
            .clipped()
            .animation(LiquidGlassTokens.motion(LiquidGlassTokens.stateSpring, reduceMotion: reduceMotion), value: service.selectedProviders)
            .animation(LiquidGlassTokens.motion(LiquidGlassTokens.stateSpring, reduceMotion: reduceMotion), value: service.dualActiveProvider)
            .animation(LiquidGlassTokens.motion(LiquidGlassTokens.stateSpring, reduceMotion: reduceMotion), value: alertsNoticeKind)
        }
        .background(
            // Provider-coloured tint bleed pooled behind the glass
            AmbientTintBackground(tint: activeTint)
                .animation(LiquidGlassTokens.motion(LiquidGlassTokens.stateSpring, reduceMotion: reduceMotion), value: activeTint)
        )
        .frame(width: 380)
        .fixedSize(horizontal: true, vertical: true)
        .background(
            // The NSVisualEffectView is injected at the AppKit level in StatusBarController.
            // This layer adds a subtle dark tint that scales with the Liquid Glass slider.
            Group {
                if reduceTransparency {
                    Color(red: 0.11, green: 0.12, blue: 0.15)
                } else {
                    Color(red: 0.05, green: 0.06, blue: 0.09)
                        .opacity(colorScheme == .dark
                                 ? (0.06 + 0.10 * glassIntensity)  // 0.06 (glass off) → 0.16 (glass on)
                                 : (0.01 + 0.04 * glassIntensity))
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    LiquidGlassTokens.specularBorder(
                        isDark: colorScheme == .dark,
                        intensity: 0.4 + 0.7 * glassIntensity  // scales with slider
                    ),
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(
            color: Color.black.opacity(colorScheme == .dark
                ? (0.20 + 0.18 * glassIntensity)
                : (0.06 + 0.08 * glassIntensity)),
            radius: 10 + 8 * glassIntensity,
            x: 0,
            y: 4 + 5 * glassIntensity
        )
        .animation(LiquidGlassTokens.stateSpring, value: glassIntensity)
    }

    // MARK: - Shared Helpers
    
    /// Preferred height of the scrolling content area. Fixed rather than fitted to content so the
    /// popover doesn't jump when switching providers; tall enough that a typical page fits.
    private static let preferredContentHeight: CGFloat = 580
    /// Room left on screen for the header, provider switcher, popover arrow and a margin.
    private static let reservedScreenHeight: CGFloat = 150
    
    /// Content height, shrunk on small displays so the popover never runs past the bottom of the screen.
    /// Measured on the screen under the pointer: the popover opens from a click on the status item,
    /// and NSScreen.main follows the key window, which can be on another display.
    private var contentHeight: CGFloat {
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame.height else { return Self.preferredContentHeight }
        return max(320, min(Self.preferredContentHeight, visible - Self.reservedScreenHeight))
    }

    /// Accent of the provider currently on screen, used for the ambient tint bleed
    private var activeTint: Color {
        let selected = service.selectedInstalledProviders
        if selected.count == 1 {
            return LiquidGlassPalette.accent(for: selected[0])
        } else if selected.count > 1 {
            return LiquidGlassPalette.accent(for: service.dualActiveProvider)
        }
        return LiquidGlassPalette.aiBlue
    }

    /// Provider whose numbers are on screen
    private var visibleProvider: AIProvider? {
        let selected = service.selectedInstalledProviders
        if selected.count == 1 { return selected[0] }
        return selected.isEmpty ? nil : service.dualActiveProvider
    }
    
    /// Header status: age of the numbers on screen, with the dot showing health (blue while
    /// refreshing, amber once stale or offline). Measured per provider, since one provider can
    /// serve cached figures while the others refresh.
    private func headerStatus(now: Date) -> (text: String, color: Color) {
        guard let provider = visibleProvider else { return ("No tools", Color.gray) }
        guard let asOf = service.dataAsOf(provider) else {
            return service.isLoading
                ? ("Connecting…", LiquidGlassPalette.aiBlue)
                : ("Offline", LiquidGlassPalette.moderate)
        }
        let text = Freshness.label(lastUpdated: asOf, now: now)
        if service.isLoading {
            return (text, LiquidGlassPalette.aiBlue)
        }
        let stale = Freshness.isStale(
            lastUpdated: asOf,
            refreshInterval: TimeInterval(service.refreshInterval.rawValue),
            now: now
        )
        return (text, stale ? LiquidGlassPalette.moderate : LiquidGlassPalette.healthy)
    }
    
    /// Hairline that fades out at both ends, like light along a glass edge
    private var specularDivider: some View {
        LinearGradient(
            colors: [Color.white.opacity(0.0), Color.white.opacity(0.16), Color.white.opacity(0.0)],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 1)
        .padding(.horizontal, 14)
    }

    /// Tab subtitle. The menu bar's terse "Off" becomes what's actually wrong: the desktop
    /// app isn't running (Antigravity, ChatGPT) or no Claude account is signed in. When the
    /// figure comes from the weekly limit, it says so.
    private func tabStatus(for provider: AIProvider) -> String {
        guard service.isProviderConnected(provider) else {
            return provider == .claude ? "Signed out" : "Not running"
        }
        let badge = service.badgeText(for: provider)
        return service.menuBarPercentage(for: provider) != nil && service.isWeeklyBinding(for: provider)
            ? "\(badge) weekly"
            : badge
    }
    
    /// Remaining fraction shown on a provider's switcher tab, or nil when it has no figure
    private func remainingFraction(for provider: AIProvider) -> Double? {
        service.menuBarPercentage(for: provider).map { Double($0) / 100.0 }
    }
    
    // MARK: - Header
    
    private var headerBar: some View {
        HStack(alignment: .center, spacing: 8) {
            // App Branding
            HStack(spacing: 8) {
                if let icon = AppIconHelper.appIconImage {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 22, height: 22)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(LiquidGlassTokens.specularBorder(isDark: true, intensity: 1.0), lineWidth: 0.8)
                        )
                        .shadow(color: activeTint.opacity(0.45), radius: 5, x: 0, y: 1)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(LiquidGlassPalette.aiBlue)
                        .shadow(color: LiquidGlassPalette.aiBlue.opacity(0.50), radius: 4, x: 0, y: 0)
                }
                
                // The version lives in the ⋯ menu
                Text("AIUsage")
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundColor(LiquidGlassText.primary)
                    .lineLimit(1)
                    .fixedSize()
            }
            
            // Freshness pill: how current the numbers are, re-rendered as they age.
            // The dot carries connection health; hover lists each provider's status.
            TimelineView(.periodic(from: .now, by: 10)) { context in
                let status = headerStatus(now: context.date)
                HStack(spacing: 5) {
                    Circle()
                        .fill(status.color)
                        .frame(width: 6, height: 6)
                        .shadow(color: status.color.opacity(0.80), radius: 3, x: 0, y: 0)
                    
                    Text(status.text)
                        .font(.system(size: 10.5, weight: .semibold))
                        .monospacedDigit()
                        .foregroundColor(LiquidGlassText.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3.5)
                .liquidGlassPill(isProminent: false, tint: status.color)
                .animation(LiquidGlassTokens.motion(LiquidGlassTokens.stateSpring, reduceMotion: reduceMotion), value: status.text)
            }
            .help(service.menuBarTooltip)
            
            Spacer(minLength: 4)
            
            // Update Button (when update is available)
            if let update = updateService.availableUpdate {
                Button(action: {
                    updateService.promptUpdate(update)
                }) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 26, height: 26)
                        .liquidGlassButton(cornerRadius: 13, isProminent: true, tint: LiquidGlassPalette.aiBlue)
                }
                .buttonStyle(.plain)
                .help("Update \(update.tagName) available. Click to download.")
            }
            
            // Control cluster: one glass capsule holding the header actions
            HStack(spacing: 0) {
                if service.installedProvidersCount > 1 {
                    GlassIconButton(
                        systemImage: "slider.horizontal.3",
                        isActive: isShowingProviderFocusPopover,
                        help: "Select active AI providers (Multi-Choice)"
                    ) {
                        isShowingProviderFocusPopover.toggle()
                    }
                    .popover(isPresented: $isShowingProviderFocusPopover, arrowEdge: .bottom) {
                        ProviderFocusSubmenuView(service: service, onDismiss: {
                            isShowingProviderFocusPopover = false
                        })
                        .padding(4)
                    }
                }
                
                GlassIconButton(
                    systemImage: "arrow.clockwise",
                    isActive: service.isLoading,
                    rotation: spinAngle,
                    help: "Refresh quotas for all selected providers"
                ) {
                    withAnimation(LiquidGlassTokens.motion(LiquidGlassTokens.stateSpring, reduceMotion: reduceMotion)) {
                        spinAngle += 360
                    }
                    service.refresh(forceDiscovery: true)
                }
                
                moreMenu
            }
            .padding(2)
            .liquidGlassPill()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
    
    /// Settings and app actions. Quit lives here rather than as a bare button next to Refresh,
    /// where it was easy to hit by mistake.
    private var moreMenu: some View {
        Menu {
            Text("AIUsage \(AppVersion.displayString)")
            Divider()
            Picker("Refresh Interval", selection: $service.refreshInterval) {
                ForEach(RefreshInterval.allCases, id: \.self) { interval in
                    Text(interval.title).tag(interval)
                }
            }
            Toggle("Launch at Login", isOn: Binding(
                get: { LaunchAtLogin.isEnabled },
                set: { _ in LaunchAtLogin.toggle() }
            ))
            Picker("Menu Bar", selection: $service.displayMode) {
                ForEach(MenuBarDisplayMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            Menu("Low-Quota Alerts") {
                Picker("Low-Quota Alerts", selection: $service.alertMode) {
                    ForEach(LowQuotaAlertMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                Divider()
                notificationStatusItems
            }
            Toggle("Hide Email Addresses", isOn: $hideEmails)
            Divider()
            if !service.installedProviders.isEmpty {
                Menu("Open App") {
                    if service.isGeminiInstalled {
                        Button("Antigravity") { ProcessDiscovery.launchAntigravityApp() }
                    }
                    if service.isCodexInstalled {
                        Button("ChatGPT") { CodexDiscovery.launchChatGPTApp() }
                    }
                    if service.isClaudeInstalled {
                        Button("Claude") { ClaudeDiscovery.launchClaudeApp() }
                    }
                }
                Divider()
            }
            Button("Check for Updates…") {
                UpdateService.shared.checkForUpdates(isUserInitiated: true)
            }
            Button("Quit AIUsage") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11.5, weight: .semibold))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 26, height: 26)
        .help("More")
    }
    
    /// Notification permission as menu items: a status line, plus the one action that fixes it
    @ViewBuilder
    private var notificationStatusItems: some View {
        switch notifications.permission {
        case .authorized:
            Text("Notifications: On")
        case .notDetermined, .unknown:
            Text("Notifications: Not Set Up")
            Button("Turn On Notifications") {
                service.turnOnAlerts()
            }
        case .denied:
            Text("Notifications: Blocked")
            Button("Open Notification Settings…") {
                NotificationManager.openNotificationSettings()
            }
        }
    }
    
    // MARK: - Alerts Notice
    
    private enum AlertsNoticeKind: Equatable {
        case none
        /// Never asked: invite the user to turn alerts on, so the macOS prompt arrives when expected
        case setUp
        /// Alerts are on but notifications are blocked, so none can appear
        case blocked
    }
    
    /// Shown at the top of the popover whenever low-quota alerts are on but can't be delivered.
    /// Turning alerts off (from the notice or the menu) clears it.
    private var alertsNoticeKind: AlertsNoticeKind {
        guard service.alertMode != .off else { return .none }
        switch notifications.permission {
        case .notDetermined: return .setUp
        case .denied: return .blocked
        case .authorized, .unknown: return .none
        }
    }
    
    private func turnOffAlerts() {
        withAnimation(LiquidGlassTokens.motion(LiquidGlassTokens.stateSpring, reduceMotion: reduceMotion)) {
            service.alertMode = .off
        }
    }
    
    @ViewBuilder
    private var alertsNotice: some View {
        if alertsNoticeKind != .none {
            alertsNoticeContent
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
    
    @ViewBuilder
    private var alertsNoticeContent: some View {
        Group {
            switch alertsNoticeKind {
            case .none:
                EmptyView()
            case .setUp:
                // "Not Now" turns alerts off: that's what declining means, and it can be undone from the menu
                AlertsOnboardingCard(
                    onTurnOn: { service.turnOnAlerts() },
                    onDismiss: turnOffAlerts
                )
            case .blocked:
                NotificationsBlockedStrip(
                    onOpenSettings: { NotificationManager.openNotificationSettings() },
                    onTurnOffAlerts: turnOffAlerts
                )
            }
        }
    }
    
    // MARK: - Persistent Provider Views
    
    @ViewBuilder
    private var geminiView: some View {
        if service.isGeminiConnected {
            geminiContentView
        } else {
            geminiOfflineView
                .frame(minHeight: 320)
        }
    }
    
    @ViewBuilder
    private var chatgptView: some View {
        if service.isCodexConnected {
            chatgptContentView
        } else {
            chatgptOfflineView
                .frame(minHeight: 320)
        }
    }
    
    @ViewBuilder
    private var claudeView: some View {
        if service.isClaudeConnected {
            claudeContentView
        } else {
            claudeOfflineView
                .frame(minHeight: 320)
        }
    }
    
    // MARK: - Multi-Provider Flipping Switcher Bar
    
    private var multiProviderSwitcherBar: some View {
        HStack(spacing: 4) {
            if service.selectedInstalledProviders.contains(.gemini) {
                dualProviderTabButton(
                    provider: .gemini,
                    icon: AppIconHelper.antigravityIcon,
                    systemFallback: "sparkles"
                )
            }
            
            if service.selectedInstalledProviders.contains(.chatgpt) {
                dualProviderTabButton(
                    provider: .chatgpt,
                    icon: AppIconHelper.chatgptIcon,
                    systemFallback: "circle.hexagongrid"
                )
            }
            
            if service.selectedInstalledProviders.contains(.claude) {
                dualProviderTabButton(
                    provider: .claude,
                    icon: AppIconHelper.claudeIcon,
                    systemFallback: "asterisk"
                )
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.18))
        )
        .overlay(
            // Recessed track: shadow rim on top, light catch on the bottom edge
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.black.opacity(0.25), Color.white.opacity(0.10)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.8
                )
        )
        .padding(.horizontal, 14)
        .padding(.top, 2)
        .padding(.bottom, 8)
    }
    
    private func dualProviderTabButton(
        provider: AIProvider,
        icon: NSImage?,
        systemFallback: String
    ) -> some View {
        let isSelected = service.dualActiveProvider == provider
        let accentColor = LiquidGlassPalette.accent(for: provider)
        let fraction = remainingFraction(for: provider)
        
        return Button(action: {
            withAnimation(LiquidGlassTokens.motion(LiquidGlassTokens.interactiveSpring, reduceMotion: reduceMotion)) {
                service.dualActiveProvider = provider
            }
        }) {
            HStack(spacing: 6) {
                ZStack {
                    if let fraction = fraction {
                        CircularProgressView(fraction: fraction, size: 22, strokeWidth: 2.5)
                    }
                    Group {
                        if let icon = icon {
                            Image(nsImage: icon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 12, height: 12)
                                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                        } else {
                            Image(systemName: systemFallback)
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundColor(isSelected ? .white : accentColor)
                        }
                    }
                }
                .frame(width: 22, height: 22)
                
                VStack(alignment: .leading, spacing: 0) {
                    Text(provider.displayName)
                        .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                        .foregroundColor(isSelected ? LiquidGlassText.primary : LiquidGlassText.secondary)
                        .lineLimit(1)
                    
                    Text(tabStatus(for: provider))
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(isSelected ? LiquidGlassText.secondary : LiquidGlassText.tertiary)
                        .lineLimit(1)
                }
                
                Spacer(minLength: 0)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 7)
            .frame(maxWidth: .infinity)
            .background(
                ZStack {
                    if isSelected {
                        // Glass lens that slides to the selected provider
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [accentColor.opacity(0.55), accentColor.opacity(0.30)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(LiquidGlassTokens.specularBorder(isDark: true, intensity: 1.3), lineWidth: 1)
                            )
                            .shadow(color: accentColor.opacity(0.45), radius: 6, x: 0, y: 2)
                            .matchedGeometryEffect(id: "providerLens", in: switcherNamespace)
                    }
                }
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("\(provider.fullName): \(tabStatus(for: provider))")
    }
    
    // MARK: - Dual Flipping Content View
    
    @ViewBuilder
    private var dualFlippingContentView: some View {
        OverflowScrollView {
            alertsNotice
            Group {
                switch service.dualActiveProvider {
                case .gemini:
                    geminiView
                    
                case .chatgpt:
                    chatgptView
                    
                case .claude:
                    claudeView
                }
            }
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.98)),
                removal: .opacity.combined(with: .scale(scale: 1.02))
            ))
            .id(service.dualActiveProvider)
        }
    }
    
    // MARK: - Claude Views
    
    private var claudeContentView: some View {
        ClaudeQuotaCardView(
            account: service.claudeAccount,
            limits: service.claudeLimits,
            service: service
        )
        .padding(14)
    }
    
    private var claudeOfflineView: some View {
        GlassEmptyState(
            icon: AppIconHelper.claudeIcon,
            systemFallback: "asterisk",
            tint: LiquidGlassPalette.claude,
            title: "Claude (Anthropic) Disconnected",
            message: service.claudeErrorMessage ?? "Claude desktop app or local session not detected. Launch Claude to view real-time quota telemetry."
        ) {
            GlassCapsuleButton("Launch Claude", systemImage: "arrow.up.forward.app", style: .prominent(LiquidGlassPalette.claude)) {
                ClaudeDiscovery.launchClaudeApp()
            }
        }
        .padding(.vertical, 14)
    }
    
    // MARK: - Gemini Views
    
    private var geminiCards: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Plan Card
            PlanCardView(
                userTier: service.userStatus?.userTier,
                email: service.userStatus?.email,
                name: service.userStatus?.name
            )
            
            // Quota Models (all groups including Claude and GPT)
            if let groups = service.quotaSummary?.groups {
                let primaryGroupName = service.quotaSummary?.primaryGroup?.displayName
                ForEach(groups) { group in
                    QuotaCardView(
                        group: group,
                        menuBarBucketId: group.displayName == primaryGroupName ? service.quotaSummary?.bindingBucket?.bucketId : nil
                    )
                }
            }
        }
    }
    
    private var geminiContentView: some View {
        geminiCards
            .padding(14)
    }
    
    private var geminiOfflineView: some View {
        GlassEmptyState(
            icon: AppIconHelper.antigravityIcon,
            systemFallback: "sparkles",
            tint: LiquidGlassPalette.antigravity,
            title: "Antigravity (Google) Not Running",
            message: "Launch Antigravity or Antigravity IDE to monitor live Gemini model quotas, 5h burst limits, and weekly resets."
        ) {
            GlassCapsuleButton("Retry", systemImage: "arrow.clockwise", style: .prominent(LiquidGlassPalette.antigravity), help: "Retry Antigravity") {
                service.refresh(forceDiscovery: true)
            }
            GlassCapsuleButton("Launch App", systemImage: "arrow.up.forward.app") {
                ProcessDiscovery.launchAntigravityApp()
            }
        }
        .padding(.vertical, 6)
    }
    
    // MARK: - ChatGPT Views
    
    private var chatgptCards: some View {
        ChatGPTQuotaCardView(
            account: service.codexAccount,
            rateLimits: service.codexRateLimits,
            usage: service.codexUsage,
            service: service
        )
    }
    
    private var chatgptContentView: some View {
        chatgptCards
            .padding(14)
    }
    
    private var chatgptOfflineView: some View {
        GlassEmptyState(
            icon: AppIconHelper.chatgptIcon,
            systemFallback: "circle.hexagongrid",
            tint: LiquidGlassPalette.chatgpt,
            title: "ChatGPT (OpenAI) Not Connected",
            message: "Ensure ChatGPT.app is installed and signed in. AIUsage reads limits directly from the local ChatGPT runtime."
        ) {
            GlassCapsuleButton("Retry", systemImage: "arrow.clockwise", style: .prominent(LiquidGlassPalette.chatgpt), help: "Retry ChatGPT") {
                service.refresh()
            }
            GlassCapsuleButton("Launch App", systemImage: "arrow.up.forward.app") {
                CodexDiscovery.launchChatGPTApp()
            }
        }
        .padding(.vertical, 6)
    }
    
    // MARK: - No Tools Installed View
    
    private var noToolsInstalledView: some View {
        GlassEmptyState(
            icon: nil,
            systemFallback: "sparkles.rectangle.stack",
            tint: LiquidGlassPalette.aiBlue,
            title: "No AI Tools Detected",
            message: "Install Antigravity, ChatGPT, or Claude for macOS to monitor live model quotas and rate limits."
        ) {
            GlassCapsuleButton("Check Again", systemImage: "arrow.clockwise", style: .prominent(LiquidGlassPalette.aiBlue)) {
                service.refresh(forceDiscovery: true)
            }
        }
        .frame(minHeight: 280)
    }
}
