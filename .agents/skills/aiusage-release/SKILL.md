---
name: aiusage-release
description: Cut AIUsage releases - bump the version, tag it, and let GitHub Actions build the DMGs and publish the GitHub Release. Use whenever the user asks to release a new version of AIUsage, publish an update, bump the app version, roll out a DMG update, create a GitHub release, tag a new release, re-publish a failed release, or automate the deployment of AIUsage updates.
license: MIT
---

# AIUsage Release Management

This skill guides cutting new releases of the **AIUsage** macOS menu bar application.

---

## 1. Overview & Release Pipeline

Releases are **tag-driven**. Merging a PR never releases anything; a release happens only when the owner pushes a `vX.Y.Z` tag.

```
./scripts/release.sh --patch        (owner's machine)
  ├─ swift test
  ├─ bump AppVersion.swift + scripts/build_app.sh
  ├─ commit "chore(release): vX.Y.Z (build N)" + annotated tag vX.Y.Z
  └─ push main + tag
        │
        ▼
.github/workflows/release.yml       (GitHub Actions, macOS runner)
  ├─ verify: semver tag, commit is on main, tag == version in source
  ├─ swift test
  ├─ scripts/build_dmg.sh → AIUsage.dmg + AIUsage-vX.Y.Z.dmg
  ├─ scripts/release_notes.sh → changelog from Conventional Commits
  └─ gh release create (pre-release if the tag has a suffix, e.g. v2.2.0-beta.1)
```

The pipeline ensures:
1. **In-App Updater Synchronization**: The native updater (`UpdateService.swift`) checks the GitHub Releases API and requires both `AIUsage.dmg` and versioned `AIUsage-vX.Y.Z.dmg` to be attached.
2. **Deterministic Version Alignment**: `Sources/Models/AppVersion.swift` and `scripts/build_app.sh` must stay in lockstep. The Release workflow refuses to publish if the tag doesn't match them.
3. **Clean, Reproducible Builds**: DMGs are built on a fresh GitHub-hosted macOS runner, not a developer machine.
4. **Owner-Only Releases**: Only accounts with push access can push tags, so contributors can't trigger releases.

---

## 2. Quick Automated Release

The release script lives at `scripts/release.sh` (a copy is bundled in this skill under `scripts/release.sh`).

### Common Commands:

- **Patch Release (e.g. `2.1.0` -> `2.1.1`)**:
  ```bash
  ./scripts/release.sh --patch
  ```

- **Minor Release (e.g. `2.1.0` -> `2.2.0`)**:
  ```bash
  ./scripts/release.sh --minor
  ```

- **Explicit Version with Highlights** (shown above the generated changelog):
  ```bash
  ./scripts/release.sh 2.1.1 -m "Fixed quota spending alerts and added Launch App submenu."
  ```

- **Pre-Release** (hidden from the in-app updater, which only reads `/releases/latest`):
  ```bash
  ./scripts/release.sh 2.2.0-beta.1
  ```

- **Dry-Run Mode (Preview changes without touching git or releasing)**:
  ```bash
  ./scripts/release.sh --dry-run --patch
  ```

- **Non-Interactive Automated Execution**:
  ```bash
  ./scripts/release.sh --yes --patch
  ```

- **Local Fallback** (build and publish from this machine if GitHub Actions is unavailable; the workflow then skips because the release already exists):
  ```bash
  ./scripts/release.sh --patch --local-publish
  ```

After pushing, follow the build at https://github.com/desmondlee95700/AIUsage/actions/workflows/release.yml or with:
```bash
gh run watch $(gh run list --workflow release.yml --limit 1 --json databaseId -q '.[0].databaseId')
```

---

## 3. Step-by-Step Manual Release Workflow

If executing the release manually or troubleshooting a pipeline failure, follow this exact sequence:

### Step 1: Pre-Flight Verification
1. Ensure the working directory is clean, on `main`, and up to date:
   ```bash
   git status
   git checkout main
   git pull origin main
   ```
2. Confirm CI is green for the commit being released:
   ```bash
   gh run list --workflow ci.yml --branch main --limit 1
   ```
3. Run the tests locally:
   ```bash
   swift test
   ```

### Step 2: Bump Version & Build Number
Synchronize the version string and increment the internal build number in two files:

1. **`Sources/Models/AppVersion.swift`**: update the fallback strings in `current` (e.g. `"2.1.1"`) and `build` (e.g. `"13"`).
2. **`scripts/build_app.sh`**: update `APP_VERSION` and `APP_BUILD`.

### Step 3: Git Commit & Tag
Stage only the release configuration files, commit, and create an annotated tag. The tag message becomes the release highlights; use `Release vX.Y.Z` for none.
```bash
git add Sources/Models/AppVersion.swift scripts/build_app.sh
git commit -m "chore(release): vX.Y.Z (build N)"
git tag -a "vX.Y.Z" -m "Release vX.Y.Z"
```

### Step 4: Push Branch & Tag
```bash
git push origin main
git push origin vX.Y.Z
```
The tag push starts the Release workflow, which builds, tests, and publishes.

---

## 4. Post-Release Verification

After the Release workflow succeeds:
1. Verify the release and both assets exist:
   ```bash
   gh release view vX.Y.Z
   ```
2. Test the in-app updater:
   - Open the current menu bar instance.
   - Trigger `Check for Updates...` (`⌘U`) from the menu bar status context menu.
   - Confirm the alert shows the new version and that "Download & Install" fetches the DMG.

---

## 5. Troubleshooting & Rollback

- **"Tag does not match build_app.sh / AppVersion.swift"**: The tag was created without bumping the version. Delete the tag (below) and use `./scripts/release.sh` so bump and tag happen together.
- **"Tag points at a commit that is not on main"**: Only commits on `main` can be released. Merge first, then tag.
- **Workflow failed after the tag was pushed** (flaky runner, transient error): re-run it for the existing tag:
  ```bash
  gh workflow run release.yml -f tag=vX.Y.Z
  ```
- **Tag Collision**: If `vX.Y.Z` already exists, check `git tag -l` and choose the next version.
- **Rollback Tag (Owner Only)**:
  ```bash
  git tag -d vX.Y.Z
  git push origin :refs/tags/vX.Y.Z
  ```
- **Re-upload Release Assets**:
  ```bash
  gh release upload vX.Y.Z AIUsage.dmg AIUsage-vX.Y.Z.dmg --clobber
  ```

For more architectural details and pre-flight references, consult `references/release-checklist.md`.
