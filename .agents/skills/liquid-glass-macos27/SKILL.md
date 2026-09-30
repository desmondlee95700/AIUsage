---
name: liquid-glass-macos27
description: Design and implement Apple's next-generation Liquid Glass UI interfaces (WWDC 2025+, macOS Tahoe 26+, iOS 26+) using SwiftUI. Use this skill whenever building or styling macOS interfaces, menu bar popovers, Control Center style widgets, HUDs, or cards requiring translucent materials, specular refraction highlights, dynamic optical blur, chromatic dispersion, ambient tint bleed, glass buttons (.buttonStyle(.glass), .glassProminent), or visionOS/macOS glassmorphic aesthetics.
license: MIT
---

# macOS 27 Liquid Glass UI Design System

A comprehensive design and implementation guide for building modern Apple interfaces using **Apple's Liquid Glass** design language (introduced at WWDC 2025 for macOS 26 Tahoe / iOS 26+ and forward-compatible with macOS 27) in Swift and SwiftUI.

Liquid Glass represents the evolution of Apple's materials design: moving beyond flat blur overlays into dynamic, optical-grade refractive surfaces with specular edge highlights, ambient tint bleeding, and fluid spring physics — exactly as showcased in macOS Control Center, visionOS, and next-generation macOS desktop accessories.

---

## 1. Core Visual Tenets

Every Liquid Glass surface adheres to five foundational laws:

1. **Refractive Substrates, Not Flat Panels**:
   Never use flat solid hex background fills (avoid opaque `#1c1d22`). Instead, use native translucent materials (`.ultraThinMaterial`, `.thinMaterial`, `.regularMaterial`) layered with an optical color bleed and ambient depth.

2. **Directional Specular Rim Highlights**:
   Real glass catches light on its chamfered edges. All cards, popovers, and containers feature a 1pt stroke border using an angled `LinearGradient` (from bright translucent white at `.topLeading` down to near-invisible opacity at `.bottomTrailing`).

3. **Glass Styles & Tint Bleeding**:
   - `.regular`: Standard UI (cards, popovers, toolbars, navigation bars) with medium optical blur.
   - `.clear`: High transparency for media-rich backgrounds.
   - `.tint(color)`: Color-tinted glass (e.g. celestial blue for Gemini, emerald/mint for ChatGPT) where color bleeds dynamically through the refractive layer.
   - `.prominent`: High-contrast prominent glass (e.g. active toggles in macOS Control Center with high-contrast glyphs).

4. **Fluid Spring Mechanics**:
   Physical elements must behave like polished lenses immersed in viscous fluid. Avoid linear or standard easeInOut transitions. Use interactive spring curves with controlled damping (e.g., `response: 0.32, dampingFraction: 0.72`).

5. **Accessibility First (Zero Distortion Fallback)**:
   Always respect `@Environment(\.accessibilityReduceTransparency)`. When reduced transparency is active, gracefully switch to opaque system surfaces with distinct border definition.

---

## 2. Component Blueprints

### A. Liquid Glass Card Container (Control Center Module Style)
For main content sections, quota buckets, metrics, and panels:

```swift
RoundedRectangle(cornerRadius: 16, style: .continuous)
    .fill(.thinMaterial)
    .overlay(
        // Ambient Tint Bleed
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        tintColor.opacity(colorScheme == .dark ? 0.08 : 0.04),
                        Color.white.opacity(colorScheme == .dark ? 0.03 : 0.25)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    )
    .overlay(
        // Specular Refraction Rim
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(
                LiquidGlassTokens.specularBorder(isDark: colorScheme == .dark),
                lineWidth: 1
            )
    )
    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.25 : 0.08), radius: 10, x: 0, y: 5)
```

### B. Glass Buttons (.glass & .glassProminent)
As seen in macOS Control Center toggles:

```swift
// Standard Glass Button (.buttonStyle(.glass))
Capsule(style: .continuous)
    .fill(.regularMaterial)
    .overlay(
        Capsule(style: .continuous)
            .strokeBorder(
                LiquidGlassTokens.specularBorder(isDark: true, intensity: 0.8),
                lineWidth: 1
            )
    )

// Prominent Glass Button (.buttonStyle(.glassProminent))
Capsule(style: .continuous)
    .fill(
        LinearGradient(
            colors: [accentColor, accentColor.opacity(0.85)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    )
    .overlay(
        Capsule(style: .continuous)
            .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
    )
    .shadow(color: accentColor.opacity(0.35), radius: 8, x: 0, y: 3)
```

### C. Menu Bar Popover Root Window
Menu bar popovers must configure clear backing layers in AppKit/SwiftUI:

```swift
popover.contentViewController?.view.window?.isOpaque = false
popover.contentViewController?.view.window?.backgroundColor = .clear

// SwiftUI Root Container:
VStack(spacing: 0) {
    header
    content
}
.frame(width: 380)
.background(.ultraThinMaterial)
.overlay(
    RoundedRectangle(cornerRadius: 18, style: .continuous)
        .strokeBorder(LiquidGlassTokens.specularBorder(isDark: true, intensity: 0.9), lineWidth: 1)
)
.clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
```

### D. Circular Liquid Progress Gauges
Dynamic usage gauges feature glowing tracks, neon heads, and high-contrast typography:

```swift
ZStack {
    Circle()
        .stroke(Color.white.opacity(0.08), lineWidth: 4.5)
    
    Circle()
        .trim(from: 0.0, to: min(fraction, 1.0))
        .stroke(
            AngularGradient(
                gradient: Gradient(colors: [tintColor.opacity(0.70), tintColor]),
                center: .center,
                startAngle: .degrees(-90),
                endAngle: .degrees(270)
            ),
            style: StrokeStyle(lineWidth: 4.5, lineCap: .round)
        )
        .rotationEffect(.degrees(-90))
        .shadow(color: tintColor.opacity(0.50), radius: 5, x: 0, y: 0)
}
```

---

## 3. Best Practices & Pitfalls

- **Do Not Stack Excessive Blurs**: Limit blur materials to two nested levels to maintain near-zero idle CPU and GPU utilization.
- **Always Provide Specular Rim Gradients**: Flat 1px white strokes look harsh. Multi-stop gradients fading downward create authentic refraction.
- **Maintain High Contrast**: Always ensure text over glass passes WCAG AA contrast (minimum 4.5:1).
- **Graceful Reduced-Transparency**: When `accessibilityReduceTransparency` is enabled, replace materials with opaque semantic colors (`NSColor.controlBackgroundColor`).
