#!/bin/bash
set -e

# ==============================================================================
# AIUsage Release Automation Script
# ==============================================================================
# Cuts an AIUsage release:
# 0. Requires main/master and pulls the latest commits from origin
# 1. Runs the test suite
# 2. Bumps version & build number in AppVersion.swift & scripts/build_app.sh
# 3. Commits, creates an annotated vX.Y.Z tag, and pushes both to origin
# 4. The tag push triggers .github/workflows/release.yml, which builds the DMGs
#    on a clean macOS runner and publishes the GitHub Release
#
# Use --local-publish to build and publish from this machine instead (fallback).
# ==============================================================================

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

# Defaults
DRY_RUN=false
SKIP_PUSH=false
LOCAL_PUBLISH=false
AUTO_CONFIRM=false
BUMP_TYPE=""
TARGET_VERSION=""
TARGET_BUILD=""
RELEASE_TITLE=""
RELEASE_NOTES=""
NOTES_FILE=""

# Usage help
show_help() {
    cat << EOF
Usage: ./scripts/release.sh [OPTIONS] [VERSION]

Bumps the AIUsage version, tags it, and pushes. GitHub Actions then builds the
DMGs and publishes the GitHub Release (see .github/workflows/release.yml).
Must be run on 'main' or 'master'; the branch is fast-forwarded to origin first.

Arguments:
  VERSION                Target version string (e.g. 2.1.1, v2.1.1)

Options:
  --patch                Bump patch version (e.g. 2.1.0 -> 2.1.1)
  --minor                Bump minor version (e.g. 2.1.0 -> 2.2.0)
  --major                Bump major version (e.g. 2.1.0 -> 3.0.0)
  -b, --build NUM        Explicit build number (default: auto-incremented by 1)
  -t, --title TITLE      Release title (default: "AIUsage v<VERSION>")
  -m, --notes NOTES      Release highlights (Markdown), shown above the generated changelog
  -f, --notes-file FILE  Path to file containing release highlights
  -d, --dry-run          Preview changes and actions without modifying files or releasing
  -s, --skip-push        Commit and tag locally without pushing to GitHub
  -l, --local-publish    Build DMGs and publish the GitHub Release from this machine
                         instead of GitHub Actions (fallback if CI is unavailable)
  -y, --yes              Automatic yes to prompts; run non-interactively
  -h, --help             Display this help message

Examples:
  ./scripts/release.sh --patch
  ./scripts/release.sh 2.1.1 -m "Fixed quota alerts and updated icons."
  ./scripts/release.sh --dry-run --minor
EOF
}

# Parse options
while [[ $# -gt 0 ]]; do
    case "$1" in
        --patch)
            BUMP_TYPE="patch"
            shift
            ;;
        --minor)
            BUMP_TYPE="minor"
            shift
            ;;
        --major)
            BUMP_TYPE="major"
            shift
            ;;
        -b|--build)
            TARGET_BUILD="$2"
            shift 2
            ;;
        -t|--title)
            RELEASE_TITLE="$2"
            shift 2
            ;;
        -m|--notes)
            RELEASE_NOTES="$2"
            shift 2
            ;;
        -f|--notes-file)
            NOTES_FILE="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -s|--skip-push)
            SKIP_PUSH=true
            shift
            ;;
        -l|--local-publish)
            LOCAL_PUBLISH=true
            shift
            ;;
        -y|--yes)
            AUTO_CONFIRM=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            if [[ -z "$TARGET_VERSION" && ! "$1" =~ ^- ]]; then
                TARGET_VERSION="${1#v}" # strip leading v if present
                shift
            else
                echo "❌ Unknown argument: $1"
                show_help
                exit 1
            fi
            ;;
    esac
done

# Releases are cut only from main/master, synced with origin, so the version bump
# lands on top of the latest remote commit
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [[ "$CURRENT_BRANCH" != "main" && "$CURRENT_BRANCH" != "master" ]]; then
    echo "❌ Releases must be cut from 'main' or 'master', but the current branch is '${CURRENT_BRANCH}'."
    echo "   Run 'git checkout main' and try again."
    exit 1
