import Foundation

/// What the menu bar and its tooltip show for each provider, derived from QuotaService's state.
extension QuotaService {
    func menuBarQuotaLines(for provider: AIProvider, includeWindowLabels: Bool = false) -> [String] {
        guard isProviderConnected(provider) else { return ["Off"] }
        let short: Int?
        let weekly: Int?
        switch provider {
        case .gemini:
            short = primary5hBucket?.remainingFraction.map { Int(($0 * 100).rounded()) }
            weekly = primaryWeeklyBucket?.remainingFraction.map { Int(($0 * 100).rounded()) }
        case .chatgpt:
            short = codex5hWindow?.windowDurationMins == 300 ? codex5hPercentage : nil
            weekly = codexWeeklyPercentage
        case .claude:
            short = claude5hPercentage
            weekly = claudeWeeklyPercentage
        }
        var lines: [String] = []
        if let short { lines.append("\(short)%" + (includeWindowLabels ? " 5h" : "")) }
        if let weekly { lines.append("\(weekly)%" + (includeWindowLabels ? " wk" : "")) }
        return lines.isEmpty ? [badgeText(for: provider)] : lines
    }

    /// Remaining percentage the menu bar shows for a provider, or nil when disconnected or without data.
    public func menuBarPercentage(for provider: AIProvider) -> Int? {
        guard isProviderConnected(provider) else { return nil }
        switch provider {
        case .gemini: return geminiPercentage
        case .chatgpt: return codexRemainingPercentage
        case .claude: return claudePercentage
        }
    }
    
    /// The 5-hour and weekly bars drawn beside a provider's menu bar figure, or nil when the
    /// provider is disconnected or doesn't report both windows.
    public func menuBarMeter(for provider: AIProvider) -> MenuBarMeter? {
        guard isProviderConnected(provider) else { return nil }
        switch provider {
        case .gemini:
            // primary5hBucket falls back to any non-weekly bucket, so it is never the weekly one itself
            return MenuBarMeter(fiveHour: primary5hBucket?.remainingFraction, weekly: primaryWeeklyBucket?.remainingFraction)
        case .chatgpt:
            return MenuBarMeter(fiveHour: codex5hWindow?.remainingFraction, weekly: codexWeeklyWindow?.remainingFraction)
        case .claude:
            return MenuBarMeter(fiveHour: claude5hPercentage.map { Double($0) / 100 }, weekly: claudeWeeklyPercentage.map { Double($0) / 100 })
        }
    }

    /// Whether the menu bar figure for a provider comes from its weekly limit rather than the
    /// 5-hour one, so the popover can say which limit the number belongs to.
    public func isWeeklyBinding(for provider: AIProvider) -> Bool {
        switch provider {
        case .gemini:
            guard let binding = quotaSummary?.bindingBucket, let weekly = primaryWeeklyBucket else { return false }
            return binding.bucketId == weekly.bucketId && primary5hBucket?.bucketId != weekly.bucketId
        case .chatgpt:
            // Same 6–10 day range as CodexRateLimitSnapshot.weeklyWindow, so 30-day windows aren't called weekly
            guard let mins = codexSnapshot?.bindingWindow?.windowDurationMins else { return false }
            return (6 * 1440...10 * 1440).contains(mins)
        case .claude:
            return claudeLimits?.isWeeklyBinding ?? false
        }
    }
    
    /// When the numbers shown for a provider were fetched. Claude can serve its last good limits
    /// through brief failures, so its age comes from the limits themselves.
    public func dataAsOf(_ provider: AIProvider) -> Date? {
        guard isProviderConnected(provider) else { return nil }
        if provider == .claude, let fetched = claudeLimits?.lastUpdated {
            return fetched
        }
        return providerUpdatedAt[provider]
    }
    
    /// Short status for a provider as shown in the menu bar and provider tabs: "42%", "–" when
    /// connected without quota data, "Off", or a tier badge.
    public func badgeText(for provider: AIProvider) -> String {
        switch provider {
        case .gemini:
            return isGeminiConnected ? (geminiPercentage.map { "\($0)%" } ?? "–") : "Off"
        case .chatgpt:
            return isCodexConnected ? (codexRemainingPercentage.map { "\($0)%" } ?? "–") : "Off"
        case .claude:
            guard isClaudeConnected else { return "Off" }
            if let pct = claudePercentage {
                return "\(pct)%"
            }
            return claudeAccount?.tierBadge ?? "–"
        }
    }
    
