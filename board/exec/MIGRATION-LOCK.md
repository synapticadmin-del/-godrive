# MIGRATION-LOCK

D1 migrations serialise globally. Two chats picking `0020` from a directory listing is a guaranteed
collision, so the number comes from this file instead.

**Next free number: 0024**

This file is the **only** authority on migration numbers. A brief that says `@NEXT_…` is unresolved
and its owner must come here first; a brief that names a concrete number has already been reconciled
against the table below and you should use exactly that filename.

To take a number: `github__create_or_update_file` on this file **with** its `sha`, appending your row
and bumping the "next free number" line above. On `409`, re-read, take the next number, rename your
file. Never guess from a directory listing.

Migrations are forward-only. State the rollback in your PR (a forward repair migration, or a restore
rehearsed under E18). Migrations `0005`, `0009`, `0017` and `0018` contain irreversible backfills —
do not add a fifth without saying so explicitly.

## 1. Assigned

| Number | Task | Chat | File | Merged |
|---|---|---|---|---|
| 0001–0019 | (pre-existing) | — | — | yes |
| 0020 | E06 | chat-20260801-1840-091b | `migrations/0020_payout_requests.sql` | no — PR #90 open |
| 0021 | E16 | chat-20260801-1845-7a4c | `migrations/0021_consent_and_deletion.sql` | no — PR #92 open |
| 0022 | E13 | *(unclaimed — reserved)* | `migrations/0022_sos_lifecycle.sql` | no |
| 0023 | E15 | *(unclaimed — reserved)* | `migrations/0023_route_source.sql` | no |

**0022 and 0023 are reserved, not taken.** Their tasks are blocked on unmerged dependencies (E13→E02,
E15→E01+E03), so neither has an owning chat yet. The numbers are pinned in advance because the two
briefs previously carried `migrations/@NEXT_…` in their `owns:` list, and an `owns:` entry containing
a placeholder cannot be intersected against another claim — the file lock in PROTOCOL-EXEC §3 was
silently weaker for exactly the two tasks that touch the schema. When you claim E13 or E15, take the
row below with the file's `sha` (fill in your chat id); do not take a new number.

## 2. Reserved for known future work — number on claim, not now

These are migration points the plan names that have no numbered slot yet. They are listed so that a
chat which discovers it needs one does not conclude the board forgot, and so the count is honest:
four schema changes are known to be outstanding beyond the gate.

| Point | Source | Why it has no number | Wave |
|---|---|---|---|
| `UNIQUE(company_id, period_start)` on `company_invoices` | plan §4 R7 · T08 top action | Gate item 5 **disables** the B2B invoice cron rather than fixing it; the constraint is what makes the double-billing structurally impossible when B2B returns. `E07` is `migration: no` correctly — its scope is the disable. | 2 |
| Timestamp format normalisation across all TEXT datetime columns | plan §4 R7 | An irreversible backfill touching every table, and the fifth such backfill. §6 requires it be called out explicitly; it needs its own task and a rehearsed restore (E18) before it can be numbered. | 2 |
| Retention / TTL on `trip_path_points`, `audit_log`, `notifications`, `chat_messages` | T08 · F-25-07 | D1's 10 GB cap is hard and unraisable; `trip_path_points` alone breaches it in ~166 days at the benchmark. Explicitly **not** on the launch gate (plan §2.2 closing note). The sweeper needs `cron/` (E02) and `lib/cleanup.ts` (E09) to land first. | 2 |
| Integer-piastres cutover completion | plan §5.3 | Ruled: **one** cutover owned by T03, not three. `0005` already half-did this. Numbering it now would invite the fourth partial migration §5.3 exists to prevent. | 2 |

## 3. Process notes added after round 1

- **A migration's number and its filename move together.** If you take `0024` and later have to renumber,
  rename the file in the same commit and amend your `owns:` in your claim. A claim whose `owns:` names a
  file that does not exist locks nothing.
- **Two migrations that never met in CI are not proven.** Each PR's `check_migrations_apply.py` run only
  ever saw its own migration on top of `0001`–`0019`. `0020` and `0021` first apply *together* on the CI
  run against `main` after both merge. Watch that run; it is the first real test of the pair.
- **`check_migrations.py` enforces `NNNN_lower_snake_case.sql`, ordered, no BOM.** A placeholder filename
  like `@NEXT_foo.sql` would fail it outright, which is a second reason the placeholders are gone.
