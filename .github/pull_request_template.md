## Summary

<!-- What does this change and why? Link any related issue. -->

## Screenshots

<!-- Required for UI changes: before / after of the menu bar or popover. Delete if not applicable. -->

## Checklist

- [ ] PR title follows [Conventional Commits](https://www.conventionalcommits.org) (e.g. `fix(codex): …`, `feat: …`). It becomes the changelog entry.
- [ ] `swift build` has no warnings and `swift test` passes
- [ ] UI changes follow the Liquid Glass guidelines (`.agents/skills/liquid-glass-macos27/`)
- [ ] No new network destinations, LLM calls, or telemetry (AGENTS.md §6.3)
- [ ] Version numbers are **not** bumped. Releases are cut by the owner with `scripts/release.sh`.
