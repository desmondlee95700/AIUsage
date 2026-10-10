# AIUsage Release Checklist & Architecture Reference

This reference outlines the required pre-flight checks, release artifacts, and troubleshooting steps for releasing new versions of **AIUsage**.

---

## 1. Release Architecture & File Dependencies

When a release is triggered, the following critical files must stay synchronized:

| File Path | Purpose | Key Variables / Fields |
| :--- | :--- | :--- |
| `Sources/Models/AppVersion.swift` | In-app version telemetry & update checking | `current` (e.g. `"2.1.0"`), `build` (e.g. `"12"`) |
| `scripts/build_app.sh` | App bundle compilation script | `APP_VERSION="2.1.0"`, `APP_BUILD="12"` |
| `AIUsage.app/Contents/Info.plist` | macOS bundle metadata | `CFBundleShortVersionString`, `CFBundleVersion` |
| `AIUsage.dmg` | Canonical unversioned DMG | Staged drag-to-Applications installer |
| `AIUsage-vX.Y.Z.dmg` | Version-tagged DMG asset | Uploaded alongside `AIUsage.dmg` to GitHub Release |

---

## 2. Pre-Flight Checklist

Before cutting a release, verify:

1. **Working Tree Cleanliness**:
   - Run `git status` to ensure all intended changes are committed.
   - Stash or discard temporary debug files.
2. **Build & Test Verification**:
   - Confirm CI is green on `main` (`gh run list --workflow ci.yml --branch main --limit 1`).
   - `release.sh` runs `swift test` before bumping; the Release workflow runs it again.
3. **Branch Protection**:
   - Ensure the current working branch is `main`.
   - Never push directly to main without repository owner privileges (`desmondlee95700`).
4. **GitHub CLI Authentication** (only needed for `--local-publish` and re-running workflows):
   - Run `gh auth status` to ensure active token authentication with `repo` scope.
5. **No Existing Tag Collisions**:
   - Verify `git rev-parse vX.Y.Z` does not already exist locally or remotely.

---

## 3. Standard Release Steps

### Automated Mode (Recommended)
Run the release tool. It tests, bumps, commits, tags, and pushes; the tag push triggers
`.github/workflows/release.yml`, which builds the DMGs and publishes the GitHub Release.
```bash
# Patch update (e.g. 2.1.0 -> 2.1.1):
./scripts/release.sh --patch

# Minor update (e.g. 2.1.0 -> 2.2.0):
./scripts/release.sh --minor

# Explicit version with release highlights:
./scripts/release.sh 2.1.1 -m "Fixed quota alerts and reorganized context menu."
```

### Manual Mode
If executing manually without the script:

1. **Update Version Strings**:
   - Edit `Sources/Models/AppVersion.swift`: update the fallback strings in `current` (`"X.Y.Z"`) and `build` (`"N"`).
   - Edit `scripts/build_app.sh`: `APP_VERSION="X.Y.Z"` and `APP_BUILD="N"`.

2. **Stage, Commit & Tag**:
   ```bash
   git add Sources/Models/AppVersion.swift scripts/build_app.sh
   git commit -m "chore(release): vX.Y.Z (build N)"
   git tag -a "vX.Y.Z" -m "Release vX.Y.Z"
   ```

3. **Push Branch & Tag** (starts the Release workflow):
   ```bash
   git push origin main
   git push origin vX.Y.Z
   ```

4. **Fallback - publish locally** only if GitHub Actions is unavailable:
   ```bash
   ./scripts/build_dmg.sh
   ./scripts/release_notes.sh vX.Y.Z > notes.md
   gh release create "vX.Y.Z" AIUsage.dmg "AIUsage-vX.Y.Z.dmg" --title "AIUsage vX.Y.Z" --notes-file notes.md --verify-tag
   ```

---

## 4. Post-Release Verification

1. **Verify GitHub Release**:
   - Check `gh release view vX.Y.Z` to confirm assets `AIUsage.dmg` and `AIUsage-vX.Y.Z.dmg` are attached.
2. **In-App Updater Check**:
   - In running AIUsage app, click `Check for Updates...` (`⌘U`) in the context menu.
   - Ensure the updater discovers the latest release tag from GitHub Releases API:
     `https://api.github.com/repos/desmondlee95700/AIUsage/releases/latest`
   - Verify that clicking "Download & Update" correctly downloads the DMG to `~/Downloads` and mounts the volume in Finder.

---

## 5. Rollback & Troubleshooting

- **Tag already exists**: If a tag was created in error before publishing:
  ```bash
  git tag -d vX.Y.Z
  git push origin :refs/tags/vX.Y.Z
  ```
- **Release workflow failed**: Re-run it for the existing tag:
  ```bash
  gh workflow run release.yml -f tag=vX.Y.Z
  ```
- **Release failed mid-upload**: Re-upload assets or edit existing release:
  ```bash
  gh release upload vX.Y.Z AIUsage.dmg AIUsage-vX.Y.Z.dmg --clobber
  ```
