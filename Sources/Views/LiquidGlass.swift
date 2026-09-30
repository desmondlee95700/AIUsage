//
//  LiquidGlass.swift
//  AIUsage
//  Apple Liquid Glass UI Design System (macOS Tahoe 26 / 27 & Control Center)
//

import SwiftUI
import AppKit

// MARK: - Native Visual Effect View (Real-time Desktop Sampling)

public struct VisualEffectView: NSViewRepresentable {
    public var material: NSVisualEffectView.Material
    public var blendingMode: NSVisualEffectView.BlendingMode
    public var state: NSVisualEffectView.State
    
    public init(
        material: NSVisualEffectView.Material = .popover,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
        state: NSVisualEffectView.State = .active
    ) {
        self.material = material
        self.blendingMode = blendingMode
        self.state = state
    }
    
    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        return view
    }
    
    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

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
    
    // Viscous Fluid Springs (Authentic Apple physical motion)
    public static let interactiveSpring = Animation.spring(response: 0.28, dampingFraction: 0.72, blendDuration: 0.15)
    public static let stateSpring = Animation.spring(response: 0.38, dampingFraction: 0.78, blendDuration: 0.20)
    public static let metricSpring = Animation.spring(response: 0.46, dampingFraction: 0.74, blendDuration: 0.25)
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
