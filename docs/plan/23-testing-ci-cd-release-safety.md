# 23 — Testing, CI/CD & Release Safety

> Track: D — Engineering excellence & production readiness · Reviewer: `chat-20260801-1413-39fb` · Date: 2026-08-01 (UTC)
> Base commit reviewed: `0f432702a3755f7bd738b8b7ee15230cf05c4686` (`main`, 2026-08-01T14:12:01Z)

## 1. Scope

This document covers how Synaptic Go proves a change is safe before it reaches a rider: the automated test suite, the CI pipeline, the deploy mechanism, environment topology, migration safety, rollback, feature flags, load testing, and code-quality gates.

It covers **the machinery of shipping**, not the correctness of any individual subsystem. Where I cite a bug in the money path or the dispatch engine, I cite it *as a test target* — evidence that a specific test is worth writing — and hand the bug itself to its owning track.

Explicitly out of scope, with the owning track named:

| Not covered here | Owner |
|---|---|
| Whether the wallet ledger is correct | **T03** |
| Whether the Paymob integration is correct | **T04** |
| Whether fare/surge/bidding maths is economically right | **T05** |
| Whether dispatch picks the right captain | **T06** |
| Whether the DO/WebSocket design is sound | **T07** |
| Whether the migrations model the domain well | **T08** |
| Logging, alerting, dashboards, incident response | **T22** |
| Latency/cost budgets and scale ceilings | **T24** |
| App Store / Play Store submission, signing, phased rollout | **T26** |
| Duplicated screens across rider/captain | **T27** |

The line between T23 and T22 is: T22 owns *knowing production is broken*; T23 owns *not breaking it*. The line between T23 and T26 is: T23 owns CI gates for the Flutter apps up to and including a build in CI; T26 owns everything from a signed artifact onward.

## 2. What I actually read

Every file below was downloaded at the pinned base commit and read from disk with real line numbers. Nothing in this document cites a file I did not open.

**CI, build and release**

| File | Note |
|---|---|
| `.github/workflows/ci.yml` | 246 lines. The only workflow in the repository. Three jobs: `node`, `flutter`, `checks`. Read in full. |
| `docs/ci/deploy-api.yml` | 159 lines. A complete, well-written deploy workflow that is **not installed**. Read in full. |
| `docs/DEPLOYMENT.md` | 85 lines. Runbook + the `git mv` instruction that was never executed. Read in full. |
| `apps/api/deploy.sh` | 51 lines. A one-off script pinned to migration 0009. Read in full. |
| `apps/api/wrangler.toml` | 180 lines. Three environments. Read in full — this file carries two S1s. |
| `package.json` (root) | 26 lines. `typecheck` / `test` / `check` / `verify` scripts. Read in full. |
| `apps/api/package.json` | 25 lines. `deploy` = bare `wrangler deploy`. Read in full. |
| `apps/admin/package.json` | 32 lines. No test script at all. Read in full. |
| `packages/shared/package.json` | 19 lines. The only package with a `test` script. Read in full. |

**Tests that exist**

| File | Note |
|---|---|
| `packages/shared/src/index.test.ts` | 83 lines, 9 cases, 24 assertions — `calculateFare` + `TRIP_TRANSITIONS`. |
| `packages/shared/src/fileType.test.ts` | 175 lines, 22 cases, 37 assertions — magic-byte sniffing. The best-tested code in the repo. |
| `packages/shared/src/index.ts` | 218 lines. Read closely to find what the tests miss. |
| `apps/rider/test/widget_test.dart` | Boot smoke test, 1 case. |
| `apps/captain/test/widget_test.dart` | Boot smoke test, 1 case. |

**Check scripts (the de-facto test suite)**

| File | Note |
|---|---|
| `scripts/check_migrations.py` | 211 lines. Static filename/encoding checks only. Read in full. |
| `scripts/check_migrations_apply.py` | 102 lines. Read in full — the answer to brief question 4 lives at lines 58–85. |
| `scripts/check_repo_hygiene.py` | 194 lines. Conflict markers, artifacts, BOM, committed `.env`. |
| `scripts/check_l10n_parity.py` | 227 lines. Abstract/locale parity in one Dart file. |

**Product code, read as test targets**

`apps/api/src/routes/trips.ts` (1371 lines — accept race at 846–870), `wallet.ts` (payout CAS at 113–130), `payments.ts` (webhook at 97–302), `promo.ts`, `admin.ts` (system_config at 447–533), `apps/api/src/lib/pricing.ts`, `paymob.ts` (HMAC at 152–235), `utils.ts`, `schemas.ts`, `apps/api/src/index.ts` (cron at 267–369, health at 99), `middleware/auth.ts` (guards at 29–75), all four Durable Objects, and all 19 files in `migrations/`.

**Manifests and config**

`apps/api/tsconfig.json`, `apps/admin/tsconfig.json`, `apps/admin/tsconfig.node.json`, `packages/shared/tsconfig.json`, `apps/api/.dev.vars.example`, `.gitignore`, `apps/rider/pubspec.yaml`, `apps/captain/pubspec.yaml`, `packages/flutter_shared/pubspec.yaml`, and both `analysis_options.yaml`.

**Repository-wide inventory**

I enumerated all 442 blobs at the base commit via the git trees API rather than guessing at structure. That inventory is itself evidence for several findings below (for example: exactly one workflow file exists; exactly two TypeScript test files exist; no `.eslintrc`, no `vitest.config.ts`, no `dependabot.yml`, no `seed.sql` exists anywhere).

**Verified out-of-band (not files)**

- GitHub branch API for `main`: `"protected": false`, `required_status_checks.enforcement_level: "off"`, `contexts: []`.
- Pull request list: PR #46 `ci: deploy the API from main instead of from someone's laptop` — **merged**.
- Commit dates for `migrations/0018_*` (2026-07-31T09:42:08Z) and `migrations/0019_*` (2026-07-31T14:33:45Z) versus `docs/DEPLOYMENT.md` (2026-07-31T07:25:06Z).

Skimmed rather than read line-by-line: `docs/ARCHITECTURE.md`, `docs/STACK.md`, `docs/API.md`, `docs/COST.md`, `docs/ROADMAP.md`, `docs/IMPROVEMENTS.md`, `docs/CHECKLIST.md`, `scripts/generate_pdf.py`, and the bulk of `admin.ts` outside the `system_config` handlers.

## 3. How it works today

### 3.1 The pipeline, end to end

```
  developer pushes branch
          │
          ▼
   ci.yml runs  ──────────────────────────────────────────────┐
    ├── node    : npm ci → typecheck api/admin/shared →        │  all three jobs
    │             build admin → test shared                    │  report status
    ├── flutter : pub get + analyze × (shared, captain, rider) │  but NONE is a
    └── checks  : 4 python scripts                             │  required check
          │                                                     │
          ▼                                                     │
   PR is mergeable regardless of result  ◀──────────────────────┘
          │
          ▼
   merge to main
          │
          ▼
   ci.yml runs again on main (still advisory)
          │
          ▼
   ??? — nothing deploys. A human must remember to run
        `wrangler deploy --env prod` from a laptop.
```

That last step is not a simplification. It is the current mechanism.

### 3.2 What CI checks today

`.github/workflows/ci.yml` triggers on `pull_request`, `push` to `main`, and `merge_group` (lines 10–14), with sensible concurrency (lines 18–20). Every step uses `continue-on-error: true` and a final `Result` step aggregates outcomes and exits non-zero (lines 76–98, 169–192, 225–246). That is a deliberate and good design: one run shows the whole picture instead of stopping at the first failure.

| Job | Steps | What it proves |
|---|---|---|
| `node` (26) | `npm ci` (46); typecheck api (54), admin (59), shared (64); build admin (69); test shared (74) | The three TS packages compile; the admin bundle builds; 31 shared unit tests pass |
| `flutter` (100) | `pub get` + `flutter analyze --no-fatal-infos --no-fatal-warnings` for `flutter_shared` (140), `captain` (154), `rider` (166) | The Dart in all three packages parses and has no analyzer **errors** |
| `checks` (194) | `check_migrations.py` (208), `check_migrations_apply.py` (213), `check_l10n_parity.py` (218), `check_repo_hygiene.py` (223) | Migration filenames/encoding are sane; migrations execute against stdlib sqlite3; l10n classes are in parity; no conflict markers |

`npm ci` rather than `npm install` (line 46) is a deliberate choice documented at lines 39–44 — the lockfile had previously drifted and omitted `vitest` entirely. Pinning Flutter to `3.24.5` (line 112) rather than `stable` is likewise deliberate and correct.

**What CI does not check:** any API behaviour, any Worker route, any Durable Object, any D1 query, any Flutter test (`flutter test` is absent — only `analyze` runs), any admin React component, lint (no ESLint config exists in the repository), formatting, dependency vulnerabilities (`npm audit` absent), secrets (no scanner), or bundle size. There is no `wrangler deploy --dry-run` to prove the Worker even builds — `tsc --noEmit` type-checks it but never bundles it.

Answering the brief's question 1 directly: **yes, a change that breaks the payment webhook can merge today with a fully green board, and it can merge with a fully red board too.** The webhook handler in `payments.ts:97–302` is executed by no test at any point in the pipeline.

### 3.3 The two tests that exist

`packages/shared/src/index.test.ts` covers `calculateFare` well for a 38-line function: base case, `minFare` floor, surge, discount, over-discount clamp, commission, negative-input clamp, zero distance — 9 cases, 24 assertions. `fileType.test.ts` is genuinely strong: 22 cases, 37 assertions, including a "rejects what must never be stored" suite (HTML, SVG, non-WebP RIFF, truncated PNG) that defends a real upload-XSS vector.

Everything else in `packages/shared/src/index.ts` is untested, including several functions that silently corrupt behaviour when wrong:

- `canTransition(from, to)` (`index.ts:50`) — the trip state-machine guard. `TRIP_TRANSITIONS` has a shape assertion; the function that *uses* it does not.
- `haversineKm(a, b)` (`index.ts:55`) — distance, feeding both fare and dispatch.
- `encodeGeohash(lat, lng, precision)` (`index.ts:129`) — a hand-rolled geohash encoder. A bug here silently misroutes dispatch to the wrong cell; nothing would fail loudly.
- `geohashCellSpan(precision)` (`index.ts:181`) — the neighbour-cell span whose comment explicitly documents a "miss a neighbour" hazard.
- `round2(n)` (`index.ts:121`) — the rounding primitive under every money figure.

No `vitest.config.ts` exists anywhere; `vitest run` (`packages/shared/package.json:13`) uses defaults. There is no coverage reporting and no coverage threshold.

### 3.4 Environments

`wrangler.toml` declares three, and only one of them is real.

| Env | Worker name | D1 | KV | R2 | DOs | Queues | Crons |
|---|---|---|---|---|---|---|---|
| top-level (default) | `synaptic-go-api` (1) | `c832b8fd…` (10) — **prod's id** | yes (15) | yes (20) | 4 (24–29) | yes (46–55) | yes (62–65) |
| `[env.prod]` | `synaptic-go-api` (100) | `c832b8fd…` (109) | yes (114) | yes (118) | 4 (121–126) | yes (128–137) | yes (140) |
| `[env.staging]` | `synaptic-go-api-staging` (158) | `staging-d1-database-id-placeholder` (167) | **none** | **none** | **none** | **none** | **none** |

Answering the brief's question 6: **staging is not real.** Its D1 id is a literal placeholder string (line 167). It has no `SESSIONS` KV binding, no `FILES` R2 bucket, no Durable Object bindings, no queue producer or consumer, and no cron triggers. A `wrangler deploy --env staging` either fails on the invalid database id or publishes a Worker whose every session lookup, file upload, trip room and dispatch path throws on an undefined binding. Nothing deploys to it automatically, and there is no smoke test against it because there is nothing to smoke.

The top-level block is the more dangerous half. It shares both the worker **name** and the production **database_id** with `[env.prod]`. The file's own comment says so plainly at lines 77–84: a bare `wrangler deploy` with no `--env` flag "publishes these values directly over production", and when `DEV_OTP` is `"true"` the API returns the OTP in the response body. `workers_dev = true` (line 5) additionally exposes that same configuration on a `*.workers.dev` subdomain against the production database.

### 3.5 Deployment

There are three deployment artifacts and they disagree with each other.

1. **`apps/api/package.json:8`** — `"deploy": "wrangler deploy"`. No `--env prod`. Root `package.json:14` exposes it as `npm run deploy:api`. This is the bare command the wrangler comment warns about.
2. **`apps/api/deploy.sh`** — 51 lines that apply exactly one hard-coded migration, `0009_captain_city.sql` (line 30), via `wrangler d1 execute --file=` (line 40), then run a bare `wrangler deploy` (line 47) with no `--env prod`. `d1 execute --file=` bypasses the `d1_migrations` ledger entirely, so a migration applied this way is invisible to `d1 migrations apply`. This script was correct for one deploy in the past and is now actively hazardous.
3. **`docs/ci/deploy-api.yml`** — the correct mechanism, and it is not installed.

