import SwiftUI

public struct ChatGPTQuotaCardView: View {
    public let account: CodexAccountInfo?
    public let rateLimits: CodexRateLimitsResponse?
    public let usage: CodexUsageSummary?
    
    @State private var isWebHovered: Bool = false
    
    public init(
        account: CodexAccountInfo?,
        rateLimits: CodexRateLimitsResponse?,
        usage: CodexUsageSummary?
    ) {
        self.account = account
        self.rateLimits = rateLimits
        self.usage = usage
    }
    
    private var window: CodexRateLimitWindow? {
        rateLimits?.rateLimits?.primary
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Plan Card
            planSection
            
            // Primary Quota Card
            quotaSection
            
            // Usage Statistics Card
            if let usage = usage {
                usageStatsSection(usage: usage)
            }
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
                
                Text("OpenAI Subscription")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
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
                    
                    Text("Bundled Codex runtime inside ChatGPT.app")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.60))
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer()
                
                Button(action: {
                    if let url = URL(string: "https://chatgpt.com") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    HStack(spacing: 5) {
                        Text("ChatGPT")
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
                                        Color(red: 0.12, green: 0.68, blue: 0.48),
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
                                        .init(color: Color.white.opacity(isWebHovered ? 0.60 : 0.35), location: 0.0),
                                        .init(color: Color.white.opacity(0.08), location: 1.0)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(
                        color: Color(red: 0.10, green: 0.60, blue: 0.45).opacity(isWebHovered ? 0.45 : 0.20),
                        radius: 8,
                        x: 0,
                        y: 3
                    )
                    .scaleEffect(isWebHovered ? 1.03 : 1.0)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(LiquidGlassTokens.interactiveSpring) {
                        isWebHovered = hovering
                    }
                }
            }
            .padding(14)
            .liquidGlassCard(cornerRadius: 14, material: .thinMaterial)
        }
    }
    
    // MARK: - Quota Section
    
    private var quotaSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "cpu")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(red: 0.20, green: 0.82, blue: 0.60))
                
                Text("Codex Rate Limits")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(.white.opacity(0.90))
            }
            
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text("Model Quota")
                                .font(.system(size: 13.5, weight: .medium))
                                .foregroundColor(.white)
                            
                            if let dur = window?.formattedDuration {
                                Text("• \(dur)")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white.opacity(0.50))
                            }
                        }
                        
                        if let resetInfo = window?.formattedResetCountdown {
                            HStack(spacing: 4) {
                                Image(systemName: "hourglass")
                                    .font(.system(size: 9.5))
                                    .foregroundColor(.white.opacity(0.40))
                                Text(resetInfo)
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.55))
                            }
                        }
                        
                        if let used = window?.usedPercent {
                            Text("\(used)% quota utilized")
                                .font(.system(size: 10.5))
                                .foregroundColor(.white.opacity(0.40))
                        }
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 10) {
                        let remaining = window?.remainingPercent ?? 0
                        Text("\(remaining)%")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        
                        CircularProgressView(
                            fraction: window?.remainingFraction ?? 0.0,
                            size: 32,
                            strokeWidth: 4.0
                        )
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                
                // Reset Credits Row (if applicable)
                if let resetCredits = rateLimits?.rateLimitResetCredits, resetCredits.availableCount > 0 {
                    Divider()
                        .background(Color.white.opacity(0.06))
                        .padding(.horizontal, 14)
                    
                    HStack {
                        HStack(spacing: 6) {
                            Image(systemName: "bolt.badge.automatic.fill")
                                .font(.system(size: 11))
                                .foregroundColor(Color.orange)
                            Text("Reset Credits Available")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white.opacity(0.85))
                        }
                        Spacer()
                        Text("\(resetCredits.availableCount)")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }
            .liquidGlassCard(cornerRadius: 14, material: .thinMaterial)
        }
    }
    
    // MARK: - Usage Stats Section
    
    private func usageStatsSection(usage: CodexUsageSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(red: 0.38, green: 0.65, blue: 1.0))
                
                Text("Codex Activity")
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
        .liquidGlassCard(cornerRadius: 10, material: .thinMaterial)
    }
}
