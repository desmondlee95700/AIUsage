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

- **Menu Bar At-A-Glance Status**:
  - Live weekly percentage (e.g. `✦ 71%`) directly in your macOS menu bar.
  - Color-coded status indicator (Green for healthy, Amber for moderate, Red when low).
  - Hover tooltip displaying active account email and model quota status.
- **Detailed Model Quota Breakdown**:
  - **Gemini Models** (Gemini Flash, Gemini Pro): Weekly Limit Remaining & Rolling 5-Hour Limit Remaining with live circular progress rings.
  - **Claude & GPT Models** (Claude Sonnet, Claude Opus, GPT-OSS): Track third-party quota allowances and reset schedules.
  - Dynamic reset countdowns (e.g. *"Fully refreshes in 2 days, 6 hours"*).
- **Plan & Account Identity**:
  - Displays your active logged-in Google / Antigravity account email.
  - Current tier badge (e.g. **Google AI Pro**).
  - One-click **Upgrade** button to manage subscription.
- **macOS 27 Liquid Glass Design**:
  - Translucent refractive substrate (`.ultraThinMaterial` / `.thinMaterial`).
  - Specular rim refraction highlight with continuous bevelled corners.
  - Viscous fluid spring mechanics and auto-expanding popover (no scrollbars).
- **Zero Token Overhead & Complete Privacy**:
  - Communicates directly via high-speed local loopback Connect-RPC (`127.0.0.1`) with the local Antigravity server.
  - Consumes **0 prompt tokens**.
  - No external servers, no third-party telemetry, no credentials stored.
- **Auto-Discovery & Auto-Reconnection**:
  - Automatically discovers running instances of Antigravity 2.0 desktop app and Antigravity IDE.
  - Seamlessly re-probes and reconnects whenever Antigravity is restarted.

---

## 🛠️ Building from Source

```bash
# Clone the repository
git clone https://github.com/desmondlee95700/AIUsage.git
cd AIUsage

# Build and package the .app bundle
./build_app.sh

# Or create a distributable compressed DMG
./build_dmg.sh

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