    public var menuBarTooltip: String {
        var lines: [String] = ["AIUsage \(AppVersion.displayString) — AI Model Quota Tracker"]
        
        let providers = selectedInstalledProviders
        
        if providers.contains(.gemini) {
            if isGeminiConnected {
                let tier = userStatus?.userTier?.name ?? "Connected"
                if menuBarMeter(for: .gemini) != nil, let short = primary5hBucket, let weekly = primaryWeeklyBucket {
                    let shortReset = short.formattedResetCountdown ?? "Active"
                    let weeklyReset = weekly.formattedResetCountdown ?? "Active"
                    lines.append("• Antigravity (Google): 5h: \(short.percentage)% (\(shortReset)) · Weekly: \(weekly.percentage)% (\(weeklyReset)) (\(tier))")
                } else if let bucket = quotaSummary?.bindingBucket {
                    let reset = bucket.formattedResetCountdown ?? "Active"
                    let windowDesc = isWeeklyBinding(for: .gemini) ? "Weekly" : "5h limit"
                    lines.append("• Antigravity (Google): \(bucket.percentage)% (\(windowDesc)) remaining (\(tier)) · \(reset)")
                } else {
                    lines.append("• Antigravity (Google): No quota data (\(tier))")
                }
            } else {
                lines.append("• Antigravity (Google): Not running (open Antigravity to see quotas)")
            }
        }
        
        if providers.contains(.chatgpt) {
            if isCodexConnected {
                let plan = codexAccount?.formattedPlan ?? "Connected"
                if let short = codex5hWindow, let weekly = codexWeeklyWindow {
                    let shortReset = short.formattedResetCountdown ?? "Active"
                    let weeklyReset = weekly.formattedResetCountdown ?? "Active"
                    lines.append("• ChatGPT (OpenAI): 5h: \(short.remainingPercent)% (\(shortReset)) · Weekly: \(weekly.remainingPercent)% (\(weeklyReset)) (\(plan))")
                } else if let active = codexActiveWindow {
                    let reset = active.formattedResetCountdown ?? "Active"
                    let desc = active.windowDisplayName
                    lines.append("• ChatGPT (OpenAI): \(active.remainingPercent)% (\(desc)) remaining (\(plan)) · \(reset)")
                } else {
                    lines.append("• ChatGPT (OpenAI): No rate limit data (\(plan))")
                }
            } else {
                lines.append("• ChatGPT (OpenAI): Not connected (open ChatGPT and sign in)")
            }
        }
        
        if providers.contains(.claude) {
            if isClaudeConnected {
                let tier = claudeAccount?.formattedTier ?? "Connected"
                if let limits = claudeLimits {
                    var parts: [String] = []
                    if let fiveH = claude5hPercentage {
                        parts.append("5h: \(fiveH)% (\(limits.formattedFiveHourCountdown ?? "Full Quota"))")
                    }
                    if let weekly = claudeWeeklyPercentage {
                        parts.append("Weekly: \(weekly)% (\(limits.formattedWeeklyCountdown ?? "Full Quota"))")
                    }
                    lines.append("• Claude (Anthropic): \(parts.joined(separator: " · ")) (\(tier))")
                } else if claudeAccount?.canSeeUsageLimits == true {
                    lines.append("• Claude (Anthropic): Usage unavailable (\(tier))")
                } else {
                    lines.append("• Claude (Anthropic): Dynamic Free Tier (\(tier))")
                }
            } else {
                lines.append("• Claude (Anthropic): Signed out (open Claude and sign in)")
            }
        }
        
        if providers.isEmpty {
            lines.append("• No AI providers selected")
        } else {
            lines.append("The menu bar shows 5-hour limits on top and weekly limits below, with a progress bar beside each percentage. Click for details, right-click for actions.")
        }
        return lines.joined(separator: "\n")
    }
}
