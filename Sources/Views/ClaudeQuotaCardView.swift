import SwiftUI

public struct ClaudeQuotaCardView: View {
    public let account: ClaudeAccountInfo?
    public let limits: ClaudeUsageLimits?
    @ObservedObject var service: QuotaService
    
    public init(
        account: ClaudeAccountInfo?,
        limits: ClaudeUsageLimits?,
        service: QuotaService
    ) {
        self.account = account
        self.limits = limits
        self.service = service
    }
    
    private let tint = LiquidGlassPalette.claude
    
    private struct LimitTile {
        let title: String
        let caption: String
        let remainingPercent: Int
        let reset: String?
        let resetDate: Date?
    }
    
    private func tiles(for limits: ClaudeUsageLimits) -> [LimitTile] {
        var list: [LimitTile] = []
        if limits.hasFiveHourWindow {
            list.append(LimitTile(
                title: "5-Hour",
                caption: "Rolling burst window",
                remainingPercent: limits.fiveHourRemainingPercent,
                reset: limits.formattedFiveHourCountdown,
                resetDate: limits.fiveHourResetTime
            ))
        }
        if limits.hasWeeklyWindow {
            list.append(LimitTile(
                title: "Weekly",
                caption: "All models",
                remainingPercent: limits.weeklyRemainingPercent,
                reset: limits.formattedWeeklyCountdown,
                resetDate: limits.weeklyResetTime
            ))
        }
        if let sonnet = limits.sonnetRemainingPercent {
            list.append(LimitTile(
                title: "Sonnet",
                caption: "Weekly dedicated quota",
                remainingPercent: sonnet,
                reset: limits.formattedWeeklyCountdown,
                resetDate: limits.weeklyResetTime
            ))
        }
        return list
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ProviderPlanCard(
                provider: .claude,
                icon: AppIconHelper.claudeIcon,
                systemFallback: "asterisk",
                planName: account?.formattedTier ?? "Claude",
                email: account?.emailAddress,
                appName: "Claude",
                onLaunch: { ClaudeDiscovery.launchClaudeApp() },
                planLink: planLink
            )
            
            quotaSection
            
            if let extra = limits?.extraUsagePercent, account?.hasExtraUsageEnabled == true {
                extraUsageSection(remainingPercent: extra)
            }
            
            if let activity = service.claudeActivity {
                TokenActivityCardView(title: "Claude Activity", activity: activity, tint: tint)
            }
        }
    }
    
    // MARK: - Quota Section
    
    private var quotaSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            GlassSectionHeader("Rate Limits", systemImage: "gauge.with.dots.needle.67percent", tint: tint)
            
            Group {
                // Limits from the server win over the plan name: if they're reported, the plan has them
                if let limits = limits {
                    // Re-render periodically so the reset countdowns tick between refreshes
                    TimelineView(.periodic(from: .now, by: LiquidGlassTokens.countdownTick)) { _ in
                        let items = tiles(for: limits)
                        QuotaTileGrid(count: items.count) { index in
                            let item = items[index]
                            QuotaTile(
                                title: item.title,
                                caption: nil,
                                fraction: Double(item.remainingPercent) / 100.0,
                                resetText: item.reset,
                                resetDate: item.resetDate
                            )
                            .help(item.caption)
                        }
                    }
                    .padding(8)
                } else if account?.canSeeUsageLimits ?? true {
                    // Paid plan, usage not available: Claude Code's login has lapsed. Retries automatically.
                    notice(
                        systemImage: "wifi.slash",
                        color: LiquidGlassPalette.moderate,
                        title: "Connection Lost",
                        message: "5-hour and weekly limits are unavailable because Claude Code hasn't been active recently. They'll return automatically once you use Claude Code again."
                    )
                } else {
                    notice(
                        systemImage: "info.circle.fill",
                        color: LiquidGlassPalette.moderate,
                        title: "Dynamic Free Tier Limits",
                        message: "Claude Free does not include fixed weekly quota limits. Capacity is dynamically allocated based on real-time server traffic. Upgrade to Claude Pro to unlock guaranteed 5-hour limits and weekly model tracking."
                    )
                }
            }
            .liquidGlassCard(cornerRadius: 16, tint: tint, material: .thinMaterial)
        }
    }
    
    private func notice(systemImage: String, color: Color, title: String, message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 28, height: 28)
                .background(Circle().fill(color.opacity(0.16)))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(LiquidGlassText.primary)
                Text(message)
                    .font(.system(size: 11.5))
                    .foregroundColor(LiquidGlassText.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
    }
    
    // MARK: - Extra Usage Section
    
    private func extraUsageSection(remainingPercent: Int) -> some View {
        let gold = LiquidGlassPalette.credit
        
        return VStack(alignment: .leading, spacing: 8) {
            GlassSectionHeader("Extra Usage Credits", systemImage: "bolt.fill", tint: gold)
            
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Pay-as-you-go extra usage is active")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundColor(LiquidGlassText.primary)
                        Text("Allows continued generation after standard limits are exhausted.")
                            .font(.system(size: 11))
                            .foregroundColor(LiquidGlassText.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    Spacer(minLength: 8)
                    
                    Text("\(remainingPercent)%")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(LiquidGlassText.primary)
                }
                
                LiquidMeterBar(fraction: Double(remainingPercent) / 100.0, tint: gold, height: 7)
            }
            .padding(14)
            .liquidGlassCard(cornerRadius: 16, tint: gold, material: .thinMaterial)
        }
    }
    
    /// Paid plans manage billing; free plans see the upgrade page.
    private var planLink: ProviderPlanCard.PlanLink? {
        account?.canSeeUsageLimits == true || limits != nil
            ? URL(string: "https://claude.ai/settings/billing").map { .init(title: "Manage plan", url: $0) }
            : URL(string: "https://claude.ai/upgrade").map { .init(title: "Upgrade plan", url: $0) }
    }
}