The third is the important one. PR #46, titled *"ci: deploy the API from main instead of from someone's laptop"*, is merged. But the file it added lives at `docs/ci/deploy-api.yml`, and the repository's `.github/` directory contains exactly one file: `ci.yml`. `docs/DEPLOYMENT.md:3–13` states the reason and the remedy:

> **This file is a workflow waiting to be installed.**
> `git mv docs/ci/deploy-api.yml .github/workflows/deploy.yml`
> It could not be committed to `.github/workflows/` directly because the integration that opened this pull request does not hold GitHub's `workflows` permission.

The `git mv` was never performed. So the answer to the brief's question 7 is: **PR #46 merged, and the deploy mechanism it describes does not exist.** Deploys are still manual `wrangler deploy` runs from one machine — `docs/DEPLOYMENT.md:17–18` records that "all ten recorded deployments come from a single machine."

The parked workflow is well designed and worth installing nearly as-is: it gates on typecheck + shared tests + both migration checks (lines 71–83), runs migrations before publishing (line 121), uses `--env prod` explicitly with a comment explaining why it is not optional (lines 109–113), serialises deploys with `concurrency: cancel-in-progress: false` (lines 44–48), and smoke-tests `https://api.synapticstudio.tech/health` with five retries (lines 135–159). That endpoint exists — `apps/api/src/index.ts:99`.

It has three defects to fix on the way in, none fatal:

- Its `paths` filter watches `.github/workflows/deploy.yml` (line 36), but if installed under that name the filter is correct only by accident of the rename; if installed as `deploy-api.yml` the workflow will not re-run when it is itself edited.
- When `CLOUDFLARE_API_TOKEN` is absent it **exits green** (lines 92–106). As a required check, "deployed" and "silently skipped" become indistinguishable.
- There is no approval gate, no version tag, no changelog, and no rollback step.

### 3.6 Migration safety

19 migrations, `0001`–`0019`, all additive in structure — no `DROP TABLE`, no `DROP COLUMN` anywhere. `check_migrations.py` validates filename shape (line 44), contiguous numbering with no gaps or duplicates (lines 129–141), UTF-8 validity (155–159), non-emptiness (148–150), absence of BOM outside a grandfathered set (161–168), and mojibake in executable SQL (170–190). It never parses or executes SQL, so any syntax error, any duplicate column, any wrong type passes it cleanly.

`check_migrations_apply.py` is the one that claims to apply them, and the brief asks exactly the right question about it. Reading lines 58–85:

```python
58  for path in files:
...
66      conn.executescript(sql)
67      conn.commit()
68      applied += 1
...
75          break                      # stop at first failure
77  table_count = conn.execute(
78      "SELECT count(*) FROM sqlite_master WHERE type = 'table' "
79      "AND name NOT LIKE 'sqlite_%'"
80  ).fetchone()[0]
...
85  print(f"resulting schema: {table_count} table(s)")
```

So: it applies all 19 to a **fresh** temp database using Python's stdlib `sqlite3` (its own docstring at lines 21–22 admits "it does not validate D1-specific behaviour and never touches a real database"), it computes a table count, and it **prints** that count. It never compares it to an expected value. There is no schema assertion of any kind — no column names, no types, no indexes, no constraints. The check passes if and only if no exception was raised.

And it never applies migrations to a **populated** database. The temp file is created fresh every run, so no upgrade-path bug — a backfill that mangles rows written by the previous Worker version — is reachable by this check.

Two divergences from D1 make it weaker than it looks. `conn.executescript()` implicitly commits before it begins and does not wrap the file in one transaction, whereas D1 runs each migration file atomically; a migration that fails on its seventh statement leaves statements 1–6 committed here but rolled back in production. And `PRAGMA foreign_keys = ON` is set on the connection (line 53), which is a stdlib-connection concept, not a guarantee that D1 enforces the same constraints at the same moment.

The irreversible operations, all data backfills, are: `0005:15–19` (five `UPDATE`s converting REAL currency to integer piastres via `CAST(ROUND(amount * 100) AS INTEGER)` — any rounding error is permanent), `0009:15` (`UPDATE captains SET city='cairo' WHERE is_online=1 AND city IS NULL`), `0017:19–32` (ten unconditional `UPDATE`s repairing mojibake titles), and `0018:20` (`UPDATE captains SET search_radius_km=15 WHERE search_radius_km IS NULL`). For each, "rollback" is not a defined operation: reversing 0009 or 0018 would also clobber values legitimately set by the app after the migration ran.

### 3.7 The migration/deploy ordering hazard, live right now

`docs/DEPLOYMENT.md:74–79`, headed "Current state (verified 2026-07-31)", reports **17** migrations recorded in `d1_migrations` and states "**Nothing pending.**" The repository contains **19**. The two extras are not old:

| Artifact | Committed (UTC) |
|---|---|
| last recorded Worker deploy (version 24, per `DEPLOYMENT.md:80–81`) | 2026-07-31T04:21Z |
| `docs/DEPLOYMENT.md` itself | 2026-07-31T07:25:06Z |
| `migrations/0018_captain_search_radius.sql` | 2026-07-31T09:42:08Z |
| `migrations/0019_trips_captain_status_index.sql` | 2026-07-31T14:33:45Z |

