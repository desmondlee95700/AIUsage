<p align="center">
  <img src="Assets/AppIcon.png" alt="AIUsage" width="128" height="128" />
</p>

<h1 align="center">AIUsage</h1>

<p align="center">
  A native macOS menu bar app that shows your remaining AI quotas for Antigravity, ChatGPT and Claude at a glance, without spending a single token.
</p>

<p align="center">
  <a href="https://github.com/desmondlee95700/AIUsage/releases/latest"><img src="https://img.shields.io/github/v/release/desmondlee95700/AIUsage?label=Release&color=007AFF" alt="Latest release"></a>
  <a href="https://github.com/desmondlee95700/homebrew-tap"><img src="https://img.shields.io/badge/Homebrew-tap-FBB040?logo=homebrew&logoColor=white" alt="Homebrew tap"></a>
  <img src="https://img.shields.io/badge/macOS-13%2B-000000?logo=apple" alt="macOS 13+">
  <img src="https://img.shields.io/badge/Swift-5.9%2B-F05138?logo=swift&logoColor=white" alt="Swift 5.9+">
  <a href="https://github.com/desmondlee95700/AIUsage/actions/workflows/ci.yml"><img src="https://github.com/desmondlee95700/AIUsage/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-green.svg" alt="License: MIT"></a>
</p>

---

## Contents

