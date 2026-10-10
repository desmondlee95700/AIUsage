import SwiftUI

/// Token activity over a selectable 7 / 14 / 30-day period, read from a CLI's local session logs.
public struct TokenActivityCardView: View {
    public let title: String
    public let fullActivity: TokenActivitySummary
    public let tint: Color

    @State private var hoveredDay: Date? = nil
    @Namespace private var rangeNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
            GlassSectionHeader(title, systemImage: "chart.bar.fill", tint: tint) {
                rangePicker
            }

            VStack(alignment: .leading, spacing: 12) {
                statsRow
                barChart

                Text(activity.isEmpty
                     ? "No CLI sessions in the last \(activity.days.count) days. Activity appears here after your next session."
                     : "Tokens exclude cache reads. Counted from local CLI session logs on this Mac.")
                    .font(.system(size: 10))
                    .foregroundColor(LiquidGlassText.tertiary)
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
                    withAnimation(LiquidGlassTokens.motion(LiquidGlassTokens.interactiveSpring, reduceMotion: reduceMotion)) {
                        rangeDays = option.rawValue
                        hoveredDay = nil
                    }
                }) {
                    Text(option.shortLabel)
                        .font(.system(size: 10, weight: isSelected ? .bold : .medium, design: .rounded))
                        .foregroundColor(isSelected ? LiquidGlassText.primary : LiquidGlassText.tertiary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(
                            ZStack {
                                if isSelected {
                                    // Selection lens slides between options
                                    Capsule(style: .continuous)
                                        .fill(tint.opacity(0.40))
                                        .overlay(
                                            Capsule(style: .continuous)
                                                .strokeBorder(LiquidGlassTokens.specularBorder(isDark: true, intensity: 1.0), lineWidth: 0.8)
                                        )
                                        .shadow(color: tint.opacity(0.40), radius: 4, x: 0, y: 1)
                                        .matchedGeometryEffect(id: "rangeLens", in: rangeNamespace)
                                }
                            }
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Show the last \(option.rawValue) days")
            }
        }
        .padding(2)
        .liquidGlassPill()
    }
    
    // MARK: - Stats

    private var statsRow: some View {
        let detail = focusedDay
        let primaryTitle = detail.map { Self.dayFormatter.string(from: $0.day) } ?? "Today"
        let primary = detail?.usage ?? activity.today

        return HStack(alignment: .top, spacing: 8) {
            stat(title: primaryTitle, value: primary.total, caption: cacheCaption(primary.cacheRead), isFocused: detail != nil)
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

    private func stat(title: String, value: Int, caption: String, isFocused: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundColor(isFocused ? tint : LiquidGlassText.tertiary)
                .lineLimit(1)

            Text(TokenActivitySummary.formatTokens(value))
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(LiquidGlassText.primary)
                .lineLimit(1)

            Text(caption)
                .font(.system(size: 9.5))
                .foregroundColor(LiquidGlassText.tertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
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
    
    private static let chartHeight: CGFloat = 64

    private var barChart: some View {
        let peak = max(activity.peakDayTotal, 1)
        let todayId = activity.days.last?.id
        let activeDays = activity.days.filter { $0.usage.total > 0 }
        let average = activeDays.isEmpty ? 0 : activeDays.reduce(0) { $0 + $1.usage.total } / activeDays.count
        let averageFraction = CGFloat(average) / CGFloat(peak)
        let height = Self.chartHeight
        
        return VStack(spacing: 5) {
            ZStack(alignment: .bottom) {
                // Faint baseline grid
                VStack(spacing: 0) {
                    ForEach(0..<3) { _ in
                        Rectangle()
                            .fill(Color.white.opacity(0.05))
                            .frame(height: 0.5)
                        Spacer(minLength: 0)
                    }
                    Rectangle()
                        .fill(Color.white.opacity(0.10))
                        .frame(height: 0.5)
                }
                .frame(height: height)
                
                HStack(alignment: .bottom, spacing: barSpacing) {
                    ForEach(activity.days) { day in
                        let fraction = CGFloat(day.usage.total) / CGFloat(peak)
                        let isHovered = day.id == hoveredDay
                        let isHighlighted = day.id == todayId || isHovered
                        
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: barCornerRadius, style: .continuous)
                                .fill(Color.white.opacity(isHovered ? 0.10 : 0.03))
                            
                            RoundedRectangle(cornerRadius: barCornerRadius, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [tint.opacity(isHighlighted ? 1.0 : 0.70), tint.opacity(isHighlighted ? 0.55 : 0.28)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .overlay(
                                    // Specular cap on top of each bar
                                    RoundedRectangle(cornerRadius: barCornerRadius, style: .continuous)
                                        .fill(
                                            LinearGradient(
                                                colors: [Color.white.opacity(isHighlighted ? 0.45 : 0.22), Color.white.opacity(0.0)],
                                                startPoint: .top,
                                                endPoint: UnitPoint(x: 0.5, y: 0.3)
                                            )
                                        )
                                )
                                .shadow(color: tint.opacity(isHighlighted ? 0.55 : 0.0), radius: 5, x: 0, y: 0)
                                // Keep a sliver visible on days with any activity
                                .frame(height: day.usage.total > 0 ? max(3, height * fraction) : 0)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: height)
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
                
                // Daily average across active days
                if average > 0 {
                    HStack(spacing: 4) {
                        Line()
                            .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .foregroundColor(Color.white.opacity(0.45))
                            .frame(height: 1)
                        Text("avg \(TokenActivitySummary.formatTokens(average))")
                            .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                            .foregroundColor(LiquidGlassText.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule(style: .continuous).fill(Color.black.opacity(0.35)))
                            .fixedSize()
                    }
                    .offset(y: -height * averageFraction + 0.5)
                    .allowsHitTesting(false)
                }
            }
            .frame(height: height)
            
            HStack {
                if let first = activity.days.first {
                    Text(Self.shortDateFormatter.string(from: first.day))
                }
                Spacer()
                Text("Today")
            }
            .font(.system(size: 9.5, weight: .medium, design: .rounded))
            .foregroundColor(LiquidGlassText.tertiary)
        }
        .animation(LiquidGlassTokens.motion(LiquidGlassTokens.metricSpring, reduceMotion: reduceMotion), value: activity)
        .animation(LiquidGlassTokens.motion(LiquidGlassTokens.hoverSpring, reduceMotion: reduceMotion), value: hoveredDay)
        .animation(LiquidGlassTokens.motion(LiquidGlassTokens.stateSpring, reduceMotion: reduceMotion), value: rangeDays)
    }
}

/// Horizontal line shape for the dashed average marker
private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}
