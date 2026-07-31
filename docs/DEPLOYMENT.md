# Deploying the GoDrive API

> **This file is a workflow waiting to be installed.**
>
> ```bash
> mkdir -p .github/workflows
> git mv docs/ci/deploy-api.yml .github/workflows/deploy.yml
> git commit -m "ci: install the API deploy workflow"
> ```
>
> It could not be committed to `.github/workflows/` directly because the
> integration that opened this pull request does not hold GitHub's `workflows`
> permission. Moving it is a one-line change and needs no edits to the file.

## Why this exists

Every deploy of `synaptic-go-api` so far has been a `wrangler deploy` run by
hand — all ten recorded deployments come from a single machine. That is the
mechanism behind the failure this repo keeps hitting: **work lands on `main` and
then simply does not reach production.**

The clearest case: PR #45 carried the rider profile-photo upload fix, the
captain logout black screen and the approval hand-off. It sat open for a day
while all three were reported as still broken. The live Worker at the time of
writing is version 24, uploaded 2026-07-31T04:21Z — *before* the merge that
finally landed those fixes on `main`.

## What the workflow does

| Stage | Behaviour |
|---|---|
| Trigger | push to `main` touching `apps/api/**`, `packages/shared/**`, `migrations/**`; plus manual dispatch |
| Gates | typecheck api + shared, shared test suite, both migration checks — a failure stops the deploy |
| Migrations | `wrangler d1 migrations apply synaptic-go --remote --env prod` before publishing |
| Publish | `wrangler deploy --env prod` |
| Smoke test | polls `https://api.synapticstudio.tech/health` and fails if it never returns 200 |

## `--env prod` is not optional

`apps/api/wrangler.toml`'s top-level block shares the worker name
`synaptic-go-api` **and** the production D1 binding with `[env.prod]`. Its own
comment warns that a bare `wrangler deploy` publishes the top-level `[vars]`
straight over production — and those are the local-dev values, including
`DEV_OTP`. When `DEV_OTP` is `"true"` the API returns the OTP in the HTTP
response body, which lets anyone sign in as any user.

Encoding the flag in CI removes the chance of getting it wrong by hand.

## One-time setup

Add a repository secret `CLOUDFLARE_API_TOKEN` under
**Settings → Secrets and variables → Actions**.

Create it at <https://dash.cloudflare.com/profile/api-tokens> from the
**Edit Cloudflare Workers** template, scoped to the account owning
`synaptic-go-api` (`780ddc00154813b98d142686dc31ecde`), and add **D1:Edit** so
the migration step can run. Add `CLOUDFLARE_ACCOUNT_ID` too if the token spans
several accounts.

Until that secret exists the workflow still runs every gate, writes what is
missing to the job summary and exits green — no red X on every push.

## Deploying by hand in the meantime

```bash
npm ci
npm run verify                      # same gates the workflow runs
cd apps/api
npx wrangler d1 migrations apply synaptic-go --remote --env prod
npx wrangler deploy --env prod      # the --env flag matters, see above
curl -s https://api.synapticstudio.tech/health
```

## Current state (verified 2026-07-31)

- **D1 `synaptic-go`** (`c832b8fd-ca8c-4198-b7e5-cde3451c4b5a`) — all 17
  migrations recorded in `d1_migrations`, the last two at 2026-07-30 11:08.
  39 tables. `users.avatar_url` and `captains.birth_date` both present.
  **Nothing pending.**
- **Worker** — version 24, deployed 2026-07-31T04:21Z from wrangler, serving
  `api.synapticstudio.tech/*`. Healthy, reports `0.4.0`. This predates the
  PR #45 merge, so the API half of the upload fix is not confirmed live.
- **Clients** — the Flutter apps need a rebuild regardless; the upload fix has
  a client half (`imageMediaTypeForPath`) and a new `http_parser` dependency,
  so a `flutter pub get` is required before building.