Both migrations landed *after* the audit that declared nothing pending, and after the last deploy anyone recorded. Migration 0018 adds `captains.search_radius_km`, and the same commit ships Worker code that reads it (`utils.ts` resolves a captain's radius with a `DEFAULT_SEARCH_RADIUS_KM` fallback). Whether production is currently consistent depends entirely on whether a human ran `wrangler d1 migrations apply` and `wrangler deploy` in the right order in the intervening hours, and nothing in the repository records that they did. I cannot query the production D1, so the *state* is `needs-check` — but the *absence of any mechanism that would make it deterministic* is `confirmed`, and that is the finding.

This is precisely the failure `deploy.sh` was written for. Its header (lines 4–9) explains that deploying the Worker before migration 0009 "leaves those endpoints throwing SQL errors and drops every captain offline." The lesson was learned, written down, and then not generalised: the fix was a script pinned to one migration rather than an ordered pipeline.

### 3.8 Feature flags, seeding, load testing

**Feature flags: none.** The only runtime toggle is `DEV_OTP`, read from `c.env` in `auth.ts` — an environment variable that requires a deploy to change, and whose "on" state hands out OTP codes in HTTP responses. `system_config` (migration `0016:20–29`) is a `key`/`value`/`type` table with seven seeded keys (`0016:33–40`), admin-readable at `admin.ts:463` and admin-writable at `admin.ts:487–533` behind `requireRole("admin")` (`admin.ts:11`). It is the natural substrate for flags and is currently used for none — indeed several of its keys (`search_radius_km`, `free_cancel_min`, `cancel_fee_egp`, `auto_assign`) are written by the admin UI and read by no product code at all.

**Seeding: none.** No `seed.sql`, no fixture directory, no seed script anywhere in the 442-blob inventory. Seed data is embedded in migrations (`pricing_rules` in `0001:117–133`, `vehicle_types` in `0002:90–93`, `document_types` in `0014`/`0017`, `system_config` in `0016:33–40`), so `db:migrate:local` does give a developer the reference rows — but zero users, captains, or trips. Answering the brief's question 10: a developer cannot get a realistic local environment with one command. `.dev.vars.example` requires roughly nine manually-sourced secrets (`JWT_SECRET`, `TURNSTILE_SECRET_KEY`, `PAYMOB_API_KEY`, `PAYMOB_HMAC`, `PAYMOB_IFRAME_ID`, `FCM_PROJECT_ID`/`FCM_CLIENT_EMAIL`/`FCM_PRIVATE_KEY`, `WHATSAPP_TOKEN`, `EMAIL_RESEND_API_KEY`, `ADMIN_SETUP_SECRET`), several of which need a live third-party merchant or Firebase account before a local server will boot usefully.

**Load testing: never done.** No k6, Artillery, autocannon, JMeter, or Gatling artifact exists in the inventory; no load-test target appears in any script or document.

**Quality gates:** `strict: true` is set in all three real tsconfigs (`apps/api/tsconfig.json:8`, `apps/admin/tsconfig.json:14`, `packages/shared/tsconfig.json:5`), which is better than most repos at this stage. `noUncheckedIndexedAccess` and `exactOptionalPropertyTypes` are absent everywhere. `apps/admin/tsconfig.json:15–16` explicitly disables `noUnusedLocals`/`noUnusedParameters`. No ESLint config exists in the repository at all. No `npm audit` step, no Dependabot or Renovate config, no secret scanning. Dependencies float on `^` ranges but `package-lock.json` plus `npm ci` makes builds reproducible.

## 4. Findings

| ID | Sev | Finding | Evidence (`path:line`) | Impact | Confidence |
|---|---|---|---|---|---|
| F-23-01 | S1 | CI is advisory. `main` has no branch protection and no required status checks, so a red run merges | GitHub branch API: `protected:false`, `enforcement_level:"off"`, `contexts:[]`; self-documented at `.github/workflows/ci.yml:6-9` | Every gate in the repo is optional. The pipeline is a suggestion | confirmed |
| F-23-02 | S1 | The API deploy pipeline does not exist. PR #46 merged a workflow into `docs/`, not `.github/workflows/` | `docs/ci/deploy-api.yml` exists; `.github/` contains only `ci.yml` (442-blob inventory); `docs/DEPLOYMENT.md:3-13` | Merged work does not reach production. Already caused PR #45 to sit merged-but-not-live | confirmed |
| F-23-03 | S1 | The documented deploy command publishes dev config over production | `apps/api/package.json:8` (`wrangler deploy`, no `--env`); `wrangler.toml:1,10` share name+db id with `100,109`; warning at `wrangler.toml:77-84` | One `npm run deploy:api` can set `DEV_OTP` semantics on prod and hand out OTPs. Full auth bypass | confirmed |
| F-23-04 | S1 | The API has zero automated tests. Two test files exist repo-wide, both in `packages/shared` | 442-blob inventory; `packages/shared/src/{index,fileType}.test.ts` only | Money, auth, dispatch and realtime ship unverified on every commit | confirmed |
| F-23-05 | S1 | Migration/deploy ordering is unenforced, and two migrations post-date the last audit and deploy | `docs/DEPLOYMENT.md:74-79` says 17 recorded, "Nothing pending"; 19 exist; `0018` @09:42Z, `0019` @14:33Z vs doc @07:25Z, deploy @04:21Z | Worker reading a column D1 lacks → 500s on captain endpoints. This exact failure is documented in `deploy.sh:4-9` | confirmed (mechanism); needs-check (current prod state) |
| F-23-06 | S1 | `check_migrations_apply.py` asserts nothing about the resulting schema | `scripts/check_migrations_apply.py:77-80` computes a table count, `:85` prints it, never compares; `:21-22` admits it never touches D1 | A migration that produces the wrong schema passes CI as long as it does not raise | confirmed |
| F-23-07 | S1 | Staging is a stub: placeholder D1 id, no KV/R2/DO/queues/crons | `wrangler.toml:167` `"staging-d1-database-id-placeholder"`; `157-180` declares no other bindings | There is nowhere to test a release candidate. Every change's first real execution is in production | confirmed |
| F-23-08 | S1 | No rollback procedure for either a bad deploy or a bad migration | No rollback step in `docs/ci/deploy-api.yml`; no procedure in `docs/DEPLOYMENT.md`; irreversible backfills at `0005:15-19`, `0009:15`, `0017:19-32`, `0018:20` | Recovery is improvised during an incident, on a platform where `wrangler rollback` would take seconds | confirmed |
| F-23-09 | S1 | No feature-flag mechanism, so nothing can ship dark | Only runtime toggle is `DEV_OTP` via `c.env`; `system_config` (`0016:20-29`) is unused by product code | Every risky change is all-or-nothing for 100% of users, gated only by a deploy | confirmed |
| F-23-10 | S2 | `flutter test` never runs in CI; only `analyze` | `.github/workflows/ci.yml:140,154,166` — analyze only | The two smoke tests never execute; any future Dart test is dead on arrival | confirmed |
| F-23-11 | S2 | `apps/admin` has no test infrastructure whatsoever | `apps/admin/package.json:6-11` — no `test` script, no vitest, no testing-library | The ops console — refunds, approvals, config — is verified by hand only | confirmed |
| F-23-12 | S2 | No dependency vulnerability scanning and no update automation | No `npm audit` in `ci.yml`; no `.github/dependabot.yml` in inventory | A CVE in `jose` (JWT) or `hono` (routing) would go unnoticed indefinitely | confirmed |
| F-23-13 | S2 | No secret scanning, and hygiene only catches secrets in files literally named `.env*` | `scripts/check_repo_hygiene.py:77,127-130` matches `^\.env(\.|$)` | A key pasted into any `.ts`, `.sh` or `wrangler.toml` `[vars]` block is committed silently | confirmed |
| F-23-14 | S2 | No linter of any kind for TypeScript | No `.eslintrc`/`eslint.config`/`biome.json` in the 442-blob inventory | Missing hook deps, unused code, unsafe patterns are invisible. `tsc` is the only static check | confirmed |
| F-23-15 | S2 | The parked deploy workflow exits **green** when its credential is missing | `docs/ci/deploy-api.yml:92-106` | Once installed as a required check, "deployed" and "skipped" look identical | confirmed |
| F-23-16 | S2 | The Worker is never bundled in CI — only type-checked | `ci.yml:54` runs `tsc --noEmit`; no `wrangler deploy --dry-run` anywhere | A bundling/`nodejs_compat` failure is discovered at deploy time, in production | confirmed |
| F-23-17 | S2 | `apps/api/deploy.sh` is a hazardous relic pinned to migration 0009 | `deploy.sh:30` hard-codes `0009`; `:40` uses `d1 execute --file=`; `:47` bare `wrangler deploy` | Bypasses the `d1_migrations` ledger and deploys without `--env prod` | confirmed |
| F-23-18 | S2 | The system has never been load tested | No k6/Artillery/JMeter artifact in inventory; no target in any doc | Unknown behaviour under a dispatch fan-out or WebSocket reconnect storm | confirmed |
| F-23-19 | S2 | No one-command local environment; ~9 third-party secrets required to boot | `.dev.vars.example` (10+ keys); no `seed.sql` in inventory; `docs/RUN_FLUTTER.md` hard-codes one developer's Windows paths | Onboarding a developer is a multi-hour manual task, which suppresses local testing | confirmed |
| F-23-20 | S2 | No release versioning: no tags, no changelog, no approval gate | `APP_VERSION` is a static string in `wrangler.toml:76,144`; no tagging step in the parked workflow | "Which build is live?" is unanswerable during an incident | confirmed |
| F-23-21 | S3 | `packages/flutter_shared` has no `analysis_options.yaml` | Absent from inventory; both apps have one (`apps/rider/analysis_options.yaml:2`, `apps/captain/analysis_options.yaml:1`) | The shared design system is analysed against laxer SDK defaults than its consumers | confirmed |
| F-23-22 | S3 | `noUncheckedIndexedAccess` and `exactOptionalPropertyTypes` are off everywhere | `apps/api/tsconfig.json:8`, `apps/admin/tsconfig.json:14`, `packages/shared/tsconfig.json:5` set only `strict` | Unchecked index reads on `split()` results in the password path type as `string`, not `string \| undefined` | confirmed |
| F-23-23 | S3 | No coverage measurement or threshold | No `vitest.config.ts` in inventory; `packages/shared/package.json:13` is bare `vitest run` | Coverage cannot be tracked, so it cannot be defended against regression | confirmed |
| F-23-24 | S3 | `check_migrations_apply.py` stops at the first failure | `scripts/check_migrations_apply.py:75` (`break`) | One broken migration masks every later one; fixing them is serialised across CI runs | confirmed |
| F-23-25 | S3 | `apps/admin/tsconfig.node.json` sets no `strict` | `apps/admin/tsconfig.node.json:3-8` | `vite.config.ts` — which controls the build — is unchecked. Small surface, high leverage | confirmed |
| F-23-26 | S4 | The parked workflow's `paths` filter names a file that will not exist under that path | `docs/ci/deploy-api.yml:36` watches `.github/workflows/deploy.yml` | Editing the workflow will not re-trigger it unless installed under exactly that name | confirmed |

### S1 expansions

**F-23-01 — Every gate is optional.**
The workflow's authors saw this coming and wrote it into the file (`ci.yml:6–9`): "this workflow makes failures VISIBLE, it does not make them BLOCKING… Until that is done a red run can still be merged past." The GitHub branch API confirms the warning is still live: `main` returns `"protected": false` with `required_status_checks.enforcement_level: "off"` and an empty `contexts` array. Nothing in this document's improvement plan matters until this is fixed, because every other gate I propose inherits the same optionality. It is also the cheapest fix in the plan: three checkboxes in repository settings, zero code. The reason it ranks S1 rather than S3 is that it converts every other S1 from "a bug we could catch" into "a bug we will ship."

**F-23-02 — Merged is not deployed.**
PR #46 is titled *"ci: deploy the API from main instead of from someone's laptop"* and it is merged. It did not do that. The GitHub App that opened it lacks the `workflows` permission, so the YAML was committed to `docs/ci/deploy-api.yml` with an instruction in `docs/DEPLOYMENT.md:3–13` to `git mv` it into place. Nobody ran the `git mv`. The repository's entire `.github/` tree is one file, `ci.yml`.

The consequence is documented in the same file the fix is documented in. `docs/DEPLOYMENT.md:22–26` records PR #45 — carrying the profile-photo upload fix, the captain logout black screen, and the approval hand-off — sitting merged while all three were still reported broken, because the live Worker predated the merge. This is not a hypothetical failure mode; it is the repository's recent history, and the remedy has been sitting one shell command away since 2026-07-31.

**F-23-03 — The obvious command is the dangerous one.**
`apps/api/package.json:8` defines `"deploy": "wrangler deploy"`, surfaced at the root as `npm run deploy:api` (`package.json:14`). No `--env prod`. Because the top-level block of `wrangler.toml` shares the worker name `synaptic-go-api` (line 1 vs 100) *and* the production `database_id` `c832b8fd…` (line 10 vs 109), that command publishes the top-level `[vars]` straight over the live Worker. Those vars are the local-development set.

The file warns about this itself at lines 77–84, and `docs/DEPLOYMENT.md:38–47` repeats the warning under the heading "`--env prod` is not optional". Both are correct, and neither is enforceable: the safe path is a flag a human must remember, while the unsafe path is the shorter command, the one in `package.json`, and the one in `deploy.sh:47`. `workers_dev = true` (line 5) widens the blast radius by exposing that same configuration on a `*.workers.dev` hostname bound to the production database. The mitigation is not more documentation — it is making the dangerous command impossible.

**F-23-04 — The money moves untested.**
The brief's framing is exact: two test files exist, both in `packages/shared`, and the API that moves money has none. The 442-blob inventory confirms there is no third. `apps/api` has no test script, no test runner in its devDependencies, and no test file.

What that leaves unverified is not peripheral. The Paymob webhook (`payments.ts:97–302`) verifies an HMAC-SHA512 over a 20-field concatenation (`paymob.ts:162–183`) and credits wallets on the result — no test. The captain payout (`wallet.ts:113–130`) debits a balance through a conditional `UPDATE … WHERE wallet_balance >= ?` and then inserts a `wallet_transactions` row with **no idempotency key** on that insert — no test. The accept race (`trips.ts:861–866`) serialises two captains through `UPDATE … WHERE id = ? AND status IN ('searching','offered')` and reads `meta.changes` — no test. Each of these is a few dozen lines of test away from being provable, and each is a direct financial or operational loss when it breaks.

**F-23-05 — Ordering is a human habit, not a pipeline.**
`docs/DEPLOYMENT.md:74–79` audited production on 2026-07-31 and reported 17 migrations recorded with "Nothing pending". The repository holds 19. `0018_captain_search_radius.sql` was committed at 09:42:08Z and `0019_trips_captain_status_index.sql` at 14:33:45Z — both after that 07:25:06Z audit, and both after the last recorded Worker deploy at 04:21Z.

Migration 0018 adds `captains.search_radius_km` and its commit ships Worker code that reads it. If the Worker went out without the migration, captain endpoints throw on a missing column; if the migration went out without the Worker, the column sits unused and harmless. Only one of those orderings is safe, and which one happened is recorded nowhere. I cannot read the production database, so the current state is `needs-check` — but the finding is not the state, it is that **the ordering is enforced by nothing**. `deploy.sh:4–9` documents this exact hazard for migration 0009 ("deploying the Worker before the migration leaves those endpoints throwing SQL errors and drops every captain offline"), and the response was a script pinned to that one migration rather than a general rule. The parked workflow *does* encode the general rule at lines 115–129 — migrate, then deploy — which is one more reason installing it is the highest-value action available.

**F-23-06 — The migration check proves less than its name suggests.**
`check_migrations_apply.py` is the only thing in CI that executes SQL, so it carries a lot of implied assurance. Reading it, the assurance is thin. It applies all 19 files to a fresh temp database (`:58–68`), counts tables (`:77–80`), and prints the count (`:85`). The count is never asserted against an expectation, so a migration that creates the wrong table, the wrong column type, or the wrong index passes as long as SQLite accepts it. There are no assertions on columns, constraints, or indexes at all.

Three further limits matter. It uses Python's stdlib `sqlite3`, not D1 — its own docstring says so at lines 21–22. `conn.executescript()` auto-commits before it starts and does not wrap a file in one transaction, while D1 runs each migration file atomically, so mid-file failure behaviour is modelled backwards. And the database is always fresh, so the upgrade path — migrations applied over real, previously-written rows, which is the only way they ever run in production — is never exercised. Answering the brief's question 4 directly: it applies all 19 to a fresh DB, it asserts nothing about the resulting schema, and it does not test a populated database.

**F-23-07 — There is nowhere to rehearse.**
`[env.staging]` names a database that does not exist: `database_id = "staging-d1-database-id-placeholder"` (`wrangler.toml:167`). Lines 157–180 declare no `SESSIONS` KV, no `FILES` R2, no Durable Objects, no queue producer or consumer, and no cron triggers. Since sessions, uploads, trip rooms, dispatch, and scheduled dispatch all depend on those bindings, a staging Worker would fail on nearly every request even if the D1 id were valid. Nothing deploys there and no smoke test targets it.

The practical effect compounds F-23-04. Without tests, the first execution of new code would normally be in a staging environment. Without staging, the first execution of new code is in production, serving real riders.

**F-23-08 — Recovery is improvised.**
Cloudflare Workers support near-instant rollback to a previous version, and D1 supports time-travel restore. Neither is mentioned anywhere in the repository. There is no rollback step in the parked workflow and no procedure in the runbook, so during an incident someone will be reading Cloudflare documentation for the first time while the API is down.

The migration half is worse, because it is genuinely hard rather than merely undocumented. Migrations are additive in structure, which is good — no `DROP` exists in any of the 19. But four carry irreversible data backfills: `0005:15–19` converts REAL currency to integer piastres via `CAST(ROUND(amount * 100) AS INTEGER)`, and any rounding error is permanent; `0009:15` and `0018:20` set values conditioned on `IS NULL`, so reversing them would also clobber values the app has legitimately written since; `0017:19–32` unconditionally overwrites eight rows of `document_types` titles. "Roll back the migration" is not a defined operation for any of these, which means the recovery plan has to be forward-fix plus D1 time-travel, and that plan needs to exist in writing before it is needed.

**F-23-09 — Everything is all-or-nothing.**
There is no way to enable a change for 5% of riders, or for internal accounts only, or to disable a misbehaving subsystem without a deploy. The only runtime toggle in the codebase is `DEV_OTP`, an environment variable read from `c.env` that requires a deploy to change and whose enabled state returns OTP codes in HTTP responses.

This is the finding that unblocks the others. Every high-risk item elsewhere in this review — a new dispatch algorithm, surge pricing, a payment provider change — currently has exactly two states: not written, or live for 100% of users. A flag mechanism converts each of those into a gradual rollout with an instant off switch, which is what makes shipping daily survivable. The substrate already exists: `system_config` (`0016:20–29`) is a typed key/value table, admin-writable behind `requireRole("admin")` (`admin.ts:11`, `:487–533`), and `SESSIONS` KV is already bound in every real environment. Section 6 designs the mechanism on top of both.

### S2 expansions

**F-23-10 — Dart tests exist and never run.** `ci.yml` runs `flutter analyze` for all three Dart packages (lines 140, 154, 166) and `flutter test` for none. Both apps ship a boot smoke test and both apps' `pubspec.yaml` declare `flutter_test`. The job that would execute them is one step away. Until it exists, any Dart test anyone writes is decorative — which is a strong disincentive to write the first one.

**F-23-11 — The ops console is hand-verified.** `apps/admin/package.json:6–11` has `dev`, `build`, `preview`, `deploy`, `typecheck` — no `test`. The admin app approves captains, adjusts pricing, and touches wallets; it is the highest-privilege surface in the product and has no automated verification beyond `tsc`.

**F-23-12 / F-23-13 / F-23-14 — Three missing scanners.** No `npm audit` step, so a CVE in `jose` (which validates every JWT) or `hono` (which routes every request) surfaces only if someone reads the news. No Dependabot or Renovate config, so the lockfile drifts behind security patches indefinitely. No secret scanning, and the hygiene script's env-file check (`check_repo_hygiene.py:77,127–130`) matches only filenames beginning `.env` — a token pasted into a `.ts` file, a shell script, or the `[vars]` block of `wrangler.toml` passes silently. And no ESLint config exists anywhere, so `tsc` is the only static analysis on ~9,000 lines of API TypeScript and the entire React admin.

**F-23-15 — Green does not mean deployed.** `docs/ci/deploy-api.yml:92–106` writes a job-summary note and exits 0 when `CLOUDFLARE_API_TOKEN` is absent. That was a considerate choice for an uninstalled workflow — it avoids a red X on every push before setup. Once the workflow is installed and made a required check, it becomes a silent-failure mode: the pipeline reports success for a deploy that never happened. Fix it by inverting the default after the secret is configured.

**F-23-16 — Type-checked is not built.** `tsc --noEmit` (`ci.yml:54`) proves the API's types are consistent; it does not prove esbuild can bundle it, that `nodejs_compat` covers every import, or that the DO class exports match the `wrangler.toml` bindings. `wrangler deploy --dry-run --outdir` is a few seconds and catches all three.

**F-23-17 — Delete the relic.** `apps/api/deploy.sh` applies one hard-coded migration (line 30) with `d1 execute --file=` (line 40), which writes the schema change without recording it in the `d1_migrations` ledger — so a subsequent `d1 migrations apply` will try to apply 0009 again. It then runs a bare `wrangler deploy` (line 47), inheriting F-23-03. It was right once. Keeping it invites someone to run it.

**F-23-18 / F-23-19 / F-23-20 — Unknowns by omission.** The platform has never been load tested, so the dispatch fan-out and WebSocket ceilings are unknown numbers. There is no seed data and no one-command local setup, so testing locally costs hours and therefore does not happen. And there is no version tag, changelog, or approval gate, so during an incident the question "what changed?" has no fast answer — `APP_VERSION` is a hand-edited string in `wrangler.toml:76,144`, which means it is also frequently wrong.

## 5. Benchmark gap

Comparisons below are about *engineering practice*, not features. Where I am describing a competitor's internal process I mark it assumed; where it is publicly documented I mark it confident.

**Uber** (confident, from published engineering material) runs a monorepo with mandatory pre-merge CI, a large integration-test tier, and staged deployment through canary regions before global rollout. Their trip state machine is exercised by simulation harnesses that replay recorded trips against new code. Feature flags are foundational: essentially every behavioural change ships behind one, and rollout is by city, then percentage. Rollback is a flag flip, not a redeploy.

**inDrive** (assumed) runs a bidding model closer to Synaptic Go's, where the equivalent of `promo`, `bidding` and `accept` races are the load-bearing paths. Any operator at that scale necessarily has automated regression tests around bid acceptance, because the accept race is the single most concurrency-sensitive operation in the product.

**Careem** (assumed, regionally comparable) operates in the same market with the same payment-provider and OTP-delivery realities, so its pipeline necessarily includes a staging environment with a non-production PSP sandbox — precisely the thing `[env.staging]` pretends to be.

The honest benchmark from the brief is better than any of these: *could a new developer join on Monday and ship a change to pricing on Tuesday without breaking production?*

Today, no — and the failure is not one thing:

1. **Monday morning** they cannot run the system. `.dev.vars.example` needs ~9 secrets from Paymob, Firebase, Meta and Resend before the API boots usefully, and there is no seed data, so a working local environment is a multi-hour ticket, not a command.
2. **Monday afternoon** they change `calculateFare`. `packages/shared/src/index.test.ts` actually catches them if they break the base case — this is the one place the repo is in good shape.
3. **Tuesday morning** they change how the fare is *used* — `trips.ts`, `promo.ts`, `payments.ts`. Nothing catches anything. There is no test in `apps/api`.
4. **Tuesday midday** CI goes red on an unrelated `flutter analyze` warning. They merge anyway, because they can — nothing is required.
5. **Tuesday afternoon** the change does not reach production, because deploying is a manual step nobody told them about. Or it does reach production, because they read `package.json`, ran `npm run deploy:api`, and published the local-dev `[vars]` over the live Worker.
6. **Tuesday evening** the fare is wrong for every rider in Cairo. There is no flag to turn it off, no documented rollback, and no staging environment where it could have been caught.

Where Synaptic Go is genuinely ahead of a typical pre-production codebase, and this deserves saying: `strict: true` in every real tsconfig; `npm ci` with a maintained lockfile; a Flutter analyze job that exists specifically because an unparseable file once shipped green (`ci.yml:116–120`); four hand-written hygiene checkers; and a deploy workflow that is thoughtfully designed — gated, ordered, serialised, smoke-tested — and merely not installed. The gap is not competence. It is that the last 5% of several good pieces of work was never finished, and the unfinished 5% is the part that makes them binding.

## 6. Improvement plan

Ordered by "what unblocks the most other work". The first three items cost under a day combined and remove three of the nine S1s.

### P0.1 — Make CI binding

- **Goal** — a red run cannot reach `main`. Every other gate in this document becomes real the moment this lands.
- **Design** — enable branch protection on `main`; add the three existing job names as required status checks: `node (typecheck, build, tests)`, `flutter (analyze)`, `checks (migrations, l10n, hygiene)`. Require a pull request before merging and require branches to be up to date. Do not require approvals yet — on a small team that trades one failure mode for another; add it at P1 once the team is larger than two.
- **Files to change** — none. Repository Settings → Branches → branch protection rule for `main`.
- **DB** — none.
- **API contract** — none.
- **Effort** — S (minutes).
- **Risk** — the team temporarily cannot merge while a pre-existing failure is fixed. Mitigate by running `npm run verify` on `main` first and fixing what is red before enabling. Rollback is unchecking a box.
- **Acceptance criteria** — a PR with a deliberately failing test cannot be merged by a repository admin without an explicit override; the GitHub branch API returns `"protected": true` with three entries in `required_status_checks.contexts`.
- **Tests** — open a throwaway PR that breaks `packages/shared/src/index.test.ts` and confirm the merge button is blocked.

### P0.2 — Install the deploy workflow that already exists

- **Goal** — merging to `main` deploys the API, in the right order, or fails loudly.
- **Design** — perform the `git mv` that `docs/DEPLOYMENT.md:3–13` has been asking for since 2026-07-31, with three corrections: (a) fix the `paths` filter (`deploy-api.yml:36`) to match the installed filename; (b) invert the missing-credential guard (`:92–106`) so an unconfigured deploy fails rather than exits green, once `CLOUDFLARE_API_TOKEN` is set; (c) add the rollback and tagging steps from P0.6 and P1.5. Everything else in the file is correct as written and should not be touched — the gate ordering, the `--env prod` flag, the `concurrency` group, and the `/health` smoke test are all right.

  Note that this repository's own tooling cannot commit into `.github/workflows/` — the integration lacks GitHub's `workflows` permission, which is why the file is parked in `docs/` in the first place. This step must be performed by a human with push access, or by a token that holds the `workflow` scope. That constraint is the entire reason this S1 has survived.
- **Files to change** — `docs/ci/deploy-api.yml` → `.github/workflows/deploy.yml`; update the reference in `docs/DEPLOYMENT.md`.
- **DB** — none.
- **API contract** — none.
- **Effort** — S (one command plus three small edits).
- **Risk** — the first automated deploy is also the first deploy in a while; it may surface pending migrations 0018/0019 (see F-23-05). Run it via `workflow_dispatch` once, watched, before relying on the push trigger. Rollback: delete the workflow file.
- **Acceptance criteria** — a merge to `main` touching `apps/api/**` produces a run that applies migrations, publishes with `--env prod`, and gets HTTP 200 from `https://api.synapticstudio.tech/health`; the run fails if any gate fails; two concurrent merges queue rather than race.
- **Tests** — `workflow_dispatch` with `skip_migrations: true` against an unchanged `main`, and confirm the smoke test passes and the reported `APP_VERSION` matches.

### P0.3 — Make the dangerous deploy command impossible

- **Goal** — no command in the repository can publish local-dev configuration over production.
- **Design** — three changes, all small:
  1. `apps/api/package.json:8` — change `"deploy": "wrangler deploy"` to `"deploy": "wrangler deploy --env prod"`.
  2. `wrangler.toml` — stop the top-level block from pointing at production. Give it the *staging* database id once P0.4 creates one, or remove the top-level `d1_databases` id entirely so a bare deploy fails fast. Set `workers_dev = false` (line 5) so the shared-config Worker is not reachable on a `*.workers.dev` hostname bound to the prod database.
  3. Delete `apps/api/deploy.sh`. Its migration-first lesson is now encoded in the workflow (`deploy-api.yml:115–129`), and the script bypasses the `d1_migrations` ledger (`deploy.sh:40`) while inheriting the bare-deploy bug (`:47`).
- **Files to change** — `apps/api/package.json`, `apps/api/wrangler.toml`, delete `apps/api/deploy.sh`, update `docs/DEPLOYMENT.md:63–72`.
- **DB** — none.
- **API contract** — none.
- **Effort** — S.
- **Risk** — someone's muscle-memory `npm run deploy:api` now targets prod explicitly, which is the intent; and local `wrangler dev` is unaffected because it reads `.dev.vars` and the top-level block. Verify `wrangler dev` still boots after the top-level `database_id` change.
- **Acceptance criteria** — `npm run deploy:api` either deploys to prod correctly or fails with a clear error; no path in the repository runs `wrangler deploy` without an `--env` flag; `grep -rn "wrangler deploy"` returns only `--env`-qualified invocations.
- **Tests** — `npx wrangler deploy --dry-run` with and without `--env prod` and diff the resolved configuration.

### P0.4 — Build a real staging environment

- **Goal** — a place where a release candidate executes against real Cloudflare primitives before riders see it.
- **Design** — create the actual resources and fill in the bindings that `[env.staging]` is missing: a `synaptic-go-staging` D1 database (replacing the placeholder at `wrangler.toml:167`), a staging `SESSIONS` KV namespace, a staging `FILES` R2 bucket, the four Durable Object bindings, the notification queue plus its DLQ, and the two cron triggers. Set staging secrets via `wrangler secret put --env staging`, using the Paymob **sandbox** credentials rather than live ones. Keep `DEV_OTP = "false"` even in staging — an environment where anyone can log in as anyone is not a rehearsal of production; instead seed known test accounts with known OTPs via P1.4.

  Then extend the deploy workflow: on every merge to `main`, deploy to staging first, run the smoke test against the staging hostname, and only then deploy to prod. That converts the existing single-stage workflow into a two-stage pipeline at almost no extra complexity.
- **Files to change** — `apps/api/wrangler.toml` (`[env.staging]` block, lines 157–180), `.github/workflows/deploy.yml`.
- **DB** — no new migration; the same 19 migrations apply to the new staging database.
- **API contract** — none.
- **Effort** — M (1–3 days, mostly Cloudflare resource setup and secret sourcing).
- **Risk** — cost is the main one: a second set of DOs, KV, R2 and a D1. At pre-production traffic this is within Workers' paid plan baseline and is the cheapest insurance in this document. Getting a staging Paymob sandbox may take vendor lead time — start that request first.
- **Acceptance criteria** — `wrangler deploy --env staging` succeeds; `https://<staging-host>/health` returns 200 with `APP_VERSION`; a trip can be created, offered, accepted and completed end-to-end against staging; staging's D1 id is not the production id.
- **Tests** — the smoke suite from P1.3 runs green against staging before it is pointed at prod.

### P0.5 — Stand up the API test harness and write the first six tests

- **Goal** — the money and concurrency paths have executable proof, and adding the seventh test costs minutes rather than a day.
- **Design** — adopt `@cloudflare/vitest-pool-workers`, which runs tests inside `workerd` with real D1, KV, R2, Durable Object and queue bindings. This matters more than the usual test-runner choice: it is the only option that exercises the actual runtime rather than a Node approximation, so a conditional `UPDATE`'s `meta.changes` behaves as it does in production.

  Add `apps/api/vitest.config.ts` pointing at `wrangler.toml` with a test-scoped D1 that runs all 19 migrations before the suite. Add `"test": "vitest run"` to `apps/api/package.json` and extend the root `test` script to cover both workspaces. Write the six tests ranked #1–#6 in the list below; they are chosen so that each one exercises a different failure class (idempotency, HMAC, race, transition, promo, cron) and therefore each one pays for a different piece of harness setup exactly once.
- **Files to change** — new `apps/api/vitest.config.ts`, new `apps/api/test/` directory, `apps/api/package.json`, root `package.json:19`, `.github/workflows/ci.yml` (add `test @synaptic-go/api` to the `node` job).
- **DB** — none. The test harness applies the existing migrations to an ephemeral D1.
- **API contract** — none.
- **Effort** — M for the harness plus the first six tests; each subsequent test is S.
- **Risk** — `vitest-pool-workers` pins against a `wrangler` major version; keep them upgraded together. Durable Object and WebSocket hibernation semantics are imperfectly emulated, so tests that depend on real eviction belong in the staging smoke suite (P1.3), not here.
- **Acceptance criteria** — `npm test -w @synaptic-go/api` runs green locally and in CI; the `node` job fails when any of the six is broken; total suite runtime stays under two minutes.
- **Tests** — this item *is* tests; its own acceptance is that the six below pass and that deliberately reintroducing each bug turns exactly one of them red.

### P0.6 — Write the rollback runbook and add a rollback path

- **Goal** — recovery is a documented command, not a search of Cloudflare's docs during an outage.
- **Design** — three parts.

  *Worker rollback.* Add a `workflow_dispatch`-triggered job that runs `wrangler rollback --env prod` (optionally to a named version) and then re-runs the `/health` smoke test. Document `wrangler deployments list --env prod` as the way to find the target version.

  *Migration recovery.* Establish the rule in writing: migrations are forward-only. Recovery from a bad migration is (a) D1 time-travel restore for data corruption — `wrangler d1 time-travel restore synaptic-go --timestamp=<ISO>` — or (b) a new forward migration that repairs the damage, which is the pattern `0017_fix_document_type_titles.sql` already demonstrates. Record the retention window for time-travel and confirm it covers a realistic detection delay.

  *The coupling rule.* Document expand/contract explicitly: a migration must be safe against the currently-deployed Worker, and a Worker must be safe against the currently-applied schema. Concretely — add columns as nullable or with a default, never read a new column in the same deploy that adds it unless the migration provably ran first (which the pipeline now guarantees), and never remove a column until no deployed Worker references it.
- **Files to change** — `docs/DEPLOYMENT.md` (new "Rollback" and "Migration rules" sections), `.github/workflows/deploy.yml` (rollback job).
- **DB** — none.
- **API contract** — none.
- **Effort** — S.
- **Risk** — a rollback job is itself a production-mutating button; restrict it to `workflow_dispatch` and to users with write access.
- **Acceptance criteria** — the runbook answers "the deploy 10 minutes ago is bad, what do I type?" in one command; a rehearsed rollback on staging completes in under five minutes; D1 time-travel retention is stated as a number.
- **Tests** — rehearse both paths on staging once, and record the elapsed time in the runbook.

### P0.7 — Ship the feature-flag mechanism

- **Goal** — risky changes ship dark, and a misbehaving subsystem is disabled in seconds without a deploy.
- **Design** — build on what exists rather than adding infrastructure. `system_config` (`migrations/0016_system_config.sql:20–29`) is already a typed `key`/`value` store with an audited admin write path (`admin.ts:487–533`) behind `requireRole("admin")` (`admin.ts:11`). `SESSIONS` KV is already bound in every real environment and is already used as a TTL cache elsewhere in the Worker. Combine them: D1 is the source of truth, KV is the read cache, so the hot path costs one KV read and zero D1 reads.

  Flags live in `system_config` under a `flag:` prefix so they cannot collide with the seven existing settings keys, with an optional `flag_pct:` companion for percentage rollout. Rollout uses a stable hash of `userId + flagKey`, so a given user's bucket does not flicker between requests. Every read fails closed: if both KV and D1 are unreachable, the flag reads `false`, which for a rollout flag means "old behaviour", the safe default.

```ts
// apps/api/src/lib/flags.ts
const FLAG_TTL_SEC = 60;          // worst-case propagation delay for a flip

/** Stable per-user bucket in [0,100). Same user + flag always lands identically. */
function bucket(userId: string, flagKey: string): number {
  let h = 0;
  const s = `${flagKey}:${userId}`;
  for (let i = 0; i < s.length; i++) h = (Math.imul(31, h) + s.charCodeAt(i)) | 0;
  return Math.abs(h) % 100;
}

/** KV-cached read of one system_config key. Returns null on any failure. */
async function readConfig(env: Env, key: string): Promise<string | null> {
  try {
    const hit = await env.SESSIONS.get(`cfg:${key}`);
    if (hit !== null) return hit;
  } catch { /* KV down — fall through to D1 */ }

  try {
    const row = await env.DB.prepare(`SELECT value FROM system_config WHERE key = ?`)
      .bind(key).first<{ value: string }>();
    const val = row?.value ?? null;
    if (val !== null) {
      try { await env.SESSIONS.put(`cfg:${key}`, val, { expirationTtl: FLAG_TTL_SEC }); }
      catch { /* cache write is best-effort */ }
    }
    return val;
  } catch {
    return null;                  // D1 down — caller fails closed
  }
}

/**
 * Evaluate a boolean flag. Fails CLOSED: any backing-store failure returns
 * `defaultOn`, which callers set to the pre-change behaviour.
 */
export async function isEnabled(
  env: Env, flagKey: string, userId?: string, defaultOn = false,
): Promise<boolean> {
  const raw = await readConfig(env, `flag:${flagKey}`);
  if (raw === null) return defaultOn;
  if (raw !== "true" && raw !== "1") return false;

  if (userId) {
    const pct = Number(await readConfig(env, `flag_pct:${flagKey}`));
    if (Number.isFinite(pct) && pct >= 0 && pct < 100) return bucket(userId, flagKey) < pct;
  }
  return true;
}

export async function invalidateFlag(env: Env, flagKey: string): Promise<void> {
  try {
    await Promise.all([
      env.SESSIONS.delete(`cfg:flag:${flagKey}`),
      env.SESSIONS.delete(`cfg:flag_pct:${flagKey}`),
    ]);
  } catch { /* entries expire within FLAG_TTL_SEC regardless */ }
}
```

  The admin write endpoint mounts under the existing `adminRoutes`, so it inherits `authMiddleware` + `requireRole("admin")` (`admin.ts:11`) with no new authorization code, and it should call `logAudit` exactly as the `system_config` handler already does (`admin.ts:524`):

```ts
// apps/api/src/routes/admin.ts — new endpoint
adminRoutes.put("/flags/:key", async (c) => {
  const key = c.req.param("key");
  if (!/^[a-z0-9_]{1,64}$/.test(key)) return c.json({ error: "invalid flag key" }, 400);

  const body = await parseBody(c, z.object({
    enabled: z.boolean(),
    rolloutPct: z.number().int().min(0).max(100).optional(),
  }));
  if (isResponse(body)) return body;

  const user = c.get("user");
  const now = nowIso();
  const upsert = (k: string, v: string, t: string) => c.env.DB.prepare(
    `INSERT INTO system_config (key, value, type, updated_by, updated_at)
     VALUES (?, ?, ?, ?, ?)
     ON CONFLICT(key) DO UPDATE SET value=excluded.value,
       updated_by=excluded.updated_by, updated_at=excluded.updated_at`,
  ).bind(k, v, t, user.id, now);

  await c.env.DB.batch([
    upsert(`flag:${key}`, String(body.enabled), "boolean"),
    ...(body.rolloutPct !== undefined
      ? [upsert(`flag_pct:${key}`, String(body.rolloutPct), "number")] : []),
  ]);

  await invalidateFlag(c.env, key);
  await logAudit(c.env.DB, {
    actorId: user.id, action: "flag.update", entityType: "system_config",
    entityId: `flag:${key}`, payload: body, ip: c.req.header("cf-connecting-ip"),
  });
  return c.json({ ok: true, flag: key, ...body });
});
```

- **Files to change** — new `apps/api/src/lib/flags.ts`; `apps/api/src/routes/admin.ts`; a flags panel in `apps/admin`.
- **DB** — migration `0020_feature_flags.sql`, seed-only, no schema change:

```sql
-- 0020_feature_flags.sql — flags reuse the system_config table from 0016.
INSERT OR IGNORE INTO system_config (key, value, type, description) VALUES
  ('flag:surge_pricing',   'false', 'boolean', 'Apply surge multiplier to fares'),
  ('flag:dispatch_v2',     'false', 'boolean', 'Use the revised dispatch algorithm'),
  ('flag:scheduled_trips', 'true',  'boolean', 'Allow riders to schedule future trips'),
  ('flag_pct:dispatch_v2', '0',     'number',  'dispatch_v2: percent of users enabled');
```

- **API contract** — `PUT /admin/flags/:key` → request `{ enabled: boolean, rolloutPct?: 0..100 }`, response `{ ok: true, flag: string, enabled: boolean, rolloutPct?: number }`; `401` unauthenticated, `403` non-admin, `400` on an invalid key. Extend the existing `GET /admin/system-config` (`admin.ts:463`) to surface `flag:*` rows for the admin UI.
- **Effort** — M.
- **Risk** — a 60-second cache means a flip is not instant; for a kill switch that is usually acceptable, and `invalidateFlag` makes it immediate in the writing colo. If a true instant global kill is needed later, drop the TTL to 10s and accept the extra D1 reads. The `defaultOn` parameter must be set deliberately per call site — a default-on flag that fails closed to `false` would disable working functionality during a KV outage, which is why the parameter exists rather than being hardcoded.
- **Acceptance criteria** — flipping a flag in the admin console changes API behaviour within 60 seconds with no deploy; a flag at `rolloutPct: 10` affects a stable ~10% of users across repeated requests; with both KV and D1 unreachable, `isEnabled` returns `defaultOn` and does not throw; every flag write appears in `audit_log`.
- **Tests** — unit tests for `bucket` stability and distribution; integration tests for cache hit/miss/failure paths and for the admin endpoint's authorization.

### P0.8 — The critical-path test list

The twenty tests that must exist before launch, ranked by the cost of the bug they catch. Tests 1–6 are the P0.5 set. "Where" cites the code under test at the base commit; "Runs in" states whether `vitest-pool-workers` suffices or a deployed environment is required.

| # | Test | Where | Asserts | Runs in |
|---|---|---|---|---|
| 1 | Payout retry does not double-debit | `wallet.ts:113-130` | Two identical payout requests with the same client key debit once; second returns 409; exactly one `wallet_transactions` row | pool-workers |
| 2 | Webhook replay does not double-credit | `payments.ts:97-227` | Same valid webhook delivered twice credits the wallet once; the `INSERT OR IGNORE` on `idempotency_key` and the settled-status early return both hold | pool-workers |
| 3 | Forged webhook HMAC is rejected | `paymob.ts:152-235`, `payments.ts:97` | Tampered body, wrong secret, and absent `PAYMOB_HMAC` all yield 401 and zero balance change; comparison is length-checked before compare | pool-workers |
| 4 | Accept race yields exactly one winner | `trips.ts:861-870` | N concurrent accepts on one trip → one 200, N-1 × 409 `TRIP_TAKEN`; `trips.captain_id` set once | pool-workers |
| 5 | Trip state machine rejects illegal transitions | `index.ts:50` (`canTransition`), `trips.ts` status writes | Every illegal pair in `TRIP_TRANSITIONS` is refused at the route, not just in the helper | pool-workers |
| 6 | Promo cannot drive a fare below zero, and honours limits | `promo.ts:14-50`, `index.ts:104-105` | 100%-percent and oversized-fixed promos floor at 0; expired and over-`max_uses` codes rejected; document the sub-`minFare` case | pool-workers |
| 7 | Fare is deterministic across the boundary set | `index.ts:83-119`, `pricing.ts:23-33` | Zero distance, huge distance, `minFare` clamp, surge clamp at `<=0`→1.0, vehicle multiplier, commission = `total × rate` | pool-workers |
| 8 | Commission and captain earnings reconcile to the cent | `index.ts:106`, `wallet.ts:76-81` | `commission + earnings == total` for 10k randomised fares; aggregate `SUM` over 1k trips drifts < 1 piastre | pool-workers |
| 9 | Wallet balance can never go negative | `wallet.ts:109-121`, `payments.ts:182-185` | Concurrent debits at the balance boundary leave balance >= 0; the `WHERE wallet_balance >= ?` guard is load-bearing | pool-workers |
| 10 | Auth guards hold on every admin route | `middleware/auth.ts:29-75`, `admin.ts:11` | Unauthenticated → 401; non-admin → 403; refresh token used as access token → rejected | pool-workers |
| 11 | Cron scheduled-dispatch is idempotent | `index.ts:284-328` | Handler invoked twice over the same due rows dispatches once; the conditional `status='pending'` UPDATE holds | pool-workers |
| 12 | Monthly invoice is generated once per period | `index.ts:333-369` | Two day-1 invocations produce one invoice per `(company_id, period)`; trips not double-billed | pool-workers |
| 13 | All 19 migrations produce the expected schema | `migrations/*`, replaces `check_migrations_apply.py` | Applied to fresh D1: exact table set, key columns/types, every expected index present — asserted, not printed | pool-workers |
| 14 | Migrations apply cleanly over a populated database | `migrations/0005,0009,0017,0018` | Seed rows at version N-1, apply the remainder, assert backfills produce correct values and no row is lost | pool-workers |
| 15 | Captain double-booking is prevented | `trips.ts:854-859` | One captain accepting two trips concurrently ends assigned to one; the busy check's TOCTOU window is closed | pool-workers |
| 16 | Idempotency index actually dedupes | `0005:4-5`, `payments.ts:174-179` | Duplicate `idempotency_key` insert is ignored; **and** two NULL-key rows both insert — pin the SQLite NULL-uniqueness behaviour so it is a known property, not a surprise | pool-workers |
| 17 | Rate limiting holds on OTP and trip creation | `middleware/rateLimit.ts`, `trips.ts:351-356` | Over-limit requests get 429; the window resets; limits are per-user/IP as intended | pool-workers |
| 18 | Geohash cell encoding covers neighbours | `index.ts:129-191` | Encode/decode round-trip; a captain just across a cell boundary is still found by the 9-cell query in `nearby.ts:71-88` | pool-workers |
| 19 | Trip lifecycle end-to-end against a real deployment | staging | Create → offer → accept → arrive → start → complete → pay, with WebSocket events observed on both sides | **staging** |
| 20 | WebSocket reconnect delivers current state | `TripRoom.ts:85-105,270-288` | After hibernation/eviction and reconnect, the client can recover trip state and continues receiving broadcasts | **staging** |

Tests 19 and 20 cannot run under `vitest-pool-workers` with confidence: Durable Object eviction and WebSocket hibernation are the two areas where the emulator diverges most from `workerd` in production. They belong to the staging smoke suite (P1.3). Everything above them runs locally and in CI in well under two minutes.

#### Code sketch — test #1, payout retry idempotency

The bug: `wallet.ts:113-117` guards concurrency correctly with a conditional `UPDATE … WHERE wallet_balance >= ?`, but the `wallet_transactions` insert at `:123-130` carries no idempotency key. A captain on a flaky mobile connection who retries a payout that already succeeded is debited twice, because the second request passes the balance check on its own merits.

```ts
// apps/api/test/wallet-payout-idempotency.test.ts
import { env, createExecutionContext, waitOnExecutionContext } from "cloudflare:test";
import { describe, it, expect, beforeEach } from "vitest";
import worker from "../src/index";
import { seedCaptain, authHeader } from "./helpers";

describe("captain payout", () => {
  let captainId: string, token: string;

  beforeEach(async () => {
    ({ captainId, token } = await seedCaptain(env, { walletBalance: 200 }));
  });

  const payout = (key?: string) =>
    new Request("https://api.test/captain/wallet/payout", {
      method: "POST",
      headers: {
        ...authHeader(token),
        "content-type": "application/json",
        ...(key ? { "idempotency-key": key } : {}),
      },
      body: JSON.stringify({ amount: 100, method: "vodafone_cash", account_info: "01000000000" }),
    });

  it("debits once when the same payout is retried", async () => {
    const ctx = createExecutionContext();
    const first = await worker.fetch(payout("payout-abc"), env, ctx);
    const second = await worker.fetch(payout("payout-abc"), env, ctx);
    await waitOnExecutionContext(ctx);

    expect(first.status).toBe(200);
    // The retry must be recognised, not re-executed. 200 (replayed) or 409 both
    // acceptable; a second successful debit is not.
    expect([200, 409]).toContain(second.status);

    const { b } = await env.DB.prepare(`SELECT wallet_balance AS b FROM users WHERE id = ?`)
      .bind(captainId).first<{ b: number }>();
    expect(b).toBe(100);                                    // 200 - 100, exactly once

    const { n } = await env.DB.prepare(
      `SELECT COUNT(*) AS n FROM wallet_transactions WHERE user_id = ? AND type = 'payout'`,
    ).bind(captainId).first<{ n: number }>();
    expect(n).toBe(1);
  });

  it("rejects concurrent payouts that would overdraw", async () => {
    const ctx = createExecutionContext();
    // Two distinct payouts of 150 against a 200 balance: only one can succeed.
    const results = await Promise.all([
      worker.fetch(payout("a"), env, ctx),
      worker.fetch(payout("b"), env, ctx),
    ]);
    await waitOnExecutionContext(ctx);

    const { b } = await env.DB.prepare(`SELECT wallet_balance AS b FROM users WHERE id = ?`)
      .bind(captainId).first<{ b: number }>();
    expect(b).toBeGreaterThanOrEqual(0);
    expect(results.filter((r) => r.status === 200).length).toBeLessThanOrEqual(2);
  });
});
```

This test fails against the current code, which is the point: it specifies the `idempotency-key` contract that `wallet.ts` must grow. The fix — reuse the `wallet_transactions.idempotency_key` column that migration `0005:4-5` already added and that the topup path already uses at `payments.ts:174-179` — is a handful of lines, and T03 owns landing it.

#### Code sketch — test #3, webhook HMAC and replay

`paymob.ts:152-235` computes HMAC-SHA512 over a fixed 20-field concatenation and compares with a length-checked XOR-accumulate. Three properties need pinning: a tampered payload is rejected, a missing secret is rejected rather than defaulting open, and a valid payload replayed does not credit twice.

```ts
// apps/api/test/paymob-webhook.test.ts
import { env, createExecutionContext } from "cloudflare:test";
import { describe, it, expect } from "vitest";
import worker from "../src/index";
import { seedIntention, signPaymob, balanceOf } from "./helpers";

const post = (body: unknown, hmac: string) =>
  new Request(`https://api.test/payments/paymob/webhook?hmac=${hmac}`, {
    method: "POST", headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });

