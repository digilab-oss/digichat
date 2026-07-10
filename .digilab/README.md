# digichat — how this fork works

> **Modified by Digilab, starting 2026-07-09.** A minimally-patched fork of Mattermost
> **Team Edition** (3 small commits, each marked `// DIGILAB:` in-tree). Not affiliated
> with, or endorsed by, Mattermost, Inc. Self-compiled source is **AGPLv3** (root
> `LICENSE.txt`); this fork publishes it to satisfy AGPL §13. *(This paragraph is the
> §5(a) dated-modification notice.)*

We run Mattermost v11 as a bridge, but v11's licensing removed free GitLab/Authentik
SSO and added a 250-user cap. Rather than pay, we self-compile Team Edition with three
tiny changes that undo those on the AGPL-licensed code. Full rationale:
`digilab/ecosystem/messaging/digi-messenger/docs/mattermost/v11-self-hosting-runway.md`.

`.digilab/` files:

| File | Role |
|---|---|
| `version.env` | `UPSTREAM=<tag>` + `UPSTREAM_SHA=<commit>` (immutable anchor) + `PATCHREV=<n>` — the single source of truth |
| `check-upstream.sh` | detects a newer patch on our ESR line, and whether the pinned tag was moved (the security-fix + tag-move watch) |
| `license-gate.sh` | blocking post-build proof that no Source-Available/non-permissive code ships |
| `README.md` | this document |

Our changes are **git commits** on `release-11.7-digilab` (not patch files); the build
+ sync automation lives in `.github/`.

---

## 1. Flow / lifecycle — *where the rebase happens*

```
Genesis (once, by hand)
   fork mattermost/mattermost → git checkout -B release-11.7-digilab v11.7.6
   → 3 //DIGILAB commits (+ .digilab/ + .github/ tooling commit) → push

Every push (digichat-build.yml)
   checkout branch → build-digichat action: guards → build → license-gate
   → build image → push to the GitLab registry            (NO rebase here)

Daily, automatic (digichat-sync.yml)              ◀── THE rebase lives here
   check-upstream.sh → new v11.7.x?  no → stop
   git rebase --onto <new> <old> release-11.7-digilab
        └ conflict → git rebase --abort + open a GitHub issue → stop
   bump version.env → build-digichat action (build + gate + push image)
        └ any failure → open a GitHub issue, DON'T move the branch → stop
   success → force-with-lease push branch
             + push upstream base tag <new>  + our release tag v<new>-digilab.<rev>

Deploy (gated)
   maintainer pins the new image @sha256:<digest> in the Flux digikluster-test
   values (reviewed MR) → Flux rolls it out
```

**Rebase is automated, in `digichat-sync.yml`** — not a manual step and not in the
plain build. CI never resolves conflicts: on conflict it aborts and files an issue for
a human. The branch `release-11.7-digilab` is **machine-maintained and only ever
force-pushed in a green (built+gated) state** — "fixed and correct".

`git rebase --onto` only ever replays **our** commits onto the new tag; it never
rewrites upstream history.

## 2. Auditing & transparency

Everything a reviewer/auditor needs is in the repo:
- **Our exact diff** = compare the branch against its base tag: `git range-diff
  <UPSTREAM> release-11.7-digilab`, or GitHub "compare". It's 3 tiny commits.
- **`// DIGILAB:` markers** in the source → `grep -rn DIGILAB server/` is the live
  in-tree inventory of every change.
- **`version.env`** declares the exact upstream base; CI **guards** it
  (`version.go` must equal `version.env:UPSTREAM`, and ≥3 DIGILAB files must be present)
  so an image can't be labelled 11.7.7 while shipping 11.7.6, nor built from clean
  upstream by mistake.
- **Immutable tags**: every built image has a `v<up>-digilab.<rev>` tag and the upstream
  **base tag** is kept in the fork — so the exact source of any running image survives
  branch force-pushes and even upstream tag deletion.
- **Image provenance**: labels `org.opencontainers.image.source` (the fork) +
  `.revision` (commit sha) + `nl.digilab.upstream-version`, and deploys pin by
  **digest** → any image traces back to an exact commit.

## 3. Reproducibility

The build is deterministic from things in the repo:
- **Immutable base commit** — `version.env:UPSTREAM_SHA` pins the exact commit. Git
  tags are *mutable*, so we rebase onto the SHA, never the tag; the image carries an
  `nl.digilab.upstream-sha` label; and `check-upstream.sh` **alerts (exit 4)** if
  upstream force-moves or deletes the tag (our builds are unaffected).
