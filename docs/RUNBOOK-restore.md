# RUNBOOK — restoring the GoDrive database

> **If you are reading this during an incident, go to [§3](#3-procedure-b--restore-a-dump-into-a-new-database).**
> Read §1 and §2 only if you do not yet know which kind of loss you are dealing with.

This runbook covers the D1 database `synaptic-go`, which holds wallet balances, the
`wallet_transactions` ledger, trips and payout requests. It exists because gate item 15 says a backup
nobody has restored is not a backup — finding **F-08-04 / S-015**, filed against the state where the
only recovery mechanism was platform-default Time Travel and nobody had ever run it.

Companion pieces:

| | |
|---|---|
| Taking a backup | `scripts/backup-d1.sh` |
| Deploying (and the migration ordering that matters here) | `docs/DEPLOYMENT.md` |
| Schema history | `migrations/` — 20 files as of this writing, `0001` … `0020` |

---

## 0. Rehearsal record

The acceptance criterion for this runbook is that someone has executed it. This table is that record.
**Add a row every time anyone runs a restore, drill or real.** A runbook whose last rehearsal is a
year old is back to being a claim.

| Date (UTC) | By | Kind | Target | Duration | Result |
|---|---|---|---|---|---|
| 2026-08-01 | `chat-20260801-2006-b2a8` (task E18, automated) | Drill — scratch SQLite built from `migrations/` | throwaway local DB | **0.136 s** total (0.068 s schema, 0.003 s export, 0.065 s restore) | **21/21 assertions passed.** 20 migrations → 37 tables, 29 seeded money rows, 25,276-byte dump; restored copy byte-identical to the origin across all 37 tables; `integrity_check` ok; `foreign_key_check` clean. Found the ordering trap in [§6](#6-the-foreign-key-ordering-trap). |
| _(not yet done)_ | _needs a human with production credentials_ | **Production rehearsal** — real `wrangler d1 export` → real restore into a scratch D1 database | scratch D1 | — | **Outstanding.** See [§7](#7-what-has-not-been-tested). This is the row that has to be filled before anyone claims gate item 15 is closed. |

Reproduce the drill at any time, from a clean checkout, with no credentials and no network:

```bash
./scripts/backup-d1.sh --rehearse
```

---

## 1. First: do not improvise

Three rules, in order of how much damage breaking them does.

1. **Do not run `wrangler d1 time-travel restore` as a first move.** It is an *in-place, destructive
   overwrite* of the live database. It does not make a copy, it does not ask twice, and everything
   written since your chosen timestamp is gone. It is a legitimate tool (§2, procedure A) but it is
   never the tool you reach for while you are still working out what happened.
2. **Do not restore on top of a database that has data in it.** Restore into a **new** database and
   compare. The drill asserts this: importing a dump over a populated schema fails with
   `table audit_log already exists`, which is the good outcome — the bad one is a half-merged
   database nobody can reason about.
3. **Take a backup of the broken state before you change it.** It is evidence, and twice now this
   repository's post-mortems have turned on what a table looked like *before* the fix.

```bash
./scripts/backup-d1.sh prod --keep-local ./incident-$(date -u +%Y%m%dT%H%M%SZ)
```

---

## 2. Which procedure

| Situation | Procedure | Destructive? |
|---|---|---|
| A few rows are wrong; the schema is fine | **C** — forward repair migration | No |
| A table was dropped or mass-corrupted, and you have a recent dump in R2 | **B** — restore the dump into a new database | No |
| The whole database is wrong as of a known moment, the moment is inside the Time Travel window, and you accept losing everything written since | **A** — Time Travel | **Yes, irreversibly** |

Migrations in this repository are **forward-only**. `0005`, `0009`, `0017` and `0018` contain
irreversible backfills; there is no `down` migration anywhere and none should be written. A mistake is
repaired by a further migration (C) or by a restore (B).

### Procedure A — Time Travel, and why it is last

```bash
npx wrangler d1 time-travel info synaptic-go --env prod          # what is even available
npx wrangler d1 time-travel restore synaptic-go --env prod --timestamp=<ISO8601>
```

Check the retention window with `info` rather than trusting a number in a document — it depends on
the plan and Cloudflare has changed it before. Time Travel's weakness is not its retention, it is
that **you cannot test it.** There is no "restore to a copy" mode, so the first time you run it in
anger is also the first time you have ever run it. That is the whole reason procedure B exists.

### Procedure C — forward repair

Write a new migration, take its number from `board/exec/MIGRATION-LOCK.md` (never from a directory
listing — two people will pick the same one), and ship it through `apps/api/deploy.sh`. State the
repair and its own rollback in the PR.

---

## 3. Procedure B — restore a dump into a NEW database

This is the default. Nothing live is touched until step 6, and step 6 is a separate decision.

### 3.1 Find the backup

```bash
npx wrangler r2 object get synaptic-go-backups/d1/synaptic-go/2026/08/01/ --remote   # browse
```

Objects are keyed `d1/<database>/<YYYY>/<MM>/<DD>/<database>-<YYYYMMDDTHHMMSS>Z.sql`, so they sort
chronologically. Each dump has a `.manifest.json` sibling recording its `sha256`, byte count, the repo
commit at backup time, and the list of migrations that were applied on the source database. **Read
the manifest first** — it tells you which schema the dump expects.

```bash
KEY=d1/synaptic-go/2026/08/01/synaptic-go-20260801T030000Z.sql
npx wrangler r2 object get "synaptic-go-backups/$KEY"                --file ./restore.sql      --remote
npx wrangler r2 object get "synaptic-go-backups/$KEY.manifest.json"  --file ./manifest.json    --remote
```

### 3.2 Verify the dump before you trust it

```bash
sha256sum ./restore.sql          # must equal .sha256 in manifest.json
./scripts/backup-d1.sh --check-dump ./restore.sql
```

`--check-dump` loads the file into a throwaway local database and reports the table list, the row
counts, the money totals and whether the dump can be replayed as-is. It touches nothing remote. If it
fails here, the backup is bad — **stop and pick an earlier one** rather than importing a broken file
into a fresh database and discovering it half way.

### 3.3 Create a new database

```bash
npx wrangler d1 create synaptic-go-restore-$(date -u +%Y%m%d)
```

Note the `database_id` it prints. **Do not reuse the production database.**

### 3.4 Load the schema from `migrations/`, not from the dump

This is the step that is not obvious, and it is the one the rehearsal exists to have found. **Read
[§6](#6-the-foreign-key-ordering-trap) if you want to know why**; the short version is that the dump
lists tables alphabetically, `audit_log` references `users`, and D1 will not let you switch foreign
keys off.

```bash
npx wrangler d1 migrations apply synaptic-go-restore-YYYYMMDD --remote
```

This gives you the correct schema in dependency order, and records it in `d1_migrations`. Confirm the
migration list matches `applied_migrations_remote` in the manifest. If the dump is older than the
current `migrations/`, apply only up to the migration the manifest names, then run the rest *after*
the data loads.

### 3.5 Load the data from the dump

Strip the schema statements and keep the inserts, bracketed by the deferral pragma:

```bash
{ echo "PRAGMA defer_foreign_keys = ON;"
  grep -E '^INSERT INTO' ./restore.sql | grep -v '^INSERT INTO "\?d1_migrations'
  echo "PRAGMA defer_foreign_keys = OFF;"
} > ./restore-data.sql

npx wrangler d1 execute synaptic-go-restore-YYYYMMDD --remote --file=./restore-data.sql
```

Two things that will bite you:

- **Skip `d1_migrations`.** Step 3.4 already populated it correctly for the new database; replaying
  the old rows duplicates them.
- **Some tables are seeded by migrations** — `document_types` (0014), `system_config` (0016),
  `pricing_rules`, `vehicle_types`. Those rows exist both in the freshly-migrated schema and in the
  dump, so the load collides on the primary key. Clear them first; the dump is the authority:
  ```bash
  npx wrangler d1 execute synaptic-go-restore-YYYYMMDD --remote \
    --command "DELETE FROM document_types; DELETE FROM system_config; DELETE FROM pricing_rules; DELETE FROM vehicle_types;"
  ```
- **D1 caps a single SQL statement at 100 KB and an imported file at 5 GB.** A `grep`-extracted
  insert list is one statement per line, so the statement cap is the one to watch only if a single row
  is enormous. If you hit it, split the file.

### 3.6 Verify — name the effect, not the artefact

"The import ran" is not verification. These are:

```bash
# same tables?
npx wrangler d1 execute synaptic-go-restore-YYYYMMDD --remote \
  --command "SELECT count(*) FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"

# referential integrity intact after a deferred load?
npx wrangler d1 execute synaptic-go-restore-YYYYMMDD --remote --command "PRAGMA foreign_key_check"

# the money. compare each against the same query on the source, or against --check-dump's output.
npx wrangler d1 execute synaptic-go-restore-YYYYMMDD --remote --command "
  SELECT (SELECT ROUND(SUM(wallet_balance),2) FROM users)               AS wallet_total,
         (SELECT SUM(wallet_balance_piastres) FROM users)               AS wallet_total_piastres,
         (SELECT count(*) FROM wallet_transactions)                     AS ledger_rows,
         (SELECT ROUND(SUM(amount),2) FROM wallet_transactions)         AS ledger_total,
         (SELECT count(*) FROM trips)                                   AS trips,
         (SELECT ROUND(SUM(final_fare),2) FROM trips)                   AS fares,
         (SELECT count(*) FROM payout_requests WHERE status='requested') AS open_payouts"
```

`PRAGMA foreign_key_check` returning nothing is load-bearing: the data went in with constraints
deferred, so this is the moment the constraints are actually tested.

Write the numbers down. Compare them against `--check-dump ./restore.sql`, which prints the same
totals computed locally from the same file.

### 3.7 Cut over — a separate decision, made deliberately

The restored database is not live until someone points the Worker at it. That means editing
`database_id` under `[[env.prod.d1_databases]]` in `apps/api/wrangler.toml` and redeploying:

```bash
cd apps/api && ./deploy.sh prod
```

Do this only after §3.6 passes. Until then you have a verified copy sitting next to a broken
production database, which is a good position to be in and worth staying in while you think.

> **Ownership note.** `apps/api/wrangler.toml` is owned by task **E15** in the current execution wave.
> This runbook *describes* the edit; task E18 did not make it. During an incident, edit it.

---

## 4. Scheduling the backup — one human step

`scripts/backup-d1.sh` does not schedule itself, deliberately. A Worker cron would need a handler in
`apps/api/src/index.ts` (frozen by task E02) **and** a `[triggers]` entry in `apps/api/wrangler.toml`
(task E15) — two collisions for a job that has no reason to run inside the Worker.

The scheduling workflow is written and waiting at
**`docs/plan/assets/e18-backup-d1-schedule.yml`**. Installing it is one command, and it needs a human
because the GitHub App these changes were authored through has no `workflows` permission:

```bash
git mv docs/plan/assets/e18-backup-d1-schedule.yml .github/workflows/backup-d1.yml
git commit -m "ci: install the nightly D1 backup workflow"
```

It needs the same `CLOUDFLARE_API_TOKEN` secret `docs/DEPLOYMENT.md` describes, with **R2:Edit**
("Workers R2 Storage:Edit") added alongside D1. And the bucket has to exist:

```bash
npx wrangler r2 bucket create synaptic-go-backups
```

Set a lifecycle rule on the bucket so backups expire — R2 → the bucket → Settings → Object lifecycle
rules. Nightly dumps of a growing database with no expiry is a bill, not a policy.

---

## 5. Recovery objectives, as they actually stand

Stating these honestly is more useful than aspiring to them.

| | Today | Note |
|---|---|---|
| **RPO** (data you can lose) | **Up to 24 h** once §4 is installed. Unbounded until then. | The window is the backup interval. Tighten it by changing the cron, not by hoping. |
| **RTO** (time to be live again) | **Unmeasured against production.** | The drill restores 29 rows in 0.065 s, which tells you the procedure is sound and nothing about production scale. Measure it during the §0 production rehearsal and write the number here. |
| Time Travel window | Whatever `wrangler d1 time-travel info` reports | Plan-dependent. Do not hardcode it. |

---

## 6. The foreign-key ordering trap

**Read this before you improvise a restore, because the error message lies about the cause.**

A `.dump`-shaped SQL export — which is what `wrangler d1 export` produces — lists tables in
**alphabetical** order, not dependency order. In this schema:

- `audit_log`, `captains`, `device_tokens` and `payout_requests` all carry `REFERENCES users(id)`
- all four sort before `users`

Replay that with foreign keys enforced and it dies partway through with:

```
no such table: main.users
```

which reads like a corrupt backup and is nothing of the sort. The dump is fine. The order is wrong.

The obvious fix does **not** work. Cloudflare's import documentation prescribes bracketing the file
with `PRAGMA defer_foreign_keys = ON` / `OFF`, and the 2026-08-01 rehearsal measured it: it still
fails with the same error. Deferral postpones *constraint checking*; it cannot help when the parent
table does not exist yet, because that is name resolution, not constraint evaluation.

And you cannot fall back to `PRAGMA foreign_keys = OFF` on D1: D1 runs every statement inside an
implicit transaction, where that pragma is a documented no-op. It works on a local SQLite file
(`--check-dump` uses it) and is unavailable where you need it.

Hence §3.4/§3.5: **take the schema from `migrations/`, which orders itself, and take only the data
from the dump.** Once every table exists, the only remaining violations are row-ordering ones, and
those are exactly what `defer_foreign_keys` is for. The drill exercises all four strategies on every
run and asserts which ones work:

```
PASS  naive replay with foreign keys enforced fails (expected)  [OperationalError: no such table: main.users]
note  defer_foreign_keys prelude on local SQLite: does not work — OperationalError: no such table: main.users
PASS  schema-from-migrations + data-from-dump restores cleanly  [29 INSERTs across 8 table(s)]
PASS  local shortcut (foreign_keys=OFF) also restores — laptops only
```

---

## 7. What has not been tested

The 2026-08-01 rehearsal ran against a scratch SQLite database built from `migrations/`, because no
agent on the execution board holds production credentials. D1 is SQLite underneath and the dump
format is the same, so the drill genuinely exercises the dump format, the restore procedure, the
ordering trap and every verification query in §3.6.

It does **not** exercise, and nobody should claim it does:

- `wrangler d1 export` itself — the real dump's exact preamble, whether it wraps statements in
  `BEGIN`/`COMMIT`, and how it handles the 100 KB statement cap. **§3.5 assumes the insert statements
  match `^INSERT INTO`.** Confirm that against a real export before relying on the `grep`.
- R2 upload, read-back and the hash comparison in `backup-d1.sh` steps 4–5.
- D1's own behaviour under `defer_foreign_keys` — measured on local SQLite only.
- Anything at production scale. 29 rows is a correctness test, not a timing one.
- `wrangler d1 create` and the §3.7 cutover.

**The production rehearsal in §0 is what closes these.** Until that row has a date in it, this
runbook is a rehearsed procedure against a faithful model, which is a great deal better than what
came before it and is not the same thing as a rehearsed production restore.
