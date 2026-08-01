# board/exec/drafts — migrations written ahead of their task

## What these are

`0022_sos_lifecycle.sql` (E13) and `0023_route_source.sql` (E15) are the two
outstanding **wave 1** migrations. Both numbers are reserved in
`board/exec/MIGRATION-LOCK.md`; neither task can start yet, because E13 depends on
E02 and E15 on E01+E03, and nothing has merged.

They are here rather than in `migrations/` **on purpose.** `migrations/0022_sos_lifecycle.sql`
is in E13's `owns:` and `migrations/0023_route_source.sql` is in E15's. Writing them
into the real directory would be exactly the boundary violation PROTOCOL-EXEC §4 exists
to prevent — the file would be locked to a task nobody has claimed, and the claiming chat
would find its own deliverable already committed by a stranger.

A draft on the board branch has no such problem. It is inert, it is reviewable now, and
the owning chat adopts it in one copy.

## Adoption — for whoever claims E13 or E15

1. Claim the task as normal (PROTOCOL-EXEC §3).
2. In `MIGRATION-LOCK.md`, edit the row that already exists for your number — replace
   `*(unclaimed — reserved)*` with your `CHAT_ID`. **Do not take a new number** and do
   not append a row.
3. Copy the file verbatim to `migrations/<same name>.sql` on your branch.
4. Read the header. It states the rollback, and it states which gate item it half-closes.
   Both belong in your PR body.
5. Change whatever you disagree with — this is a draft, not a decision. If you do change
   it, say what and why on the PR, because the reasoning below was written against the
   schema as it stands and someone will diff the two.

## What is already proven

Applied together with all 21 predecessors to a fresh SQLite database, foreign keys on,
using the repository's own CI scripts:

```
python3 scripts/check_migrations.py        -> OK   (23 migrations)
python3 scripts/check_migrations_apply.py  -> OK   (23/23 applied, 40 tables)
```

`test_migrations_0022_0023.py` in this directory then asserts the behaviour, not just the
parse — 22 assertions, 0 failures. It applies `0001`–`0021`, writes real rows, applies
`0022`+`0023` **on top of live data**, and checks:

- **No backfill.** The pre-existing `sos_alerts` row is byte-identical afterwards, its
  three new columns are `NULL` rather than defaulted, and a pre-`0023` trip has
  `route_source IS NULL` rather than `'unknown'`.
- **The SOS trail is append-only in the database**, not by convention: `UPDATE` and
  `DELETE` are both refused by trigger, an invented event name is refused by CHECK, and
  deleting an alert that has a trail fails on the foreign key instead of taking the
  evidence with it.
- **Acknowledgement did not widen the status CHECK.** `sos_alerts.status` still refuses
  `'acknowledged'` — the 0003 constraint is intact, no table was rebuilt.
- **`route_source` rejects a typo.** `'osrm '` with a trailing space fails, which is the
  failure mode that would otherwise produce a metric that silently never matches.
- **Every index is actually used** by the query it was added for, via `EXPLAIN QUERY PLAN`.

Run it with `python3 test_migrations_0022_0023.py` from a directory containing `mig/`
with all 23 files, or adapt the two paths at the top.

## What is NOT proven, and what a reviewer should push back on

- **This is SQLite, not D1.** The harness matches what `check_migrations_apply.py` does
  and no more. Trigger behaviour under D1's batching, and whether a `RAISE(ABORT)` inside
  a `db.batch()` rolls back the whole batch, are untested here.
- **Nobody has run these against production data volumes.** The three new indexes are
  justified by query shape, not measured.
- **`0022` decides that acknowledgement is a property of an open alert, not a state.**
  That was forced by the schema — SQLite cannot widen `CHECK (status IN
  ('open','resolved','false_alarm'))` without a full table rebuild of a live safety table.
  It also happens to be the more truthful model, but if E13's owner wants a real fourth
  state, that is a rebuild and it needs E18's rehearsed restore behind it first.
- **`0022` makes the SOS trail undeletable, including by cascade.** Verified that nothing
  deletes `sos_alerts` today — `lib/cleanup.ts` touches only `otp_codes` and
  `refresh_tokens` — but any future retention sweep over `sos_alerts` will now fail rather
  than silently erase an emergency trail. That is the intended trade and it should be a
  conscious one.
- **Neither migration closes its gate item.** `0022` is part of item 10, which is split
  four ways (E05 · E09 · E13 · E14). `0023` is part of item 11, where **E09 writes the
  value** at the trip INSERT site in `trips.ts` — a column nobody populates is root R3, a
  value defined with nothing ever calling it. Say so on the PR so a verifier does not
  close the item on the schema alone.

## What was found while writing these

- **`trip_share_tokens.revoked_at` already exists** (`0003:181`). E13's
  `revokeShareToken()` needs no schema change at all, which the brief does not say and a
  chat could easily miss while writing a migration it does not need.
- **`purgeExpiredShareTokens()` is a full table scan today.** `trip_share_tokens` carries
  exactly one index, `idx_share_trip` on `trip_id` (`0003:185`), and the sweep filters on
  `expires_at`. `0022` adds that index — it is E13's sweep, so it belongs in E13's
  migration rather than E09's, even though E09 calls the function.
- **`sos_alerts.created_at` is indexed alone** (`0003:175`), which cannot serve the
  operator queue's `status` filter. `0022` adds the composite.
