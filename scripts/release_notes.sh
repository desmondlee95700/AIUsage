#!/bin/bash
set -euo pipefail

# Prints Markdown release notes for <tag>, built from the Conventional Commit
# subjects since the previous version tag.
#
# Usage: ./scripts/release_notes.sh v2.1.3

TAG="${1:?usage: release_notes.sh <tag>}"
REPO="desmondlee95700/AIUsage"
REPO_URL="https://github.com/${REPO}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

# A final release is compared against the previous final release, skipping its own
# pre-releases, so users upgrading from the last stable version see every change.
if [[ "$TAG" == *-* ]]; then
    PREV_TAG=$(git describe --tags --abbrev=0 --match 'v*' "${TAG}^" 2>/dev/null || true)
else
    PREV_TAG=$(git describe --tags --abbrev=0 --match 'v*' --exclude 'v*-*' "${TAG}^" 2>/dev/null || true)
fi
RANGE="${PREV_TAG:+${PREV_TAG}..}${TAG}"

# Regexes live in variables: bash 3.2 (macOS default) can't parse them inline
RELEASE_COMMIT_PATTERN='^chore\(release\)'
CONVENTIONAL_PATTERN='^([a-z]+)(\(([^)]+)\))?!?: (.+)$'

FEATURES=""
FIXES=""
OTHER=""

while IFS= read -r subject; do
    [[ -z "$subject" ]] && continue
    # Version bump commits aren't user-facing
    [[ "$subject" =~ $RELEASE_COMMIT_PATTERN ]] && continue

    if [[ "$subject" =~ $CONVENTIONAL_PATTERN ]]; then
        type="${BASH_REMATCH[1]}"
        scope="${BASH_REMATCH[3]}"
        description="${BASH_REMATCH[4]}"
        line="- ${scope:+**${scope}:** }${description}"
    else
        type="other"
        line="- ${subject}"
    fi

    case "$type" in
        feat) FEATURES+="${line}"$'\n' ;;
        fix|perf) FIXES+="${line}"$'\n' ;;
        docs|test|ci|build|style|chore) ;; # internal; omitted from user-facing notes
        *) OTHER+="${line}"$'\n' ;;
    esac
done < <(git log --no-merges --format='%s' "$RANGE")

# Highlights written with `release.sh -m/-f` are stored in the annotated tag message
HIGHLIGHTS=$(git tag -l --format='%(contents)' "$TAG" 2>/dev/null | sed '/^-----BEGIN PGP SIGNATURE-----/,$d' || true)
if [[ -n "$HIGHLIGHTS" && "$HIGHLIGHTS" != "Release ${TAG}" ]]; then
    printf '%s\n\n' "$HIGHLIGHTS"
fi

[[ -n "$FEATURES" ]] && printf '## ✨ Features\n\n%s\n' "$FEATURES"
[[ -n "$FIXES" ]] && printf '## 🐛 Fixes\n\n%s\n' "$FIXES"
[[ -n "$OTHER" ]] && printf '## 🔧 Other Changes\n\n%s\n' "$OTHER"
if [[ -z "$FEATURES$FIXES$OTHER" ]]; then
    printf 'Maintenance release.\n\n'
fi

# Contributors: commit authors and Co-authored-by trailers in the range, as GitHub @handles.
# AI assistants and bots are left out; they're tools, not contributors.
AI_OR_BOT_PATTERN='\[bot\]|noreply@anthropic\.com|noreply@openai\.com|copilot|^claude|^codex|^chatgpt|^gemini|^cursor|^devin'
NOREPLY_PATTERN='^([0-9]+\+)?([^@]+)@users\.noreply\.github\.com$'

# "<email>\t<name>\t<sha>" per commit author, then per co-author (no sha: they didn't author it)
PEOPLE=$(
    git log --no-merges --format='%ae%x09%an%x09%H' "$RANGE"
    git log --no-merges --format='%(trailers:key=Co-authored-by,valueonly,separator=%x0A)' "$RANGE" \
        | sed -nE 's/^ *(.*[^ ]) *<([^>]+)>.*$/\2\t\1\t/p'
)

HANDLES=""
while IFS=$'\t' read -r email name sha; do
    [[ -z "$email" ]] && continue
    who=$(printf '%s <%s>' "$name" "$email" | tr '[:upper:]' '[:lower:]')
    [[ "$who" =~ $AI_OR_BOT_PATTERN ]] && continue

    # GitHub login: from a noreply address, else from the commit via the API (CI and
    # release.sh both have gh); the plain name when neither works
    login=""
    if [[ "$email" =~ $NOREPLY_PATTERN ]]; then
        login="${BASH_REMATCH[2]}"
    elif [[ -n "$sha" ]]; then
        login=$(gh api "repos/${REPO}/commits/${sha}" -q '.author.login // empty' 2>/dev/null || true)
    fi
    if [[ -n "$login" ]]; then
        HANDLES+="@${login}"$'\n'
    else
        HANDLES+="${name}"$'\n'
    fi
done < <(printf '%s\n' "$PEOPLE" | awk -F'\t' '!seen[$1]++')

# One line per person; two emails for the same login collapse here
CONTRIBUTORS=$(printf '%s' "$HANDLES" | sort -fu | sed 's/^/- /')
if [[ -n "$CONTRIBUTORS" ]]; then
    printf '## 🙌 Contributors\n\n%s\n\n' "$CONTRIBUTORS"
fi

if [[ -n "$PREV_TAG" ]]; then
    printf '**Full changelog:** %s/compare/%s...%s\n' "$REPO_URL" "$PREV_TAG" "$TAG"
fi
