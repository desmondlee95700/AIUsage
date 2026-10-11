import SwiftUI

public struct QuotaCardView: View {
    public let group: QuotaGroup

    public init(group: QuotaGroup) {
        self.group = group
    }

    private let tint = LiquidGlassPalette.antigravity

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GlassSectionHeader(group.displayName, systemImage: "cpu", tint: tint) {
                if let desc = group.description, !desc.isEmpty {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                        .foregroundColor(LiquidGlassText.tertiary)
                        .help(desc)
                }
            }

            VStack(spacing: 4) {
                ForEach(group.buckets) { bucket in
                    QuotaBucketRowView(bucket: bucket)
                }
            }
            .padding(6)
            .liquidGlassCard(cornerRadius: 16, tint: tint, material: .thinMaterial)
        }
    }
}

public struct QuotaBucketRowView: View {
    public let bucket: QuotaBucket
    @State private var isHovered: Bool = false

    public init(bucket: QuotaBucket) {
        self.bucket = bucket
    }

    public var body: some View {
        let fraction = bucket.remainingFraction ?? 0.0
        let level = QuotaLevel(fraction: fraction)

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle()
                    .fill(level.color)
                    .frame(width: 6, height: 6)
                    .shadow(color: level.color.opacity(0.8), radius: 3)
                    .alignmentGuide(.firstTextBaseline) { d in d[.bottom] }

                Text(bucket.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(LiquidGlassText.primary)
                    .lineLimit(1)

                Spacer(minLength: 6)

                Text(bucket.formattedPercentage)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(LiquidGlassText.primary)
            }

            LiquidMeterBar(fraction: fraction, height: 7)

            // Re-render periodically so the countdown ticks between refreshes
            TimelineView(.periodic(from: .now, by: LiquidGlassTokens.countdownTick)) { _ in
                if let resetInfo = bucket.formattedResetCountdown {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 9, weight: .semibold))
                        Text(resetInfo)
                            .font(.system(size: 10.5))
                            .fixedSize(horizontal: false, vertical: true)
                            .help(bucket.resetDate.map { "Resets \(DateParsing.exact($0))" } ?? "")
                        Spacer(minLength: 4)
                        if level.needsAttention {
                            Text(level.label)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(level.color)
                        }
                    }
                    .foregroundColor(LiquidGlassText.tertiary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.white.opacity(isHovered ? 0.07 : 0.0))
        )
        .animation(LiquidGlassTokens.hoverSpring, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