- [Installation](#installation)
- [Supported providers](#supported-providers)
- [Features](#features)
- [Usage](#usage)
- [Privacy](#privacy)
- [Building from source](#building-from-source)
- [Contributing](#contributing)
- [License](#license)

## Installation

**Requirements:** macOS 13 Ventura or later, and at least one supported provider signed in on this Mac (see [Supported providers](#supported-providers)).

### Homebrew

```bash
brew install --cask desmondlee95700/tap/aiusage
```

Using the full name adds and trusts the [tap](https://github.com/desmondlee95700/homebrew-tap) automatically. The cask tracks the latest stable release.

### Direct download

1. Download **[AIUsage.dmg](https://github.com/desmondlee95700/AIUsage/releases/latest/download/AIUsage.dmg)** from the latest release.
2. Open the DMG and drag **AIUsage** into **Applications**.
3. Launch AIUsage. It appears in the menu bar; there is no Dock icon.

### First launch

> [!IMPORTANT]
> AIUsage is not yet signed with an Apple Developer ID, so macOS Gatekeeper blocks it the first time it opens, whichever way you installed it. Open **System Settings → Privacy & Security**, scroll to **Security**, and click **Open Anyway** next to AIUsage.

If that option doesn't appear:

- **The DMG won't open:** click **Done** (not *Move to Trash*) and clear the quarantine flag. Use the file name you downloaded, for example `AIUsage-v2.6.6.dmg`:

  ```bash
  xattr -d com.apple.quarantine ~/Downloads/AIUsage.dmg
  ```

- **macOS says AIUsage "is damaged and can't be opened":**

  ```bash
  xattr -cr /Applications/AIUsage.app
  ```

### Updating and uninstalling

AIUsage checks GitHub Releases for new versions and offers to download them. Choose **Check for Updates…** (<kbd>⌘</kbd><kbd>U</kbd>) to check now. Homebrew users can also run `brew upgrade --cask aiusage`.

To uninstall, quit AIUsage and move it to the Trash, or run `brew uninstall --cask aiusage`.

> [!TIP]
> `brew uninstall --zap --cask aiusage` also removes AIUsage's saved settings.

## Supported providers

| Provider | What is shown | Data source | Needs |
| :--- | :--- | :--- | :--- |
| <img src="Assets/AntigravityIcon.png" width="16" height="16" /> **Google Antigravity** | 5-hour and weekly limits, prompt and flow credits, account tier and email | Antigravity's local language server (`127.0.0.1`) | Antigravity running |
| <img src="Assets/ChatGPTIcon.png" width="16" height="16" /> **ChatGPT** | 5-hour and weekly limits, reset credits, plan and email | Codex `app-server` over stdio | ChatGPT desktop app (bundles Codex) or the Codex CLI, signed in |
| <img src="Assets/ClaudeIcon.png" width="16" height="16" /> **Claude** | 5-hour and weekly limits, Sonnet and Opus weekly limits where the plan has them, extra usage credits, plan and email | Claude's read-only usage endpoints | Claude desktop app or Claude Code, signed in |

Providers are discovered automatically and reconnect when their apps restart.

> [!NOTE]
> AIUsage reads the same usage figures the providers show in their own apps. It never sends a prompt, so checking your quota doesn't use any of it.

## Features

- **Menu bar summary.** Each provider's lowest remaining limit is shown side by side (for example `78% · 90% · 4%`), so a fresh 5-hour window can't hide an exhausted weekly one. Two thin bars beside each figure show the 5-hour (top) and weekly (bottom) limits. ⚠︎ marks anything at 10% or below. Switch to **Icon Only** for a quieter menu bar.
- **Detailed popover.** One tab per provider with every limit, its reset time and account details. A status pill shows how fresh the numbers are and turns amber after several missed refreshes.
- **Low-quota alerts.** Notifications when a 5-hour or weekly limit falls past 30% and 10%, and when it resets. Alerts fire only during active use, never for quota that was already low at launch.
- **Token activity.** 7, 14 or 30-day charts of Claude Code and Codex token use, read from local session logs.
- **Blackout.** Turns every display black and puts it to sleep while your agents keep working, then ends on the first key press, click or mouse move. Your Mac stays awake underneath, and the key press that wakes it never reaches the app behind.
- **Native design.** SwiftUI with translucent materials that follows macOS's Reduce Transparency setting. The popover keeps a fixed height, so switching providers never resizes it.
- **Launch at login**, a configurable refresh interval, and **Hide Email Addresses** for screenshots and screen sharing.

## Usage

### Menu bar

| Action | Result |
| :--- | :--- |
| Click | Opens or closes the popover. |
| Right-click or Control-click | Opens the menu with settings and actions. |
| Hover | Shows a tooltip with every limit and its reset time. |
| Option-click a provider in **Provider Focus** | Shows only that provider. |

### Popover header

| Control | Action |
| :--- | :--- |
| Provider tabs | Switch between providers. Each tab shows its menu bar figure, labelled "weekly" when it comes from the weekly limit. |
| Filter (`slider.horizontal.3`) | Choose which providers are shown. |
| Refresh (`arrow.clockwise`) | Rediscovers providers and fetches quotas now. |
| Update (`arrow.down`) | Appears when a new release is available. |
| More (`ellipsis`) | Refresh interval, alerts, menu bar style, Hide Email Addresses, Launch at Login, Check for Updates and Quit. |

A small menu bar glyph beside a limit marks the figure the menu bar is showing.

### Menu commands

| Shortcut | Command |
| :---: | :--- |
| <kbd>⌘</kbd><kbd>R</kbd> | Refresh All Now |
| <kbd>⌘</kbd><kbd>B</kbd> | Blackout |
| <kbd>⌘</kbd><kbd>U</kbd> | Check for Updates… |
| <kbd>⌘</kbd><kbd>Q</kbd> | Quit AIUsage |

The same menu sets **Provider Focus**, the **Refresh Interval** (30 seconds, 1, 2 or 5 minutes, or manual), the **Menu Bar** style, **Low-Quota Alerts** (at 30% and 10%, at 10% only, or off), **Launch at Login** and **Hide Email Addresses**.

## Privacy

AIUsage has no telemetry, analytics or LLM calls. It only talks to:

| Destination | Purpose |
| :--- | :--- |
| `127.0.0.1` | Antigravity's local language server |
| Codex `app-server` (local subprocess) | ChatGPT limits, fetched by Codex with your existing sign-in |
| `claude.ai`, `api.anthropic.com` | Claude's read-only usage endpoints, using your existing Claude desktop or Claude Code sign-in |
| `api.github.com`, `github.com` | Checking for and downloading AIUsage updates |

Token activity charts are built from local files only (`~/.claude/projects` and `~/.codex/sessions`). Credentials are read from your Keychain or cookie store when needed and are never saved, logged or sent anywhere except the provider they belong to. CI enforces this list with [`scripts/check_network_policy.sh`](scripts/check_network_policy.sh).

## Building from source

Requires Xcode command line tools with Swift 5.9 or later.

```bash
git clone https://github.com/desmondlee95700/AIUsage.git
cd AIUsage

swift build              # compile
swift test               # run the unit tests
./scripts/build_app.sh   # package AIUsage.app
./scripts/build_dmg.sh   # build a distributable DMG

open AIUsage.app
```

## Contributing

Issues and pull requests are welcome.

- Open pull requests from a feature branch or fork. CI must pass: build, tests and the network policy check.
- Use [Conventional Commits](https://www.conventionalcommits.org) for PR titles (`feat:`, `fix(scope):`, `docs:` …); they become the release notes.
- Don't bump version numbers. Releases are cut by the maintainer.

> [!WARNING]
> Pull requests that add network destinations, telemetry, analytics or LLM calls won't be accepted. See [Privacy](#privacy).

[`AGENTS.md`](AGENTS.md) covers the architecture and design guidelines in more detail.

## License

Released under the [MIT License](LICENSE). Copyright © 2026 [Desmond Lee](https://github.com/desmondlee95700).
