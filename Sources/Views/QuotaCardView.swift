import SwiftUI

public struct QuotaCardView: View {
    public let group: QuotaGroup
    
    public init(group: QuotaGroup) {
        self.group = group
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "cpu")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(red: 0.35, green: 0.65, blue: 0.98))
                
                Text(group.displayName)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(.white.opacity(0.90))
                
                if let desc = group.description, !desc.isEmpty {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10.5))
                        .foregroundColor(.white.opacity(0.40))
                        .help(desc)
                }
            }
            
            VStack(spacing: 0) {
                ForEach(Array(group.buckets.enumerated()), id: \.element.id) { index, bucket in
                    if index > 0 {
                        Divider()
                            .background(Color.white.opacity(0.06))
                            .padding(.horizontal, 14)
                    }
                    
                    QuotaBucketRowView(bucket: bucket)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                }
            }
            .liquidGlassCard(cornerRadius: 14, material: .thinMaterial)
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
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(bucket.displayName)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundColor(.white)
                
                if let resetInfo = bucket.formattedResetCountdown {
                    HStack(spacing: 4) {
                        Image(systemName: "hourglass")
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.40))
                        Text(resetInfo)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.55))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            
            Spacer()
            
            HStack(spacing: 10) {
                Text(bucket.formattedPercentage)
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                CircularProgressView(
                    fraction: bucket.remainingFraction ?? 0.0,
                    size: 28,
                    strokeWidth: 3.5
                )
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(isHovered ? 0.04 : 0.0))
        )
        .animation(LiquidGlassTokens.interactiveSpring, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
