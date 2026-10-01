#!/bin/bash
set -e

# ==============================================================================
# AIUsage Release Automation Script
# ==============================================================================
# Automates the complete end-to-end release lifecycle for AIUsage:
# 1. Version & build number bumping across AppVersion.swift & scripts/build_app.sh
# 2. Release compilation and Universal DMG generation via scripts/build_dmg.sh
# 3. Git commit, tag creation, and push to origin
# 4. GitHub Release creation with attached DMG artifacts and changelog notes
# ==============================================================================

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

# Defaults
DRY_RUN=false
SKIP_PUSH=false
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

Automates AIUsage version bumps, DMG compilation, git tagging, and GitHub Release.

Arguments:
  VERSION                Target version string (e.g. 2.1.1, v2.1.1)

Options:
  --patch                Bump patch version (e.g. 2.1.0 -> 2.1.1)
  --minor                Bump minor version (e.g. 2.1.0 -> 2.2.0)
  --major                Bump major version (e.g. 2.1.0 -> 3.0.0)
  -b, --build NUM        Explicit build number (default: auto-incremented by 1)
  -t, --title TITLE      Release title (default: "AIUsage v<VERSION>")
  -m, --notes NOTES      Release notes markdown body
  -f, --notes-file FILE  Path to file containing release notes
  -d, --dry-run          Preview changes and actions without modifying files or releasing
  -s, --skip-push        Build DMG and commit/tag locally without pushing to GitHub
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

# Read current version and build number from build_app.sh
CURRENT_VERSION=$(grep '^APP_VERSION=' scripts/build_app.sh | head -n 1 | cut -d'"' -f2)
CURRENT_BUILD=$(grep '^APP_BUILD=' scripts/build_app.sh | head -n 1 | cut -d'"' -f2)

if [[ -z "$CURRENT_VERSION" || -z "$CURRENT_BUILD" ]]; then
    echo "❌ Failed to read current version or build number from scripts/build_app.sh"
    exit 1
fi

echo "🔍 Current AIUsage Version: v${CURRENT_VERSION} (build ${CURRENT_BUILD})"

# Parse semantic version components
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"
MAJOR=${MAJOR:-0}
MINOR=${MINOR:-0}
PATCH=${PATCH:-0}

# Determine new version
if [[ -n "$TARGET_VERSION" ]]; then
    NEW_VERSION="$TARGET_VERSION"
elif [[ "$BUMP_TYPE" == "patch" ]]; then
    NEW_PATCH=$((PATCH + 1))
    NEW_VERSION="${MAJOR}.${MINOR}.${NEW_PATCH}"
elif [[ "$BUMP_TYPE" == "minor" ]]; then
    NEW_MINOR=$((MINOR + 1))
    NEW_VERSION="${MAJOR}.${NEW_MINOR}.0"
elif [[ "$BUMP_TYPE" == "major" ]]; then
    NEW_MAJOR=$((MAJOR + 1))
    NEW_VERSION="${NEW_MAJOR}.0.0"
else
    # Default if nothing specified: patch bump
    NEW_PATCH=$((PATCH + 1))
    NEW_VERSION="${MAJOR}.${MINOR}.${NEW_PATCH}"
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

# Verify git repository state
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [[ "$CURRENT_BRANCH" != "main" ]]; then
    echo "⚠️ Warning: Currently on branch '${CURRENT_BRANCH}', not 'main'."
    if [[ "$DRY_RUN" == false && "$AUTO_CONFIRM" == false ]]; then
        read -p "Do you want to proceed on '${CURRENT_BRANCH}'? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Release aborted."
            exit 1
        fi
    fi
fi

# Check tag collision
if git rev-parse "$TAG_NAME" >/dev/null 2>&1; then
    echo "❌ Git tag '${TAG_NAME}' already exists locally. Aborting."
    exit 1
fi

if git ls-remote --tags origin | grep -q "refs/tags/${TAG_NAME}$"; then
    echo "❌ Git tag '${TAG_NAME}' already exists on remote origin. Aborting."
    exit 1
fi

# Check GitHub CLI authentication if pushing
if [[ "$SKIP_PUSH" == false ]]; then
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
    echo "1. Files to update:"
    echo "   - Sources/Models/AppVersion.swift  -> Version ${NEW_VERSION}, Build ${NEW_BUILD}"
    echo "   - scripts/build_app.sh            -> APP_VERSION=\"${NEW_VERSION}\", APP_BUILD=\"${NEW_BUILD}\""
    echo "2. Build & Package DMG:"
    echo "   - Run ./scripts/build_dmg.sh"
    echo "   - Generates AIUsage.dmg and AIUsage-${TAG_NAME}.dmg"
    echo "3. Git Commit & Tag:"
    echo "   - git commit -m \"chore(release): ${TAG_NAME} (build ${NEW_BUILD})\""
    echo "   - git tag -a \"${TAG_NAME}\" -m \"Release ${TAG_NAME}\""
    if [[ "$SKIP_PUSH" == false ]]; then
        echo "4. Push & GitHub Release:"
        echo "   - git push origin ${CURRENT_BRANCH}"
        echo "   - git push origin ${TAG_NAME}"
        echo "   - gh release create ${TAG_NAME} AIUsage.dmg AIUsage-${TAG_NAME}.dmg --title \"${RELEASE_TITLE}\""
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

# 1. Update version files
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

# 2. Build DMG
echo "🔨 Compiling release bundle and building DMG..."
"$DIR/scripts/build_dmg.sh"

# Verify artifact existence
if [[ ! -f "$DIR/AIUsage.dmg" || ! -f "$DIR/AIUsage-${TAG_NAME}.dmg" ]]; then
    echo "❌ DMG artifacts missing after build! Check build_dmg.sh output."
    exit 1
fi

# 3. Git commit & tag
echo "📦 Staging and committing release files..."
git add Sources/Models/AppVersion.swift scripts/build_app.sh
git commit -m "chore(release): ${TAG_NAME} (build ${NEW_BUILD})"
echo "🏷️ Creating git tag ${TAG_NAME}..."
git tag -a "${TAG_NAME}" -m "Release ${TAG_NAME}"

# 4. Git push & GitHub Release
if [[ "$SKIP_PUSH" == false ]]; then
    echo "🚀 Pushing branch and tag to GitHub..."
    git push origin "$CURRENT_BRANCH"
    git push origin "$TAG_NAME"

    echo "🌐 Publishing GitHub Release ${TAG_NAME}..."
    GH_ARGS=("$TAG_NAME" "AIUsage.dmg" "AIUsage-${TAG_NAME}.dmg" "--title" "$RELEASE_TITLE")

    if [[ -n "$NOTES_FILE" && -f "$NOTES_FILE" ]]; then
        GH_ARGS+=("--notes-file" "$NOTES_FILE")
    elif [[ -n "$RELEASE_NOTES" ]]; then
        GH_ARGS+=("--notes" "$RELEASE_NOTES")
    else
        GH_ARGS+=("--generate-notes")
    fi

    gh release create "${GH_ARGS[@]}"
    echo ""
    echo "🎉 Release ${TAG_NAME} successfully published!"
    echo "🔗 URL: https://github.com/desmondlee95700/AIUsage/releases/tag/${TAG_NAME}"
else
    echo "ℹ️ --skip-push enabled: Git commit and tag '${TAG_NAME}' created locally. Remote push skipped."
fi
