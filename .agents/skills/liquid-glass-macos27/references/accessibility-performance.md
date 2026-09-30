# Accessibility & Performance: macOS 27 Liquid Glass

Translucent, refractive interfaces require careful consideration of accessibility and GPU performance.

---

## 1. Accessibility: Reduced Transparency

macOS users who enable **Reduce Transparency** (System Settings > Accessibility > Display) expect opaque surfaces with high legibility.

### Implementation Checklist
1. Always inject `@Environment(\.accessibilityReduceTransparency) private var reduceTransparency`.
2. When `reduceTransparency` is `true`:
   - Replace `.ultraThinMaterial` / `.thinMaterial` with solid semantic system colors: `Color(NSColor.windowBackgroundColor)` or `Color(NSColor.controlBackgroundColor)`.
   - Maintain border strokes with standard opacity `0.15` to preserve card boundaries.
   - Disable ambient blur layers.

```swift
@ViewBuilder
private var backgroundLayer: some View {
    if reduceTransparency {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(NSColor.controlBackgroundColor))
    } else {
        RoundedRectangle(cornerRadius: 12)
            .fill(.thinMaterial)
    }
}
```

---

## 2. Text Contrast on Glass Substrates

Because glass backgrounds dynamically blur content beneath them, text placed on glass can suffer from low contrast if the background changes.

- **Primary Text**: Use solid white (`.white`) in dark mode or near-black in light mode. Avoid applying transparency below `0.9` to primary body or headers.
- **Secondary / Caption Text**: Minimum opacity `0.65` in dark mode, `0.60` in light mode.
- **Iconography**: Use hierarchical rendering (`.symbolRenderingMode(.hierarchical)`) so SF Symbols automatically maintain contrast.

---

## 3. GPU Performance & Energy Optimization

Rendering multiple layers of real-time Gaussian and refraction blurs can consume GPU cycles on MacBooks running on battery.

- **Limit Material Layering**: Never nest more than 2 material layers (e.g., a card on top of a popover). For elements inside a card (chips, rows, progress bars), use semi-transparent fills (`Color.white.opacity(0.06)`) instead of additional `.thinMaterial` views.
- **Offscreen Rendering**: Avoid applying `.blur(radius:)` on top of `.material`. Materials already use hardware-accelerated compositor pipelines.
- **Drawing Group**: For static or complex vector shapes inside a glass container, consider `.drawingGroup()` to flatten into Metal textures if frame drops occur during window dragging.
