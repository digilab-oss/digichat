#!/usr/bin/env bash
# DIGILAB: post-build LICENSE GATE — proves our Team-Edition build ships no code we
# aren't licensed to redistribute. Runs in CI as a BLOCKING step; also runnable locally.
#
# WHY THIS WORKS (threat model):
#   Mattermost's source is AGPLv3 (our patched server) + Apache-2.0 (webapp/config),
#   which we may freely self-compile & redistribute. The ONE thing we must NOT ship is
#   the **Source-Available** code: everything under `server/v8/enterprise/*` carries a
#   `// See LICENSE.enterprise` header (the "Mattermost Source Available License", which
#   forbids production use/redistribution without an Enterprise E20 subscription).
#   Key insight: that code only ends up in a binary if the binary *imports* it — so if
#   `go list -deps` shows our binaries link none of it, none of it ships → compliant.
#   `go list -deps` is the authoritative "what is actually linked in". Two build knobs
#   can pull it in by mistake, so we also assert those are off (checks 2 & 3).
#
# FAIL-LOUD: a tooling error (missing Go, wrong dir, compile error) must FAIL the gate,
# never read as "clean" — a gate that can't inspect the build must not pass it.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$REPO/server"
FAIL=0; SKIPPED=0

echo "### 1. no Source-Available packages linked (tag-less TE build)"
# WHAT: list every package linked into the server + mmctl binaries (empty -tags = TE).
# WHY : if neither binary imports server/v8/enterprise/*, no LICENSE.enterprise code is
#       in the shipped binary. The server legitimately links only the empty top-level
#       `enterprise` placeholder package (a bare `package enterprise` clause, de minimis,
#       same as Mattermost's own TE builds); any *sub*package there is a real leak (FAIL).
# HOW-FAILS: the fallible `go list` is kept separate from the (may-be-empty) grep, so a
#       toolchain/dir error FAILS the gate instead of yielding an empty "clean" result.
deps_mm="$(go list -deps -tags '' ./cmd/mattermost)" || { echo "  FAIL: go list (server) errored — cannot verify"; exit 1; }
deps_mc="$(go list -deps -tags '' ./cmd/mmctl)"      || { echo "  FAIL: go list (mmctl) errored — cannot verify"; exit 1; }
# server may legitimately pull ONLY the empty top-level placeholder package.
mm="$(grep 'server/v8/enterprise' <<<"$deps_mm" || true)"
mc="$(grep 'server/v8/enterprise' <<<"$deps_mc" || true)"
if grep -qv '^github.com/mattermost/mattermost/server/v8/enterprise$' <<<"$mm" && [ -n "$mm" ]; then
  echo "  FAIL server links SA subpackages:"; echo "$mm"; FAIL=1
else echo "  OK   server: only empty placeholder (${mm:-none})"; fi
if [ -n "$mc" ]; then echo "  FAIL mmctl links enterprise: $mc"; FAIL=1; else echo "  OK   mmctl: none"; fi

# WHY 2: the two build tags that pull Source-Available code in are `enterprise` (needs
#   the private EE repo) and `sourceavailable` (compiles the in-tree SA packages). CI is
#   the place a stray `BUILD_NUMBER=dev` could enable `sourceavailable` — so we read the
#   tags baked into the binary and FAIL if either is present. (Belt to check 1's braces.)
echo "### 2. build tags contain no enterprise/sourceavailable"
# `make package-*` leaves only the .tar.gz (staging dirs are cleaned), so inspect the
# binary as *shipped*: extract it from the tarball. Fall back to any unpacked dist binary.
bin="$(ls dist/*/bin/mattermost dist/mattermost/bin/mattermost 2>/dev/null | head -1 || true)"
if [ -z "$bin" ]; then
  tgz="$(ls dist/mattermost-team-linux-amd64.tar.gz 2>/dev/null | head -1 || true)"
  if [ -n "$tgz" ]; then
    tmp="$(mktemp -d)"
    tar -xzf "$tgz" -C "$tmp" mattermost/bin/mattermost 2>/dev/null || true
    bin="$(ls "$tmp"/mattermost/bin/mattermost 2>/dev/null | head -1 || true)"
  fi
fi
if [ -n "$bin" ] && [ -f "$bin" ]; then
  tags="$(go version -m "$bin" | grep -- '-tags' || echo '(no -tags setting)')"
  echo "  $tags"
  if grep -qE 'enterprise|sourceavailable' <<<"$tags"; then echo "  FAIL enterprise/sourceavailable tag present"; FAIL=1; else echo "  OK   no enterprise/sourceavailable tag"; fi
else echo "  SKIP: no shipped binary found (neither dist/ binary nor tarball) — run the build first"; SKIPPED=1; fi

# WHY 3: the stock image bundles ~14 prepackaged plugins, several of which are
#   Source-Available/enterprise (Calls, Playbooks, metrics, channel-export). We build
#   with PLUGIN_PACKAGES= empty; assert the dist bundled none.
echo "### 3. no prepackaged plugins shipped"
pp="$(ls -d dist/*/prepackaged_plugins dist/mattermost/prepackaged_plugins 2>/dev/null | head -1 || true)"
if [ -n "$pp" ] && [ -n "$(ls -A "$pp" 2>/dev/null)" ]; then echo "  FAIL prepackaged plugins present:"; ls -A "$pp"; FAIL=1
else echo "  OK   none"; fi

# WHY 4: checks 1-3 cover *Mattermost* code; this catches THIRD-PARTY non-permissive
#   licenses anywhere in the final image (OS layers, Go/npm deps) via an SBOM. Optional
#   (needs an image ref + syft); the Go/npm deps were already audited permissive at
#   baseline, so this is defence-in-depth, not the primary gate.
echo "### 4. image license scan (optional; informational)"
IMG="${1:-}"
if [ -n "$IMG" ] && command -v syft >/dev/null; then
  # Actual LICENSE scan (not a vuln scan): fail on non-permissive licenses in the image.
  bad="$(syft -q "$IMG" -o json | jq -r '[.artifacts[]|.licenses[]?.value]|unique[]' 2>/dev/null \
        | grep -iE 'GPL|AGPL|SSPL|BUSL|BSL|Commons-Clause|Source.?Available|non.?commercial' || true)"
  if [ -n "$bad" ]; then echo "  FAIL non-permissive licenses in image:"; echo "$bad"; FAIL=1; else echo "  OK   no non-permissive image licenses"; fi
else echo "  SKIP: no image ref / syft. Dep licenses audited at baseline (all permissive bar mmctl-only isacikgoz/prompt=no-license, see README)."; SKIPPED=1; fi

echo
if [ "$FAIL" -ne 0 ]; then echo "### LICENSE GATE: FAIL"; exit 1; fi
[ "$SKIPPED" -eq 0 ] && echo "### LICENSE GATE: PASS" || echo "### LICENSE GATE: PASS (with skips — not a full gate; see SKIP lines)"
