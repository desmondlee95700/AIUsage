# AGENTS.md — AIUsage Development & Architecture Guide

Welcome to the **AIUsage** codebase. This document outlines architectural standards, development workflows, and design guidelines for AI agents working in this repository.

`GEMINI.md` in the project root is symlinked to this file to maintain a single source of truth across Antigravity, Gemini CLI, and other agentic environments.

---

## 1. Project Overview & Philosophy

**AIUsage** is a native macOS menu bar application designed for instant, real-time tracking of AI model quotas, subscription tiers, and credit balances.

- **Zero Token Overhead**: Reads quota data without consuming tokens: local loopback Connect-RPC (`127.0.0.1`) for Antigravity, the bundled Codex CLI subprocess for ChatGPT, and the provider's own read-only usage endpoints for Claude (see §6.3 for the full list of allowed network calls). **Never introduce LLM inference calls or telemetry.**
- **Native macOS Experience**: Implemented entirely in Swift and SwiftUI, targeting macOS 13+ (the `Package.swift` and Info.plist deployment target) with full forward-compatibility for macOS 27 design standards.
- **Minimal Footprint**: Operates with near-zero idle CPU and memory utilization.

---

## 2. Codebase Architecture

```
AIUsage/
├── Package.swift               # SPM manifest (Swift 5.9+, macOS v13+)
├── README.md                   # User documentation
├── AGENTS.md                   # Canonical agent operational guide
├── GEMINI.md -> AGENTS.md      # Symlink for Gemini CLI / Antigravity rule loading
├── .github/                    # CI/CD (see §6.4)
│   ├── workflows/ci.yml        # PR & main checks: build, test, conventions, SwiftLint
│   ├── workflows/release.yml   # Tag-triggered DMG build & GitHub Release publisher
│   ├── CODEOWNERS              # Owner review on every PR
│   └── pull_request_template.md
├── .swiftlint.yml              # Advisory lint rules tuned to house style
├── scripts/                    # Build and packaging automation
│   ├── build_app.sh            # App bundle compiler & packaging script
│   ├── build_dmg.sh            # Distributable compressed DMG builder
│   ├── release.sh              # Version bump, tag & push (CI publishes)
│   ├── release_notes.sh        # Changelog from Conventional Commits since the previous tag
│   └── check_network_policy.sh # Enforces the §6.3 network allowlist
├── Assets/                     # Application icons and branding assets
│   ├── AppIcon.icns            # Multi-scale Apple ICNS icon
│   └── AppIcon.png             # Master 1024x1024 icon
├── .agents/skills/             # Workspace-level skills
│   ├── liquid-glass-macos27/   # macOS 27 Liquid Glass UI design skill
│   └── aiusage-release/        # Automated release & DMG publishing skill
├── Sources/
│   ├── main.swift              # AppKit lifecycle entry point & NSApplicationDelegate
│   ├── MenuBar/                # Status item management & menu bar glyph rendering
│   ├── Models/                 # Quota models, bucket structures, user tiers, low-quota alert thresholds
│   ├── Services/               # Provider clients & discovery (Antigravity loopback RPC, Codex CLI, Claude usage), updates, notifications
│   └── Views/                  # SwiftUI components:
│       ├── MainUsageView.swift             # Root popover view & header chrome
│       ├── QuotaCardView.swift             # Antigravity quota group cards & bucket progress rows
│       ├── ChatGPTQuotaCardView.swift      # ChatGPT plan, rate-limit windows & reset credits
│       ├── ClaudeQuotaCardView.swift       # Claude plan & 5-hour / weekly limits
│       ├── ProviderFocusSubmenuView.swift  # Multi-select provider filter (popover & context menu)
│       ├── CircularProgressView.swift      # Dynamic circular quota progress gauges
│       ├── PlanCardView.swift              # User tier badge & subscription management
│       ├── CreditsCardView.swift           # Prompt & flow credit indicators
│       ├── LiquidGlass.swift               # macOS 27 Liquid Glass design system helpers
│       └── AppIconHelper.swift             # Dynamic app icon loader & cache
└── Tests/
    └── AIUsageTests/           # XCTest unit tests for pure logic (`swift test`)
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
- **Run Unit Tests** (`Tests/AIUsageTests`, XCTest; covers parsing, quota alerts, window classification, version comparison):
  ```bash
  swift test
  ```
- **Build & Package macOS App Bundle**:
  ```bash
  ./scripts/build_app.sh
  ```
- **Build Distributable DMG**:
  ```bash
  ./scripts/build_dmg.sh
  ```
- **Cut a Release (owner only, via aiusage-release)**: bumps, tags and pushes; GitHub Actions builds and publishes:
  ```bash
  ./scripts/release.sh --patch
  # Or preview with dry-run:
  ./scripts/release.sh --dry-run --patch
  ```
- **Check Network Policy** (also runs in CI):
  ```bash
  ./scripts/check_network_policy.sh
  ```
- **Launch Application**:
  ```bash
  open AIUsage.app
  ```
- **Validate Skills (via skill-creator)**:
  ```bash
  python3 ~/.gemini/skills/skill-creator/scripts/quick_validate.py .agents/skills/liquid-glass-macos27
  python3 ~/.gemini/skills/skill-creator/scripts/quick_validate.py .agents/skills/aiusage-release
  ```

---

## 6. Repository Contribution & Branch Protection Rules

To maintain codebase stability, security, and strict quality control:

1. **Main Branch Protection**:
   - Direct pushes to the `main` branch are strictly prohibited for external contributors.
   - Direct push, release tagging, and branch management privileges are strictly reserved for the repository owner (`desmondlee95700` / `dessy`).
2. **Pull Request (PR) Workflow**:
   - All community and external contributions must be submitted via a dedicated feature branch or fork through a **GitHub Pull Request**.
   - PRs must pass the required CI checks (§6.4) and follow the macOS 27 Liquid Glass design specifications.
   - PR titles must follow [Conventional Commits](https://www.conventionalcommits.org) (`feat:`, `fix(scope):`, `docs:` …); they become changelog entries.
   - PRs must not bump version numbers. Releases are cut separately by the owner.
3. **Zero Token Overhead Policy**:
   - Any PR introducing LLM inference/completion calls, telemetry or analytics, or third-party quota proxies will be rejected.
   - The complete list of allowed data sources is:
     - **Antigravity**: local loopback Connect-RPC (`127.0.0.1`).
     - **ChatGPT**: the bundled Codex CLI `app-server` subprocess.
     - **Claude**: read-only usage endpoints on `claude.ai` (using the Claude desktop session cookie) and `api.anthropic.com/api/oauth/usage` (using the Claude Code OAuth token).
     - **Updates**: the GitHub Releases API for this repository.
     - **Browser links** (opened in the user's browser, no data requests): `claude.ai`, `chatgpt.com`.
   - Credentials are read from the local Keychain or cookie store at request time. They are never persisted, logged, or sent anywhere other than the provider's own HTTPS endpoint.
   - Adding a new network destination requires explicit approval from the repository owner. `scripts/check_network_policy.sh` enforces the allowlist in CI.
4. **CI/CD Pipeline**:
   - **`CI` workflow** (every PR and push to `main`):
     - *Build & Test* (required): `swift build` with warnings as errors, `swift test`, and app bundle packaging.
     - *Conventions* (required): network policy check and Conventional Commits PR title check.
     - *SwiftLint* (advisory): annotates style findings inline; never blocks merging.
   - **`Release` workflow**: runs only when a `vX.Y.Z` tag is pushed. It verifies the tag is on `main` and matches the version in source, runs the tests, builds both DMGs, generates release notes, and publishes the GitHub Release. Tags with a suffix (`v2.2.0-beta.1`) are published as pre-releases.
   - Merging a PR never triggers a release.

