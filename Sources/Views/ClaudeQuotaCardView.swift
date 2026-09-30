import SwiftUI

public struct ClaudeQuotaCardView: View {
    public let account: ClaudeAccountInfo?
    public let limits: ClaudeUsageLimits?
    @ObservedObject var service: QuotaService
    
    @State private var isUpgradeHovered: Bool = false
    @State private var isLaunchHovered: Bool = false
    
    public init(
        account: ClaudeAccountInfo?,
        limits: ClaudeUsageLimits?,
        service: QuotaService = .shared
    ) {
        self.account = account
        self.limits = limits
        self.service = service
    }
    
    private let terracottaColor = Color(red: 0.85, green: 0.45, blue: 0.25)
    private let darkTerracotta = Color(red: 0.70, green: 0.32, blue: 0.16)
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Plan Card
            planSection
            
            // Primary Quota Rate Limits Card
            quotaSection
            
            // Extra Usage Section (if available)
            if let extra = limits?.extraUsagePercent, account?.hasExtraUsageEnabled == true {
                extraUsageSection(remainingPercent: extra)
            }
        }
    }
    
    // MARK: - Plan Card
    
    private var planSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if let icon = AppIconHelper.claudeIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 14, height: 14)
                        .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
                } else {
                    Image(systemName: "asterisk")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(terracottaColor)
                }
                
                Text("Claude (Anthropic) Subscription")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                
                Spacer()
                
                Button(action: {
                    ClaudeDiscovery.launchClaudeApp()
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
                .help("Launch Claude desktop app")
                .onHover { hovering in
                    isLaunchHovered = hovering
                }
            }
            
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(account?.formattedTier ?? "Claude Free")
                            .font(.system(size: 14.5, weight: .bold))
                            .foregroundColor(.white)
                        
                        Text(account?.tierBadge ?? "Free")
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .foregroundColor(terracottaColor)
                            .padding(.horizontal, 5.5)
                            .padding(.vertical, 1.5)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(terracottaColor.opacity(0.18))
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(terracottaColor.opacity(0.35), lineWidth: 0.8)
                            )
                    }
                    
                    if let email = account?.emailAddress, !email.isEmpty {
                        HStack(spacing: 4.5) {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 10.5))
                                .foregroundColor(terracottaColor)
                            
                            Text(email)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundColor(Color(red: 0.95, green: 0.82, blue: 0.75))
                                .lineLimit(1)
                        }
                    }
                    
                    Text(account?.tierDescription ?? "Free tier uses dynamic server capacity cooldowns. Upgrade to Claude Pro for full quota limits.")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.60))
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer()
                
                Button(action: {
                    openClaudeUpgrade()
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
                                        terracottaColor,
                                        darkTerracotta
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
                        color: terracottaColor.opacity(isUpgradeHovered ? 0.45 : 0.20),
                        radius: 8,
                        x: 0,
                        y: 3
                    )
                    .scaleEffect(isUpgradeHovered ? 1.03 : 1.0)
                    .animation(LiquidGlassTokens.interactiveSpring, value: isUpgradeHovered)
                }
                .buttonStyle(.plain)
                .help("Upgrade Claude subscription")
                .onHover { hovering in
                    isUpgradeHovered = hovering
                }
            }
            .padding(14)
            .liquidGlassCard(cornerRadius: 16, tint: terracottaColor, material: .thinMaterial)
        }
    }
    
    // MARK: - Quota Section
    
    private var quotaSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "cpu")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(terracottaColor)
                
                Text("Claude (Anthropic) Rate Limits")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(.white.opacity(0.90))
            }
            
            VStack(spacing: 0) {
                if account?.canSeeUsageLimits ?? true, let limits = limits {
                    // 1. 5-Hour Limit
                    quotaRow(
                        title: "5-Hour Limit",
                        subtitle: "Rolling burst window",
                        remainingPercent: limits.fiveHourRemainingPercent,
                        usedPercent: limits.fiveHourUsedPercent,
                        resetCountdown: limits.formattedFiveHourCountdown
                    )
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    
                    Divider()
                        .background(Color.white.opacity(0.06))
                        .padding(.horizontal, 14)
                    
                    // 2. Weekly Limit
                    quotaRow(
                        title: "Weekly Limit",
                        subtitle: "All models (Sonnet, Opus & Haiku)",
                        remainingPercent: limits.weeklyRemainingPercent,
                        usedPercent: limits.weeklyUsedPercent,
                        resetCountdown: limits.formattedWeeklyCountdown
                    )
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    
                    // 3. Optional Model-specific limit (Sonnet)
                    if let sonnet = limits.sonnetRemainingPercent {
                        Divider()
                            .background(Color.white.opacity(0.06))
                            .padding(.horizontal, 14)
                        
                        quotaRow(
                            title: "Claude 3.7 Sonnet",
                            subtitle: "Weekly dedicated quota",
                            remainingPercent: sonnet,
                            usedPercent: 100 - sonnet,
                            resetCountdown: limits.formattedWeeklyCountdown
                        )
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }
                } else {
                    // Free Tier Informational State
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 13))
                                .foregroundColor(Color.orange)
                            
                            Text("Dynamic Free Tier Limits")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        
                        Text("Claude Free does not include fixed weekly quota limits. Capacity is dynamically allocated based on real-time server traffic. Upgrade to Claude Pro to unlock guaranteed 5-hour limits and weekly model tracking.")
                            .font(.system(size: 11.5))
                            .foregroundColor(.white.opacity(0.65))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                }
            }
            .liquidGlassCard(cornerRadius: 16, tint: terracottaColor, material: .thinMaterial)
        }
    }
    
    private func quotaRow(
        title: String,
        subtitle: String,
        remainingPercent: Int,
        usedPercent: Int,
        resetCountdown: String?
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundColor(.white)
                    
                    Text("• \(subtitle)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.50))
                }
                
                if let resetInfo = resetCountdown {
                    HStack(spacing: 4) {
                        Image(systemName: "hourglass")
                            .font(.system(size: 9.5))
                            .foregroundColor(.white.opacity(0.40))
                        Text(resetInfo)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.55))
                    }
                }
                
                Text("\(usedPercent)% quota utilized")
                    .font(.system(size: 10.5))
                    .foregroundColor(.white.opacity(0.40))
            }
            
            Spacer()
            
            HStack(spacing: 10) {
                Text("\(remainingPercent)%")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                CircularProgressView(
                    fraction: Double(remainingPercent) / 100.0,
                    size: 32,
                    strokeWidth: 4.0
                )
            }
        }
    }
    
    // MARK: - Extra Usage Section
    
    private func extraUsageSection(remainingPercent: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(red: 0.98, green: 0.78, blue: 0.25))
                
                Text("Extra Usage Credits")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
            }
            
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Pay-as-you-go extra usage is active")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(.white)
                    Text("Allows continued generation after standard limits are exhausted.")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.55))
                }
                
                Spacer()
                
                Text("\(remainingPercent)%")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            .padding(14)
            .liquidGlassCard(cornerRadius: 16, tint: Color(red: 0.98, green: 0.78, blue: 0.25), material: .thinMaterial)
        }
    }
    
    private func openClaudeUpgrade() {
        if let url = URL(string: "https://claude.ai/upgrade") {
            NSWorkspace.shared.open(url)
        }
    }
}
