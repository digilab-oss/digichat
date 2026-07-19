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
  ESR line, rebases our commits onto it, rebuilds, gates, and pushes. Security fixes flow through
  with no manual work.
- **Never silent**: any non-advance (rebase conflict, moved tag, ESR line ended, build/gate/push
  failure) **fails the run red** and never moves the branch. GitHub's own failed-run email is the
  notification — for a manual dispatch it reaches whoever triggered it; for the scheduled run, the
  account the cron runs as plus anyone **Watching → Custom → Actions**. Maintainers who want the
  alert should watch the repo that way.
- **Publishing needs a `workflow`-scoped token**: the rebased tooling commit touches
  `.github/workflows/*`, which the default `GITHUB_TOKEN` may never push. The sync mints a token
  from the org-owned **digichat-sync GitHub App** (Contents + Workflows write; secrets
  `SYNC_APP_ID` / `SYNC_APP_PRIVATE_KEY`) and checks out with it, so it can push the branch and
  tags. Org-owned, so it survives any one maintainer leaving.
- **Provenance**: the build refuses unless the upstream tag resolves to the pinned commit SHA,
  HEAD is built on it, and the commit is GitHub-signed; images carry the upstream tag/SHA labels.

## Verifying an image really contains the version it claims

The image *tag* is only a label — it does not prove what binary is inside. The trustworthy trace
is baked into the **binary itself** via ldflags at compile time and cannot be changed without
recompiling: `Version`, `Build Number` (`<upstream>-digilab.<rev>`), and `Build Hash` (the git
commit). Read it from any image or running pod:

```
# any image, by tag or digest:
docker run --rm --entrypoint mattermost <image>@<digest> version
# a running pod:
kubectl exec deploy/mattermost -- mmctl version
```

`Build Number` must match the deployed tag, and `Build Hash` must match the git commit (also on the
image's `org.opencontainers.image.revision` label and the `nl.digilab.upstream-*` labels). The build
**enforces this automatically**: after pushing, it runs the binary from the pushed image and fails
the run if it doesn't report the expected version — so a stale/mislabeled image (e.g. an 11.7.7 tag
carrying an 11.7.6 binary) can never have its digest recorded for deploy. This is why we pin by
**digest**, not tag, and why the layer cache is disabled (a cached package layer once shipped an old
binary under a new tag).

## Upstream CI in the fork

We **keep** upstream's `.github/workflows/*` files (our commits only add files, never delete
upstream ones) so a rebase never hits a `modify/delete` conflict when upstream edits its own CI —
the only conflicts left are genuine ones in the three patched files. Those upstream workflows are
**disabled via repo state** (`gh workflow disable`, which survives rebases), so they never run.
The committed source of truth is the sync's *Keep upstream CI disabled* step, which re-asserts this
after each advance for any workflow a future release adds. The existing set just needs disabling
once at bootstrap — the same `gh workflow disable` over every non-`digichat-*` workflow.

## Versioning

Tag = `${UPSTREAM#v}-digilab.${PATCHREV}-<sha7>` (e.g. `11.7.6-digilab.1`). `UPSTREAM` bumps on
each rebase; `PATCHREV` is bumped by hand only when our commits change for the same upstream tag;
the `-<sha7>` suffix makes each build unique. Deploys pin by **digest**.

## `.digilab/` files

`version.env` (upstream pin + patch revision — the single source of truth), `check-upstream.sh`,
`license-gate.sh`, and this README.
