import SwiftUI

public struct ChatGPTQuotaCardView: View {
    public let account: CodexAccountInfo?
    public let rateLimits: CodexRateLimitsResponse?
    public let usage: CodexUsageSummary?
    @ObservedObject var service: QuotaService
    
    @State private var isUpgradeHovered: Bool = false
    @State private var isLaunchHovered: Bool = false
    @State private var showingConfirmAlert: Bool = false
    
    public init(
        account: CodexAccountInfo?,
        rateLimits: CodexRateLimitsResponse?,
        usage: CodexUsageSummary?,
        service: QuotaService = .shared
    ) {
        self.account = account
        self.rateLimits = rateLimits
        self.usage = usage
        self.service = service
    }
    
    private var windows: [(title: String, window: CodexRateLimitWindow)] {
        rateLimits?.rateLimits?.allWindows ?? []
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Plan Card
            planSection
            
            // Primary Quota Card
            quotaSection
            
            // Usage Limit Resets Section (if available)
            if let resets = rateLimits?.rateLimitResetCredits, resets.availableCount > 0 {
                resetsSection(resets: resets)
            }
            
            // Usage Statistics Card
            if let usage = usage {
                usageStatsSection(usage: usage)
            }
        }
        .alert(isPresented: $showingConfirmAlert) {
            Alert(
                title: Text("Use Usage Limit Reset?"),
                message: Text("This will consume 1 reset credit to restore your 5-hour limit and weekly limit.\n\nResets are provided by OpenAI and expire after their set validity period."),
                primaryButton: .default(Text("Use Reset")) {
                    service.consumeCodexReset()
                },
                secondaryButton: .cancel()
            )
        }
    }
    
    // MARK: - Plan Card
    
    private var planSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if let icon = AppIconHelper.chatgptIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 14, height: 14)
                        .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
                } else {
                    Image(systemName: "circle.hexagongrid.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(red: 0.18, green: 0.82, blue: 0.58))
                }
                
                Text("ChatGPT (OpenAI) Subscription")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                
                Spacer()
                
                Button(action: {
                    openChatGPTApp()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 9.5, weight: .semibold))
                        Text("Launch App")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.white.opacity(isLaunchHovered ? 1.0 : 0.80))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3.5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(isLaunchHovered ? 0.15 : 0.08))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(isLaunchHovered ? 0.35 : 0.16), lineWidth: 0.8)
                    )
                    .scaleEffect(isLaunchHovered ? 1.03 : 1.0)
                    .animation(LiquidGlassTokens.interactiveSpring, value: isLaunchHovered)
                }
                .buttonStyle(.plain)
                .help("Launch ChatGPT desktop app")
                .onHover { hovering in
                    isLaunchHovered = hovering
                }
            }
            
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(account?.formattedPlan ?? "ChatGPT Free")
                        .font(.system(size: 14.5, weight: .bold))
                        .foregroundColor(.white)
                    
                    if let email = account?.email, !email.isEmpty {
                        HStack(spacing: 4.5) {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 10.5))
                                .foregroundColor(Color(red: 0.20, green: 0.80, blue: 0.58))
                            
                            Text(email)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundColor(Color(red: 0.65, green: 0.95, blue: 0.82))
                                .lineLimit(1)
                        }
                    }
                    
                    let upgradeText: String = {
                        let plan = account?.planType?.lowercased() ?? "free"
                        if plan == "free" {
                            return "Upgrade to Plus or Pro for higher rate limits."
                        } else {
                            return "Manage subscription or upgrade for higher limits."
                        }
                    }()
                    Text(upgradeText)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.60))
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer()
                
                Button(action: {
                    openChatGPTUpgrade()
                }) {
                    HStack(spacing: 5) {
                        Text("Upgrade")
                            .font(.system(size: 12, weight: .semibold))
                        Image(systemName: "arrow.up.forward")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.14, green: 0.70, blue: 0.50),
                                        Color(red: 0.08, green: 0.52, blue: 0.36)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    stops: [
                                        .init(color: Color.white.opacity(isUpgradeHovered ? 0.60 : 0.35), location: 0.0),
                                        .init(color: Color.white.opacity(0.08), location: 1.0)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(
                        color: Color(red: 0.10, green: 0.60, blue: 0.45).opacity(isUpgradeHovered ? 0.45 : 0.20),
                        radius: 8,
                        x: 0,
                        y: 3
                    )
                    .scaleEffect(isUpgradeHovered ? 1.03 : 1.0)
                    .animation(LiquidGlassTokens.interactiveSpring, value: isUpgradeHovered)
                }
                .buttonStyle(.plain)
                .help("Upgrade ChatGPT subscription")
                .onHover { hovering in
                    isUpgradeHovered = hovering
                }
            }
            .padding(14)
            .liquidGlassCard(cornerRadius: 16, tint: Color(red: 0.12, green: 0.65, blue: 0.45), material: .thinMaterial)
        }
    }
    
    private func openChatGPTApp() {
        CodexDiscovery.launchChatGPTApp()
    }
    
    private func openChatGPTUpgrade() {
        if let url = URL(string: "https://chatgpt.com/#pricing") {
            NSWorkspace.shared.open(url)
        }
    }
    
    // MARK: - Quota Section
    
    private var quotaSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "cpu")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(red: 0.20, green: 0.82, blue: 0.60))
                
                Text("ChatGPT (OpenAI) Rate Limits")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(.white.opacity(0.90))
            }
            
            VStack(spacing: 0) {
                if !windows.isEmpty {
                    ForEach(Array(windows.enumerated()), id: \.offset) { index, item in
                        if index > 0 {
                            Divider()
                                .background(Color.white.opacity(0.06))
                                .padding(.horizontal, 14)
                        }
                        
                        quotaRow(title: item.title, window: item.window)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                    }
                } else if let window = rateLimits?.rateLimits?.primary {
                    quotaRow(title: "Model Quota", window: window)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                } else {
                    Text("No active rate limit data available")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.50))
                        .padding(14)
                }
            }
            .liquidGlassCard(cornerRadius: 16, tint: Color(red: 0.12, green: 0.65, blue: 0.45), material: .thinMaterial)
        }
    }
    
    private func quotaRow(title: String, window: CodexRateLimitWindow) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundColor(.white)
                    
                    Text("• \(window.formattedDuration)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.50))
                }
                
                if let resetInfo = window.formattedResetCountdown {
                    HStack(spacing: 4) {
                        Image(systemName: "hourglass")
                            .font(.system(size: 9.5))
                            .foregroundColor(.white.opacity(0.40))
                        Text(resetInfo)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.55))
                    }
                }
                
                Text("\(window.usedPercent)% quota utilized")
                    .font(.system(size: 10.5))
                    .foregroundColor(.white.opacity(0.40))
            }
            
            Spacer()
            
            HStack(spacing: 10) {
                Text("\(window.remainingPercent)%")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                CircularProgressView(
                    fraction: window.remainingFraction,
                    size: 32,
                    strokeWidth: 4.0
                )
            }
        }
    }
    
    // MARK: - Usage Stats Section
    
    private func usageStatsSection(usage: CodexUsageSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(red: 0.38, green: 0.65, blue: 1.0))
                
                Text("ChatGPT Activity")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
            }
            
            HStack(spacing: 10) {
                statTile(
                    title: "Lifetime Tokens",
                    value: usage.formattedLifetimeTokens,
                    systemImage: "flame.fill",
                    tintColor: Color(red: 0.98, green: 0.52, blue: 0.20)
                )
                
                statTile(
                    title: "Peak Daily",
                    value: usage.formattedPeakTokens,
                    systemImage: "arrow.up.right.circle.fill",
                    tintColor: Color(red: 0.20, green: 0.80, blue: 0.60)
                )
                
                statTile(
                    title: "Top Streak",
                    value: "\(usage.longestStreakDays ?? 0)d",
                    systemImage: "calendar.badge.clock",
                    tintColor: Color(red: 0.40, green: 0.65, blue: 1.0)
                )
            }
        }
    }
    
    private func statTile(title: String, value: String, systemImage: String, tintColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 10))
                    .foregroundColor(tintColor)
                Text(title)
                    .font(.system(size: 10.5))
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(1)
            }
            
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .liquidGlassCard(cornerRadius: 12, tint: tintColor, material: .thinMaterial)
    }
    
    // MARK: - Usage Limit Resets Section
    
    private func resetsSection(resets: CodexRateLimitResetCreditsSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header Row
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(red: 0.18, green: 0.82, blue: 0.58))
                    
                    Text("Usage limit resets")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                // Available Count Pill
                Text("Available \(resets.availableCount)")
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundColor(Color(red: 0.18, green: 0.82, blue: 0.58))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color(red: 0.18, green: 0.82, blue: 0.58).opacity(0.14))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color(red: 0.18, green: 0.82, blue: 0.58).opacity(0.35), lineWidth: 0.8)
                    )
            }
            
            Text("Use a reset to restore your 5-hour limit, weekly limit, or both")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.55))
            
            // Credit Items List
            if let credits = resets.credits, !credits.isEmpty {
                VStack(spacing: 8) {
                    ForEach(credits) { credit in
                        resetCreditItem(
                            title: credit.formattedResetType,
                            subtitle: credit.formattedExpiration
                        )
                    }
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(0..<resets.availableCount, id: \.self) { _ in
                        resetCreditItem(
                            title: "Resets Available",
                            subtitle: "Ready to use"
                        )
                    }
                }
            }
            
            // Action Feedback Message
            if let message = service.resetActionMessage {
                HStack(spacing: 5) {
                    Image(systemName: service.resetActionIsSuccess ? "checkmark.circle.fill" : "info.circle.fill")
                        .font(.system(size: 10.5))
                        .foregroundColor(service.resetActionIsSuccess ? Color(red: 0.20, green: 0.85, blue: 0.55) : Color.orange)
                    
                    Text(message)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(service.resetActionIsSuccess ? Color(red: 0.70, green: 0.95, blue: 0.82) : Color.orange.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: 16, tint: Color(red: 0.16, green: 0.74, blue: 0.52), material: .thinMaterial)
    }
    
    private func resetCreditItem(title: String, subtitle: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2.5) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(.white)
                
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.48))
            }
            
            Spacer()
            
            Button(action: {
                showingConfirmAlert = true
            }) {
                if service.isConsumingReset {
                    ProgressView()
                        .scaleEffect(0.55)
                        .frame(width: 78, height: 26)
                } else {
                    Text("Use reset")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.12))
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(Color.white.opacity(0.24), lineWidth: 0.8)
                        )
                }
            }
            .buttonStyle(.plain)
            .disabled(service.isConsumingReset)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.25))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.8)
        )
    }
}
