# AIUsage ✦

A sleek, native macOS menu bar app for instant, real-time access to your **AI Model Quotas** and account usage.

Built entirely in Swift and SwiftUI, styled with the next-generation **macOS 27 Liquid Glass UI** design system, and engineered for zero LLM prompt token consumption.

---

## ⬇️ Download & Installation

### Option 1: Direct Download (Recommended)
Download the latest pre-compiled macOS disk image:

👉 **[Download AIUsage.dmg](https://github.com/desmondlee95700/AIUsage/releases/latest/download/AIUsage.dmg)**

1. Open `AIUsage.dmg`.
2. Drag **AIUsage.app** into your `/Applications` folder.
3. Launch **AIUsage** — it will immediately appear in your macOS menu bar!

---

## ✨ Features

- **Dual AI Provider Support (Gemini & ChatGPT)**:
  - **Gemini (Antigravity)**: Weekly & 5-hour quota tracking, prompt & flow credits, and plan status via local Connect-RPC.
  - **ChatGPT (Codex)**: Live quota tracking, 30-day rolling window, reset credits, and token usage via the bundled Codex runtime inside `ChatGPT.app`.
- **At-A-Glance Dual Status & Awareness**:
  - **Dual Menu Bar Mode**: Displays both models side-by-side (e.g. `✦ 71% · ✷ 29%`) so you always know both limits at a glance.
  - **Liquid Glass Provider Switcher**: Prominent top tab bar with live remaining percentage pills (`[ ✦ Gemini 71% ]  [ ✷ ChatGPT 29% ]`) and connection indicators.
  - **Multi-Model Tooltip**: Hovering over the menu bar item shows a detailed breakdown for both Gemini and ChatGPT.
- **Detailed Quota Breakdown**:
  - **Gemini Models**: Weekly Limit Remaining & Rolling 5-Hour Limit Remaining with live circular progress rings.
  - **ChatGPT Codex**: Remaining model quota %, exact countdown to reset, reset credit allowances, and daily token activity.
  - Dynamic reset countdowns (e.g. *"Fully refreshes in 2 days, 6 hours"*, *"Resets in 11d 15h"*).
- **Plan & Account Identity**:
  - Displays your active logged-in Google / Antigravity and ChatGPT account emails and subscription tiers.
- **macOS 27 Liquid Glass Design**:
  - Translucent refractive substrate (`.ultraThinMaterial` / `.thinMaterial`).
  - Specular rim refraction highlight with continuous bevelled corners.
  - Viscous fluid spring mechanics and auto-expanding popover (no scrollbars).
- **Zero Token Overhead & Complete Privacy**:
  - Local loopback Connect-RPC for Gemini; local JSON-RPC stdio for ChatGPT Codex.
  - Consumes **0 prompt tokens**.
  - No external servers, no third-party telemetry, no credentials stored.
- **Auto-Discovery & Auto-Reconnection**:
  - Automatically discovers running instances of Antigravity and ChatGPT Codex.
  - Seamlessly re-probes and reconnects whenever either application is restarted.

---

## 🛠️ Building from Source

```bash
# Clone the repository
git clone https://github.com/desmondlee95700/AIUsage.git
cd AIUsage

# Build and package the .app bundle
./scripts/build_app.sh

# Or create a distributable compressed DMG
./scripts/build_dmg.sh

# Launch the app
open AIUsage.app
```

---

## ⚙️ Controls & Shortcuts

- **Left-Click Menu Bar Item**: Toggles the interactive quota breakdown popover.
- **Right-Click Menu Bar Item**: Opens quick context menu (Refresh Now, Quit AIUsage).
- **Header Action Buttons**:
  - **Refresh (🔄)**: Forces an immediate re-probe and quota fetch.
  - **Quit (⏻)**: Terminates the menu bar application.

---

## 📄 License
MIT License.
