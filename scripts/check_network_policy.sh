#!/bin/bash
set -euo pipefail

# Fails if any URL host referenced in Sources/ is outside the allowlist in AGENTS.md §6.3.
# Only literal URLs are visible here; hosts that arrive in API responses (update downloads)
# are enforced at runtime by UpdateService.allowedHosts.
# Adding a host here requires repository owner approval.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

ALLOWED_HOSTS=(
    "127.0.0.1"          # Antigravity loopback Connect-RPC
    "claude.ai"          # Claude usage endpoints (desktop session) + browser fallback link
    "api.anthropic.com"  # Claude Code OAuth usage endpoint
    "api.github.com"     # In-app update check
    "github.com"         # Update DMG download link (release assets of this repo only)
    "release-assets.githubusercontent.com"  # CDN that GitHub redirects release downloads to
    "chatgpt.com"        # Browser fallback link only (no data requests)
)

violations=0
while IFS= read -r host; do
    allowed=false
    for allowedHost in "${ALLOWED_HOSTS[@]}"; do
        if [[ "$host" == "$allowedHost" ]]; then
            allowed=true
            break
        fi
    done
    if [[ "$allowed" == false ]]; then
        echo "::error::Sources reference '$host', which is not an allowed network destination (AGENTS.md §6.3):"
        grep -rn "://$host" Sources | sed 's/^/    /'
        violations=$((violations + 1))
    fi
done < <(grep -rhoE 'https?://[A-Za-z0-9.-]+' Sources | sed -E 's#^https?://##' | sort -u)

if [[ $violations -gt 0 ]]; then
    echo "❌ $violations disallowed host(s). Get owner approval, then add them to AGENTS.md §6.3 and this allowlist."
    exit 1
fi
echo "✅ All network destinations are on the allowlist."
