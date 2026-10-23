//
//  LiquidGlass.swift
//  AIUsage
//  Apple Liquid Glass UI Design System (macOS Tahoe 26 / 27 & Control Center)
//

import SwiftUI
import AppKit

// MARK: - Tokens

public enum LiquidGlassTokens {
    // Dynamic Specular Rim Gradient (Directional chamfer highlight)
    public static func specularBorder(
        isDark: Bool = true,
        intensity: CGFloat = 1.0
    ) -> LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color.white.opacity(isDark ? 0.32 * intensity : 0.85 * intensity), location: 0.0),
                .init(color: Color.white.opacity(isDark ? 0.10 * intensity : 0.35 * intensity), location: 0.45),
                .init(color: Color.white.opacity(isDark ? 0.03 * intensity : 0.06 * intensity), location: 1.0)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    // Ambient Inner Highlight (Creates physical glass refraction depth)
    public static func innerRimHighlight(isDark: Bool = true) -> LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color.white.opacity(isDark ? 0.12 : 0.35), location: 0.0),
                .init(color: Color.clear, location: 0.5)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    // Viscous Fluid Springs (design-tokens.md §4)
    public static let interactiveSpring = Animation.spring(response: 0.28, dampingFraction: 0.65, blendDuration: 0.15)
    public static let hoverSpring = Animation.spring(response: 0.35, dampingFraction: 0.75, blendDuration: 0.20)

    /// How often reset countdowns re-render while visible (seconds); they show minute precision.
    public static let countdownTick: TimeInterval = 30
    public static let stateSpring = Animation.spring(response: 0.42, dampingFraction: 0.78, blendDuration: 0.25)
    public static let metricSpring = Animation.spring(response: 0.50, dampingFraction: 0.70, blendDuration: 0.30)

    /// Returns `nil` when Reduce Motion is on so value changes snap instead of springing
    public static func motion(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}

// MARK: - Palette (design-tokens.md §5)

public enum LiquidGlassPalette {
    public static let aiBlue = Color(red: 0.25, green: 0.48, blue: 0.98)
    public static let healthy = Color(red: 0.20, green: 0.82, blue: 0.48)
    public static let moderate = Color(red: 0.98, green: 0.68, blue: 0.18)
    public static let critical = Color(red: 0.96, green: 0.28, blue: 0.32)
    public static let credit = Color(red: 0.98, green: 0.78, blue: 0.25)

    public static let antigravity = Color(red: 0.28, green: 0.54, blue: 0.98)
    public static let chatgpt = Color(red: 0.16, green: 0.74, blue: 0.52)
    public static let claude = Color(red: 0.85, green: 0.45, blue: 0.25)

    public static func accent(for provider: AIProvider) -> Color {
        switch provider {
        case .gemini: return antigravity
        case .chatgpt: return chatgpt
        case .claude: return claude
        }
    }
}

// MARK: - Text Contrast (accessibility-performance.md §2)

public enum LiquidGlassText {
    public static let primary = Color.white
    /// Secondary labels and descriptions
    public static let secondary = Color.white.opacity(0.78)
    /// Captions, units and footnotes: the 0.65 floor for text on dark glass
    public static let tertiary = Color.white.opacity(0.65)
}

// MARK: - Quota Level

/// Health band for a remaining-quota fraction, shared by gauges, meters and chips.
/// Remaining-quota bands. The boundaries match the low-quota alerts (30% and 10%, see
/// `QuotaAlertTracker`), so a gauge turns amber exactly when the first alert would fire.
public enum QuotaLevel {
    case healthy, moderate, critical

    public init(fraction: Double) {
        if fraction > 0.3 {
            self = .healthy
        } else if fraction > 0.1 {
            self = .moderate
        } else {
            self = .critical
        }
    }
    
    /// Healthy quota needs no label; the gauge colour already says it.
    public var needsAttention: Bool {
        self != .healthy
    }

    public var color: Color {
        switch self {
        case .healthy: return LiquidGlassPalette.healthy
        case .moderate: return LiquidGlassPalette.moderate
        case .critical: return LiquidGlassPalette.critical
        }
    }

    /// Two-stop ramp for arcs and bars, ending on the band colour
    public var gradientColors: [Color] {
        switch self {
        case .healthy: return [Color(red: 0.18, green: 0.72, blue: 0.85), color]
        case .moderate: return [Color(red: 0.98, green: 0.84, blue: 0.30), color]
        case .critical: return [Color(red: 0.98, green: 0.48, blue: 0.42), color]
        }
    }

    public var label: String {
        switch self {
        case .healthy: return "Healthy"
        case .moderate: return "Low"
        case .critical: return "Almost out"
        }
    }
}

// MARK: - Liquid Glass Card Modifier (Control Center Module)

