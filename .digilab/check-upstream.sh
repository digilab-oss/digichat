#!/usr/bin/env bash
# DIGILAB: security-fix guard + tag-move guard. Detects (a) a newer patch on OUR ESR
# minor line, and (b) whether our pinned tag was force-moved/deleted upstream.
#
# We track the ESR *minor* line from .digilab/version.env's UPSTREAM (e.g. 11.7.*),
# NOT upstream's "latest release" (which would jump to a newer minor off our ESR).
# Everything is anchored on the immutable COMMIT SHA, because git tags are mutable.
#
# Exit: 0 = up to date & tag unmoved · 3 = a newer patch exists · 2 = ESR line ended
#       · 4 = our pinned tag now points at a DIFFERENT commit (upstream moved/deleted it)
# In GitHub Actions, writes latest=<tag> and latest_sha=<commit> to $GITHUB_OUTPUT.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$REPO"

# shellcheck disable=SC1091
source .digilab/version.env                                       # UPSTREAM, UPSTREAM_SHA, PATCHREV
MINOR="$(echo "$UPSTREAM" | sed -E 's/^v([0-9]+\.[0-9]+)\..*/\1/')"  # 11.7

git remote get-url upstream >/dev/null 2>&1 || git remote add upstream https://github.com/mattermost/mattermost.git

# Resolve a tag to its upstream COMMIT sha (handles annotated via ^{} and lightweight).
resolve_sha() {
  local s
  s="$(git ls-remote upstream "refs/tags/$1^{}" 2>/dev/null | awk '{print $1; exit}')"
  [ -z "$s" ] && s="$(git ls-remote upstream "refs/tags/$1" 2>/dev/null | awk '{print $1; exit}')"
  printf '%s' "$s"
}

# Highest released v<MINOR>.<patch> tag (exclude -rc). Network error must fail loud;
# "no matching tags" must fall through to the ESR-EOL branch.
REMOTE_TAGS="$(git ls-remote --tags upstream "refs/tags/v${MINOR}.*")" \
  || { echo "ERROR: git ls-remote upstream failed (network?)"; exit 1; }
LATEST="$(printf '%s\n' "$REMOTE_TAGS" \
  | sed -E 's#.*refs/tags/(v[0-9]+\.[0-9]+\.[0-9]+)$#\1#' \
  | grep -E "^v${MINOR}\.[0-9]+$" | sort -V | tail -1 || true)"

echo "pinned : $UPSTREAM @ $UPSTREAM_SHA"
echo "latest ${MINOR} tag upstream: ${LATEST:-<none>}"

if [ -z "$LATEST" ]; then
  echo "WARN: no v${MINOR}.* tags upstream — the ${MINOR} ESR line may have ended."
  echo "      Move to the next ESR (bump the minor + rebase onto its first tag)."
  exit 2
fi

LATEST_SHA="$(resolve_sha "$LATEST")"
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  { echo "latest=$LATEST"; echo "latest_sha=$LATEST_SHA"; } >> "$GITHUB_OUTPUT"
fi

if [ "$LATEST" != "$UPSTREAM" ]; then
  echo "BEHIND: newer patch $LATEST ($LATEST_SHA) — the sync workflow will rebase onto it."
  echo "        (Contains security fixes.)"
  exit 3
fi

# Same tag name — verify it still points where we pinned it (detect a force-moved/deleted tag).
CUR_SHA="$(resolve_sha "$UPSTREAM")"
if [ -z "$CUR_SHA" ]; then
  echo "ALERT: pinned tag $UPSTREAM no longer exists upstream (deleted)."; exit 4
fi
if [ "$CUR_SHA" != "$UPSTREAM_SHA" ]; then
  echo "ALERT: upstream MOVED $UPSTREAM — now $CUR_SHA, we pinned $UPSTREAM_SHA."
  echo "       Our builds stay on the pinned commit (we never rebase onto the moving tag);"
  echo "       a human should investigate why upstream re-tagged."
  exit 4
fi

echo "OK: up to date on ${MINOR}; $UPSTREAM still points at the pinned commit."