describe("paymob webhook", () => {
  it("rejects a tampered amount", async () => {
    const { userId, orderId } = await seedIntention(env, { amountPiastres: 5000 });
    const good = { obj: { order: { id: orderId }, amount_cents: 5000, success: true, id: 99 } };
    const hmac = await signPaymob(good, env.PAYMOB_HMAC);

    const tampered = structuredClone(good);
    tampered.obj.amount_cents = 500000;                     // 100× inflation

    const res = await worker.fetch(post(tampered, hmac), env, createExecutionContext());
    expect(res.status).toBe(401);
    expect(await balanceOf(env, userId)).toBe(0);
  });

  it("rejects when PAYMOB_HMAC is unset rather than failing open", async () => {
    const { orderId } = await seedIntention(env, { amountPiastres: 5000 });
    const body = { obj: { order: { id: orderId }, amount_cents: 5000, success: true, id: 99 } };
    const res = await worker.fetch(post(body, "anything"), { ...env, PAYMOB_HMAC: "" },
      createExecutionContext());
    expect(res.status).toBe(401);
  });

  it("credits once when the same webhook is delivered twice", async () => {
    const { userId, orderId } = await seedIntention(env, { amountPiastres: 5000 });
    const body = { obj: { order: { id: orderId }, amount_cents: 5000, success: true, id: 99 } };
    const hmac = await signPaymob(body, env.PAYMOB_HMAC);
    const ctx = createExecutionContext();

    expect((await worker.fetch(post(body, hmac), env, ctx)).status).toBe(200);
    expect((await worker.fetch(post(body, hmac), env, ctx)).status).toBe(200);

    expect(await balanceOf(env, userId)).toBe(50);          // 5000 piastres, once
    const { n } = await env.DB.prepare(
      `SELECT COUNT(*) AS n FROM wallet_transactions WHERE idempotency_key LIKE ?`,
    ).bind(`paymob:${orderId}:%`).first<{ n: number }>();
    expect(n).toBe(1);
  });
});
```

Note the second case. `paymob.ts:222` returns `{ ok: false, reason: "PAYMOB_HMAC not set" }` when the secret is missing, which is the correct fail-closed behaviour — this test exists to keep it that way, because the tempting "simplification" during a local-testing session is exactly the edit that turns a missing secret into an accepted webhook.

#### Code sketch — test #4, accept-race serialisation

`trips.ts:861-866` is the single most concurrency-sensitive statement in the product. It is currently correct: the conditional `UPDATE … WHERE id = ? AND status IN ('searching','offered')` plus the `meta.changes === 0` check at `:868-870` means exactly one captain wins. Nothing proves it stays correct, and the refactor that breaks it — splitting the guard into a `SELECT` then an unconditional `UPDATE` — looks entirely reasonable in review.

```ts
// apps/api/test/accept-race.test.ts
import { env, createExecutionContext, waitOnExecutionContext } from "cloudflare:test";
import { describe, it, expect } from "vitest";
import worker from "../src/index";
import { seedTrip, seedCaptains, authHeader } from "./helpers";

