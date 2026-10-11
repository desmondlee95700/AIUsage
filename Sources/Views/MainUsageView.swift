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
                    ScrollView(.vertical, showsIndicators: false) {
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
            .frame(height: 440)
            .clipped()
            .animation(LiquidGlassTokens.motion(LiquidGlassTokens.stateSpring, reduceMotion: reduceMotion), value: service.selectedProviders)
            .animation(LiquidGlassTokens.motion(LiquidGlassTokens.stateSpring, reduceMotion: reduceMotion), value: service.dualActiveProvider)
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

    /// Header status: data age when something is connected, with the dot showing health
    /// (blue while refreshing, amber once stale or offline).
    private func headerStatus(now: Date) -> (text: String, color: Color) {
        let selected = service.selectedInstalledProviders
        guard !selected.isEmpty else { return ("No tools", Color.gray) }
        guard selected.contains(where: service.isProviderConnected) else {
            return service.isLoading
                ? ("Connecting…", LiquidGlassPalette.aiBlue)
                : ("Offline", LiquidGlassPalette.moderate)
        }
        let text = Freshness.label(lastUpdated: service.lastUpdated, now: now)
        if service.isLoading {
            return (text, LiquidGlassPalette.aiBlue)
        }
        let stale = Freshness.isStale(
            lastUpdated: service.lastUpdated,
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

    /// Remaining fraction shown on a provider's switcher tab, or nil when it has no figure
    private func remainingFraction(for provider: AIProvider) -> Double? {
        switch provider {
        case .gemini:
            return service.isGeminiConnected ? Double(service.geminiPercentage) / 100.0 : nil
        case .chatgpt:
            return service.isCodexConnected ? Double(service.codexRemainingPercentage) / 100.0 : nil
        case .claude:
            guard service.isClaudeConnected, let pct = service.claudePercentage else { return nil }
            return Double(pct) / 100.0
        }
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
                
                VStack(alignment: .leading, spacing: 0) {
                    Text("AIUsage")
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundColor(LiquidGlassText.primary)
                        .lineLimit(1)
                        .fixedSize()
                    
                    Text(AppVersion.displayString)
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundColor(LiquidGlassText.tertiary)
                        .lineLimit(1)
                        .fixedSize()
                }
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
                
                GlassIconButton(systemImage: "power", help: "Quit AIUsage") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(2)
            .liquidGlassPill()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
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
                    
                    Text(service.badgeText(for: provider))
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
        .help("\(provider.fullName): \(service.badgeText(for: provider))")
    }
    
    // MARK: - Dual Flipping Content View
    
    @ViewBuilder
    private var dualFlippingContentView: some View {
        ScrollView(.vertical, showsIndicators: false) {
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
                ForEach(groups) { group in
                    QuotaCardView(group: group)
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
