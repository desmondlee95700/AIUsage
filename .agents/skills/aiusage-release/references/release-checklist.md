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
2. **Swift Build Verification**:
   - Run `swift build` to ensure zero compilation warnings or errors.
3. **Branch Protection**:
   - Ensure the current working branch is `main`.
   - Never push directly to main without repository owner privileges (`desmondlee95700`).
4. **GitHub CLI Authentication**:
   - Run `gh auth status` to ensure active token authentication with `repo` scope.
5. **No Existing Tag Collisions**:
   - Verify `git rev-parse vX.Y.Z` does not already exist locally or remotely.

---

## 3. Standard Release Steps

### Automated Mode (Recommended)
Run the bundled release tool:
```bash
# Patch update (e.g. 2.1.0 -> 2.1.1):
./scripts/release.sh --patch

# Minor update (e.g. 2.1.0 -> 2.2.0):
./scripts/release.sh --minor

# Explicit version with release notes:
./scripts/release.sh 2.1.1 -m "Fixed quota alerts and reorganized context menu."
```

### Manual Mode
If executing manually without the script:

1. **Update Version Strings**:
   - Edit `Sources/Models/AppVersion.swift`:
     - Update fallback string in `current` to `"X.Y.Z"`.
     - Update fallback string in `build` to `"N"`.
   - Edit `scripts/build_app.sh`:
     - `APP_VERSION="X.Y.Z"`
     - `APP_BUILD="N"`

2. **Compile Release Binary & DMGs**:
   ```bash
   ./scripts/build_dmg.sh
   ```
   Verify that `AIUsage.dmg` and `AIUsage-vX.Y.Z.dmg` are generated in the project root.

3. **Stage, Commit & Tag**:
   ```bash
   git add Sources/Models/AppVersion.swift scripts/build_app.sh
   git commit -m "chore(release): vX.Y.Z (build N)"
   git tag -a "vX.Y.Z" -m "Release vX.Y.Z"
   ```

4. **Push Branch & Tags**:
   ```bash
   git push origin main
   git push origin vX.Y.Z
   ```

5. **Publish GitHub Release**:
   ```bash
   gh release create "vX.Y.Z" AIUsage.dmg "AIUsage-vX.Y.Z.dmg" \
       --title "AIUsage vX.Y.Z" \
       --generate-notes
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
- **Release failed mid-upload**: Re-upload assets or edit existing release:
  ```bash
  gh release upload vX.Y.Z AIUsage.dmg AIUsage-vX.Y.Z.dmg --clobber
  ```