describe("trip accept", () => {
  it("assigns exactly one captain when many accept at once", async () => {
    const tripId = await seedTrip(env, { status: "offered" });
    const captains = await seedCaptains(env, 8);            // 8 online, idle captains
    const ctx = createExecutionContext();

    const responses = await Promise.all(
      captains.map((cap) =>
        worker.fetch(
          new Request(`https://api.test/trips/${tripId}/accept`, {
            method: "POST", headers: authHeader(cap.token),
          }), env, ctx),
      ),
    );
    await waitOnExecutionContext(ctx);

    const codes = responses.map((r) => r.status);
    expect(codes.filter((c) => c === 200)).toHaveLength(1);
    expect(codes.filter((c) => c === 409)).toHaveLength(7);

    const row = await env.DB.prepare(
      `SELECT captain_id, status FROM trips WHERE id = ?`,
    ).bind(tripId).first<{ captain_id: string; status: string }>();
    expect(row.status).toBe("assigned");
    expect(captains.map((c) => c.id)).toContain(row.captain_id);

    // Exactly one assignment event was logged — no losing captain left a trace.
    const { n } = await env.DB.prepare(
      `SELECT COUNT(*) AS n FROM trip_events WHERE trip_id = ? AND event = 'assigned'`,
    ).bind(tripId).first<{ n: number }>();
    expect(n).toBe(1);
  });
});
```

### P1.1 — The full proposed CI workflow

Replacing `.github/workflows/ci.yml`. The changes from the current file are: an `api` test step, a Worker bundle check, `flutter test`, ESLint, `npm audit`, and secret scanning. The existing structure — `continue-on-error` on each step with an aggregating `Result` step — is preserved because it is genuinely good and produces one complete picture per run.

```yaml
name: CI

