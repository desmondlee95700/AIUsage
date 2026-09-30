import SwiftUI

public struct MainUsageView: View {
    @ObservedObject var service: QuotaService
    @State private var spinAngle: Double = 0.0
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    
    public init(service: QuotaService = .shared) {
        self.service = service
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            headerBar
            
            Divider()
                .background(Color.white.opacity(0.06))
            
            // Content Body
            if service.isConnected {
                VStack(alignment: .leading, spacing: 14) {
                    // Plan Card
                    PlanCardView(
                        userTier: service.userStatus?.userTier,
                        email: service.userStatus?.email,
                        name: service.userStatus?.name
                    )
                    
                    // Quota Models
                    if let groups = service.quotaSummary?.groups {
                        ForEach(groups.filter {
                            let name = $0.displayName.lowercased()
                            return !name.contains("claude") && !name.contains("gpt")
                        }) { group in
                            QuotaCardView(group: group)
                        }
                    }
                }
                .padding(14)
            } else {
                offlineStateView
                    .frame(height: 240)
            }
        }
        .frame(width: 380)
        .fixedSize(horizontal: true, vertical: true)
        .background(
            Group {
                if reduceTransparency {
                    Color(red: 0.11, green: 0.12, blue: 0.15)
                } else {
                    ZStack {
                        Rectangle()
                            .fill(.ultraThinMaterial)
                        
                        // Ambient Liquid Glass Tint Bleed
                        Color(red: 0.07, green: 0.08, blue: 0.11)
                            .opacity(colorScheme == .dark ? 0.65 : 0.20)
                    }
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    LiquidGlassTokens.specularBorder(isDark: colorScheme == .dark, intensity: 0.8),
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    
    // MARK: - Header
    
    private var headerBar: some View {
        HStack(alignment: .center, spacing: 8) {
            // App Branding
            HStack(spacing: 8) {
                if let icon = AppIconHelper.appIconImage {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.20), lineWidth: 0.8)
                        )
                        .shadow(color: Color(red: 0.35, green: 0.65, blue: 1.0).opacity(0.40), radius: 4, x: 0, y: 1)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.38, green: 0.62, blue: 1.0),
                                    Color(red: 0.22, green: 0.44, blue: 0.95)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: Color(red: 0.25, green: 0.45, blue: 0.95).opacity(0.50), radius: 4, x: 0, y: 0)
                }
                
                Text("AIUsage")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
            }
            
            // Connection Status Pill
            HStack(spacing: 5) {
                Circle()
                    .fill(service.isConnected ? Color(red: 0.20, green: 0.84, blue: 0.50) : Color.orange)
                    .frame(width: 6.5, height: 6.5)
                    .shadow(
                        color: (service.isConnected ? Color.green : Color.orange).opacity(0.60),
                        radius: 3,
                        x: 0,
                        y: 0
                    )
                
                Text(service.isConnected ? "Live" : "Offline")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.70))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3.5)
            .background(
                Capsule(style: .continuous)
                    .fill(.regularMaterial)
                    .overlay(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.04))
                    )
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(0.25), location: 0.0),
                                .init(color: Color.white.opacity(0.04), location: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            
            Spacer()
            
            // Action Buttons
            HStack(spacing: 6) {
                // Refresh Button
                Button(action: {
                    withAnimation(LiquidGlassTokens.interactiveSpring) {
                        spinAngle += 360
                    }
                    service.refresh(forceDiscovery: true)
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(service.isLoading ? Color(red: 0.35, green: 0.60, blue: 1.0) : .white.opacity(0.80))
                        .rotationEffect(.degrees(spinAngle))
                        .frame(width: 26, height: 26)
                        .liquidGlassButton(cornerRadius: 6)
                }
                .buttonStyle(.plain)
                .help("Refresh quota")
                
                // Quit Button
                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    Image(systemName: "power")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.65))
                        .frame(width: 26, height: 26)
                        .liquidGlassButton(cornerRadius: 6)
                }
                .buttonStyle(.plain)
                .help("Quit AIUsage")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
    
    // MARK: - Offline View
    
    private var offlineStateView: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(.thinMaterial)
                    .frame(width: 72, height: 72)
                    .overlay(
                        Circle()
                            .strokeBorder(LiquidGlassTokens.specularBorder(isDark: true), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.20), radius: 8, x: 0, y: 4)
                
                if let icon = AppIconHelper.appIconImage {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .opacity(0.90)
                } else {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .font(.system(size: 28, weight: .light))
                        .foregroundColor(.white.opacity(0.40))
                }
            }
            
            VStack(spacing: 5) {
                Text("Antigravity Not Connected")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                
                Text("Launch Antigravity to monitor your live AI model quotas, weekly balance, and reset timers.")
                    .font(.system(size: 11.5))
                    .foregroundColor(.white.opacity(0.60))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
            
            Button(action: {
                service.refresh(forceDiscovery: true)
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Retry Connection")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.28, green: 0.50, blue: 0.95),
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
                                    .init(color: Color.white.opacity(0.50), location: 0.0),
                                    .init(color: Color.white.opacity(0.10), location: 1.0)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color(red: 0.25, green: 0.45, blue: 0.95).opacity(0.35), radius: 8, x: 0, y: 3)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
