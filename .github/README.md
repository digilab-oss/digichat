# digichat

digichat is a minimally-patched fork of Mattermost **Team Edition** that restores free
GitLab/Authentik SSO and lifts the v11 user cap — a self-hostable chat server with today's
features, built from the AGPL source and maintained on the 11.7 ESR.

Built on [Mattermost](https://github.com/mattermost/mattermost) Team Edition (AGPLv3);
maintained by [Digilab](https://digilab.overheid.nl) (Dutch government).

## What changes

Three small backend commits, each marked `// DIGILAB:` in-tree:

- **GitLab/Authentik login button** restored on unlicensed Team Edition (`server/config/client.go`).
- **v11 250-user cap lifted** (`server/channels/app/limits.go`).
- **mmctl kept license-clean** — drops the one file importing Source-Available code, so the image
  ships only AGPL + Apache (`server/cmd/mmctl/commands/compliance_export.go`).

Everything else is stock upstream. Exact diff: `git range-diff <base-tag> release-11.7-digilab`.

## Get the image

Public registry: `registry.gitlab.com/digilab.overheid.nl/ecosystem/messaging/digichat`

Tag = `<upstream>-digilab.<rev>-<sha7>` (e.g. `11.7.6-digilab.1`); deploy by digest.

## License

**AGPLv3**, self-compiled. The changed files are AGPL, which grants the right to modify. Per
AGPL §13 the exact deployed source is offered to users: this published fork (tagged per image)
plus the running service's About link. The image ships only AGPL server + Apache webapp code,
proven by a blocking CI license gate.

*Modified by Digilab starting 2026-07-09 — this line is the AGPL §5(a) dated-modification notice.*

## Build & maintenance

How the fork is built, license-gated, and auto-synced onto new ESR releases:
**[`.digilab/README.md`](../.digilab/README.md)**.
