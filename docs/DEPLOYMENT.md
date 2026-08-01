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
> This is task **E00** on the execution board, and it is human-only.

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

It is no longer possible to get it wrong from the command line either. As of
task E01 there is no script in this repository that deploys without an explicit
environment:

- `npm run deploy:api` — and `npm run deploy -w @synaptic-go/api`, which it
  delegates to — **refuse to run** and exit non-zero. They deploy nothing.
- `apps/api/deploy.sh` takes the environment as a **required** argument and
  validates it against the `[env.*]` blocks that actually exist in
  `wrangler.toml`.

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
./deploy.sh prod                    # typecheck → migrate → deploy → smoke test
```

`deploy.sh` applies **all** pending migrations with
`wrangler d1 migrations apply --remote`, which records each one in
`d1_migrations`.

What it used to do is worth stating precisely, because it changes what you
should expect the production database to contain. The old script ran:

```bash
wrangler d1 execute "$DB_NAME" --file=../../migrations/0009_captain_city.sql
```

Three separate faults in one line: it applied **one** migration out of 19; it
used `d1 execute`, which writes nothing to the `d1_migrations` bookkeeping
table; and it passed **no `--remote`**, so the one migration it did apply went
to the *local* development database. The `wrangler deploy` two lines later went
to production regardless. A run of this script therefore published a Worker to
production while migrating nothing there — the precise failure mode the script's
own header comment claimed to prevent.

Useful variants:

```bash
./deploy.sh prod --dry-run          # print every command, run none of them
./deploy.sh staging                 # same pipeline against synaptic-go-staging
./deploy.sh                         # refuses: no environment given, exits 1
npm run test:deploy                 # assert the guard still holds (17 checks)
```

The equivalent raw commands, if you would rather not use the script:

```bash
cd apps/api
npx wrangler d1 migrations apply synaptic-go --remote --env prod
npx wrangler deploy --env prod      # the --env flag matters, see above
curl -s https://api.synapticstudio.tech/health
```

## Current state

### Verified in this repository (base `f480905`)

- **`migrations/` contains 19 migrations**, `0001_init.sql` through
  `0019_trips_captain_status_index.sql`, contiguous with no gaps.
- `0005`, `0009`, `0017` and `0018` carry irreversible backfills. Migrations are
  forward-only; a mistake is repaired by a further migration or a restore, never
  by a rollback. The restore procedure is rehearsed under task E18.

### NOT verified — this is the correction

A previous revision of this file stated that **17** migrations were applied and
that nothing was pending, "verified 2026-07-31". That claim is withdrawn:

- the repository contains **19** migrations, so a state of 17-applied /
  nothing-pending could not have been true as written;
- nothing in this repository can observe the remote database, and no agent
  working the execution board has credentials for it. The count could only ever
  have been copied by hand, and a hand-copied number is what produced the error.

**The true remote state is currently unknown.** One command establishes it, and
it must be run by a human with production credentials:

```bash
npx wrangler d1 migrations list synaptic-go --remote --env prod
```

Its output is recorded in the **`PROJECT.md` block for task E00**, together with
the commit message — deliberately not pasted back into this file, so that the
verified state has exactly one writer and cannot drift again.

Two things follow, and both are load-bearing:

- **Run it before the first deploy of this wave.** If migrations are genuinely
  pending, the first `wrangler d1 migrations apply --remote --env prod` will
  apply as many as the gap requires, in one go, against live data. Note that
  `0009_captain_city.sql` is a specific candidate for being absent: the only
  tooling that ever singled it out applied it to the *local* database, as
  described above.
- Do not restate the number in this file. If you find yourself editing a count
  here, the count belongs in the E00 block instead.

### Worker

Version 24, deployed 2026-07-31T04:21Z from wrangler, serving
`api.synapticstudio.tech/*`, reporting `0.4.0`. This predates the PR #45 merge,
so the API half of the upload fix is not confirmed live. This paragraph is a
record of an observation made on 2026-07-31 and has not been re-verified since;
treat it as history, not as current state.

### Clients

The Flutter apps need a rebuild regardless; the upload fix has a client half
(`imageMediaTypeForPath`) and a new `http_parser` dependency, so a
`flutter pub get` is required before building.
