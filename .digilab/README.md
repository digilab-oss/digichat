# digichat — build & maintenance

How the fork is built, license-gated, and kept in sync. Overview / front page:
[`.github/README.md`](../.github/README.md). Full rationale:
`ecosystem/messaging/digi-messenger/docs/mattermost/v11-self-hosting-runway.md`.

## The three changes, in detail

Three commits on `release-11.7-digilab` (base tag in `version.env`):

| File | Change |
|---|---|
| `server/config/client.go` | Restore the GitLab/Authentik **login button** on unlicensed TE — v11 gated it behind a licence ("Move Gitlab SSO to Professional"); we set the button props unconditionally in `GenerateLimitedClientConfig`. |
| `server/channels/app/limits.go` | Remove the v11 TE **250-user cap** — zero `maxUsersLimit`/`maxUsersHardLimit` (`isAtUserLimit` short-circuits at 0). |
| `server/cmd/mmctl/commands/compliance_export.go` | Add `//go:build enterprise` so the one file importing the Source-Available `message_export/shared` drops from the tag-less TE build. Its `_test.go` files carry the same tag. |

`grep -rn 'DIGILAB:' server` is the live inventory; `git range-diff <base-tag> release-11.7-digilab`
is the exact diff.

## Build & release

- Changes are **git commits rebased onto a released upstream tag** — no `.patch` files. `git
  rebase --onto` only replays our commits; it never rewrites upstream history.
- **GitHub Actions** (`.github/`) builds amd64 → the GitLab registry, with a blocking **license
  gate** (`license-gate.sh`) proving the image ships only AGPL + Apache code.
- **Clean Team-Edition build**: no `enterprise` dir, real `BUILD_NUMBER` (not `dev`),
  `PLUGIN_PACKAGES=` empty — all enforced by the build.
- **Auto-sync** (`digichat-sync.yml`): daily, `check-upstream.sh` finds a new `v11.7.x` on the
  ESR line, rebases our commits onto it, rebuilds, gates, and pushes; opens a GitHub issue on
  conflict/failure. Security fixes flow through with no manual work.
- **Provenance**: the build refuses unless the upstream tag resolves to the pinned commit SHA,
  HEAD is built on it, and the commit is GitHub-signed; images carry the upstream tag/SHA labels.

## Versioning

Tag = `${UPSTREAM#v}-digilab.${PATCHREV}-<sha7>` (e.g. `11.7.6-digilab.1`). `UPSTREAM` bumps on
each rebase; `PATCHREV` is bumped by hand only when our commits change for the same upstream tag;
the `-<sha7>` suffix makes each build unique. Deploys pin by **digest**.

## `.digilab/` files

`version.env` (upstream pin + patch revision — the single source of truth), `check-upstream.sh`,
`license-gate.sh`, and this README.