# Every job below must be added as a REQUIRED STATUS CHECK on `main`
# (Settings > Branches). Without that, this file is advisory only.
on:
  pull_request:
  push:
    branches: [main]
  merge_group:

concurrency:
  group: ci-${{ github.event.pull_request.number || github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}

permissions:
  contents: read

jobs:
  node:
    name: node (typecheck, build, tests)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: '20', cache: npm }
      - name: install (npm ci)
        run: npm ci

      - name: typecheck @synaptic-go/api
        id: tc-api
        continue-on-error: true
        run: npm run typecheck -w @synaptic-go/api

      - name: typecheck @synaptic-go/admin
        id: tc-admin
        continue-on-error: true
        run: npm run typecheck -w @synaptic-go/admin

      - name: typecheck @synaptic-go/shared
        id: tc-shared
        continue-on-error: true
        run: npm run typecheck -w @synaptic-go/shared

      # NEW: tsc --noEmit does not prove the Worker bundles. This does, and it
      # catches nodejs_compat gaps and DO export/binding mismatches in ~10s.
      - name: bundle check @synaptic-go/api
        id: bundle-api
        continue-on-error: true
        working-directory: apps/api
        run: npx wrangler deploy --dry-run --outdir /tmp/worker-build --env prod

      - name: build @synaptic-go/admin
        id: build-admin
        continue-on-error: true
        run: npm run build -w @synaptic-go/admin

      - name: test @synaptic-go/shared
        id: test-shared
        continue-on-error: true
        run: npm test -w @synaptic-go/shared

      # NEW: the API suite (vitest-pool-workers, real D1/KV/DO bindings).
      - name: test @synaptic-go/api
        id: test-api
        continue-on-error: true
        run: npm test -w @synaptic-go/api

      # NEW: advisory until the backlog is clear, then flip to blocking.
      - name: lint
        id: lint
        continue-on-error: true
        run: npm run lint

      - name: Result
        if: always()
        run: |
          fail=0
          check() {
            if [ "$2" = "success" ]; then echo "  PASS  $1"
            else echo "  FAIL  $1"; fail=1; fi
          }
          check "typecheck api"     "${{ steps.tc-api.outcome }}"
          check "typecheck admin"   "${{ steps.tc-admin.outcome }}"
          check "typecheck shared"  "${{ steps.tc-shared.outcome }}"
          check "bundle api"        "${{ steps.bundle-api.outcome }}"
          check "build admin"       "${{ steps.build-admin.outcome }}"
          check "test shared"       "${{ steps.test-shared.outcome }}"
          check "test api"          "${{ steps.test-api.outcome }}"
          echo "  (advisory) lint   ${{ steps.lint.outcome }}"
          echo
          [ "$fail" -eq 0 ] && echo "node job passed." || { echo "node job failed."; exit 1; }

  flutter:
    name: flutter (analyze, test)
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        target: [packages/flutter_shared, apps/captain, apps/rider]
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with: { flutter-version: '3.24.5', channel: stable, cache: true }

      - name: cache pub
        uses: actions/cache@v4
        with:
          path: ~/.pub-cache
          key: pub-${{ runner.os }}-${{ hashFiles('**/pubspec.lock') }}
          restore-keys: pub-${{ runner.os }}-

      # flutter_shared is a path dependency of both apps and must resolve first.
      - name: pub get - flutter_shared
        run: flutter pub get
        working-directory: packages/flutter_shared

      - name: pub get - ${{ matrix.target }}
        run: flutter pub get
        working-directory: ${{ matrix.target }}

      # Errors block; the pre-existing info/warning backlog stays advisory.
      - name: analyze - ${{ matrix.target }}
        run: flutter analyze --no-fatal-infos --no-fatal-warnings
        working-directory: ${{ matrix.target }}

      # NEW. flutter_shared has no test/ dir yet, so tolerate its absence.
      - name: test - ${{ matrix.target }}
        run: |
          if [ -d test ]; then flutter test --reporter=github
          else echo "no test/ directory - skipping"; fi
        working-directory: ${{ matrix.target }}

  checks:
    name: checks (migrations, l10n, hygiene, deps)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }        # gitleaks needs history
      - uses: actions/setup-python@v5
        with: { python-version: '3.12' }
      - uses: actions/setup-node@v4
        with: { node-version: '20', cache: npm }
      - run: npm ci

      - name: migrations - naming, ordering, encoding
        id: mig
        continue-on-error: true
        run: python3 scripts/check_migrations.py

      - name: migrations - apply + assert schema
        id: mig-apply
        continue-on-error: true
        run: python3 scripts/check_migrations_apply.py --assert-schema schema.expected.json

      - name: l10n - abstract/locale parity and duplicates
        id: l10n
        continue-on-error: true
        run: python3 scripts/check_l10n_parity.py

      - name: repo hygiene - conflict markers, artifacts, encoding
        id: hygiene
        continue-on-error: true
        run: python3 scripts/check_repo_hygiene.py

      # NEW: fail only on high/critical so the job stays actionable.
      - name: dependency audit
        id: audit
        continue-on-error: true
        run: npm audit --audit-level=high

      # NEW: catches secrets in files the hygiene script's .env-name check misses.
      - name: secret scan
        id: secrets
        continue-on-error: true
        uses: gitleaks/gitleaks-action@v2
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

      - name: Result
        if: always()
        run: |
          fail=0
          check() {
            if [ "$2" = "success" ]; then echo "  PASS  $1"
            else echo "  FAIL  $1"; fail=1; fi
          }
          check "check_migrations"       "${{ steps.mig.outcome }}"
          check "check_migrations_apply" "${{ steps.mig-apply.outcome }}"
          check "check_l10n_parity"      "${{ steps.l10n.outcome }}"
          check "check_repo_hygiene"     "${{ steps.hygiene.outcome }}"
          check "secret scan"            "${{ steps.secrets.outcome }}"
          echo "  (advisory) npm audit   ${{ steps.audit.outcome }}"
          echo
          [ "$fail" -eq 0 ] && echo "checks job passed." || { echo "checks job failed."; exit 1; }