fi

echo "🔄 Fetching origin/${CURRENT_BRANCH}..."
if ! git fetch --tags origin "$CURRENT_BRANCH"; then
    echo "❌ Failed to fetch origin/${CURRENT_BRANCH}. Check your network connection and try again."
    exit 1
fi

REMOTE_REF="origin/${CURRENT_BRANCH}"
LOCAL_SHA=$(git rev-parse HEAD)
REMOTE_SHA=$(git rev-parse "$REMOTE_REF")
BASE_SHA=$(git merge-base HEAD "$REMOTE_REF")
# Where the current version is read from; a dry-run that is behind reads the remote copy
VERSION_REF="HEAD"

if [[ "$LOCAL_SHA" == "$REMOTE_SHA" ]]; then
    echo "✅ '${CURRENT_BRANCH}' is up to date with ${REMOTE_REF}."
elif [[ "$LOCAL_SHA" == "$BASE_SHA" ]]; then
    BEHIND_COUNT=$(git rev-list --count "HEAD..${REMOTE_REF}")
    if [[ "$DRY_RUN" == true ]]; then
        echo "⬇️ '${CURRENT_BRANCH}' is ${BEHIND_COUNT} commit(s) behind ${REMOTE_REF}; a real run pulls them first."
        VERSION_REF="$REMOTE_REF"
    else
        echo "⬇️ '${CURRENT_BRANCH}' is ${BEHIND_COUNT} commit(s) behind ${REMOTE_REF}; pulling..."
        if ! git pull --ff-only origin "$CURRENT_BRANCH"; then
            echo "❌ Failed to fast-forward '${CURRENT_BRANCH}'. Commit or stash local changes and try again."
            exit 1
        fi
    fi
elif [[ "$REMOTE_SHA" == "$BASE_SHA" ]]; then
    AHEAD_COUNT=$(git rev-list --count "${REMOTE_REF}..HEAD")
    echo "⚠️ '${CURRENT_BRANCH}' has ${AHEAD_COUNT} unpushed commit(s); they will be pushed with the release."
else
    echo "❌ '${CURRENT_BRANCH}' has diverged from ${REMOTE_REF}. Reconcile it (e.g. 'git pull --rebase') and try again."
    exit 1
fi

# Read current version and build number from build_app.sh
BUILD_SCRIPT=$(git show "${VERSION_REF}:scripts/build_app.sh")
CURRENT_VERSION=$(grep '^APP_VERSION=' <<< "$BUILD_SCRIPT" | head -n 1 | cut -d'"' -f2)
CURRENT_BUILD=$(grep '^APP_BUILD=' <<< "$BUILD_SCRIPT" | head -n 1 | cut -d'"' -f2)

if [[ -z "$CURRENT_VERSION" || -z "$CURRENT_BUILD" ]]; then
    echo "❌ Failed to read current version or build number from scripts/build_app.sh"
    exit 1
fi

echo "🔍 Current AIUsage Version: v${CURRENT_VERSION} (build ${CURRENT_BUILD})"

# Parse semantic version components. A pre-release suffix (2.1.3-rc.1) is split off
# so the numeric parts stay valid for arithmetic.
BASE_VERSION="${CURRENT_VERSION%%-*}"
IS_PRERELEASE=false
[[ "$CURRENT_VERSION" == *-* ]] && IS_PRERELEASE=true
IFS='.' read -r MAJOR MINOR PATCH <<< "$BASE_VERSION"
MAJOR=${MAJOR:-0}
MINOR=${MINOR:-0}
PATCH=${PATCH:-0}

if [[ -z "$TARGET_VERSION" && -z "$BUMP_TYPE" ]]; then
    BUMP_TYPE="patch"
    DEFAULTED_BUMP=true
fi

# Determine new version. Per semver, bumping from a pre-release finalizes it when the
# pre-release already belongs to that bump level (2.1.3-rc.1 --patch -> 2.1.3).
if [[ -n "$TARGET_VERSION" ]]; then
    NEW_VERSION="$TARGET_VERSION"
