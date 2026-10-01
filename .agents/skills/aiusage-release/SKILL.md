---
name: aiusage-release
description: Automate version bumping, building DMGs, git tagging, and publishing GitHub Releases for AIUsage. Use whenever the user asks to release a new version of AIUsage, publish an update, bump the app version, roll out a DMG update, create a GitHub release, tag a new release, or automate the deployment of AIUsage updates.
license: MIT
---

# AIUsage Release Management

This skill guides the preparation, building, packaging, tagging, and publishing of new releases for the **AIUsage** macOS menu bar application.

---

## 1. Overview & Release Pipeline

Releasing an update for AIUsage requires updating the semantic version across multiple source locations, building the compiled universal `.app` bundle, generating compressed and signed DMG installers, pushing git commits and tags, and publishing a GitHub Release with attached binaries.

The pipeline ensures:
1. **In-App Updater Synchronization**: The native updater (`UpdateService.swift`) checks GitHub Releases API and requires both `AIUsage.dmg` and versioned `AIUsage-vX.Y.Z.dmg` to be available for 1-click downloads.
2. **Deterministic Version Alignment**: `Sources/Models/AppVersion.swift` and `scripts/build_app.sh` must remain in exact lockstep.
3. **Zero Token Overhead**: All compilation, packaging, and release steps run strictly on the local machine and communicate only with GitHub via the `gh` CLI.

---

## 2. Quick Automated Release

The project includes an automated release script located at `scripts/release.sh` (and bundled in this skill under `scripts/release.sh`).

### Common Commands:

- **Patch Release (e.g. `2.1.0` -> `2.1.1`)**:
  ```bash
  ./scripts/release.sh --patch
  ```

- **Minor Release (e.g. `2.1.0` -> `2.2.0`)**:
  ```bash
  ./scripts/release.sh --minor
  ```

- **Explicit Target Version with Changelog Notes**:
  ```bash
  ./scripts/release.sh 2.1.1 -m "Fixed quota spending alerts and added Launch App submenu."
  ```

- **Dry-Run Mode (Preview changes without touching git or releasing)**:
  ```bash
  ./scripts/release.sh --dry-run --patch
  ```

- **Non-Interactive Automated Execution**:
  ```bash
  ./scripts/release.sh --yes --patch
  ```

---

## 3. Step-by-Step Manual Release Workflow

If executing the release manually or troubleshooting a pipeline failure, follow this exact sequence:

### Step 1: Pre-Flight Verification
1. Ensure the working directory is clean and on the `main` branch:
   ```bash
   git status
   git checkout main
   git pull origin main
   ```
2. Verify GitHub CLI authentication:
   ```bash
   gh auth status
   ```

### Step 2: Bump Version & Build Number
Synchronize the version string and increment the internal build number in two files:

1. **`Sources/Models/AppVersion.swift`**:
   Update the fallback string in `current` (e.g. `"2.1.1"`) and `build` (e.g. `"13"`):
   ```swift
   public static var current: String {
       // ...
       return "2.1.1"
   }
   public static var build: String {
       // ...
       return "13"
   }
   ```

2. **`scripts/build_app.sh`**:
   Update `APP_VERSION` and `APP_BUILD`:
   ```bash
   APP_VERSION="2.1.1"
   APP_BUILD="13"
   ```

### Step 3: Build Application & Generate Signed DMGs
Run the DMG packaging automation script from the repository root:
```bash
./scripts/build_dmg.sh
```

This script will:
- Run `swift build -c release`
- Assemble `AIUsage.app` with application icons and `Info.plist`
- Create a drag-and-drop DMG staging volume with an `/Applications` symlink
- Generate a compressed UDZO image: `AIUsage.dmg`
- Apply ad-hoc codesigning to the DMG
- Create a version-tagged copy: `AIUsage-vX.Y.Z.dmg`

Verify that both DMG files exist:
```bash
ls -lh AIUsage.dmg AIUsage-v*.dmg
```

### Step 4: Git Commit & Tag
Stage only the release configuration files, commit, and create an annotated git tag:
```bash
git add Sources/Models/AppVersion.swift scripts/build_app.sh
git commit -m "chore(release): vX.Y.Z (build N)"
git tag -a "vX.Y.Z" -m "Release vX.Y.Z"
```

### Step 5: Push Branch & Tag to GitHub
Push the commit and tag to the remote repository:
```bash
git push origin main
git push origin vX.Y.Z
```

### Step 6: Publish GitHub Release
Create the GitHub Release and attach both DMGs:
```bash
gh release create "vX.Y.Z" AIUsage.dmg "AIUsage-vX.Y.Z.dmg" \
    --title "AIUsage vX.Y.Z" \
    --generate-notes
```
*(Optionally replace `--generate-notes` with `--notes "Release notes markdown"` or `--notes-file <path>`)*.

---

## 4. Post-Release Verification

After the release is published:
1. Verify the release exists on GitHub:
   ```bash
   gh release view vX.Y.Z
   ```
2. Test the in-app updater:
   - Launch the newly built `AIUsage.app` or open the current menu bar instance.
   - Trigger `Check for Updates...` (`⌘U`) from the menu bar status context menu.
   - Confirm the popover or alert displays the latest version information without error.

---

## 5. Troubleshooting & Rollback

- **Tag Collision**: If `vX.Y.Z` already exists, check `git tag -l` and choose the next incremented patch/minor version.
- **Rollback Local Tag**:
  ```bash
  git tag -d vX.Y.Z
  ```
- **Rollback Remote Tag (Owner Only)**:
  ```bash
  git push origin :refs/tags/vX.Y.Z
  ```
- **Re-upload Release Assets**:
  If the GitHub release succeeded but an asset was missing or interrupted:
  ```bash
  gh release upload vX.Y.Z AIUsage.dmg AIUsage-vX.Y.Z.dmg --clobber
  ```

For more architectural details and pre-flight references, consult `references/release-checklist.md`.
