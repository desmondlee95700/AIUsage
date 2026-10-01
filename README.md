<p align="center">
  <img src="Assets/AppIcon.png" alt="AIUsage Logo" width="128" height="128" />
</p>

<h1 align="center">AIUsage</h1>

<p align="center">
  <b>A sleek, native macOS menu bar app for instant, real-time access to your AI Model Quotas and account usage.</b>
  <br />
  Built in Swift &amp; SwiftUI &bull; macOS 27 Liquid Glass UI &bull; Zero Prompt Token Overhead
</p>

<p align="center">
  <a href="https://github.com/desmondlee95700/AIUsage/releases/latest"><img src="https://img.shields.io/github/v/release/desmondlee95700/AIUsage?label=Download%20DMG&logo=apple&color=007AFF" alt="Download DMG"></a>
  <img src="https://img.shields.io/badge/Platform-macOS%2014%2B-000000?logo=apple" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-5.9%2B-F05138?logo=swift&logoColor=white" alt="Swift 5.9+">
  <img src="https://img.shields.io/badge/Design-macOS%2027%20Liquid%20Glass-8A2BE2" alt="Liquid Glass UI">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-green.svg" alt="License: MIT"></a>
</p>

---

## ⬇️ Download & Installation

### Option 1: Direct Download (Recommended)
Download the latest pre-compiled macOS disk image:

👉 **[Download AIUsage.dmg](https://github.com/desmondlee95700/AIUsage/releases/latest/download/AIUsage.dmg)**

1. Open `AIUsage.dmg`.
2. Drag **AIUsage.app** into your `/Applications` folder.
3. Launch **AIUsage** — it will immediately appear in your macOS menu bar!

> [!TIP]
> **macOS Gatekeeper Notice ("AIUsage is damaged and can't be opened")**:  
> Because AIUsage is an independent open-source app distributed outside the Mac App Store without an Apple Developer ID certificate, macOS attaches a quarantine flag to files downloaded via browsers (Chrome, Safari) and blocks them.
> 
> If you see this warning, open **Terminal** and run this one-line command:
> ```bash
> xattr -cr /Applications/AIUsage.app
> ```
> *(Or navigate to **System Settings > Privacy & Security**, scroll down to **Security**, and click **Open Anyway**.)*

---

## ✨ Features

- **Tri-Provider AI Support (Antigravity, ChatGPT, Claude)**:
  - <img src="Assets/AntigravityIcon.png" width="16" height="16" valign="middle" /> **Antigravity (Google)**: Weekly & 5-hour quota tracking, prompt & flow credits, and plan status via local Connect-RPC.
  - <img src="Assets/ChatGPTIcon.png" width="16" height="16" valign="middle" /> **ChatGPT (OpenAI)**: Live quota tracking, 5-hour burst and weekly limits, reset credit redemption, and token usage via the bundled Codex runtime inside `ChatGPT.app`.
  - <img src="Assets/ClaudeIcon.png" width="16" height="16" valign="middle" /> **Claude (Anthropic)**: Native desktop session quota tracking, 5-hour rolling burst and weekly limits, Claude 3.7 Sonnet allocation, and dynamic free tier capacity indicators.
- **Flexible Multi-Choice Provider Focus**:
  - Customize your active providers with complete flexibility (Antigravity only, ChatGPT only, Claude only, Antigravity & Claude, ChatGPT & Claude, or All Providers).
  - **Persistent In-Menu Multi-Select**: Context submenu stays open while toggling multiple checkboxes without premature dismissal.
  - **In-Popover Provider Filter**: Dedicated `slider.horizontal.3` button in the header bar for instant configuration.
- **At-A-Glance Status & Awareness**:
  - **Multi-Provider Menu Bar Display**: Displays metrics for your selected models side-by-side (e.g. `78% · 90% · Free`) with template glyphs.
  - **Liquid Glass Provider Switcher**: Segmented tab bar dynamically displays only your selected active providers with zero height shift.
  - **Multi-Model Tooltip**: Hovering over the menu bar item shows a detailed breakdown for all selected providers.
- **Detailed Quota Breakdown**:
  - **Antigravity Models**: Weekly Limit Remaining & Rolling 5-Hour Limit Remaining with live circular progress rings.
  - **ChatGPT Models**: 5-hour burst window, weekly window, exact reset countdowns, and reset credit allowances.
  - **Claude Models**: 5-hour rolling session, weekly quota, dedicated Sonnet quota, and dynamic server capacity limits.
- **Plan & Account Identity**:
  - Displays your active logged-in Google, OpenAI, and Anthropic account emails and subscription badges.
- **macOS 27 Liquid Glass Design**:
  - Translucent refractive substrate (`.ultraThinMaterial` / `.thinMaterial`).
  - Specular rim refraction highlight with continuous bevelled corners.
  - Viscous fluid spring mechanics and auto-expanding popover (no scrollbars).
- **Zero Token Overhead & Complete Privacy**:
  - Local loopback Connect-RPC for Antigravity; local JSON-RPC stdio for ChatGPT; local desktop session cookies for Claude.
  - Consumes **0 prompt tokens**.
  - No external servers, no third-party telemetry, no credentials stored.
- **Auto-Discovery & Auto-Reconnection**:
  - Automatically discovers running instances of Antigravity, ChatGPT.app, and Claude.app.
  - Seamlessly re-probes and reconnects whenever any application is restarted.

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
