# SwiftUI Implementation Guide: macOS 27 Liquid Glass

This guide provides production-ready SwiftUI components and ViewModifiers adhering to the macOS 27 Liquid Glass design specifications.

---

## 1. Liquid Glass Card Modifier

Use this modifier to turn any standard container into a refractive Liquid Glass panel.

```swift
import SwiftUI

public struct LiquidGlassCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    
    public var cornerRadius: CGFloat
    public var material: Material
    public var isInteractive: Bool
    
    public init(
        cornerRadius: CGFloat = 14,
        material: Material = .thinMaterial,
        isInteractive: Bool = false
    ) {
        self.cornerRadius = cornerRadius
        self.material = material
        self.isInteractive = isInteractive
    }
    
    public func body(content: Content) -> some View {
        content
            .background(
                Group {
                    if reduceTransparency {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(colorScheme == .dark ? Color(white: 0.16) : Color(white: 0.94))
                    } else {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(material)
                            .overlay(
                                // Subtle ambient tint bleed
                                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                    .fill(
                                        colorScheme == .dark
                                            ? Color.white.opacity(0.04)
                                            : Color.white.opacity(0.35)
                                    )
                            )
                    }
                }
            )
            .overlay(
                // Specular Refractive Border
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: colorScheme == .dark ? Color.white.opacity(0.24) : Color.white.opacity(0.80), location: 0.0),
                                .init(color: colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.35), location: 0.45),
                                .init(color: colorScheme == .dark ? Color.white.opacity(0.02) : Color.black.opacity(0.06), location: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.28 : 0.08),
                radius: 12,
                x: 0,
                y: 6
            )
    }
}

public extension View {
    func liquidGlassCard(
        cornerRadius: CGFloat = 14,
        material: Material = .thinMaterial,
        isInteractive: Bool = false
    ) -> some View {
        self.modifier(LiquidGlassCardModifier(
            cornerRadius: cornerRadius,
            material: material,
            isInteractive: isInteractive
        ))
    }
}
```

---

## 2. Interactive Liquid Glass Button

Liquid Glass buttons dynamically refract on hover and compress fluidly on click.

```swift
public struct LiquidGlassButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered: Bool = false
    
    public var tintColor: Color?
    
    public init(tintColor: Color? = nil) {
        self.tintColor = tintColor
    }
    
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(.regularMaterial)
                    .overlay(
                        Capsule(style: .continuous)
                            .fill(
                                tintColor?.opacity(isHovered ? 0.22 : 0.12)
                                ?? (colorScheme == .dark ? Color.white.opacity(isHovered ? 0.12 : 0.06) : Color.black.opacity(isHovered ? 0.08 : 0.03))
                            )
                    )
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(isHovered ? 0.40 : 0.20), location: 0.0),
                                .init(color: Color.white.opacity(0.05), location: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.96 : (isHovered ? 1.02 : 1.0))
            .animation(.spring(response: 0.25, dampingFraction: 0.65), value: configuration.isPressed)
            .animation(.spring(response: 0.30, dampingFraction: 0.72), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}
```

---

## 3. macOS Popover Window Transparency Setup

For macOS menu bar apps (such as `AIUsage`), the hosting `NSPopover` or `NSWindow` must allow vibrancy and transparency to pass through:

```swift
// In NSApplicationDelegate or StatusItemController:
popover.appearance = NSAppearance(named: .darkAqua) // Or .aqua / system adaptive
if let popoverWindow = popover.contentViewController?.view.window {
    popoverWindow.isOpaque = false
    popoverWindow.backgroundColor = .clear
}
```
