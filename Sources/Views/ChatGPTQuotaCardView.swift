import SwiftUI

public struct ChatGPTQuotaCardView: View {
    public let account: CodexAccountInfo?
    public let rateLimits: CodexRateLimitsResponse?
    public let usage: CodexUsageSummary?
    @ObservedObject var service: QuotaService
    
    @State private var showingConfirmAlert: Bool = false
    
    public init(
        account: CodexAccountInfo?,
        rateLimits: CodexRateLimitsResponse?,
        usage: CodexUsageSummary?,
        service: QuotaService
    ) {
        self.account = account
        self.rateLimits = rateLimits
        self.usage = usage
        self.service = service
    }
    
    private let tint = LiquidGlassPalette.chatgpt
    
    private var windows: [(title: String, window: CodexRateLimitWindow)] {
        let all = rateLimits?.rateLimits?.allWindows ?? []
        if all.isEmpty, let primary = rateLimits?.rateLimits?.primary {
            return [(title: "Model Quota", window: primary)]
        }
        return all
    }
    
    /// Free plans see an upgrade link; paid plans manage their subscription on the same page.
    private var planLink: ProviderPlanCard.PlanLink? {
        let isFree = (account?.planType?.lowercased() ?? "free") == "free"
        return URL(string: "https://chatgpt.com/#pricing").map {
            .init(title: isFree ? "Upgrade plan" : "Manage plan", url: $0)
        }
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ProviderPlanCard(
                provider: .chatgpt,
                icon: AppIconHelper.chatgptIcon,
                systemFallback: "circle.hexagongrid.fill",
                planName: account?.formattedPlan ?? "ChatGPT Free",
                email: account?.email,
                appName: "ChatGPT",
                onLaunch: { CodexDiscovery.launchChatGPTApp() },
                planLink: planLink
            )
            
            quotaSection
            
            if let resets = rateLimits?.rateLimitResetCredits, resets.availableCount > 0 {
                resetsSection(resets: resets)
            }
            
            if let usage = usage {
                usageStatsSection(usage: usage)
            }
            
            if let activity = service.codexActivity {
                TokenActivityCardView(
                    title: "Codex CLI Activity",
                    activity: activity,
                    tint: LiquidGlassPalette.aiBlue
                )
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
    
    // MARK: - Quota Section
    
    private var quotaSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            GlassSectionHeader("Rate Limits", systemImage: "gauge.with.dots.needle.67percent", tint: tint)
            
            Group {
                if windows.isEmpty {
                    Text("No active rate limit data available")
                        .font(.system(size: 12))
                        .foregroundColor(LiquidGlassText.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                } else {
                    let items = windows
                    // Re-render periodically so the reset countdowns tick between refreshes
                    TimelineView(.periodic(from: .now, by: LiquidGlassTokens.countdownTick)) { _ in
                        QuotaTileGrid(count: items.count) { index in
                            let item = items[index]
                            QuotaTile(
                                title: item.title,
                                caption: nil,
                                fraction: item.window.remainingFraction,
                                resetText: item.window.formattedResetCountdown
                            )
                        }
                    }
                    .padding(8)
                }
            }
            .liquidGlassCard(cornerRadius: 16, tint: tint, material: .thinMaterial)
        }
    }
    
    // MARK: - Usage Stats Section
    
    private func usageStatsSection(usage: CodexUsageSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            GlassSectionHeader("ChatGPT Activity", systemImage: "chart.bar.xaxis", tint: LiquidGlassPalette.aiBlue)
            
            HStack(spacing: 8) {
                statTile(
                    title: "Lifetime",
                    value: usage.formattedLifetimeTokens,
                    systemImage: "flame.fill",
                    tintColor: Color(red: 0.98, green: 0.52, blue: 0.20)
                )
                
                statTile(
                    title: "Peak Day",
                    value: usage.formattedPeakTokens,
                    systemImage: "arrow.up.right",
                    tintColor: LiquidGlassPalette.healthy
                )
                
                statTile(
                    title: "Top Streak",
                    value: "\(usage.longestStreakDays ?? 0)d",
                    systemImage: "calendar",
                    tintColor: LiquidGlassPalette.aiBlue
                )
            }
            .padding(8)
            .liquidGlassCard(cornerRadius: 16, tint: LiquidGlassPalette.aiBlue, material: .thinMaterial)
        }
    }
    
    private func statTile(title: String, value: String, systemImage: String, tintColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 10.5, weight: .bold))
                .foregroundColor(tintColor)
                .frame(width: 24, height: 24)
                .background(Circle().fill(tintColor.opacity(0.18)))
                .overlay(Circle().strokeBorder(tintColor.opacity(0.35), lineWidth: 0.8))
            
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(LiquidGlassText.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(title)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(LiquidGlassText.tertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [tintColor.opacity(0.12), Color.white.opacity(0.03)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(LiquidGlassTokens.specularBorder(isDark: true, intensity: 0.6), lineWidth: 0.8)
        )
    }
    
    // MARK: - Usage Limit Resets Section
    
    private func resetsSection(resets: CodexRateLimitResetCreditsSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            GlassSectionHeader("Usage Limit Resets", systemImage: "arrow.counterclockwise", tint: tint) {
                GlassChip("\(resets.availableCount) available", tint: tint)
            }
            
            VStack(alignment: .leading, spacing: 10) {
                Text("Use a reset to restore your 5-hour limit, weekly limit, or both.")
                    .font(.system(size: 11))
                    .foregroundColor(LiquidGlassText.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                
                VStack(spacing: 6) {
                    if let credits = resets.credits, !credits.isEmpty {
                        ForEach(credits) { credit in
                            resetCreditItem(title: credit.formattedResetType, subtitle: credit.formattedExpiration)
                        }
                    } else {
                        ForEach(0..<resets.availableCount, id: \.self) { _ in
                            resetCreditItem(title: "Reset Available", subtitle: "Ready to use")
                        }
                    }
                }
                
                if let message = service.resetActionMessage {
                    let color = service.resetActionIsSuccess ? LiquidGlassPalette.healthy : LiquidGlassPalette.moderate
                    HStack(spacing: 5) {
                        Image(systemName: service.resetActionIsSuccess ? "checkmark.circle.fill" : "info.circle.fill")
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
    
    private func resetCreditItem(title: String, subtitle: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "ticket.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 26, height: 26)
                .background(Circle().fill(tint.opacity(0.16)))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(LiquidGlassText.primary)
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundColor(LiquidGlassText.tertiary)
            }
            
            Spacer(minLength: 6)
            
            if service.isConsumingReset {
                ProgressView()
                    .scaleEffect(0.55)
                    .frame(width: 78, height: 24)
            } else {
                GlassCapsuleButton("Use reset", style: .prominent(tint), size: .small) {
                    showingConfirmAlert = true
                }
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
}