- **Our commits** — in git, replayed by rebase.
- **Pinned toolchain** — CI reads `server/.go-version` (Go) and `.nvmrc` (Node), the
  same pins upstream builds with.
- **Version derived, never hardcoded** — from `version.env` everywhere (scripts + CI).
- **Clean-TE flags** (below). Deploys pin by **digest**, so a cluster runs the exact
  bytes that were gated.

## 4. License compliance

- **AGPLv3 (self-compiled).** All 3 changed files are AGPL; the AGPL grants the right to
  modify (incl. undoing vendor feature-gating — §3 even neutralises any
  anti-circumvention angle). Obligation: **§13** — network users must be offered the
  *exact deployed source*. We satisfy it by publishing this fork (tagged per image) and
  surfacing it from the running service via `MM_SUPPORTSETTINGS_ABOUTLINK` +
  the image `source` label. (Independently reviewed — the one live go-live gate is
  publishing the source *before* it serves users.)
- **No Source-Available code ships.** `license-gate.sh` proves it (see that file's header
  for the threat model): our binaries link none of `server/v8/enterprise/*`
  (`LICENSE.enterprise`); the mmctl commit removes the one leak; no `enterprise`/
  `sourceavailable` build tags; no prepackaged plugins. **Blocking in CI.**
- **Trademark.** De-branded as *digichat* (repo + image); the running service is
  branded *Digilab* via config (`SITENAME`, custom brand, button text). We don't patch
  in-code "Mattermost" strings (large, conflict-prone, and impossible for the official
  client apps anyway).
- **Keep the fork on GitHub; don't mirror the full tree (incl. `server/enterprise/`)
  elsewhere.** The GitLab side is registry-only.

---

## Our changes — 3 commits (base: `version.env:UPSTREAM`, currently v11.7.6)

| File | What / why |
|---|---|
| `server/config/client.go` | Re-enable the GitLab/Authentik SSO **login button** on unlicensed TE. Upstream `b85027e65a` ("Move Gitlab SSO to Professional") gated the button props behind a license; we set them unconditionally in `GenerateLimitedClientConfig` (pure insertion — the licensed block is left untouched and harmlessly re-sets them). |
| `server/channels/app/limits.go` | Remove the v11 TE **250-user cap** by zeroing `maxUsersLimit`/`maxUsersHardLimit` (the unlicensed cap only applies when `maxUsersLimit > 0`; `isAtUserLimit` short-circuits at 0). |
| `server/cmd/mmctl/commands/compliance_export.go` | Add `//go:build enterprise` so this file (the only importer of the **Source-Available** `enterprise/message_export/shared`) drops from the tag-less TE `mmctl` build — keeps the redistributed image free of `LICENSE.enterprise` code. *Caveat: its `_test.go` files don't carry the tag, so `go test ./cmd/mmctl/...` won't compile in TE mode — expected; the shipped binary is unaffected.* |

Keep these as **3 small one-concern commits** (independently reviewable/revertable);
squashing is optional but loses that. Rebasing them never touches upstream history.

## Clean Team-Edition build rules (all enforced by the build + gate)

- **No `../../enterprise` dir** present → `BUILD_TAGS` empty, `BUILD_TYPE_NAME=team`.
- **`BUILD_NUMBER` real & non-`dev`** (unset ⇒ `dev` ⇒ the `sourceavailable` tag ⇒ pulls
  Source-Available packages into the binary). CI derives it from `version.env`.
- **`PLUGIN_PACKAGES=` empty** (ship none of the prepackaged plugins; several are SA).

## Versioning & registry

Version = `${UPSTREAM#v}-digilab.${PATCHREV}` (e.g. `11.7.6-digilab.1`). `PATCHREV` bumps
only when *our commits* change for the same upstream tag; `UPSTREAM` bumps on each
rebase. Image tag appends `-<sha>`; deploys pin by **digest**.

Registry (private): `registry.gitlab.com/digilab.overheid.nl/ecosystem/messaging/digichat`
— a dedicated GitLab project, registry-only (source is on GitHub `digilab-oss/digichat`).
Build runs on **GitHub Actions** (native amd64); pushing needs a GitLab deploy token
(`write_registry`) as the `GITLAB_REGISTRY_USER`/`GITLAB_REGISTRY_TOKEN` GH secrets.
