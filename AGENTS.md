# AGENTS.md — AIUsage Development & Architecture Guide

Welcome to the **AIUsage** codebase. This document outlines architectural standards, development workflows, and design guidelines for AI agents working in this repository.

`GEMINI.md` in the project root is symlinked to this file to maintain a single source of truth across Antigravity, Gemini CLI, and other agentic environments.

---

## 1. Project Overview & Philosophy

**AIUsage** is a native macOS menu bar application designed for instant, real-time tracking of AI model quotas, subscription tiers, and credit balances.

- **Zero Token Overhead**: Communicates solely via high-speed local loopback Connect-RPC (`127.0.0.1`) with the local Antigravity server and IDE. **Never introduce external LLM network calls or token-consuming telemetry.**
- **Native macOS Experience**: Implemented entirely in Swift and SwiftUI, targeting macOS 14+ with full forward-compatibility for macOS 27 design standards.
- **Minimal Footprint**: Operates with near-zero idle CPU and memory utilization.

---

## 2. Codebase Architecture

```
AIUsage/
├── Package.swift               # SPM manifest (Swift 5.9+, macOS v14+)
├── README.md                   # User documentation
├── AGENTS.md                   # Canonical agent operational guide
├── GEMINI.md -> AGENTS.md      # Symlink for Gemini CLI / Antigravity rule loading
├── scripts/                    # Build and packaging automation
│   ├── build_app.sh            # App bundle compiler & packaging script
│   └── build_dmg.sh            # Distributable compressed DMG builder
├── Assets/                     # Application icons and branding assets
│   ├── AppIcon.icns            # Multi-scale Apple ICNS icon
│   └── AppIcon.png             # Master 1024x1024 icon
├── .agents/skills/             # Workspace-level skills
│   └── liquid-glass-macos27/   # macOS 27 Liquid Glass UI design skill
└── Sources/
    ├── main.swift              # AppKit lifecycle entry point & NSApplicationDelegate
    ├── MenuBar/                # Status item management & menu bar glyph rendering
    ├── Models/                 # Quota models, bucket structures, user tier definitions
    ├── Services/               # Connect-RPC loopback client & Antigravity auto-discovery
    └── Views/                  # SwiftUI components:
        ├── MainUsageView.swift         # Root popover view & header chrome
        ├── QuotaCardView.swift         # Quota group cards & bucket progress rows
        ├── CircularProgressView.swift  # Dynamic circular quota progress gauges
        ├── PlanCardView.swift          # User tier badge & subscription management
        ├── CreditsCardView.swift       # Prompt & flow credit indicators
        ├── LiquidGlass.swift           # macOS 27 Liquid Glass design system helpers
        └── AppIconHelper.swift         # Dynamic app icon loader & cache
```

---

## 3. UI/UX Standard: macOS 27 Liquid Glass UI

When creating or modifying any SwiftUI views, popovers, cards, buttons, or indicators, **agents must adhere to the macOS 27 Liquid Glass UI design system**.

The dedicated UI skill **`liquid-glass-macos27`** (created with `skill-creator`) is available in this repository under `.agents/skills/liquid-glass-macos27/` and globally at `~/.gemini/skills/liquid-glass-macos27/`.

### Core Liquid Glass Rules:
1. **Translucent Refractive Substrates**:
   - Avoid flat opaque backgrounds (e.g. solid `#1c1d22`).
   - Use `.ultraThinMaterial`, `.thinMaterial`, or `.regularMaterial` layered with subtle color tint bleeding (`Color.white.opacity(0.04)` in dark mode).
2. **Specular Rim Refraction**:
   - Enclose cards, popovers, and containers in a 1pt stroke border using a `LinearGradient` from `.topLeading` (bright specular highlight: `white.opacity(0.24)`) down to `.bottomTrailing` (shadow rim: `white.opacity(0.02)`).
3. **Fluid Spring Mechanics**:
   - Use viscous spring curves for interactions and gauge updates:
     ```swift
     .animation(.spring(response: 0.32, dampingFraction: 0.72, blendDuration: 0.2), value: progress)
     ```
4. **Accessibility First**:
   - Always observe `@Environment(\.accessibilityReduceTransparency)`. When enabled, fallback cleanly to opaque semantic system backgrounds (`Color(NSColor.controlBackgroundColor)`).

Refer to the skill documentation at `.agents/skills/liquid-glass-macos27/SKILL.md` and reference tokens in `references/design-tokens.md` for full implementation details.

---

## 4. Engineering & Concurrency Guidelines

- **Swift Concurrency**: Mark UI-binding classes and methods with `@MainActor`. Use structured concurrency (`async`/`await`, `Task`) for background polling.
- **Memory Safety**: Prevent retain cycles in polling timers, Combine publishers, or escaping closures using `[weak self]`.
- **State Management**: Access telemetry and state strictly via `QuotaService.shared`. Views should remain declarative and react to `@ObservedObject` updates.
- **Clean AppKit / SwiftUI Bridge**: The menu bar popover is hosted via `NSPopover` wrapping `NSHostingView`. Ensure the hosting window maintains `isOpaque = false` and `backgroundColor = .clear` to preserve liquid glass translucency.

---

## 5. Build, Test & Run Commands

Execute commands directly from the repository root:

- **Build Swift Package**:
  ```bash
  swift build
  ```
- **Build & Package macOS App Bundle**:
  ```bash
  ./scripts/build_app.sh
  ```
- **Build Distributable DMG**:
  ```bash
  ./scripts/build_dmg.sh
  ```
- **Launch Application**:
  ```bash
  open AIUsage.app
  ```
- **Validate Liquid Glass Skill (via skill-creator)**:
  ```bash
  python3 ~/.gemini/skills/skill-creator/scripts/quick_validate.py ~/.gemini/skills/liquid-glass-macos27
  ```
