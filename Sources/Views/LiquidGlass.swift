//
//  LiquidGlass.swift
//  AIUsage
//  macOS 27 Liquid Glass UI Design System
//

import SwiftUI

public enum LiquidGlassTokens {
    // Dynamic Specular Rim Gradient
    public static func specularBorder(
        isDark: Bool,
        intensity: CGFloat = 1.0
    ) -> LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color.white.opacity(isDark ? 0.26 * intensity : 0.85 * intensity), location: 0.0),
                .init(color: Color.white.opacity(isDark ? 0.09 * intensity : 0.30 * intensity), location: 0.45),
                .init(color: Color.white.opacity(isDark ? 0.02 * intensity : 0.06 * intensity), location: 1.0)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    // Viscous Fluid Springs
    public static let interactiveSpring = Animation.spring(response: 0.28, dampingFraction: 0.70, blendDuration: 0.15)
    public static let stateSpring = Animation.spring(response: 0.38, dampingFraction: 0.76, blendDuration: 0.20)
    public static let metricSpring = Animation.spring(response: 0.48, dampingFraction: 0.72, blendDuration: 0.25)
}

public struct LiquidGlassCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    
    public var cornerRadius: CGFloat
    public var material: Material
    
    public init(cornerRadius: CGFloat = 14, material: Material = .thinMaterial) {
        self.cornerRadius = cornerRadius
        self.material = material
    }
    
    public func body(content: Content) -> some View {
        content
            .background(
                Group {
                    if reduceTransparency {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(colorScheme == .dark ? Color(red: 0.14, green: 0.15, blue: 0.18) : Color(white: 0.94))
                    } else {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(material)
                            .overlay(
                                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                    .fill(
                                        colorScheme == .dark
                                            ? Color.white.opacity(0.045)
                                            : Color.white.opacity(0.35)
                                    )
                            )
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LiquidGlassTokens.specularBorder(isDark: colorScheme == .dark),
                        lineWidth: 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.25 : 0.08),
                radius: 10,
                x: 0,
                y: 5
            )
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.12 : 0.03),
                radius: 2,
                x: 0,
                y: 1
            )
    }
}

public struct LiquidGlassButtonModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered: Bool = false
    
    public var cornerRadius: CGFloat
    
    public init(cornerRadius: CGFloat = 6) {
        self.cornerRadius = cornerRadius
    }
    
    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Color.white.opacity(isHovered ? 0.12 : 0.04))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(isHovered ? 0.40 : 0.20), location: 0.0),
                                .init(color: Color.white.opacity(0.04), location: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .scaleEffect(isHovered ? 1.04 : 1.0)
            .animation(LiquidGlassTokens.interactiveSpring, value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

public extension View {
    func liquidGlassCard(cornerRadius: CGFloat = 14, material: Material = .thinMaterial) -> some View {
        modifier(LiquidGlassCardModifier(cornerRadius: cornerRadius, material: material))
    }
    
    func liquidGlassButton(cornerRadius: CGFloat = 6) -> some View {
        modifier(LiquidGlassButtonModifier(cornerRadius: cornerRadius))
    }
}
