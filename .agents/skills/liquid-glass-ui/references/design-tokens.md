# macOS 27 Liquid Glass UI Design Tokens

This document specifies the exact design tokens, values, materials, and physics curves for implementing the macOS 27 Liquid Glass aesthetic in Swift and SwiftUI.

---

## 1. Elevation Hierarchy & Materials

macOS 27 Liquid Glass uses a 4-tier elevation hierarchy to establish depth through refractive materials rather than flat drop shadows.

| Level | Role | SwiftUI Material | Base Tint (Dark) | Base Tint (Light) | Corner Radius |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **L0: Canvas** | Desktop background / Root Window | `.ultraThinMaterial` | `Color(white: 0.08, opacity: 0.85)` | `Color(white: 0.96, opacity: 0.82)` | `0` (or `16` for popovers) |
| **L1: Primary Card** | Main content containers, cards, panels | `.thinMaterial` | `Color(white: 0.14, opacity: 0.55)` | `Color(white: 1.0, opacity: 0.65)` | `14` |
| **L2: Nested / Chip** | Inner rows, badges, pill buttons, metrics | `.regularMaterial` | `Color(white: 0.20, opacity: 0.40)` | `Color(white: 1.0, opacity: 0.45)` | `10` or `.capsule` |
| **L3: Floating / Active**| Modals, active hover states, tooltips | `.thickMaterial` | `Color(white: 0.28, opacity: 0.70)` | `Color(white: 1.0, opacity: 0.85)` | `12` |

---

## 2. Specular Stroke Tokens (Glass Rim Refraction)

Liquid Glass edges reflect ambient light. Edges must never be a flat single-color stroke; they use dual-stop linear gradients oriented from top-left (light source) to bottom-right.

### Dark Mode Specular Gradients
```swift
// Primary Card Rim
LinearGradient(
    stops: [
        .init(color: Color.white.opacity(0.24), location: 0.0),  // Light catch
        .init(color: Color.white.opacity(0.10), location: 0.4),  // Mid-sheen
        .init(color: Color.white.opacity(0.03), location: 1.0)   // Dark rim
    ],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)

// Active / Focused Rim
LinearGradient(
    stops: [
        .init(color: Color.white.opacity(0.45), location: 0.0),
        .init(color: Color.accentColor.opacity(0.35), location: 0.5),
        .init(color: Color.white.opacity(0.08), location: 1.0)
    ],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)
```

### Light Mode Specular Gradients
```swift
LinearGradient(
    stops: [
        .init(color: Color.white.opacity(0.75), location: 0.0),
        .init(color: Color.white.opacity(0.40), location: 0.5),
        .init(color: Color.black.opacity(0.06), location: 1.0)
    ],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)
```

---

## 3. Ambient Shadow & Refraction Tokens

Liquid Glass uses diffuse ambient occlusion combined with a soft, tinted drop shadow.

```swift
// Card Shadow (Dark Mode)
.shadow(color: Color.black.opacity(0.30), radius: 16, x: 0, y: 8)
.shadow(color: Color.black.opacity(0.12), radius: 4, x: 0, y: 2)

// Floating / Modal Shadow
.shadow(color: Color.black.opacity(0.45), radius: 28, x: 0, y: 14)
.shadow(color: Color.accentColor.opacity(0.08), radius: 20, x: 0, y: 0) // Ambient glow
```

---

## 4. Fluid Motion Physics (macOS 27 Springs)

Liquid glass surfaces respond with viscous, elastic fluid mechanics. Avoid linear or easeInOut transitions for UI elements.

| Interaction | SwiftUI Spring Configuration | Use Case |
| :--- | :--- | :--- |
| **Interactive Tap / Click** | `.spring(response: 0.28, dampingFraction: 0.65, blendDuration: 0.15)` | Button presses, toggle activation |
| **Hover State Sheen** | `.spring(response: 0.35, dampingFraction: 0.75, blendDuration: 0.20)` | Cursor enter/leave, card lift |
| **Modal / Sheet Reveal** | `.spring(response: 0.42, dampingFraction: 0.78, blendDuration: 0.25)` | Popover open, dialog presentation |
| **Value / Metric Pulse** | `.spring(response: 0.50, dampingFraction: 0.70, blendDuration: 0.30)` | Quota progress updates, gauge changes |

---

## 5. Color Tokens & Tint Bleed

In macOS 27, accent colors subtly bleed through translucent surfaces:

- **AI Core / Sparkle Blue**: `Color(red: 0.25, green: 0.48, blue: 0.98)`
- **Quota Healthy (Green)**: `Color(red: 0.20, green: 0.82, blue: 0.48)`
- **Quota Moderate (Amber)**: `Color(red: 0.98, green: 0.68, blue: 0.18)`
- **Quota Critical (Red)**: `Color(red: 0.96, green: 0.28, blue: 0.32)`
- **Liquid Glass Background Dark**: `Color(red: 0.08, green: 0.09, blue: 0.12)`
- **Liquid Glass Background Light**: `Color(red: 0.95, green: 0.96, blue: 0.98)`
