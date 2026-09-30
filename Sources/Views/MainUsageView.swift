import SwiftUI

public struct MainUsageView: View {
    @Namespace private var tabNamespace
    @ObservedObject var service: QuotaService
    @State private var spinAngle: Double = 0.0
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    
    public init(service: QuotaService = .shared) {
        self.service = service
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            headerBar
            
            // Provider Switcher Tab Bar (only when both are installed)
            if service.isGeminiInstalled && service.isCodexInstalled {
                providerSwitcherBar
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                
                Divider()
                    .background(Color.white.opacity(0.06))
            }
            
            // Content Body
            if service.isGeminiInstalled && service.isCodexInstalled {
                ZStack(alignment: .top) {
                    geminiView
                        .opacity(service.activeProvider == .gemini ? 1.0 : 0.0)
                        .allowsHitTesting(service.activeProvider == .gemini)
                    
                    chatgptView
                        .opacity(service.activeProvider == .chatgpt ? 1.0 : 0.0)
                        .allowsHitTesting(service.activeProvider == .chatgpt)
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .animation(.easeInOut(duration: 0.15), value: service.activeProvider)
            } else if service.isGeminiInstalled {
                geminiView
                    .frame(maxWidth: .infinity, alignment: .top)
            } else if service.isCodexInstalled {
                chatgptView
                    .frame(maxWidth: .infinity, alignment: .top)
            } else {
                noToolsInstalledView
            }
        }
        .frame(width: 380)
        .fixedSize(horizontal: true, vertical: true)
        .background(
            Group {
                if reduceTransparency {
                    Color(red: 0.11, green: 0.12, blue: 0.15)
                } else {
                    ZStack {
                        Rectangle()
                            .fill(.ultraThinMaterial)
                        
                        // Ambient Liquid Glass Tint Bleed
                        Color(red: 0.07, green: 0.08, blue: 0.11)
                            .opacity(colorScheme == .dark ? 0.65 : 0.20)
                    }
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    LiquidGlassTokens.specularBorder(isDark: colorScheme == .dark, intensity: 0.8),
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                
                Text("AIUsage")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
            }
            
            // Connection Status Pill
            let (statusText, statusColor): (String, Color) = {
                if !service.isGeminiInstalled && !service.isCodexInstalled {
                    return ("No Tools", Color.gray)
                }
                let live: Bool = {
                    if service.isGeminiInstalled && !service.isCodexInstalled {
                        return service.isGeminiConnected
                    }
                    if !service.isGeminiInstalled && service.isCodexInstalled {
                        return service.isCodexConnected
                    }
                    return service.isConnected
                }()
                return (live ? "Live" : "Offline", live ? Color(red: 0.20, green: 0.84, blue: 0.50) : Color.orange)
            }()
            
            HStack(spacing: 5) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6.5, height: 6.5)
                    .shadow(
                        color: statusColor.opacity(0.60),
                        radius: 3,
                        x: 0,
                        y: 0
                    )
                
                Text(statusText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.70))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3.5)
            .background(
                Capsule(style: .continuous)
                    .fill(.regularMaterial)
                    .overlay(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.04))
                    )
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(0.25), location: 0.0),
                                .init(color: Color.white.opacity(0.04), location: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            
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
                        .foregroundColor(service.isLoading ? Color(red: 0.35, green: 0.60, blue: 1.0) : .white.opacity(0.80))
                        .rotationEffect(.degrees(spinAngle))
                        .frame(width: 26, height: 26)
                        .liquidGlassButton(cornerRadius: 6)
                }
                .buttonStyle(.plain)
                .help("Refresh quotas for both providers")
                
                // Quit Button
                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    Image(systemName: "power")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.65))
                        .frame(width: 26, height: 26)
                        .liquidGlassButton(cornerRadius: 6)
                }
                .buttonStyle(.plain)
                .help("Quit AIUsage")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
    
    // MARK: - Liquid Glass Provider Switcher
    
    private var providerSwitcherBar: some View {
        HStack(spacing: 4) {
            providerButton(
                provider: .gemini,
                title: "Gemini",
                subtitle: "Antigravity",
                icon: AppIconHelper.antigravityIcon,
                isConnected: service.isGeminiConnected,
                percentage: service.isGeminiConnected ? "\(service.geminiPercentage)%" : "Off"
            )
            
            providerButton(
                provider: .chatgpt,
                title: "ChatGPT",
                subtitle: "Codex",
                icon: AppIconHelper.chatgptIcon,
                isConnected: service.isCodexConnected,
                percentage: service.isCodexConnected ? "\(service.codexRemainingPercentage)%" : "Off"
            )
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.black.opacity(0.30))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .animation(LiquidGlassTokens.stateSpring, value: service.activeProvider)
    }
    
    private func providerButton(
        provider: AIProvider,
        title: String,
        subtitle: String,
        icon: NSImage?,
        isConnected: Bool,
        percentage: String
    ) -> some View {
        let isSelected = service.activeProvider == provider
        
        return Button(action: {
            service.activeProvider = provider
        }) {
            HStack(spacing: 7) {
                // Real Provider Icon
                if let icon = icon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 18, height: 18)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.20), lineWidth: 0.8)
                        )
                } else {
                    Image(systemName: provider == .gemini ? "sparkles" : "circle.hexagongrid")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(
                            isSelected
                                ? (provider == .gemini ? Color(red: 0.40, green: 0.65, blue: 1.0) : Color(red: 0.20, green: 0.85, blue: 0.60))
                                : .white.opacity(0.50)
                        )
                }
                
                VStack(alignment: .leading, spacing: 0.5) {
                    Text(title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(isSelected ? .white : .white.opacity(0.65))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    
                    Text(subtitle)
                        .font(.system(size: 9.5))
                        .foregroundColor(.white.opacity(0.40))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                
                Spacer(minLength: 4)
                
                // Live Status Pill on the tab button
                HStack(spacing: 4) {
                    Circle()
                        .fill(isConnected ? (provider == .gemini ? Color(red: 0.25, green: 0.65, blue: 1.0) : Color(red: 0.20, green: 0.85, blue: 0.55)) : Color.orange)
                        .frame(width: 5.5, height: 5.5)
                    
                    Text(percentage)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(isSelected ? .white : .white.opacity(0.80))
                        .lineLimit(1)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? Color.white.opacity(0.12) : Color.white.opacity(0.05))
                )
            }
            .padding(.horizontal, 8)
            .frame(height: 36)
            .frame(maxWidth: .infinity)
            .background(
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.regularMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.white.opacity(0.06))
                            )
                            .matchedGeometryEffect(id: "activeTabHighlight", in: tabNamespace)
                    }
                }
            )
            .overlay(
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(
                                LiquidGlassTokens.specularBorder(isDark: true, intensity: 1.0),
                                lineWidth: 1
                            )
                            .matchedGeometryEffect(id: "activeTabBorder", in: tabNamespace)
                    }
                }
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
    
    // MARK: - Gemini Views
    
    private var geminiContentView: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Plan Card
            PlanCardView(
                userTier: service.userStatus?.userTier,
                email: service.userStatus?.email,
                name: service.userStatus?.name
            )
            
            // Quota Models
            if let groups = service.quotaSummary?.groups {
                ForEach(groups.filter {
                    let name = $0.displayName.lowercased()
                    return !name.contains("claude") && !name.contains("gpt")
                }) { group in
                    QuotaCardView(group: group)
                }
            }
            
            // Prompt / Flow Credits
            if let planStatus = service.userStatus?.planStatus {
                CreditsCardView(planStatus: planStatus)
            }
        }
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
                Text("Antigravity Not Running")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                
                Text("Launch Antigravity or Antigravity IDE to monitor live Gemini model quotas, 5h burst limits, and weekly resets.")
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
                    Text("Retry Gemini")
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
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - ChatGPT Views
    
    private var chatgptContentView: some View {
        ChatGPTQuotaCardView(
            account: service.codexAccount,
            rateLimits: service.codexRateLimits,
            usage: service.codexUsage
        )
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
                Text("ChatGPT / Codex Not Connected")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                
                Text("Ensure ChatGPT.app is installed and signed in. AIUsage reads limits directly from the bundled Codex runtime.")
                    .font(.system(size: 11.5))
                    .foregroundColor(.white.opacity(0.60))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            
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
                .padding(.horizontal, 16)
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