elif [[ "$BUMP_TYPE" == "patch" ]]; then
    if [[ "$IS_PRERELEASE" == true ]]; then
        NEW_VERSION="$BASE_VERSION"
    else
        NEW_VERSION="${MAJOR}.${MINOR}.$((PATCH + 1))"
    fi
elif [[ "$BUMP_TYPE" == "minor" ]]; then
    if [[ "$IS_PRERELEASE" == true && "$PATCH" == "0" ]]; then
        NEW_VERSION="$BASE_VERSION"
    else
        NEW_VERSION="${MAJOR}.$((MINOR + 1)).0"
    fi
elif [[ "$BUMP_TYPE" == "major" ]]; then
    if [[ "$IS_PRERELEASE" == true && "$MINOR" == "0" && "$PATCH" == "0" ]]; then
        NEW_VERSION="$BASE_VERSION"
    else
        NEW_VERSION="$((MAJOR + 1)).0.0"
    fi
fi

if [[ "${DEFAULTED_BUMP:-false}" == true ]]; then
    echo "💡 No version or bump type specified; defaulting to patch bump (v${NEW_VERSION})"
fi

# Determine new build number
if [[ -n "$TARGET_BUILD" ]]; then
    NEW_BUILD="$TARGET_BUILD"
else
    NEW_BUILD=$((CURRENT_BUILD + 1))
fi

TAG_NAME="v${NEW_VERSION}"
if [[ -z "$RELEASE_TITLE" ]]; then
    RELEASE_TITLE="AIUsage ${TAG_NAME}"
fi

echo "🎯 Target AIUsage Version:  ${TAG_NAME} (build ${NEW_BUILD})"

# Check tag collision
if git rev-parse "$TAG_NAME" >/dev/null 2>&1; then
    echo "❌ Git tag '${TAG_NAME}' already exists locally. Aborting."
    exit 1
fi

if git ls-remote --tags origin | grep -q "refs/tags/${TAG_NAME}$"; then
    echo "❌ Git tag '${TAG_NAME}' already exists on remote origin. Aborting."
    exit 1
fi

# Check GitHub CLI authentication if publishing locally
if [[ "$SKIP_PUSH" == false && "$LOCAL_PUBLISH" == true ]]; then
    if ! command -v gh &> /dev/null; then
        echo "❌ GitHub CLI ('gh') is not installed. Please install via 'brew install gh' or use --skip-push."
        exit 1
    fi
    if ! gh auth status &> /dev/null; then
        echo "❌ GitHub CLI ('gh') is not authenticated. Please run 'gh auth login' or use --skip-push."
        exit 1
    fi
fi

# Dry Run Summary
if [[ "$DRY_RUN" == true ]]; then
    echo ""
    echo "============================================================"
    echo "🔎 DRY-RUN SIMULATION (No files modified, no releases made)"
    echo "============================================================"
    echo "1. Run swift test"
    echo "2. Files to update:"
    echo "   - Sources/Models/AppVersion.swift  -> Version ${NEW_VERSION}, Build ${NEW_BUILD}"
    echo "   - scripts/build_app.sh            -> APP_VERSION=\"${NEW_VERSION}\", APP_BUILD=\"${NEW_BUILD}\""
    echo "3. Git Commit & Tag:"
    echo "   - git commit -m \"chore(release): ${TAG_NAME} (build ${NEW_BUILD})\""
    echo "   - git tag -a \"${TAG_NAME}\""
    if [[ "$SKIP_PUSH" == false ]]; then
        echo "4. Push:"
        echo "   - git push origin ${CURRENT_BRANCH}"
        echo "   - git push origin ${TAG_NAME}"
        if [[ "$LOCAL_PUBLISH" == true ]]; then
            echo "5. Build DMGs locally and gh release create ${TAG_NAME}"
        else
            echo "5. GitHub Actions (release.yml) builds the DMGs and publishes the release"
        fi
    fi
    echo "============================================================"
    echo "✅ Dry-run completed successfully."
    exit 0
fi

# Confirmation prompt if interactive
if [[ "$AUTO_CONFIRM" == false ]]; then
    echo ""
    read -p "Proceed with releasing ${TAG_NAME} (build ${NEW_BUILD})? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Release aborted."
        exit 0
    fi
