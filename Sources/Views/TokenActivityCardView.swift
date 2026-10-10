import SwiftUI

/// Token activity over a selectable 7 / 14 / 30-day period, read from a CLI's local session logs.
public struct TokenActivityCardView: View {
    public let title: String
    public let fullActivity: TokenActivitySummary
    public let tint: Color

    @State private var hoveredDay: Date? = nil
    /// Shared by every activity card so switching the period on one switches both
    @AppStorage(TokenActivityRange.storageKey) private var rangeDays: Int = TokenActivityRange.week.rawValue
    
    private var range: TokenActivityRange {
        TokenActivityRange(rawValue: rangeDays) ?? .week
    }
    
    private var activity: TokenActivitySummary {
        fullActivity.lastDays(range.rawValue)
    }

    public init(title: String, activity: TokenActivitySummary, tint: Color) {
        self.title = title
        self.fullActivity = activity
        self.tint = tint
    }

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return formatter
    }()

    private var focusedDay: DailyTokenActivity? {
        activity.days.first { $0.day == hoveredDay }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(tint)

                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(.white.opacity(0.90))

                Spacer()

                rangePicker
            }

            VStack(alignment: .leading, spacing: 12) {
                statsRow
                barChart

                Text(activity.isEmpty
                     ? "No CLI sessions in the last \(activity.days.count) days. Activity appears here after your next session."
                     : "Tokens exclude cache reads. Counted from local CLI session logs on this Mac.")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.40))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .liquidGlassCard(cornerRadius: 16, tint: tint, material: .thinMaterial)
        }
    }

    // MARK: - Range Picker
    
    private var rangePicker: some View {
        HStack(spacing: 2) {
            ForEach(TokenActivityRange.allCases) { option in
                let isSelected = option == range
                Button(action: {
                    withAnimation(LiquidGlassTokens.interactiveSpring) {
                        rangeDays = option.rawValue
                        hoveredDay = nil
                    }
                }) {
                    Text(option.shortLabel)
                        .font(.system(size: 10, weight: isSelected ? .bold : .medium, design: .rounded))
                        .foregroundColor(.white.opacity(isSelected ? 0.95 : 0.50))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(isSelected ? tint.opacity(0.35) : Color.clear)
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(Color.white.opacity(isSelected ? 0.22 : 0), lineWidth: 0.8)
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Show the last \(option.rawValue) days")
            }
        }
        .padding(2)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
        )
    }
    
    // MARK: - Stats

    private var statsRow: some View {
        let detail = focusedDay
        let primaryTitle = detail.map { Self.dayFormatter.string(from: $0.day) } ?? "Today"
        let primary = detail?.usage ?? activity.today

        return HStack(alignment: .top, spacing: 10) {
            stat(title: primaryTitle, value: primary.total, caption: cacheCaption(primary.cacheRead))
            stat(title: "\(activity.days.count)-Day Total", value: activity.periodTotal.total, caption: cacheCaption(activity.periodTotal.cacheRead))
            stat(
                title: "Output",
                value: (detail?.usage ?? activity.periodTotal).output,
                caption: detail == nil ? "\(activity.days.count) days" : "that day"
            )
        }
    }

    private func cacheCaption(_ cacheRead: Int) -> String {
        cacheRead > 0 ? "+\(TokenActivitySummary.formatTokens(cacheRead)) cached" : "no cache reads"
    }

    private func stat(title: String, value: Int, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10.5))
                .foregroundColor(.white.opacity(0.55))
                .lineLimit(1)

            Text(TokenActivitySummary.formatTokens(value))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)

            Text(caption)
                .font(.system(size: 9.5))
                .foregroundColor(.white.opacity(0.40))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Chart

    private var barSpacing: CGFloat {
        switch range {
        case .week: return 8
        case .fortnight: return 4
        case .month: return 2.5
        }
    }
    
    private var barCornerRadius: CGFloat {
        range == .week ? 4 : 2
    }
    
    private var barChart: some View {
        let peak = max(activity.peakDayTotal, 1)
        let todayId = activity.days.last?.id
        
        return VStack(spacing: 5) {
            HStack(alignment: .bottom, spacing: barSpacing) {
                ForEach(activity.days) { day in
                    let fraction = CGFloat(day.usage.total) / CGFloat(peak)
                    let isHighlighted = day.id == todayId || day.id == hoveredDay
                    
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: barCornerRadius, style: .continuous)
                            .fill(Color.white.opacity(day.id == hoveredDay ? 0.12 : 0.05))
                        
                        RoundedRectangle(cornerRadius: barCornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [tint.opacity(isHighlighted ? 1.0 : 0.65), tint.opacity(isHighlighted ? 0.70 : 0.40)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            // Keep a sliver visible on days with any activity
                            .frame(height: day.usage.total > 0 ? max(2, 56 * fraction) : 0)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        if hovering {
                            hoveredDay = day.id
                        } else if hoveredDay == day.id {
                            hoveredDay = nil
                        }
                    }
                    .help("\(Self.dayFormatter.string(from: day.day)): \(TokenActivitySummary.formatTokens(day.usage.total)) tokens")
                }
            }
            
            HStack {
                if let first = activity.days.first {
                    Text(Self.shortDateFormatter.string(from: first.day))
                }
                Spacer()
                Text("Today")
            }
            .font(.system(size: 9.5, weight: .medium, design: .rounded))
            .foregroundColor(.white.opacity(0.45))
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.72, blendDuration: 0.2), value: activity)
        .animation(LiquidGlassTokens.interactiveSpring, value: hoveredDay)
        .animation(LiquidGlassTokens.stateSpring, value: rangeDays)
    }
}
