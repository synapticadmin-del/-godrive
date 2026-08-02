# e08_settlement_harness — runnable proof for E08

Written by **E08** (`chat-20260802-0506-3804`) for PR
[`exec/08-settlement-money-primitive`](https://github.com/synapticadmin-del/-godrive/tree/exec/08-settlement-money-primitive).
Inert on the board branch, exactly like `board/exec/drafts/test_e13_safety.py`.

## Why it is here and not in `apps/api/test/`

`apps/api/test/` and `apps/api/vitest.config.ts` are in **E19's** `owns:`
(WAVE-PLAN §8), and E19 `depends_on: [E01, E08]` — it is round 5 and cannot start
until this task merges. Writing into that directory would hand E19 its own
deliverable pre-written by a stranger, which is the boundary violation
PROTOCOL-EXEC §4 exists to prevent.

It also would not run. `ci.yml`'s node job runs `npm test -w @synaptic-go/shared`
and never invokes the api workspace's test script, so an `apps/api/test/**` file
executes nowhere until someone edits `.github/workflows/ci.yml` — a change no
agent can make.

So the behaviour is proved here instead, and the runner-shaped version is parked
next door in `e19_adopt_settlement.test.ts`.

## What it actually does

No mocks. It imports the **shipped** `apps/api/src/lib/money.ts` and
`settlement.ts` from a repository checkout — along with the real `audit.ts`,
`log.ts` and `utils.ts` they depend on — and drives them against a real SQLite
database with **every repository migration applied in order**, through a
`D1Database` shim (`d1shim.mjs`) over `node:sqlite`. `db.batch()` is a real
transaction, `idx_wt_idem` is a real unique index, and the `users` /
`wallet_transactions` / `audit_log` tables are the real ones.

## Running it

Needs **Node ≥ 22** for `node:sqlite` and native type stripping. No install step,
no network, no `node_modules`.

```sh
GODRIVE_ROOT=/path/to/-godrive \
  node --experimental-strip-types --experimental-loader ./loader.mjs harness.ts
```

`GODRIVE_ROOT` must point at a checkout carrying E08's branch, or at `main` once
it has merged. Without it the harness walks four levels up and will exit `2` with
the path it looked for.

## Result

**69 passed, 0 failed** against `exec/08-settlement-money-primitive`, base
`c0ce1740288f7b330bd5fbb5430c105e1cf0fd6e`, 22 migrations.

| Group | Proves |
|---|---|
| **A** (19) | `resolveTripSettlement` precedence. `offered_price` beats `estimated_fare`; `accepted_price` beats both; commission is rescaled on the offer path and left alone on the bid path; payout never negative. A9 runs the *old* chain and the new one over the same row and shows 100 against 150. |
| **B** (17) | `moveMoney`. Credit and debit move the balance and the piastre column together; a repeat of the same `idempotencyKey` is refused as `duplicate` with the balance untouched; the floor refuses a debit and writes **no** ledger row; a debit to exactly the floor is allowed; zero amounts and unknown users are refused. |
| **C** (5) | The bug the old order had. It replays the pre-E08 rider debit (`UPDATE` then `INSERT OR IGNORE`) and watches a retry take the money **twice** — 500 → 400 → 300 — while the ledger still shows one row. The same retry through `moveMoney` moves it once. |
| **D** (28) | `settleTripCompletion` end to end: the cash commission floor holds and records the shortfall; the wallet mint is refused (rider unpaid ⇒ captain uncredited, and no payout row); settling twice moves nothing twice; the audit row lands with its price source; and both call shapes — today's `trips.ts` and the one E09 will move to — behave as documented. |

## What it does **not** prove

- **This is SQLite through a shim, not D1.** `d1shim.mjs` implements only what
  these modules call. D1's own batching, its `changes` accounting under
  concurrency, and its behaviour when a statement inside `batch()` fails are not
  covered. The shim maps `batch()` to `BEGIN`/`COMMIT`, which is what D1
  documents, but that is an assumption here rather than a measurement.
- **Nothing here is concurrent.** The idempotency argument rests on
  `idx_wt_idem` being a unique index, which it is (`migrations/0005:5`), but two
  simultaneous settlements of the same trip were not run against a real D1.
- **It does not touch `routes/trips.ts`.** The end-to-end accept path is gate
  item 6's other half and belongs to **E09**. D7/D8 pin the primitive's two call
  shapes; they say nothing about what the handler actually passes today.
- **It is not CI.** Nothing runs this on a pull request. Making that true is
  E19's job plus a human's `ci.yml` edit.