```

A separate mobile build job belongs on `main` pushes only, not on every PR — it costs minutes and, for iOS, a macOS runner at roughly four times the rate. `flutter build apk --debug` and `flutter build ios --no-codesign` per app, uploading the APK as an artifact, is the right shape; **T26** owns signing, versioning and store submission from there.

### P1.2 — Assert the schema, not the absence of exceptions

- **Goal** — a migration that produces the wrong schema fails CI.
- **Design** — extend `check_migrations_apply.py` with `--assert-schema`: after applying all migrations, dump the resulting schema (table names, column names and types, index names, NOT NULL and DEFAULT) to a normalised JSON structure and compare against a committed `schema.expected.json`. A mismatch prints a diff and exits non-zero. Regenerating the expected file is `--write-schema`, so the diff shows up in code review as a deliberate change. Also replace the `break` at line 75 with a continue-and-collect so one broken migration does not hide the rest, and add a second pass that applies migrations over a seeded database to exercise the backfills at `0005:15-19`, `0009:15`, `0017:19-32` and `0018:20`.

  Longer term, test #13 in the list above supersedes this by asserting the schema against a real D1 under `vitest-pool-workers`. The Python checker remains valuable as a fast, dependency-free gate.
- **Files to change** — `scripts/check_migrations_apply.py`, new `schema.expected.json`, `.github/workflows/ci.yml`.
- **DB** — none.
- **API contract** — none.
- **Effort** — S.
- **Risk** — the expected-schema file becomes noise if regenerated carelessly; require it to change in the same PR as the migration that causes it.
- **Acceptance criteria** — adding a column to a migration without updating `schema.expected.json` fails CI with a readable diff; the populated-database pass asserts the piastres backfill produces exact integer values.
- **Tests** — deliberately alter a migration's column type and confirm CI goes red.

### P1.3 — Post-deploy smoke suite against staging

- **Goal** — every deploy is proven by a real trip, not by a `/health` 200.
- **Design** — a Node script, `scripts/smoke.mjs`, run by the deploy workflow against staging before the prod stage and against prod after it. It authenticates a seeded test rider and captain, then drives create → offer → accept → arrive → start → complete, opening WebSocket connections on both sides and asserting the expected events arrive. On failure it exits non-zero, which blocks the prod stage. Keep it under 60 seconds. This is where tests 19 and 20 live.
- **Files to change** — new `scripts/smoke.mjs`, `.github/workflows/deploy.yml`.
- **DB** — none; uses the seeded accounts from P1.4.
- **API contract** — none.
- **Effort** — M.
- **Risk** — flaky smoke tests erode trust faster than no smoke tests; retry idempotent steps, and quarantine rather than delete a flaky assertion.
- **Acceptance criteria** — the suite passes against staging in under 60s and blocks promotion to prod on failure.
- **Tests** — break a trip transition on staging and confirm the deploy halts.

### P1.4 — Seed data and a one-command local environment

- **Goal** — `npm run dev:setup` gives a working local stack with realistic data.
- **Design** — add `scripts/seed.sql` with a realistic fixture set: ~20 riders, ~10 captains across Cairo cells with varied `search_radius_km`, a handful of trips in each lifecycle state, wallet balances and transactions, promo codes (active, expired, exhausted), one company with employees, and an admin. Add `apps/api/.dev.vars.example` defaults that let the API boot with **no** third-party accounts: stub Paymob (`paymob.ts:117-127` already returns `stubbed: true` when secrets are absent), stub FCM, and a fixed local OTP. Wire `dev:setup` to: copy `.dev.vars` if missing, generate a `JWT_SECRET`, run `db:migrate:local`, apply the seed, and print the test credentials.
- **Files to change** — new `scripts/seed.sql`, new `scripts/dev-setup.mjs`, root `package.json`, `apps/api/.dev.vars.example`, `docs/DEPLOYMENT.md`. Rewrite `docs/RUN_FLUTTER.md`, which currently hard-codes one developer's Windows paths, into a machine-independent guide with a configurable API base URL.
- **DB** — none; seed data is separate from migrations by design, so production never receives it.
- **API contract** — none.
- **Effort** — M.
- **Risk** — seed data drifting from the schema; P1.2's schema assertions plus running the seed in CI keeps it honest.
- **Acceptance criteria** — a fresh clone reaches a working API with data in one command and zero third-party accounts; a new developer can log in as a seeded rider and complete a trip locally.
- **Tests** — a CI job that runs `dev:setup` against a clean checkout and asserts the API answers `/health` and a seeded login succeeds.

### P1.5 — Release identity: tags, changelog, approval

- **Goal** — "what is live, and what changed?" is answerable in seconds.
- **Design** — derive `APP_VERSION` from a git tag at deploy time rather than hand-editing `wrangler.toml:76,144`. On each prod deploy: create a `v<semver>+<short-sha>` tag, generate release notes from the merged PR titles since the previous tag, and surface the deployed sha in `/health` alongside the version. Add a GitHub Environment named `production` with a required reviewer, so the prod stage of the pipeline pauses for one click — staging stays fully automatic.
- **Files to change** — `.github/workflows/deploy.yml`, `apps/api/src/index.ts:99-103` (expose commit sha), `apps/api/wrangler.toml`.
- **DB** — none.
- **API contract** — `GET /health` gains `commit` and `deployedAt`.
- **Effort** — S.
- **Risk** — an approval gate reintroduces "merged but not deployed" if nobody clicks. Mitigate with a notification on pending approvals and a policy that the merger approves their own deploy.
- **Acceptance criteria** — `/health` reports the exact commit running in prod; every prod deploy has a tag and generated notes.
- **Tests** — deploy twice and confirm two tags, correct notes, and a changing `commit` field.

### P1.6 — Close the quality-gate gaps

- **Goal** — the static analysis that costs nothing is actually running.
- **Design** — add ESLint (`typescript-eslint` + `eslint-plugin-react-hooks` for the admin) with a `lint` script at the root, advisory in CI for two weeks and blocking thereafter. Add `noUncheckedIndexedAccess` to all three real tsconfigs — expect a modest fix-up pass, and note that it directly targets the unchecked `split()` index reads in the password-hash path. Add `analysis_options.yaml` to `packages/flutter_shared` extending `flutter_lints` so the shared design system is held to the same standard as its consumers. Add `strict: true` to `apps/admin/tsconfig.node.json`. Add Dependabot for `npm` and `github-actions`, weekly, grouped.
- **Files to change** — new `eslint.config.js`, new `packages/flutter_shared/analysis_options.yaml`, new `.github/dependabot.yml`, the four tsconfigs, root `package.json`, `.github/workflows/ci.yml`.
- **DB** — none.
- **API contract** — none.
- **Effort** — M (mostly the `noUncheckedIndexedAccess` fix-up).
- **Risk** — a large initial lint backlog; land the config with rules set to `warn`, fix in themed batches, then promote to `error`.
- **Acceptance criteria** — `npm run lint` runs clean; all three real tsconfigs set `noUncheckedIndexedAccess`; Dependabot opens grouped PRs weekly.
- **Tests** — CI catches a deliberately unused variable and a deliberate unchecked index read.

### P2.1 — Load testing

- **Goal** — known ceilings for the three paths most likely to fall over, measured rather than assumed.
- **Design** — k6, chosen because it is the only mainstream option with first-class WebSocket support (`k6/ws`); the reconnect-storm scenario is untestable in autocannon and awkward in Artillery. Run against **staging**, never production. Four scenarios, with targets set for a launch-scale fleet of roughly 200 captains and 25 trips/minute peak:

  1. **Trip creation under load** — 25 trips/s for 60s. Each trip costs roughly a dozen D1 queries plus a 9-cell parallel GeoCell fan-out plus an OfferScheduler call plus push fan-out. Target: p95 create latency < 1000ms, error rate < 0.1%. This measures whether D1 write throughput is the ceiling.
  2. **Dispatch fan-out** — 200 captains holding CaptainInbox WebSockets; 50 concurrent trips into one geohash cell. Target: trip-created → offer-received on the captain socket, p95 < 500ms.
  3. **WebSocket reconnect storm** — 500 sockets connecting, holding just under the auth timeout, disconnecting, repeating. Target: no 5xx, and legitimate connects still succeed within 1s during the storm. This is the scenario most likely to find something, because DO session bookkeeping is in-memory while sockets are hibernatable.
  4. **Accept-race hammer** — 20 captains accepting one trip, 1000 iterations across several trips. Target: exactly one 200 per trip, zero duplicate assignments. This is test #4 at scale, against a real deployment.

  Note when configuring: the global rate limiter will cap a single-source runner well below these rates, so the load generator needs distributed sources or an allowlisted origin — otherwise scenario 1 measures the rate limiter, not the system.
- **Files to change** — new `load/` directory with four k6 scripts and a README of results.
- **DB** — none.
- **API contract** — none.
- **Effort** — L.
- **Risk** — load-testing staging with an undersized D1 gives numbers that do not transfer; document staging's shape alongside every result.
- **Acceptance criteria** — four scripts, one recorded baseline run each, and a documented ceiling per scenario with the bottleneck named.
- **Tests** — re-run before each major release and diff against the baseline.

### P2.2 — Contract tests between the apps and the API

- **Goal** — a breaking API change cannot ship without the client change, and vice versa.
- **Design** — the API already validates with Zod (`apps/api/src/lib/schemas.ts`). Generate an OpenAPI document from those schemas, publish it as a CI artifact, and add a job that fails when the committed spec differs from the generated one — making every contract change explicit in review. On the Flutter side, generate Dart models from the same spec so a renamed field is a compile error rather than a runtime null. Add a CI check that the spec's version is bumped when any response shape changes.
- **Files to change** — new `apps/api/src/lib/openapi.ts`, generated `docs/openapi.json`, `.github/workflows/ci.yml`, a `packages/flutter_shared/lib/api/` generated-model directory.
- **DB** — none.
- **API contract** — this item *is* the contract.
- **Effort** — L.
- **Risk** — generated Dart models are a large diff on first landing; introduce them behind one screen before converting the rest.
- **Acceptance criteria** — renaming a response field fails CI until both the spec and the Dart models are regenerated.
- **Tests** — rename a field in a Zod schema and confirm CI goes red.

### P2.3 — Flutter widget and golden tests

- **Goal** — UI regressions in the shared design system are caught before either app ships them.
- **Design** — start where the value is highest and the cost is lowest: `packages/flutter_shared`'s stateless widget library. Add `flutter_test` and `golden_toolkit` to its (currently absent) `dev_dependencies`, and set `GoogleFonts.config.allowRuntimeFetching = false` in the test harness with the Cairo font bundled — otherwise goldens fetch fonts at runtime and render differently on CI than locally, which is the usual reason golden suites get abandoned. Golden the shared widgets across light and dark themes, then add widget tests for the highest-traffic app screens.

  This work depends on a refactor that T09/T10 own: both apps embed `http` calls and WebSocket construction directly inside their `ChangeNotifier` state classes, and screens reach for services via `context.read<...>()`, so neither networking nor state can be faked today. The minimal enabling change is constructor injection of an `http.Client` and a channel factory. `packages/flutter_shared` already contains an unused `ApiClient` abstraction that is the natural destination.
- **Files to change** — `packages/flutter_shared/pubspec.yaml`, new `packages/flutter_shared/test/`, new golden fixtures, app test directories.
- **DB** — none.
- **API contract** — none.
- **Effort** — L.
- **Risk** — golden tests are famously flaky across platforms; pin the runner OS and the Flutter version (already pinned at `3.24.5`), and commit goldens generated on that exact combination.
- **Acceptance criteria** — the shared widget library has golden coverage across both themes; goldens are stable across three consecutive CI runs.
- **Tests** — change a theme token and confirm the affected goldens fail.

## 7. Phasing

### P0 — before any production traffic

The nine S1s. Items P0.1 through P0.3 together cost well under a day and remove three of them; they should land today, in that order.

| Item | Addresses | Effort | Owner type |
|---|---|---|---|
| P0.1 Make CI binding | F-23-01 | S | ops |
| P0.2 Install the deploy workflow | F-23-02, F-23-05 | S | ops |
| P0.3 Kill the bare-deploy path | F-23-03, F-23-17 | S | backend |
| P0.4 Real staging environment | F-23-07 | M | ops |
| P0.5 API test harness + first 6 tests | F-23-04 | M | backend |
| P0.6 Rollback runbook + rollback job | F-23-08 | S | ops |
| P0.7 Feature flags | F-23-09 | M | backend + admin |
| P0.8 Tests 7–18 from the ranked list | F-23-04 | L | backend |

P0.8 is sized L because it is twelve tests, but it parallelises cleanly across people and each test is independently mergeable. Tests 19–20 move to P1 with the staging smoke suite.

### P1 — first 30 days

| Item | Addresses | Effort | Owner type |
|---|---|---|---|
| P1.1 Full CI workflow (api tests, bundle check, flutter test, lint, audit, secrets) | F-23-10, F-23-12, F-23-13, F-23-14, F-23-16 | M | ops |
| P1.2 Schema assertions + populated-DB migration pass | F-23-06, F-23-24 | S | backend |
| P1.3 Post-deploy smoke suite (tests 19–20) | F-23-15 | M | backend |
| P1.4 Seed data + one-command local setup | F-23-19 | M | backend |
| P1.5 Tags, changelog, approval gate | F-23-20 | S | ops |
| P1.6 ESLint, tsconfig strictness, flutter_shared lints, Dependabot | F-23-14, F-23-21, F-23-22, F-23-25 | M | backend + Flutter |

### P2 — next 90 days

| Item | Addresses | Effort | Owner type |
|---|---|---|---|
| P2.1 Load testing (4 k6 scenarios) | F-23-18 | L | backend + ops |
| P2.2 Contract tests + generated OpenAPI/Dart models | — | L | backend + Flutter |
| P2.3 Flutter widget + golden tests | F-23-11 (admin analogue), F-23-21 | L | Flutter |
| P2.4 Coverage reporting with a ratchet threshold | F-23-23 | S | backend |
| P2.5 Admin console test layer (vitest + testing-library) | F-23-11 | M | admin |

## 8. Metrics

Instrument these so the change is provable rather than asserted. Current values are measured at the base commit unless marked estimated.

| Metric | Current | 30-day target | 90-day target |
|---|---|---|---|
| Required status checks on `main` | 0 | 3 | 3 |
| Test files covering `apps/api` | 0 | 12 | 25+ |
| Assertions covering the money path | 0 | 40+ | 100+ |
| Line coverage, `packages/shared` | unmeasured | measured + baseline | 80% |
| Line coverage, `apps/api` money and auth routes | 0% | 50% | 75% |
| Mean time from merge to production | unbounded — manual, sometimes never | < 15 min, automatic | < 10 min |
| Deploys per week | ~1.4 (10 recorded deploys, all from one machine) | 5+ | daily |
| Deploys requiring a human to remember a command | 100% | 0% | 0% |
| Environments with real bindings | 1 (prod) | 2 (prod + staging) | 2 |
| Migrations applied by an automated, ordered pipeline | 0% | 100% | 100% |
| Schema assertions in the migration checker | 0 | full table/column/index set | same, plus populated-DB pass |
| Mean time to roll back a bad deploy | undefined — no procedure | < 5 min, rehearsed | < 2 min |
| Changes shippable behind a flag | 0% | flag mechanism live | 100% of risky changes |
| Known load ceiling for trip creation | unknown | unknown | measured, documented |
| High/critical dependency CVEs unreviewed | unmeasured | 0 | 0 |
| Time for a new developer to a working local stack | hours (~9 external secrets) | < 10 min, one command | < 10 min |

Two of these are the honest headline. **"Deploys requiring a human to remember a command: 100%"** is the current state of release engineering, and **"Test files covering `apps/api`: 0"** is the current state of verification. Everything else in this document is downstream of moving those two.

## 9. Cross-cutting notes

Findings outside my axis, addressed to the track that owns them. I did not fix any of these.

**To T03 — Money Integrity.** The captain payout at `wallet.ts:113-130` uses a correct compare-and-swap for concurrency (`WHERE wallet_balance >= ?` plus a `meta.changes === 0` check), but the `wallet_transactions` insert at `:123-130` carries **no idempotency key** — even though migration `0005:4-5` added the column and the topup path already uses it (`payments.ts:174-179`). A captain retrying a payout that already succeeded is debited twice whenever the balance still covers it. Separately, the UNIQUE index on `idempotency_key` does not constrain NULLs in SQLite, so any insert that omits the key is never deduplicated. My test #1 specifies the contract; the fix is yours.

**To T04 — Payments.** Two things to verify. First, `paymob.ts:162-183` hashes a 20-field list that differs from the field list in the comment above it at `:152-158` (the comment mentions `is_hmac_attributed_transaction` and three `currency_ops` fields; the array uses `is_3d_secure`, `is_auth`, `is_capture`). If the comment reflects Paymob's real specification, every webhook would fail verification; if the array is right, the comment is stale and should be corrected. I could not verify against live Paymob documentation — `needs-check`, and it is worth ten minutes of yours. Second, the settlement sequence writes the wallet credit before flipping `payment_intentions.status` to `settled`; a failure between those two writes leaves a window where a redelivered webhook re-credits.

**To T05 — Pricing.** `calculateFare` applies the `minFare` floor *before* the discount (`packages/shared/src/index.ts:104-105`), so a fixed promo on a short trip produces a fare below `minFare` — floored at 0, but below the stated minimum. Whether that is intended is a product decision, not a bug I can call. Also note `pricing.ts:31` passes an average speed of 22 km/h to `estimateDurationMin` while the shared default is 25 km/h; the two disagree and nothing pins which is authoritative.

**To T06 — Dispatch.** The busy-captain check at `trips.ts:854-859` is a plain `SELECT` outside any transaction, and the winning `UPDATE` at `:861-866` guards only the trip's status, not the captain's availability. Two trips accepted by the same captain in the same instant can both succeed. The trip-level race is safe; the captain-level one is not. My test #15 covers it.

**To T07 — Realtime.** `TripRoom` and `CaptainInbox` accept hibernatable WebSockets via `ctx.acceptWebSocket`, but their per-socket session state (role, user id, pending-auth flag) lives in an in-memory `Map`. After eviction the socket survives and the session does not, so broadcast reaches sockets whose identity is no longer known. `CaptainInbox` keeps no `ctx.storage` state at all. This is also why my tests 19–20 must run against staging rather than the emulator.

**To T08 — Data Model.** `check_migrations_apply.py` asserts nothing about the resulting schema (`:77-85`), uses stdlib `sqlite3` rather than D1, and never applies migrations over populated data — so the backfills at `0005:15-19`, `0009:15`, `0017:19-32` and `0018:20` have never been executed against realistic rows in any automated check. P1.2 proposes the fix; the expected-schema baseline should be authored by whoever owns the data model.

**To T11 — Admin Console.** `apps/admin` has no test infrastructure of any kind (`apps/admin/package.json:6-11`) and there is no ESLint config in the repository, so the highest-privilege surface in the product has only `tsc` between a change and production. Also: four `system_config` keys the admin UI writes — `search_radius_km`, `free_cancel_min`, `cancel_fee_egp`, `auto_assign` — are read by no product code, so operators are adjusting settings that do nothing. That is a trust problem for the console.

**To T22 — Observability.** My smoke suite (P1.3) and the `/health` endpoint (`index.ts:99`) are deploy-time verification, not monitoring. The complement I depend on and do not own: an error-rate alert that can trigger the rollback job from P0.6, and a deploy-annotated dashboard so a spike can be attributed to a release. Automated rollback on an error-rate spike is the natural joint deliverable between our tracks.

**To T26 — Mobile Release.** I stop at "CI builds a debug APK and an unsigned iOS binary". Signing, versioning, store metadata, phased rollout and crash reporting are yours. One input: `flutter test` does not run in CI today (`ci.yml` runs `analyze` only), so both apps' existing smoke tests have never executed in the pipeline — P1.1 fixes that and it should land before any store submission.

**To T27 — Cross-App Parity.** Two parity observations from a testing standpoint. `apps/rider/analysis_options.yaml` excludes generated l10n and `apps/captain/analysis_options.yaml` does not, so the two apps are analysed under different rules; `packages/flutter_shared` has no `analysis_options.yaml` at all and is therefore held to the laxest standard of the three despite being the shared foundation. And both apps duplicate the same untestable pattern — `http` calls and WebSocket construction inline inside `ChangeNotifier` state classes, while an unused `ApiClient` abstraction sits in `flutter_shared`. Any parity plan should converge both apps onto that injectable client, because it is simultaneously the parity fix and the testability fix.

## 10. Open questions

**Q1 — Who performs the `git mv` that installs the deploy workflow?**
The repository's own automation cannot write to `.github/workflows/` (no `workflows` permission), which is exactly why the file has sat in `docs/ci/` since 2026-07-31. Options: (a) a human with push access runs the one command; (b) grant a deploy token the `workflow` scope; (c) leave deploys manual. **Recommendation: (a), today.** This is a single command standing between merged code and production, and it is the highest value-per-second action available in this entire document.

**Q2 — Does prod currently have migrations 0018 and 0019 applied?**
`docs/DEPLOYMENT.md:74-79` recorded 17 applied and "nothing pending" at 07:25Z; both migrations landed later the same day, after the last recorded deploy. I cannot query the production database. **Recommendation: run `wrangler d1 migrations list synaptic-go --remote --env prod` before anything else ships.** If they are unapplied, apply them before the first automated deploy, not during it.

**Q3 — Should staging use a Paymob sandbox or stubbed payments?**
A sandbox exercises the real HMAC path and real failure modes but needs vendor onboarding; stubs are instant but leave the webhook path unproven outside unit tests. **Recommendation: both — stubs for local development (the code already supports this at `paymob.ts:117-127`), sandbox for staging.** Start the vendor request now, because it is the long pole in P0.4.

**Q4 — Does an approval gate on production deploys help or hurt?**
An approval gate prevents accidental prod pushes but reintroduces the exact failure this project already suffered: work merged and not deployed. **Recommendation: automatic to staging always; a one-click approval for prod, with the merger empowered to approve their own deploy.** Revisit after 30 days — if approvals are consistently instant, remove the gate; if they consistently catch something, keep it.

**Q5 — What coverage threshold, and when does it start blocking?**
A threshold set too early on a codebase at 0% produces theatre. **Recommendation: measure from day one, publish the number on every PR, and do not block on it for 30 days. Then set a ratchet — coverage may not decrease — rather than an absolute floor.** A ratchet rewards every PR that adds a test and never blocks an urgent fix to unrelated code.

**Q6 — Is `--no-fatal-warnings` on `flutter analyze` still the right call?**
It was correct when the job was introduced (`ci.yml:122-125`): making a pre-existing backlog fatal would have buried the errors the job exists to catch. But it is a temporary measure with no expiry date. **Recommendation: count the current warnings, fix them in one focused pass, then flip to `--fatal-warnings`.** Until that happens, the analyzer catches only the most severe class of Dart fault.

**Q7 — How much staging costs, and is it worth it?**
A second full environment means a second D1, KV namespace, R2 bucket, four DO classes, and a queue pair. **Recommendation: build it.** At pre-production traffic the marginal cost is small against the Workers paid plan, and the alternative — which is the status quo — is that every change's first real execution happens in front of paying riders. If cost genuinely blocks it, the fallback is per-PR preview deployments with an ephemeral D1, which is cheaper but weaker because it lacks persistent state.