public struct LiquidGlassCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @EnvironmentObject private var glassObserver: LiquidGlassObserver

    public var cornerRadius: CGFloat
    public var tint: Color?
    public var material: Material?

    public init(
        cornerRadius: CGFloat = 16,
        tint: Color? = nil,
        material: Material? = nil
    ) {
        self.cornerRadius = cornerRadius
        self.tint = tint
        self.material = material
    }

    public func body(content: Content) -> some View {
        let isDark = colorScheme == .dark
        // Scale glass depth 0.0 (flat) → 1.0 (full refraction) from system slider
        let glassIntensity = reduceTransparency ? 0.0 : glassObserver.intensity
        let isGlassOn = glassIntensity > 0.05

        content
            .background(
                Group {
                    if !isGlassOn {
                        // ── Flat / Glass-off fallback ──────────────────────────
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(isDark
                                  ? Color(red: 0.14, green: 0.15, blue: 0.18)
                                  : Color(white: 0.94))
                    } else {
                        // ── Liquid Glass substrate (depth scales with slider) ──
                        ZStack {
                            // 1. Translucent glass substrate — fades in with slider
                            if let material = material {
                                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                    .fill(material)
                                    .opacity(0.35 + 0.30 * glassIntensity)  // 0.35 → 0.65
                            } else {
                                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                    .fill(
                                        isDark
                                        ? Color.white.opacity(0.06 + 0.06 * glassIntensity)
                                        : Color.white.opacity(0.40 + 0.20 * glassIntensity)
                                    )
                            }

                            // 2. Ambient tint bleed — scales with slider
                            if let tint = tint {
                                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                    .fill(tint.opacity((isDark ? 0.08 : 0.05) * glassIntensity))
                            }

                            // 3. Top specular sheet — scales with slider
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity((isDark ? 0.10 : 0.30) * glassIntensity),
                                            Color.white.opacity((isDark ? 0.01 : 0.05) * glassIntensity)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                    }
                }
            )
            .overlay(
                // Directional specular rim — softer when glass is dialed down
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        isGlassOn
                        ? LiquidGlassTokens.specularBorder(isDark: isDark,
                                                           intensity: 0.55 + 0.65 * glassIntensity)
                        : LiquidGlassTokens.specularBorder(isDark: isDark, intensity: 0.28),
                        lineWidth: 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(
                color: Color.black.opacity(isDark
                    ? (0.10 + 0.12 * glassIntensity)
                    : (0.04 + 0.04 * glassIntensity)),
                radius: 4 + 5 * glassIntensity,
                x: 0,
                y: 2 + 2 * glassIntensity
            )
            .animation(LiquidGlassTokens.stateSpring, value: glassIntensity)
    }
}

// MARK: - Liquid Glass Button Modifier

public struct LiquidGlassButtonModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered: Bool = false
    
    public var cornerRadius: CGFloat
    public var isProminent: Bool
    public var tint: Color?
    
    public init(
        cornerRadius: CGFloat = 8,
        isProminent: Bool = false,
        tint: Color? = nil
    ) {
        self.cornerRadius = cornerRadius
        self.isProminent = isProminent
        self.tint = tint
    }
    
    public func body(content: Content) -> some View {
        let isDark = colorScheme == .dark
        let accent = tint ?? Color.blue
        
        content
            .background(
                Group {
                    if isProminent {
                        // Prominent Liquid Glass Button (Active Control Center Toggle style)
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        accent,
                                        accent.opacity(0.85)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                    .fill(Color.white.opacity(isHovered ? 0.15 : 0.0))
                            )
                    } else {
                        // Standard Frosted Glass Button (.buttonStyle(.glass))
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                isDark
                                    ? Color.white.opacity(isHovered ? 0.12 : 0.05)
                                    : Color.white.opacity(isHovered ? 0.60 : 0.40)
                            )
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(isHovered ? 0.55 : (isProminent ? 0.40 : (isDark ? 0.22 : 0.65))), location: 0.0),
                                .init(color: Color.white.opacity(isHovered ? 0.15 : (isDark ? 0.04 : 0.12)), location: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(
                color: isProminent
                    ? accent.opacity(isHovered ? 0.50 : 0.30)
                    : Color.black.opacity(isHovered ? 0.15 : 0.06),
                radius: isHovered ? 6 : 3,
                x: 0,
                y: isHovered ? 2 : 1
            )
            .scaleEffect(isHovered ? 1.04 : 1.0)
            .animation(LiquidGlassTokens.interactiveSpring, value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

// MARK: - Liquid Glass Pill Capsule Modifier (Control Center Style)

public struct LiquidGlassPillModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    public var isProminent: Bool
    public var tint: Color?
    
    public init(isProminent: Bool = false, tint: Color? = nil) {
        self.isProminent = isProminent
        self.tint = tint
    }
    
    public func body(content: Content) -> some View {
        let isDark = colorScheme == .dark
        let accent = tint ?? Color.blue
        
        content
            .background(
                Group {
                    if isProminent {
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [accent, accent.opacity(0.85)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    } else {
                        Capsule(style: .continuous)
                            .fill(
                                isDark
                                    ? Color.white.opacity(0.06)
                                    : Color.white.opacity(0.35)
                            )
                    }
                }
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(isProminent ? 0.45 : 0.26), location: 0.0),
                                .init(color: Color.white.opacity(isProminent ? 0.10 : 0.04), location: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .clipShape(Capsule(style: .continuous))
            .shadow(
                color: isProminent ? accent.opacity(0.35) : Color.black.opacity(isDark ? 0.15 : 0.04),
                radius: isProminent ? 5 : 2,
                x: 0,
                y: 1
            )
    }
}

// MARK: - View Extensions

public extension View {
    func liquidGlassCard(
        cornerRadius: CGFloat = 16,
        tint: Color? = nil,
        material: Material? = nil
    ) -> some View {
        modifier(LiquidGlassCardModifier(cornerRadius: cornerRadius, tint: tint, material: material))
    }
    
    func liquidGlassButton(
        cornerRadius: CGFloat = 8,
        isProminent: Bool = false,
        tint: Color? = nil
    ) -> some View {
        modifier(LiquidGlassButtonModifier(cornerRadius: cornerRadius, isProminent: isProminent, tint: tint))
    }
    
    func liquidGlassPill(
        isProminent: Bool = false,
        tint: Color? = nil
    ) -> some View {
        modifier(LiquidGlassPillModifier(isProminent: isProminent, tint: tint))
    }
}
