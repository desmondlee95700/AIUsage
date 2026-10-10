# Contributing to AIUsage

Thank you for your interest in contributing to **AIUsage**!

To maintain strict stability, clean architecture, and the zero-token-overhead philosophy, all contributors must adhere to the following workflow:

---

## 🔒 Branch Protection & Pull Requests

1. **Direct Pushes to `main` Are Prohibited**:
   - The `main` branch is protected. Direct pushes are restricted solely to the repository owner ([@desmondlee95700](https://github.com/desmondlee95700)).
2. **Pull Request Required**:
   - All improvements, fixes, and features must be submitted via a **Pull Request (PR)** from a fork or topic branch.
   - Please provide a concise description of your changes and any relevant screenshots for UI modifications (the PR template has a checklist).
3. **PR Titles Follow Conventional Commits**:
   - Use `type(optional-scope): description`, e.g. `fix(codex): stop app-server reads from blocking` or `feat: add Cursor provider`.
   - Allowed types: `feat`, `fix`, `perf`, `refactor`, `docs`, `test`, `build`, `ci`, `chore`, `style`, `revert`. The title becomes the changelog entry.
4. **Automated Checks**:
   - Every PR runs **Build & Test** (warnings are errors) and **Conventions** (PR title and network policy). Both must pass before merging.
   - **SwiftLint** findings are shown inline as suggestions and don't block merging.
5. **Don't Bump Versions**:
   - Releases are cut separately by the owner; merging a PR never publishes a release.

---

## 📐 Development Guidelines

- **Zero Token Overhead**: Never introduce LLM inference calls, third-party proxies, or telemetry. Quota data may only come from the sources listed in `AGENTS.md` §6.3: local loopback Connect-RPC (`127.0.0.1`), the bundled Codex CLI subprocess, and Claude's own read-only usage endpoints. New network destinations need owner approval.
- **macOS 27 Liquid Glass UI**: All SwiftUI components, cards, popovers, and status gauges must adhere to the macOS 27 Liquid Glass design system specifications in `.agents/skills/liquid-glass-macos27/`.
- **Clean Compilation & Tests**: Ensure the project compiles cleanly with zero warnings or errors, and all tests pass, prior to opening a PR:
  ```bash
  swift build
  swift test
  ./scripts/build_app.sh
  ```
