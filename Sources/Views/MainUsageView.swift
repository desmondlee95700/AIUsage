import SwiftUI

public struct MainUsageView: View {
    @ObservedObject var service: QuotaService
    @State private var spinAngle: Double = 0.0
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @EnvironmentObject private var glassObserver: LiquidGlassObserver

    public init(service: QuotaService = .shared) {
        self.service = service
    }

    public var body: some View {
        let glassIntensity = reduceTransparency ? 0.0 : glassObserver.intensity

        VStack(spacing: 0) {
            // Header Bar
            headerBar

            Divider()
                .background(Color.white.opacity(0.06))

            // Multi-Provider Flipping Switcher (ONLY shown when Both / >1 provider is selected)
            if service.providerFocusMode == .both && (service.isGeminiInstalled && service.isCodexInstalled) {
                multiProviderSwitcherBar

                Divider()
                    .background(Color.white.opacity(0.04))
            }

            // Fixed-Height Content Container (ZERO height shift, ZERO flicker)
            ZStack(alignment: .top) {
                if !service.isGeminiInstalled && !service.isCodexInstalled {
                    noToolsInstalledView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if service.isGeminiInstalled && !service.isCodexInstalled {
                    ScrollView(.vertical, showsIndicators: false) {
                        if service.isGeminiConnected {
                            geminiContentView
                        } else {
                            geminiOfflineView
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !service.isGeminiInstalled && service.isCodexInstalled {
                    ScrollView(.vertical, showsIndicators: false) {
                        if service.isCodexConnected {
                            chatgptContentView
                        } else {
                            chatgptOfflineView
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    switch service.providerFocusMode {
                    case .gemini:
                        ScrollView(.vertical, showsIndicators: false) {
                            if service.isGeminiConnected {
                                geminiContentView
                            } else {
                                geminiOfflineView
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity)
                        
                    case .chatgpt:
                        ScrollView(.vertical, showsIndicators: false) {
                            if service.isCodexConnected {
                                chatgptContentView
                            } else {
                                chatgptOfflineView
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity)
                        
                    case .claude:
                        claudePlaceholderView
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .transition(.opacity)
                            
                    case .both:
                        dualFlippingContentView
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .transition(.opacity)
                    }
                }
            }
            .frame(height: 440)
            .clipped()
            .animation(.easeInOut(duration: 0.12), value: service.providerFocusMode)
            .animation(.easeInOut(duration: 0.20), value: service.dualActiveProvider)
        }
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

    
    // MARK: - Header
    
    private var headerBar: some View {
        HStack(alignment: .center, spacing: 8) {
            // App Branding
            HStack(spacing: 8) {
                if let icon = AppIconHelper.appIconImage {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.20), lineWidth: 0.8)
                        )
                        .shadow(color: Color(red: 0.35, green: 0.65, blue: 1.0).opacity(0.40), radius: 4, x: 0, y: 1)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.38, green: 0.62, blue: 1.0),
                                    Color(red: 0.22, green: 0.44, blue: 0.95)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: Color(red: 0.25, green: 0.45, blue: 0.95).opacity(0.50), radius: 4, x: 0, y: 0)
                }
                
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("AIUsage")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text(AppVersion.displayString)
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundColor(.white.opacity(0.40))
                }
            }
            
            // Connection Status Pill
            let (statusText, statusColor): (String, Color) = {
                if !service.isGeminiInstalled && !service.isCodexInstalled {
                    return ("No Tools", Color.gray)
                }
                let live: Bool = {
                    switch service.providerFocusMode {
                    case .gemini:
                        return service.isGeminiConnected
                    case .chatgpt:
                        return service.isCodexConnected
                    case .claude:
                        return false
                    case .both:
                        return service.isGeminiConnected || service.isCodexConnected
                    }
                }()
                return (live ? "Live" : "Offline", live ? Color(red: 0.20, green: 0.84, blue: 0.50) : Color.orange)
            }()
            
            HStack(spacing: 5) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                    .shadow(
                        color: statusColor.opacity(0.80),
                        radius: 3,
                        x: 0,
                        y: 0
                    )
                
                Text(statusText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .liquidGlassPill(isProminent: false, tint: statusColor)
            
            Spacer()
            
            // Action Buttons
            HStack(spacing: 6) {
                // Refresh Button
                Button(action: {
                    withAnimation(LiquidGlassTokens.interactiveSpring) {
                        spinAngle += 360
                    }
                    service.refresh(forceDiscovery: true)
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(service.isLoading ? Color(red: 0.35, green: 0.60, blue: 1.0) : .white.opacity(0.85))
                        .rotationEffect(.degrees(spinAngle))
                        .frame(width: 28, height: 28)
                        .liquidGlassButton(cornerRadius: 7, isProminent: false)
                }
                .buttonStyle(.plain)
                .help("Refresh quotas for both providers")
                
                // Quit Button
                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    Image(systemName: "power")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.70))
                        .frame(width: 28, height: 28)
                        .liquidGlassButton(cornerRadius: 7, isProminent: false)
                }
                .buttonStyle(.plain)
                .help("Quit AIUsage")
            }
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
    
    // MARK: - Multi-Provider Flipping Switcher Bar
    
    // MARK: - Multi-Provider Flipping Switcher Bar
    
    private var multiProviderSwitcherBar: some View {
        HStack(spacing: 5) {
            dualProviderTabButton(
                provider: .gemini,
                title: "Antigravity",
                subtitle: "Google",
                icon: AppIconHelper.antigravityIcon,
                systemFallback: "sparkles",
                badge: service.isGeminiConnected ? "\(service.geminiPercentage)%" : "Off",
                accentColor: Color(red: 0.28, green: 0.54, blue: 0.98)
            )
            
            dualProviderTabButton(
                provider: .chatgpt,
                title: "ChatGPT",
                subtitle: "OpenAI",
                icon: AppIconHelper.chatgptIcon,
                systemFallback: "circle.hexagongrid",
                badge: service.isCodexConnected ? "\(service.codexRemainingPercentage)%" : "Off",
                accentColor: Color(red: 0.16, green: 0.74, blue: 0.52)
            )
            
            dualProviderTabButton(
                provider: .claude,
                title: "Claude",
                subtitle: "Anthropic",
                icon: nil,
                systemFallback: "asterisk",
                badge: "Soon",
                accentColor: Color(red: 0.85, green: 0.45, blue: 0.25),
                isDisabled: true
            )
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.8)
        )
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }
    
    private func dualProviderTabButton(
        provider: AIProvider,
        title: String,
        subtitle: String,
        icon: NSImage?,
        systemFallback: String,
        badge: String,
        accentColor: Color,
        isDisabled: Bool = false
    ) -> some View {
        let isSelected = service.dualActiveProvider == provider
        
        return Button(action: {
            guard !isDisabled else { return }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                service.dualActiveProvider = provider
            }
        }) {
            HStack(spacing: 5) {
                if let icon = icon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 14, height: 14)
                        .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
                } else {
                    Image(systemName: systemFallback)
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundColor(isSelected ? .white : accentColor.opacity(isDisabled ? 0.40 : 1.0))
                }
                
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.system(size: 10.5, weight: isSelected ? .bold : .medium))
                        .foregroundColor(isSelected ? .white : .white.opacity(isDisabled ? 0.35 : 0.75))
                        .lineLimit(1)
                    
                    Text(subtitle)
                        .font(.system(size: 8.5, weight: .regular))
                        .foregroundColor(isSelected ? .white.opacity(0.80) : .white.opacity(isDisabled ? 0.25 : 0.45))
                        .lineLimit(1)
                }
                
                Text(badge)
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 4.5)
                    .padding(.vertical, 1.5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(isSelected ? Color.white.opacity(0.22) : Color.white.opacity(0.08))
                    )
                    .foregroundColor(isSelected ? .white : .white.opacity(isDisabled ? 0.30 : 0.60))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4.5)
            .padding(.horizontal, 4)
            .background(
                Group {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        accentColor.opacity(0.85),
                                        accentColor.opacity(0.65)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.35), lineWidth: 0.8)
                            )
                            .shadow(color: accentColor.opacity(0.40), radius: 5, x: 0, y: 1.5)
                    } else {
                        Color.clear
                    }
                }
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
    
    // MARK: - Dual Flipping Content View
    
    @ViewBuilder
    private var dualFlippingContentView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            Group {
                switch service.dualActiveProvider {
                case .gemini:
                    if service.isGeminiConnected {
                        geminiContentView
                    } else {
                        geminiOfflineView
                    }
                    
                case .chatgpt:
                    if service.isCodexConnected {
                        chatgptContentView
                    } else {
                        chatgptOfflineView
                    }
                    
                case .claude:
                    claudePlaceholderView
                }
            }
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.98)),
                removal: .opacity.combined(with: .scale(scale: 1.02))
            ))
            .id(service.dualActiveProvider)
        }
    }
    
    // MARK: - Claude Future Integration View
    
    private var claudePlaceholderView: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(.thinMaterial)
                    .frame(width: 68, height: 68)
                    .overlay(
                        Circle()
                            .strokeBorder(LiquidGlassTokens.specularBorder(isDark: true), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.20), radius: 8, x: 0, y: 4)
                
                Image(systemName: "asterisk")
                    .font(.system(size: 28, weight: .light))
                    .foregroundColor(Color(red: 0.85, green: 0.45, blue: 0.25))
            }
            
            VStack(spacing: 5) {
                Text("Claude (Anthropic) Coming Soon")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                
                Text("Anthropic Claude quota and rate-limit tracking will be available in an upcoming update.")
                    .font(.system(size: 11.5))
                    .foregroundColor(.white.opacity(0.60))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
        .padding(.vertical, 36)
        .frame(maxWidth: .infinity)
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
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(.thinMaterial)
                    .frame(width: 68, height: 68)
                    .overlay(
                        Circle()
                            .strokeBorder(LiquidGlassTokens.specularBorder(isDark: true), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.20), radius: 8, x: 0, y: 4)
                
                if let icon = AppIconHelper.antigravityIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.20), lineWidth: 0.8)
                        )
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(red: 0.40, green: 0.65, blue: 1.0), Color(red: 0.20, green: 0.45, blue: 0.95)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            }
            
            VStack(spacing: 5) {
                Text("Antigravity (Google) Not Running")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                
                Text("Launch Antigravity or Antigravity IDE to monitor live Gemini model quotas, 5h burst limits, and weekly resets.")
                    .font(.system(size: 11.5))
                    .foregroundColor(.white.opacity(0.60))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            
            HStack(spacing: 10) {
                Button(action: {
                    service.refresh(forceDiscovery: true)
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Retry Antigravity")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color(red: 0.28, green: 0.50, blue: 0.95), Color(red: 0.18, green: 0.38, blue: 0.88)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(LiquidGlassTokens.specularBorder(isDark: true, intensity: 1.2), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    ProcessDiscovery.launchAntigravityApp()
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Launch App")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.12))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(0.24), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
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
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(.thinMaterial)
                    .frame(width: 68, height: 68)
                    .overlay(
                        Circle()
                            .strokeBorder(LiquidGlassTokens.specularBorder(isDark: true), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.20), radius: 8, x: 0, y: 4)
                
                if let icon = AppIconHelper.chatgptIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.20), lineWidth: 0.8)
                        )
                } else {
                    Image(systemName: "circle.hexagongrid")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(red: 0.20, green: 0.85, blue: 0.60), Color(red: 0.12, green: 0.65, blue: 0.45)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            }
            
            VStack(spacing: 5) {
                Text("ChatGPT (OpenAI) Not Connected")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                
                Text("Ensure ChatGPT.app is installed and signed in. AIUsage reads limits directly from the local ChatGPT runtime.")
                    .font(.system(size: 11.5))
                    .foregroundColor(.white.opacity(0.60))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            
            HStack(spacing: 10) {
                Button(action: {
                    service.refresh()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Retry ChatGPT")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color(red: 0.14, green: 0.68, blue: 0.48), Color(red: 0.08, green: 0.50, blue: 0.35)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(LiquidGlassTokens.specularBorder(isDark: true, intensity: 1.2), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    CodexDiscovery.launchChatGPTApp()
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Launch App")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.12))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(0.24), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - No Tools Installed View
    
    private var noToolsInstalledView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(.thinMaterial)
                    .frame(width: 68, height: 68)
                    .overlay(
                        Circle()
                            .strokeBorder(LiquidGlassTokens.specularBorder(isDark: true), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.20), radius: 8, x: 0, y: 4)
                
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(red: 0.40, green: 0.65, blue: 1.0), Color(red: 0.20, green: 0.85, blue: 0.60)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            VStack(spacing: 6) {
                Text("No AI Tools Detected")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                
                Text("Install Antigravity or ChatGPT for macOS to monitor live model quotas and rate limits.")
                    .font(.system(size: 11.5))
                    .foregroundColor(.white.opacity(0.60))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            
            Button(action: {
                service.refresh(forceDiscovery: true)
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Check Again")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.28, green: 0.50, blue: 0.95), Color(red: 0.18, green: 0.38, blue: 0.88)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(LiquidGlassTokens.specularBorder(isDark: true, intensity: 1.2), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 36)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 280)
    }
}
