import SwiftUI

public struct ClaudeQuotaCardView: View {
    public let account: ClaudeAccountInfo?
    public let limits: ClaudeUsageLimits?
    @ObservedObject var service: QuotaService
    
    /// Reset awaiting confirmation in the alert.
    @State private var pendingReset: ClaudeResetGrant?
    
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
    
    private enum LimitTileKind { case fiveHour, weekly, model }
    
    private struct LimitTile {
        var kind: LimitTileKind = .model
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
                kind: .fiveHour,
                title: "5-Hour",
                caption: "Rolling burst window",
                remainingPercent: limits.fiveHourRemainingPercent,
                reset: limits.formattedFiveHourCountdown,
                resetDate: limits.fiveHourResetTime
            ))
        }
        if limits.hasWeeklyWindow {
            list.append(LimitTile(
                kind: .weekly,
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
                caption: "Weekly Sonnet limit",
                remainingPercent: sonnet,
                reset: limits.formattedModelCountdown(limits.sonnetResetTime),
                resetDate: limits.modelResetTime(limits.sonnetResetTime)
            ))
        }
        if let opus = limits.opusRemainingPercent {
            list.append(LimitTile(
                title: "Opus",
                caption: "Weekly Opus limit",
                remainingPercent: opus,
                reset: limits.formattedModelCountdown(limits.opusResetTime),
                resetDate: limits.modelResetTime(limits.opusResetTime)
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
            
            if let limits = limits, !limits.availableResets().isEmpty || service.claudeResetMessage != nil {
                resetsSection(limits: limits)
            }
            
            // Reported by the usage endpoint only while extra usage is turned on
            if let extra = limits?.extraUsagePercent {
                extraUsageSection(remainingPercent: extra)
            }
            
            if let activity = service.claudeActivity {
                TokenActivityCardView(title: "Claude Activity", activity: activity, tint: tint)
            }
        }
        .alert(item: $pendingReset) { grant in
            Alert(
                title: Text("Use \(grant.title(scopedModel: limits?.scopedModelName))?"),
                message: Text(resetConfirmationMessage(for: grant)),
                primaryButton: .default(Text("Use Reset")) {
                    service.redeemClaudeReset(grant)
                },
                secondaryButton: .cancel()
            )
        }
    }
    
    /// Says what's left right now, so a reset isn't spent on limits that are nearly full.
    private func resetConfirmationMessage(for grant: ClaudeResetGrant) -> String {
        var levels: [String] = []
        if let fiveHour = limits?.fiveHourPercent { levels.append("\(fiveHour)% of your 5-hour limit") }
        if let weekly = limits?.weeklyPercent { levels.append("\(weekly)% of your weekly limit") }
        let current = levels.isEmpty ? "" : "You have \(levels.joined(separator: " and ")) left.\n\n"
        return current + grant.summary(scopedModel: limits?.scopedModelName) + " This can't be undone."
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
                                resetDate: item.resetDate,
                                isInMenuBar: item.kind == (limits.isWeeklyBinding ? .weekly : .fiveHour)
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
                        title: "Limits Unavailable",
                        // Either source can fail: claude.ai rate-limits or the session lapses, or Claude Code's sign-in expires
                        message: "Couldn't fetch your 5-hour and weekly limits. Claude may be limiting requests, "
                            + "or a sign-in needs refreshing: opening Claude or Claude Code usually fixes it. AIUsage keeps retrying."
                    )
                } else {
                    notice(
                        systemImage: "info.circle.fill",
                        color: LiquidGlassPalette.moderate,
                        title: "Dynamic Free Tier Limits",
                        message: "Claude Free does not include fixed weekly quota limits. Capacity is dynamically allocated based on real-time server traffic. "
                            + "Upgrade to Claude Pro to unlock guaranteed 5-hour limits and weekly model tracking."
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
    
    // MARK: - Limit Resets Section
    
    private func resetsSection(limits: ClaudeUsageLimits) -> some View {
        // Re-render periodically so the expiry countdowns tick between refreshes
        TimelineView(.periodic(from: .now, by: LiquidGlassTokens.countdownTick)) { context in
            let resets = limits.availableResets(now: context.date)
            let count = resets.reduce(0) { $0 + $1.resetsLeft }
            
            VStack(alignment: .leading, spacing: 8) {
                GlassSectionHeader("Limit Resets", systemImage: "arrow.counterclockwise", tint: tint) {
                    if count > 0 {
                        GlassChip("\(count) available", tint: tint)
                    }
                }
                
                VStack(alignment: .leading, spacing: 10) {
                    if !resets.isEmpty {
                        Text("Free resets from Claude. Each one expires, so use it before it lapses.")
                            .font(.system(size: 11))
                            .foregroundColor(LiquidGlassText.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        VStack(spacing: 6) {
                            ForEach(resets) { grant in
                                resetItem(grant, scopedModel: limits.scopedModelName)
                            }
                        }
                    }
                    
                    if let message = service.claudeResetMessage {
                        let color = service.claudeResetIsSuccess ? LiquidGlassPalette.healthy : LiquidGlassPalette.moderate
                        HStack(alignment: .top, spacing: 5) {
                            Image(systemName: service.claudeResetIsSuccess ? "checkmark.circle.fill" : "info.circle.fill")
                                .font(.system(size: 11))
                            Text(message)
                                .font(.system(size: 11, weight: .medium))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .foregroundColor(color)
                    }
                }
                .padding(14)
                .liquidGlassCard(cornerRadius: 16, tint: tint, material: .thinMaterial)
            }
        }
    }
    
    private func resetItem(_ grant: ClaudeResetGrant, scopedModel: String?) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "ticket.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 26, height: 26)
                .background(Circle().fill(tint.opacity(0.16)))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(grant.title(scopedModel: scopedModel))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(LiquidGlassText.primary)
                Text(grant.unavailableMessage ?? grant.formattedExpiration)
                    .font(.system(size: 10.5))
                    .foregroundColor(grant.unavailableMessage == nil ? LiquidGlassText.tertiary : LiquidGlassPalette.moderate)
                    .help(grant.expiresAt.map { "Expires " + DateParsing.exact($0) } ?? "")
                Text(grant.summary(scopedModel: scopedModel))
                    .font(.system(size: 10.5))
                    .foregroundColor(LiquidGlassText.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .help(grant.label)
            
            Spacer(minLength: 6)
            
            if service.redeemingClaudeResetId == grant.id {
                ProgressView()
                    .scaleEffect(0.55)
                    .frame(width: 78, height: 24)
            } else if grant.usableNow {
                GlassCapsuleButton("Use reset", style: .prominent(tint), size: .small) {
                    pendingReset = grant
                }
                .disabled(service.redeemingClaudeResetId != nil)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.8)
        )
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
                        Text("Keeps Claude working after your plan's limits run out. The figure is what's left of your monthly cap.")
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
