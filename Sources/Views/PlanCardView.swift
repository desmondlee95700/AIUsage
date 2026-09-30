import SwiftUI

public struct PlanCardView: View {
    public let userTier: UserTier?
    public let email: String?
    public let name: String?
    @State private var isUpgradeHovered: Bool = false
    
    public init(userTier: UserTier?, email: String? = nil, name: String? = nil) {
        self.userTier = userTier
        self.email = email
        self.name = name
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if let icon = AppIconHelper.antigravityIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 14, height: 14)
                        .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
                } else {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(red: 0.98, green: 0.78, blue: 0.25))
                }
                
                Text("Current Plan")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
            }
            
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(userTier?.name ?? "Google AI")
                        .font(.system(size: 14.5, weight: .bold))
                        .foregroundColor(.white)
                    
                    if let email = email, !email.isEmpty {
                        HStack(spacing: 4.5) {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 10.5))
                                .foregroundColor(Color(red: 0.38, green: 0.65, blue: 1.0))
                            
                            Text(email)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundColor(Color(red: 0.70, green: 0.82, blue: 1.0))
                                .lineLimit(1)
                        }
                    }
                    
                    Text(userTier?.upgradeSubscriptionText ?? "You can upgrade to receive higher rate limits.")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.60))
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer()
                
                if let uri = userTier?.upgradeSubscriptionUri, let url = URL(string: uri) {
                    Button(action: {
                        NSWorkspace.shared.open(url)
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
                                            Color(red: 0.28, green: 0.50, blue: 0.96),
                                            Color(red: 0.18, green: 0.38, blue: 0.88)
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
                            color: Color(red: 0.25, green: 0.45, blue: 0.95).opacity(isUpgradeHovered ? 0.45 : 0.20),
                            radius: 8,
                            x: 0,
                            y: 3
                        )
                        .scaleEffect(isUpgradeHovered ? 1.03 : 1.0)
                        .animation(LiquidGlassTokens.interactiveSpring, value: isUpgradeHovered)
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        isUpgradeHovered = hovering
                    }
                }
            }
            .padding(14)
            .liquidGlassCard(cornerRadius: 14, material: .thinMaterial)
        }
    }
}