fi

# 1. Test before touching anything
echo "🧪 Running test suite..."
swift test

# 2. Update version files
echo "📝 Updating version strings to ${NEW_VERSION} (build ${NEW_BUILD})..."

python3 -c "
import re

# Update AppVersion.swift
with open('Sources/Models/AppVersion.swift', 'r') as f:
    content = f.read()

content = re.sub(
    r'(public static var current: String \{[\s\S]*?return\s+\")[^\"]+(\")',
    rf'\g<1>${NEW_VERSION}\g<2>',
    content
)
content = re.sub(
    r'(public static var build: String \{[\s\S]*?return\s+\")[^\"]+(\")',
    rf'\g<1>${NEW_BUILD}\g<2>',
    content
)
with open('Sources/Models/AppVersion.swift', 'w') as f:
    f.write(content)

# Update scripts/build_app.sh
with open('scripts/build_app.sh', 'r') as f:
    content = f.read()

content = re.sub(r'APP_VERSION=\"[^\"]+\"', 'APP_VERSION=\"${NEW_VERSION}\"', content)
content = re.sub(r'APP_BUILD=\"[^\"]+\"', 'APP_BUILD=\"${NEW_BUILD}\"', content)
with open('scripts/build_app.sh', 'w') as f:
    f.write(content)
"

# 3. Git commit & tag
echo "📦 Staging and committing release files..."
git add Sources/Models/AppVersion.swift scripts/build_app.sh
git commit -m "chore(release): ${TAG_NAME} (build ${NEW_BUILD})"

# The tag annotation carries optional highlights; release_notes.sh puts them above the changelog
TAG_MESSAGE="Release ${TAG_NAME}"
if [[ -n "$NOTES_FILE" && -f "$NOTES_FILE" ]]; then
    TAG_MESSAGE="$(cat "$NOTES_FILE")"
elif [[ -n "$RELEASE_NOTES" ]]; then
    TAG_MESSAGE="$RELEASE_NOTES"
fi
echo "🏷️ Creating git tag ${TAG_NAME}..."
git tag -a "${TAG_NAME}" -m "$TAG_MESSAGE"

if [[ "$SKIP_PUSH" == true ]]; then
    echo "ℹ️ --skip-push enabled: Git commit and tag '${TAG_NAME}' created locally. Remote push skipped."
    exit 0
fi

# 4. Push (the tag push triggers the Release workflow unless publishing locally)
echo "🚀 Pushing branch and tag to GitHub..."
git push origin "$CURRENT_BRANCH"
git push origin "$TAG_NAME"

if [[ "$LOCAL_PUBLISH" == false ]]; then
    echo ""
    echo "🎉 ${TAG_NAME} tagged and pushed. GitHub Actions is building and publishing the release:"
    echo "🔗 https://github.com/desmondlee95700/AIUsage/actions/workflows/release.yml"
    exit 0
fi

# 5. Local fallback: build and publish from this machine.
# The Release workflow also runs for this tag but skips once it sees the release exists.
echo "🔨 Compiling release bundle and building DMG..."
"$DIR/scripts/build_dmg.sh"

if [[ ! -f "$DIR/AIUsage.dmg" || ! -f "$DIR/AIUsage-${TAG_NAME}.dmg" ]]; then
    echo "❌ DMG artifacts missing after build! Check build_dmg.sh output."
    exit 1
fi

echo "🌐 Publishing GitHub Release ${TAG_NAME}..."
NOTES_PATH="$(mktemp)"
"$DIR/scripts/release_notes.sh" "$TAG_NAME" > "$NOTES_PATH"
gh release create "$TAG_NAME" "AIUsage.dmg" "AIUsage-${TAG_NAME}.dmg" --title "$RELEASE_TITLE" --notes-file "$NOTES_PATH" --verify-tag
rm -f "$NOTES_PATH"
echo ""
echo "🎉 Release ${TAG_NAME} successfully published!"
echo "🔗 URL: https://github.com/desmondlee95700/AIUsage/releases/tag/${TAG_NAME}"
