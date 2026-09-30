---
name: liquid-glass-macos27
description: Design and implement next-generation Liquid Glass UI interfaces for macOS 27 and modern Apple platforms using SwiftUI. Use this skill whenever building or styling macOS interfaces, windows, menu bar popovers, cards, controls, HUDs, or widgets requiring translucent materials, specular refraction highlights, dynamic fluid blur, chromatic dispersion, ambient tint bleed, or visionOS/macOS 27 glassmorphic aesthetics, even if the user just asks for modern, sleek, or polished Apple UI styling.
license: MIT
---

# macOS 27 Liquid Glass UI Design System

A specialized skill for building next-generation Apple interfaces using the **macOS 27 Liquid Glass** design language in Swift and SwiftUI.

Liquid Glass represents the evolution of Apple's materials design: moving beyond flat blur overlays into dynamic, optical-grade refractive surfaces with specular edge highlights, ambient tint bleeding, and fluid spring physics.

---

## Core Visual Tenets

Every Liquid Glass surface adheres to four visual laws:

1. **Refractive Substrates, Not Flat Panels**:
   Never use flat solid hex background fills (e.g. avoid solid `#1c1d22`). Instead, use native translucent materials (`.ultraThinMaterial`, `.thinMaterial`, `.regularMaterial`) layered with an ambient color bleed.

2. **Directional Specular Rim Highlights**:
   Real glass catches light on its chamfered edges. All cards, popovers, and containers must feature a 1pt stroke border using an angled `LinearGradient` (from bright translucent white at `.topLeading` down to near-invisible opacity at `.bottomTrailing`).

3. **Fluid Spring Mechanics**:
   Physical elements must behave like polished lenses immersed in viscous fluid. Avoid linear or standard easeInOut transitions. Use interactive spring curves with controlled damping (e.g., `response: 0.32, dampingFraction: 0.72`).

4. **Accessibility First (Zero Distortion Fallback)**:
   Always respect `@Environment(\.accessibilityReduceTransparency)`. When reduced transparency is active, gracefully switch to opaque system surfaces with distinct border definition.

---

## Component Blueprints

### 1. Liquid Glass Card Container

For main content sections, quota buckets, metrics, and panels:

```swift
RoundedRectangle(cornerRadius: 14, style: .continuous)
    .fill(.thinMaterial)
    .overlay(
        // Ambient Tint Bleed
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.white.opacity(colorScheme == .dark ? 0.04 : 0.40))
    )
    .overlay(
        // Specular Refraction Rim
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    stops: [
                        .init(color: colorScheme == .dark ? Color.white.opacity(0.24) : Color.white.opacity(0.85), location: 0.0),
                        .init(color: colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.30), location: 0.5),
                        .init(color: colorScheme == .dark ? Color.white.opacity(0.02) : Color.black.opacity(0.06), location: 1.0)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    )
    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.28 : 0.08), radius: 12, x: 0, y: 6)
```

### 2. Menu Bar Popover Root Window

Menu bar popovers must configure clear backing layers in AppKit/SwiftUI:

```swift
// Swift/AppKit Setup:
popover.contentViewController?.view.window?.isOpaque = false
popover.contentViewController?.view.window?.backgroundColor = .clear

// SwiftUI Root Container:
VStack(spacing: 0) {
    header
    content
    footer
}
.frame(width: 380)
.background(.ultraThinMaterial)
.overlay(
    RoundedRectangle(cornerRadius: 16, style: .continuous)
        .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
)
.clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
```

### 3. Circular Liquid Progress Rings

Dynamic quota and usage gauges feature layered glow tracks and glowing heads:

```swift
ZStack {
    // Background Track
    Circle()
        .stroke(Color.white.opacity(0.08), lineWidth: 6)
    
    // Progress Arc with Angular Gradient
    Circle()
        .trim(from: 0.0, to: min(progress, 1.0))
        .stroke(
            AngularGradient(
                gradient: Gradient(colors: [accentColor.opacity(0.7), accentColor]),
                center: .center,
                startAngle: .degrees(-90),
                endAngle: .degrees(270)
            ),
            style: StrokeStyle(lineWidth: 6, lineCap: .round)
        )
        .rotationEffect(.degrees(-90))
        .shadow(color: accentColor.opacity(0.4), radius: 4, x: 0, y: 0)
}
```

### 4. Interactive Glass Pill Buttons & Badges

```swift
Capsule(style: .continuous)
    .fill(.regularMaterial)
    .overlay(
        Capsule(style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [Color.white.opacity(0.35), Color.white.opacity(0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    )
    .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
```

---

## Detailed References

For comprehensive technical specifications, explore the accompanying reference files:

- [Design Tokens & Values](references/design-tokens.md): Exact colors, radii, opacities, and spring physics.
- [SwiftUI Implementation Guide](references/swiftui-materials.md): Full ViewModifiers and ready-to-paste components.
- [Accessibility & Performance Guide](references/accessibility-performance.md): Contrast benchmarks, reduce-transparency fallback, and Metal compositor optimizations.
- [Reusable Modifier Template](assets/LiquidGlassModifier.swift.template): Swift source template for plug-and-play integration.

---

## Design Anti-Patterns to Avoid

- **DO NOT** use flat solid grey/black boxes with no translucency or specular rim.
- **DO NOT** use single-color stark border strokes (`stroke(Color.gray, lineWidth: 1)`).
- **DO NOT** use generic AI purple-on-black or saturated rainbow gradients.
- **DO NOT** stack more than two levels of real-time material blur inside the same window hierarchy.
- **DO NOT** ignore `@Environment(\.accessibilityReduceTransparency)`.
