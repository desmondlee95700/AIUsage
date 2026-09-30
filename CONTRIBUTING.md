# Contributing to AIUsage

Thank you for your interest in contributing to **AIUsage**!

To maintain strict stability, clean architecture, and the zero-token-overhead philosophy, all contributors must adhere to the following workflow:

---

## 🔒 Branch Protection & Pull Requests

1. **Direct Pushes to `main` Are Prohibited**:
   - The `main` branch is protected. Direct pushes are restricted solely to the repository owner ([@desmondlee95700](https://github.com/desmondlee95700)).
2. **Pull Request Required**:
   - All improvements, fixes, and features must be submitted via a **Pull Request (PR)** from a fork or topic branch.
   - Please provide a concise description of your changes and any relevant screenshots for UI modifications.

---

## 📐 Development Guidelines

- **Zero Token Overhead**: Never introduce external cloud LLM network calls, third-party proxies, or token-consuming telemetry. All communications must remain strictly on local loopback Connect-RPC (`127.0.0.1`) or local CLI subprocesses.
- **macOS 27 Liquid Glass UI**: All SwiftUI components, cards, popovers, and status gauges must adhere to the macOS 27 Liquid Glass design system specifications in `.agents/skills/liquid-glass-macos27/`.
- **Clean Compilation**: Ensure the project compiles cleanly with zero warnings or errors prior to opening a PR:
  ```bash
  swift build
  ./scripts/build_app.sh
  ```
