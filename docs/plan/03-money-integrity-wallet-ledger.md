# 03 — Money Integrity — Wallet, Ledger & Commission

> Track: A — Foundation & safety-critical · Reviewer: `chat-20260801-1219-a7e2` · Date: 2026-08-01 (UTC)
> Base commit reviewed: `dccc2dadf206ffaba4d35b3343d55ff279bacaf4` (`main`)

**Verdict in one paragraph.** Money in Synaptic Go is not conserved. There is no double-entry ledger — `wallet_transactions` is a flat event log with no counterparty column, no entry group, and no platform account, so a trial balance is not computable at any date, by construction rather than by bug. On top of that structural gap sit five independent paths that create or destroy real EGP: a captain is credited in full when the rider's wallet debit fails; a Paymob webhook replay credits the wallet again on every delivery; card-paid intercity seats are booked without ever being charged; a `CHECK`-violating INSERT makes the intercity webhook throw after the card is captured; and there is no refund path for city trips at all. The integer-piastre migration that was supposed to end floating-point accounting (`0005`) is inert — its columns are written by five call sites, read by zero, and skipped by three. **This axis is not production-ready, and the gap is not a hardening exercise: it is a ledger rebuild.**

---

## 1. Scope

This document covers the movement, recording and reconciliation of money: the `wallet_transactions` ledger, the `users.wallet_balance` running total, trip settlement at completion, commission derivation and provenance, cash-trip commission debt, payouts, the Paymob top-up and trip-payment paths as they touch the ledger, promo/credit interaction with fare and commission, refunds, and the money surfaces in both Flutter apps and the admin console.

It explicitly does **not** cover:

| Out of scope | Owner |
|---|---|
| Fare formula, surge curve, bidding economics and price fairness | **T05** |
| PSP integration mechanics, Paymob HMAC construction, payout rails and settlement files | **T04** — I cover the webhook only where it writes to the ledger, and I flag what I found |
| Authorization on money endpoints (who may call payout, IDOR on wallet reads) | **T02** |
| Migration hygiene, D1 schema conventions, index strategy in general | **T08** |
| Dispatch, matching, offer scheduling | **T06** |
| The cross-app duplication problem systematically | **T27** — my parity findings are handed off in §9 |

Where a finding sits on a boundary — the Paymob replay bug, for instance — I have written it here because its consequence is a wrong balance, and included it in the T04 handoff.

**Standard of evidence.** Every citation below is a line I opened at the base commit above. I read the API, migrations and admin surfaces directly; four analysis subagents worked the same on-disk copies in parallel on the PSP, refund/promo, client-surface and reconciliation axes, and I re-verified every S1 and every load-bearing S2 myself before writing it down. Findings I could not verify are marked `needs-check` and are never assumed safe.

---

## 2. What I actually read

**API — routes** (`apps/api/src/routes/`)

| File | Read | Note |
|---|---|---|
| `wallet.ts` (143 lines) | full | The whole wallet surface. Contains three mutually inconsistent definitions of "balance". |
| `trips.ts` (1371 lines) | full on money paths (390-510, 700-830, 950-1090, 1280-1330), skimmed elsewhere | Trip creation/pricing, cancellation, completion settlement, bid accept. The settlement block is the heart of this document. |
| `payments.ts` (313 lines) | full | Paymob intention creation and the webhook. Four distinct ledger-write branches, three of them defective. |
| `intercity.ts` (463 lines) | full on booking (95-200) and cancel/refund (225-323), skimmed schedule CRUD | The only refund path that exists anywhere in the product. |
| `promo.ts` (108 lines) | full | Validation and code creation. |
| `admin.ts` (937 lines) | read 20-200 (analytics/GMV), 350-400 (pricing rules), 420-450 (system config), 500-510 (the one `batch` in the repo); skimmed the rest | All revenue reporting. No payout-approval or refund endpoint exists in the file. |
| `captain.ts` (700 lines) | read 270-300 (earnings summary); skimmed | Earnings aggregate, sourced from `trips`. |
| `user.ts` (328 lines) | read 70-95; skimmed | The single read of `user_credits`. |
| `companies.ts` (239 lines) | skimmed | B2B invoicing — `company_invoices.total_amount` is never populated by any path I found. `needs-check`. |

**API — lib & middleware** (`apps/api/src/lib/`, `apps/api/src/middleware/`)

`pricing.ts` (38) full — fare→charge conversion. `utils.ts` (241) full — money helpers, rounding, id generation. `schemas.ts` (331) full — money validation; the percent-vs-fraction comment at :299-302 is a live tripwire. `paymob.ts` (235) full — HMAC field list and verification. `audit.ts` (37) full — swallows its own failures, correctly. `cleanup.ts` (75) full — touches no financial rows, correctly. `types.ts` (102) full. `notifications.ts` (408) skimmed for money-path awaits. `auth.ts` (75), `rateLimit.ts` (90) read for `parseBody` and the absent rate limit on the webhook.

**Migrations** (`migrations/` — repo root)

`0001_init.sql` (133) full — `trips.commission REAL`. `0002_enhancements.sql` (129) full — `user_credits`, `promo_codes`, `trip_promo`, `trips.discount`, `audit_log`. `0003_global_transport.sql` (228) full — **the `wallet_transactions` DDL at :27-39 and `users.wallet_balance` at :45; the single most important file in this review.** `0004_bidding_system.sql` (18) full. `0005_integer_currency_and_idempotency.sql` (22) full — the integer-piastre migration. `0006_otp_attempts_and_idem_index.sql` (10) full. `0010_intercity_booking_cancel.sql` (9) full. `0011_payment_intentions.sql` (31) full. `0016_system_config.sql` (40) full — `default_commission_pct`, `cancel_fee_egp`, `free_cancel_min`. `0019_trips_captain_status_index.sql` (33) full.

I did not read `0007`–`0009`, `0012`–`0015`, `0017`–`0018` (auth, documents, avatars, onboarding, captain radius) — no money columns, confirmed by grep for `amount|balance|commission|fare|piastres`.

**Clients**

`apps/rider/lib/screens/wallet/wallet_screen.dart` (~500) full. `apps/rider/lib/screens/wallet/topup_screen.dart` (~200) full. `apps/captain/lib/screens/earnings/earnings_screen.dart` (~250) full. `apps/captain/lib/screens/earnings/wallet_screen.dart` (~810) full. `apps/admin/src/pages/AnalyticsPage.tsx` (~690) full.

**Verification method.** The reconciliation SQL in §6/§10 was not written from inspection alone — the schema was rebuilt from the ten migrations above in a local SQLite 3.40 instance, seeded with deliberate violations, and each detection query executed until it returned exactly the seeded rows. Two claims in this document (the `CHECK` violation, the `audit_log` FK failure) were confirmed by executing the offending INSERT against that schema and reading the error.

---

## 3. How it works today

### 3.1 The stores

There are **three** places a user's money is recorded, and they are not reconciled against each other by any code in the repository.

| Store | Defined | Type | Who writes | Who reads |
|---|---|---|---|---|
| `wallet_transactions` | `migrations/0003_global_transport.sql:27-39` | `amount REAL`, `direction` credit\|debit | 12 call sites | ledger views, captain balance |
| `users.wallet_balance` | `migrations/0003_global_transport.sql:45` | `REAL NOT NULL DEFAULT 0` | 9 call sites | **every sufficiency check and every payout gate** |
| `user_credits.balance` | `migrations/0002_enhancements.sql:118-122` | `REAL NOT NULL DEFAULT 0` | **nobody** | `apps/api/src/routes/user.ts:80-84` |

`users.wallet_balance` is the operative one — it is what `WHERE wallet_balance >= ?` tests before letting money leave. `wallet_transactions` is described in its own header comment as the ledger (`migrations/0003_global_transport.sql:25`: *"wallet + transactions (ledger; balance = SUM credits-debits)"*), but nothing enforces that identity and several paths break it deliberately. `user_credits` has no writer anywhere in the tree, so `GET /user/profile` returns `credits: 0` for every user on the platform, permanently.

Migration `0005` added integer mirrors — `wallet_transactions.amount_piastres`, `users.wallet_balance_piastres`, `trips.{estimated_fare,final_fare,commission}_piastres` — for *"zero-floating-point financial accounting"* (`migrations/0005_integer_currency_and_idempotency.sql:7`). Their current status:

- `wallet_balance_piastres` — written by 5 statements (`trips.ts:998`, `:1030`, `:1049`, `payments.ts:183`, `:273`), **read by none**, and skipped entirely by three writers that move the float alone (`wallet.ts:114`, `intercity.ts:151`, `intercity.ts:290`). It is therefore already provably wrong for any user who has requested a payout or booked an intercity seat.
- `trips.final_fare_piastres`, `commission_piastres`, `estimated_fare_piastres` — backfilled once by the migration, written by **zero** code paths since. Every trip created after `0005` has NULL.

The float remains authoritative. The migration bought nothing.

### 3.2 The ledger row

```sql
CREATE TABLE IF NOT EXISTS wallet_transactions (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type TEXT NOT NULL CHECK (type IN ('topup','trip_payment','refund','commission','payout','adjustment','promo_credit')),
  direction TEXT NOT NULL CHECK (direction IN ('credit','debit')),
  amount REAL NOT NULL,                -- positive amount in EGP
  currency TEXT NOT NULL DEFAULT 'EGP',
  trip_id TEXT REFERENCES trips(id) ON DELETE SET NULL,
  payment_ref TEXT,                    -- paymob order id / external ref
  note TEXT,
  status TEXT NOT NULL DEFAULT 'settled' CHECK (status IN ('pending','settled','failed','reversed')),
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
```
`migrations/0003_global_transport.sql:27-39`

One row per movement. No `counterparty_id`, no `account`, no `entry_group_id`, no `balance_after`. `trip_id` is the only grouping key and it is nullable, `ON DELETE SET NULL`, absent on the card path (`payments.ts:207-212`) and absent on intercity (`intercity.ts:166-170`, which puts `intercity:${bookingId}` in the free-text `note` instead).

Crucially, **there is no platform account.** Commission exists as `trips.commission REAL` (`migrations/0001_init.sql:75`) and, on cash trips, as a debit against the captain — the corresponding credit to the house is written nowhere. A rider debit of 100 and a captain credit of 80 sum to −20 and nothing absorbs it. The ledger cannot balance because one of the three parties to every trip has no account in it.

### 3.3 Trip settlement, step by step

`POST /trips/:id/complete` — `apps/api/src/routes/trips.ts:951-1088`.

```
 969  finalFare     = accepted_price ?? final_fare ?? estimated_fare ?? 0
 970  commission    = trip.commission ?? 0
 971  captainPayout = max(0, round((finalFare − commission)*100)/100)

 973  UPDATE trips SET status='completed', final_fare=?, completed_at=?
        WHERE id=? AND status != 'completed'          ← optimistic guard, 409 on loss
 983  logEvent(...)

      if payment_method='wallet' AND NOT billed_to_company AND rider_id:
 997    UPDATE users SET wallet_balance = wallet_balance − ?, …
          WHERE id=? AND wallet_balance >= ?           ← guarded; may match 0 rows
1003    txnStatus = changes===1 ? 'settled' : 'failed'
1005    INSERT OR IGNORE wallet_transactions(trip_payment, debit, …, txnStatus)

      if captain_id:
        if payment_method='cash':
1020      INSERT OR IGNORE wallet_transactions(commission, DEBIT, …, 'settled')
1028      if changes===1:
1029        UPDATE users SET wallet_balance = wallet_balance − commission   ← NO guard
        else:
1040      INSERT OR IGNORE wallet_transactions(commission, CREDIT, …, 'settled')
1047      if changes===1:
1048        UPDATE users SET wallet_balance = wallet_balance + captainPayout
```

Four properties of this sequence matter.

**It is not one atomic unit.** Every statement is an independent `.prepare().run()`. `DB.batch` appears exactly once in the whole codebase — `apps/api/src/routes/admin.ts:506`, for non-financial system-config upserts — and never in a money path. If the Worker is evicted mid-sequence the surviving state depends on where it died: after :997 but before :1005, the rider is debited with no ledger row; after :973 but before anything else, the trip is completed and nobody has been settled. There is no reconciliation job, no retry hook, and no way to discover either state.

**The trip is marked completed before any money moves** (:973 precedes :997). A settlement failure therefore leaves a completed, unpaid trip.

**The two branches use opposite orderings and opposite discipline.** The captain branches insert first and gate the balance move on `changes === 1` — the correct insert-as-lock pattern, and it is genuinely correct. The rider branch moves the balance first and inserts second, ungated. The knowledge is in the file; it was not applied uniformly.

**The rider's debit result is computed and then discarded.** `txnStatus` at :1003 is consumed at exactly one place — the `note` and `status` binds of the INSERT at :1009. The `if (trip.captain_id)` block at :1012 never references it. This is F-03-01.

### 3.4 Commission provenance

Four sources, three defaults, one documented conversion that does not exist:

| Source | Unit | Default | Reality |
|---|---|---|---|
| `pricing_rules.commission_rate` | 0–1 fraction | `0.2` (`migrations/0001_init.sql:54`) | the real source of truth |
| `admin.ts:372` create-city literal | fraction | `0.2` | hardcoded; ignores `system_config` |
| `trips.ts:1301` bid-accept path | fraction | `0.2` via `\|\|` | falsy-zero bug (F-03-16) |
| `system_config.default_commission_pct` | **percent** | `'20'` (`migrations/0016_system_config.sql:34`) | written by admin UI, **read by zero code** |

Commission is computed at trip creation on the post-discount fare (`trips.ts:428-429`) and **stored on the trip row**, then recomputed and overwritten at bid accept (`trips.ts:1302`). Completion reads the stored value (`trips.ts:970`). Freezing the rate on the row at accept-time is the right design and protects against a mid-trip rate change — credit where due. But `trips.commission` is a bare nullable `REAL` with no `CHECK`, so if it is ever NULL the platform silently takes **zero** commission and the captain is credited the entire fare.

A city with no `pricing_rules` row falls back to Cairo's rates *and* Cairo's commission (`trips.ts:24-32`) with no warning — a new governorate is priced as Cairo silently.

### 3.5 Cash — the dominant Egyptian case

Cash is modelled, not assumed away, and the direction is right. `trips.ts:1013-1035` debits the platform's commission from the captain's wallet rather than crediting a payout, and the comment at :988-990 shows the double-pay trap was consciously avoided. That is the correct inDrive-style model.

What is missing is everything around it. The debit at :1029 has **no** `WHERE wallet_balance >= ?` floor — unlike every other debit in the codebase — so the balance goes arbitrarily negative. There is no debt ceiling, no auto-offline at a threshold, no dunning, no collection state, and no retry. And `GET /captain/wallet` does not show the debt (§3.6), so the captain accumulating it cannot see it.

### 3.6 Three "balance" definitions

| Endpoint | Definition | Citation |
|---|---|---|
| `GET /user/wallet` | raw `users.wallet_balance` | `wallet.ts:19-24` |
| `GET /captain/wallet` | `SUM(amount) WHERE direction='credit' AND type IN ('commission','payout','adjustment')` − payout debits | `wallet.ts:58-72` |
| `POST /captain/wallet/payout` gate | `users.wallet_balance` | `wallet.ts:104-111` |

The captain's displayed balance and the number that gates their withdrawal are different queries over different data. The displayed one structurally excludes `type='commission' AND direction='debit'` — precisely the cash-commission debt — excludes `topup` and `refund` credits entirely, and applies no `status` filter, so `failed` and `pending` rows count as earnings. The captain app then submits 100% of the displayed figure as the payout amount, with no amount field (`apps/captain/lib/screens/earnings/wallet_screen.dart:242-246`).

### 3.7 Reporting

All revenue reporting reads `trips`, never the ledger: `admin.ts:28-29`, `:88-89`, `:115-116`, `:162-163`, `captain.ts:279-280`, `wallet.ts:76`. Every one is `SUM(CASE WHEN status='completed' THEN final_fare/commission …)`. GMV therefore counts fares that were never collected (failed debits, cash never reconciled, B2B never invoiced) and commission that is uncollectable.

### 3.8 Refunds

There is no refund path for city trips. `POST /trips/:id/cancel` (`trips.ts:709-827`) writes exactly one statement touching state:

```sql
UPDATE trips SET status = 'cancelled', cancel_reason = ?, cancelled_at = ?, updated_at = ? WHERE id = ?
```
`apps/api/src/routes/trips.ts:728`

No wallet statement, no ledger row, no fee. The only refund in the product is intercity seat cancellation (`intercity.ts:279-294`), and it is wallet-only. `status='reversed'` exists in the CHECK enum and is written by nothing, anywhere.

---

## 4. Findings

| ID | Sev | Finding | Evidence (`path:line`) | Impact | Confidence |
|---|---|---|---|---|---|
| F-03-01 | S1 | Captain is credited the full payout even when the rider's wallet debit failed for insufficient funds | `apps/api/src/routes/trips.ts:1003` + `:1012` | Platform pays out money it never collected, on demand, with no privilege required | confirmed |
| F-03-02 | S1 | Paymob top-up credits `wallet_balance` on every webhook delivery; the `INSERT OR IGNORE` result is discarded | `apps/api/src/routes/payments.ts:175-186` | One legitimate top-up can be replayed into unbounded balance; ledger and balance diverge silently | confirmed |
| F-03-03 | S1 | The `payment_intentions` settle guard is read-then-write with an unconditional UPDATE | `apps/api/src/routes/payments.ts:166` vs `:223-227` | N concurrent replays all pass the guard; multiplies F-03-02 by N | confirmed |
| F-03-04 | S1 | `type='intercity_booking'` violates the `wallet_transactions` CHECK; the handler has no try/catch | `apps/api/src/routes/payments.ts:215-220` vs `migrations/0003_global_transport.sql:30` | Card captured, INSERT throws, intention never settles, Paymob retries forever against a permanently failing handler | confirmed |
| F-03-05 | S1 | Card-paid intercity bookings are never charged — seat, QR and booking are issued for free | `apps/api/src/routes/intercity.ts:105`, `:149` | An entire intercity schedule can be booked out at zero cost by passing `paymentMethod:"card"` | confirmed |
| F-03-06 | S1 | No refund path exists for city trips; a card-prepaid rider who cancels loses 100% | `apps/api/src/routes/trips.ts:709-827`, esp. `:728` | Every prepaid cancellation becomes a chargeback or a manual bank transfer; no admin refund tool exists | confirmed |
| F-03-07 | S1 | The ledger is not double-entry and has no platform account, so it cannot balance | `migrations/0003_global_transport.sql:27-39` | No trial balance at any date; commission revenue is an assertion, not a recorded movement | confirmed |
| F-03-08 | S1 | Payout debits the balance, then writes the ledger row non-atomically, with no idempotency key, and nothing ever settles it | `apps/api/src/routes/wallet.ts:113-130` | Money leaves the balance and sits at `pending` forever; a crash between the two loses the record but keeps the deduction | confirmed |
| F-03-09 | S1 | Three endpoints return three different balances; the captain's displayed balance is not the one that gates their payout | `apps/api/src/routes/wallet.ts:24`, `:58-72`, `:104-111` | Every cash-taking captain is hard-blocked from withdrawing, on a figure the app just showed them as available | confirmed |
| F-03-10 | S2 | No money path is atomic anywhere; `DB.batch` is never used in a financial path | `trips.ts:997-1053`, `intercity.ts:150-170`, `:283-293`, `payments.ts:175-186` | Every settlement has a crash window that desynchronises ledger and balance, undetectably | confirmed |
| F-03-11 | S2 | Cash commission debit has no balance floor, no ceiling, no collection mechanism | `apps/api/src/routes/trips.ts:1029-1033` | Captain debt grows without bound and without visibility; the platform books it as earned revenue | confirmed |
| F-03-12 | S2 | The integer-piastre layer is inert: written 5×, read 0×, skipped by 3 writers; `trips.*_piastres` written 0× | `migrations/0005_integer_currency_and_idempotency.sql:8-12`; `wallet.ts:114`, `intercity.ts:151`, `:290` | The fix for float accounting was paid for and never landed; the shadow columns are already wrong | confirmed |
| F-03-13 | S2 | All revenue reporting reads `trips`, never the ledger | `admin.ts:28-29`, `:88-89`, `:115-116`, `:162-163`, `captain.ts:279-280` | Dashboard reports money that was never collected; finance cannot reconcile to a bank balance | confirmed |
| F-03-14 | S2 | `promo_codes.max_uses` is enforced by a TOCTOU read-then-write with an unguarded increment; no per-user cap exists at all | `apps/api/src/routes/trips.ts:402-418` then `:500` | A limited campaign is drainable to arbitrary depth by a scripted burst; a code with NULL `max_uses` is unlimited forever | confirmed |
| F-03-15 | S2 | Accepting a captain's bid silently discards the rider's promo discount | `apps/api/src/routes/trips.ts:1299-1310` | Rider is charged the full bid price after being shown a discounted estimate; the promo is already burned | confirmed |
| F-03-16 | S2 | `pricing?.commission_rate \|\| 0.2` charges 20% to a city configured at 0% | `apps/api/src/routes/trips.ts:1301` | A promotional or contract city silently has commission taken; the create path and accept path disagree for the same trip | confirmed |
| F-03-17 | S2 | Failed payments are written as `direction='credit'` rows with NULL `amount_piastres` | `apps/api/src/routes/payments.ts:234-239`, `:288-293` | Any aggregation that omits the status filter — such as `wallet.ts:59` — counts a declined card as money | confirmed |
| F-03-18 | S2 | Refunds, voids and chargebacks are entirely unhandled; `is_refunded`/`is_voided` arrive signed and are never read | `apps/api/src/lib/paymob.ts:173`, `:175`; `payments.ts:97-313` | Every chargeback is a 100% loss with no ledger trace; a refund callback is discarded as `duplicate_ignored` | confirmed |
| F-03-19 | S2 | The webhook accepts the HMAC from the query string and never checks `created_at` freshness | `apps/api/src/routes/payments.ts:103`; `paymob.ts:164` | A user-observable redirect signature becomes a replayable server credential; combined with F-03-02/03 this is the full mint chain | confirmed (code) / likely (Paymob redirect equivalence) |
| F-03-20 | S2 | The captain's only commission figure is rounded to whole pounds | `apps/captain/lib/screens/earnings/wallet_screen.dart:355` | 137.50 renders as `138`; the file's own comment 120 lines below documents this exact bug as fixed elsewhere | confirmed |
| F-03-21 | S2 | Top-up asserts success from a liveness probe, and Arabic-Indic digit entry is a silent dead button | `apps/rider/lib/screens/wallet/topup_screen.dart:91-96`, `:29-31` | Rider is told a top-up succeeded before the webhook credits; an Arabic-keyboard rider taps متابعة الدفع and nothing happens, with no error | confirmed |
| F-03-22 | S2 | Admin analytics: GMV and leaderboard use different time buckets, and the finance CSV contains a fabricated `cancelled` column | `apps/admin/src/pages/AnalyticsPage.tsx:147`, `:197`, `:336` vs `:585` | Two GMV figures on one screen that do not sum; every non-completed trip is exported to finance as cancelled | confirmed |
| F-03-23 | S2 | Webhook audit rows are silently discarded by an FK violation on `actor_id='paymob'` | `apps/api/src/routes/payments.ts:107`, `:150`; `migrations/0002_enhancements.sql:41` | The two highest-value security signals — rejected HMAC and amount mismatch — are logged to a console line and lost | confirmed (FK-enforcement dependent) |
| F-03-24 | S2 | The captain involuntarily funds ~80% of every promo discount, unlabelled and unreported | `apps/api/src/routes/trips.ts:428-429`, `:971` | A 90 EGP promo on a 100 EGP fare takes the captain from 80 to 8; no consent, no disclosure, no `promo_subsidy` line | confirmed |
| F-03-25 | S3 | `cancel_fee_egp` and `free_cancel_min` are fully plumbed admin settings that no code reads | `migrations/0016_system_config.sql:36-37`; `admin.ts:429-430` | Operators configure a 15 EGP penalty, see it save, and it is never charged; captains eat every dead-head | confirmed |
| F-03-26 | S3 | `system_config.default_commission_pct` is write-only, and `schemas.ts` promises a percent→fraction conversion that does not exist | `migrations/0016_system_config.sql:34`; `apps/api/src/lib/schemas.ts:299-302` | The day someone wires the comment up literally, `commission_rate` becomes `20` and commission is 20× the fare | confirmed |
| F-03-27 | S3 | `user_credits` is a third balance store with no writer anywhere | `migrations/0002_enhancements.sql:118-122`; `apps/api/src/routes/user.ts:80-84` | `GET /user/profile` returns `credits: 0` for everyone, forever; any referral or goodwill-credit feature is a silent no-op | confirmed |
| F-03-28 | S3 | Ledger rows are frequently unattributable: no `trip_id` on the card path, booking ids stuffed into free-text `note` | `payments.ts:207-212`; `intercity.ts:169`, `:287` | Card revenue can never be joined to the trip that earned it; refunds cannot be joined to bookings | confirmed |
| F-03-29 | S3 | Cancelling a trip burns the promo redemption with no rollback | `apps/api/src/routes/trips.ts:500` vs `:709-827` | Create-with-promo → cancel → repeat exhausts a campaign budget; 10/min/user rate limit allows ~14,400 burns/day/account | confirmed |
| F-03-30 | S3 | Financial rows are `ON DELETE CASCADE` on the user and `ON DELETE SET NULL` on the trip | `migrations/0003_global_transport.sql:29`, `:34` | Deleting a user erases their financial history; deleting a trip orphans its money rows permanently | confirmed |
| F-03-31 | S3 | No amount ceiling on payment intentions; the `topUpSchema` cap is dead code | `apps/api/src/routes/payments.ts:13` vs `wallet.ts:12-14` | A fat-fingered 500000 goes straight to Paymob; the declared 50000 cap is never applied to the live path | confirmed |
| F-03-32 | S3 | Nothing can transition a payout out of `pending`; there is no approval, rejection or reversal endpoint | `apps/api/src/routes/admin.ts` (whole file, 937 lines) | The user is promised "خلال ٢٤ ساعة" at `wallet.ts:142` against a state machine with no exit | confirmed |
| F-03-33 | S4 | `wallet_transactions` is mutable and unversioned — no `updated_at`, no hash chain, no append-only trigger | `migrations/0003_global_transport.sql:27-39` | An `UPDATE` to a settled money row leaves no trace anywhere, including in `audit_log`; disputes are unwinnable | confirmed |
| F-03-34 | S4 | Money formatting is inconsistent across three `_money` helpers and two numeral systems | `rider/…/wallet_screen.dart:279`, `captain/…/wallet_screen.dart:476`, `earnings_screen.dart:66`; `AnalyticsPage.tsx:336` vs `:615` | The same 42 EGP renders `42` and `42.00` one card apart; the admin leaderboard mixes Arabic-Indic and Western digits in adjacent columns | confirmed |

### The S1 set, in prose

**F-03-01 — The captain is paid whether or not the rider paid. This is a live mint.**

At completion the rider's wallet debit is guarded and may legitimately match zero rows:

```js
const debitRes = await c.env.DB.prepare(
  `UPDATE users SET wallet_balance = wallet_balance - ?, wallet_balance_piastres = COALESCE(wallet_balance_piastres, 0) - ?, wallet_updated_at = ? WHERE id = ? AND wallet_balance >= ?`,
).bind(finalFare, finalFarePiastres, nowIso(), trip.rider_id, finalFare).run();

const txnStatus = (debitRes.meta && debitRes.meta.changes === 1) ? 'settled' : 'failed';
```
`apps/api/src/routes/trips.ts:997-1003`

`txnStatus` is then used only to fill the `note` and `status` columns of the ledger row at `:1009`. Execution falls through to `if (trip.captain_id) {` at `:1012`, which never reads `debitRes` or `txnStatus`, and for any non-cash method takes the else branch at `:1036` and credits the captain in full at `:1040-1053`. The trip was already flipped to `completed` at `:973`.

Worked example — fare 100, commission 20, rider wallet balance 0, `payment_method: "wallet"`:

- `finalFare` 100.00, `commission` 20.00, `captainPayout` 80.00
- the debit UPDATE matches zero rows (`wallet_balance >= 100` is false) → `changes = 0` → `txnStatus = 'failed'`
- a ledger row is written with `status='failed'`; the rider's balance is unchanged at 0
- the captain is credited **+80.00**, `status='settled'`, and `users.wallet_balance` is incremented
- **platform in 0.00, out 80.00 — net −80.00 per trip**

The money is withdrawable: `POST /captain/wallet/payout` (`wallet.ts:98-142`) validates against `users.wallet_balance`, which now holds the phantom 80, and an admin pays it in real EGP. Triggering it requires no privilege and no unusual behaviour — set `paymentMethod: "wallet"` (`schemas.ts:60`), keep the wallet empty, take the ride. A rider who simply runs out of balance mid-week does it accidentally.

**F-03-02 and F-03-03 — A single real top-up can be replayed into an unbounded balance.**

```js
await c.env.DB.prepare(
  `INSERT OR IGNORE INTO wallet_transactions (…, idempotency_key, status, created_at)
   VALUES (?, ?, 'topup', 'credit', ?, ?, ?, ?, 'settled', datetime('now'))`,
).bind(id("wt"), intention.user_id, amountEgp, amountCents, orderIdStr, idempotencyKey).run();

await c.env.DB.prepare(
  `UPDATE users SET wallet_balance = COALESCE(wallet_balance, 0) + ?, … WHERE id = ?`,
).bind(amountEgp, amountCents, nowIso(), intention.user_id).run();
```
`apps/api/src/routes/payments.ts:175-186`

`INSERT OR IGNORE` returning `changes: 0` is the *only* signal that this delivery is a replay, and the return value is discarded. The ledger stays correct at one row while `users.wallet_balance` climbs by `amountEgp` on every redelivery, and no query in the codebase reconciles the two. The correct pattern exists 85 lines below in the same file — `payments.ts:268` does `if (ins.meta && ins.meta.changes === 0) return c.json({ status: "duplicate_ignored" }, 200);` — and at `trips.ts:1028` and `:1047`. It was not applied to the primary money path.

The intention-level guard that should stop replays before they reach that code is a textbook TOCTOU:

```js
if (intention.status === "settled") {            // :166 — read at :131
  return c.json({ status: "duplicate_ignored" }, 200);
}
…
UPDATE payment_intentions SET status = 'settled', settled_at = ? WHERE id = ?   // :224 — no AND status='pending'
```

N concurrent POSTs all SELECT while status is `pending`, all clear the check, all reach the credit. There is no transaction and no conditional-UPDATE-as-lock — even though `intercity.ts:259` carries a comment describing exactly that fix. Chained with F-03-19 (the HMAC is taken from `c.req.query("hmac")` at `payments.ts:103`, which is the value Paymob places in the user-visible redirect URL, and `created_at` is signed but never checked for freshness), the attack needs no forgery: complete one genuine 10 EGP top-up, copy the signed payload from your own browser, fire it concurrently.

**F-03-04 — The intercity webhook throws after the card is captured, and retries forever.**

```sql
INSERT INTO wallet_transactions (id, user_id, type, direction, amount, amount_piastres, payment_ref, status, created_at)
 VALUES (?, ?, 'intercity_booking', 'debit', ?, ?, ?, 'settled', datetime('now'))
```
`apps/api/src/routes/payments.ts:215-220`

`'intercity_booking'` is not in the CHECK list at `migrations/0003_global_transport.sql:30`. Executed against the schema rebuilt from the migrations, this returns `CHECK constraint failed`. There is no try/catch between `payments.ts:97` and `:310`, so the throw escapes as a 500 and `UPDATE payment_intentions SET status='settled'` at `:223-227` is never reached. Paymob retries a non-2xx aggressively, and every retry throws again. The rider is charged, the booking is unrecorded, and the intention is stuck `pending` permanently.

**F-03-05 — Card intercity bookings are free.**

`intercity.ts:105-112` verifies funds only when `paymentMethod === "wallet"`. `intercity.ts:149-171` debits only when `paymentMethod === "wallet"`. For `card`, the seat claim at `:116-124` succeeds, the booking is INSERTed as `'booked'` at `:128-145`, a `qr_token` is minted at `:127` and returned to the client at `:198` — with no charge, no payment intention, and no linkage to any payment. `paymentMethod` accepts `"card"` at `apps/api/src/lib/schemas.ts:122`. Combined with F-03-04, the card path is broken at both ends: bookings made through the app are free, and bookings that do reach Paymob are captured but never recorded.

**F-03-06 — There is no city-trip refund. Not a weak one; none.**

`POST /trips/:id/cancel` (`trips.ts:709-827`) flips status, logs an event, broadcasts, tears down the offer scheduler and pushes notifications. Its entire financial footprint is the UPDATE at `:728`. Meanwhile `payments.ts:197-206` settles a `purpose='trip_payment'` capture and sets `trips.payment_status='paid'` — a column written there and read nowhere in the codebase. The cancel handler never consults it, never reverses the capture, never credits the wallet. `grep -rni refund --include=*.ts` returns only `intercity.ts` and Paymob field-name strings. There is no admin refund endpoint in `admin.ts`'s 937 lines. Every card-prepaid cancellation is therefore a chargeback or a manual bank transfer, and the platform learns about it from Paymob rather than from its own system.

**F-03-07 — It is not a ledger, and it cannot be made to balance without a schema change.**

Covered structurally in §3.2. The consequence worth stating plainly here: because there is no platform account and no entry group, "did we take the right commission this month" is not a query anyone can write. The closest available answer is `SUM(trips.commission)`, which is an accrual assertion from the trips table, not a record of money that moved. For a cash trip the platform's collection is a debit against a captain wallet that `trips.ts:1029` is free to drive negative — so the revenue line and the collectability of that revenue are unrelated numbers, and only one of them is on the dashboard.

**F-03-08 — Payouts leave the balance and never arrive anywhere.**

```js
const updateRes = await c.env.DB.prepare(
  `UPDATE users SET wallet_balance = wallet_balance - ?, wallet_updated_at = ? WHERE id = ? AND wallet_balance >= ?`,
).bind(body.amount, nowIso(), user.id, body.amount).run();
…
`INSERT INTO wallet_transactions (…) VALUES (?, ?, 'payout', 'debit', ?, ?, ?, 'pending', datetime('now'))`
```
`apps/api/src/routes/wallet.ts:113-130`

The conditional guard on the UPDATE is correct and prevents a concurrent double-spend — credit where due. Everything after it is wrong: the balance moves before the row is written, so an eviction between them loses the record while keeping the deduction; `idempotency_key` is NULL, and SQLite permits unlimited NULLs in the unique index `idx_wt_idem` (`migrations/0005_integer_currency_and_idempotency.sql:5`), so the index provides zero protection; and no route in the entire API can move that row out of `'pending'`. The response tells the captain "تم تقديم طلب السحب وسيُعالج خلال ٢٤ ساعة" (`wallet.ts:142`) against a state machine with no exit.

**F-03-09 — The captain cannot withdraw the balance the app shows them.**

The captain wallet screen reads `/captain/wallet` for the hero figure and submits 100% of it:

```dart
await state.apiPost('/captain/wallet/payout', {
  'method': method,
  'amount': _balance,
  'account_info': account,
});
```
`apps/captain/lib/screens/earnings/wallet_screen.dart:242-246`

`_balance` comes from `/captain/wallet` (`:47`, `:78`), which excludes cash-commission debits. The payout gate reads `users.wallet_balance`, which includes them. Any captain who has completed one cash trip has `wallet_balance` < displayed balance, so the withdrawal is rejected with `رصيد غير كافٍ للسحب` on a figure the app presented as available. There is **no amount field** in the UI, so partial withdrawal is not a workaround. In a cash-dominant market this blocks most of the captain population.

The same screen contradicts itself in one scroll: the ledger below the hero is fetched from `/user/wallet/transactions` (`:53`), which *does* include the commission debits, and renders each as a red `− X ج.م` (`:380`, `:455`). The captain can add up the red rows and see that the green number above never subtracted any of them.

### The S2 set, in prose

**F-03-10 — Nothing is atomic.** `DB.batch` is used once in the repo and never for money. Every settlement, refund and top-up is a sequence of independent statements with a crash window between each pair. The `INSERT OR IGNORE` + `changes === 1` pattern at `trips.ts:1028`/`:1047` prevents *double application* on retry, which is valuable and correct, but it does not make a pair atomic and it is absent from the rider debit path entirely. Because no reconciliation job exists, a desync produced by an eviction is permanent and invisible.

**F-03-11 — Cash debt is unbounded and invisible.** `trips.ts:1029-1033` is the only debit in the codebase without a `wallet_balance >= ?` guard. That is defensible in isolation — a debt ledger *should* go negative — but nothing else in the design supports it: there is no ceiling that stops dispatch, no dunning, no collection endpoint, no captain-facing display (F-03-09), and `admin.ts` reports the commission as earned regardless of whether the wallet can absorb it. inDrive's equivalent mechanism is the auto-offline debt threshold; here the equivalent is a number that grows until someone notices.

**F-03-12 — The integer migration is decorative.** Detailed in §3.1. The important consequence is forward-looking: `wallet_balance_piastres` cannot be promoted to source-of-truth by a simple cutover, because three writers have been skipping it and the log it would need to be rebuilt from is itself incomplete (F-03-07, F-03-28). The longer this sits, the more expensive the eventual correction.

**F-03-13 — The dashboard reports money that does not exist.** Reproduced on the seeded fixture: `card: reported_commission 16.00, commission_collected 0.00`; `cash: reported_commission 22.00, commission_collected 10.00`. The `صافي عمولة المنصة` ("net platform commission") label at `AnalyticsPage.tsx:337` is neither net nor collected. Two further defects compound it: the KPI and the leaderboard bucket on different timestamps (`date(created_at)` in the totals query vs `datetime(t.completed_at)` at `admin.ts:106`), so two GMV figures on one screen do not agree; and the daily SQL selects no `cancelled` column, so `d.cancelled ?? Math.max(0, d.trips - d.completed)` at `AnalyticsPage.tsx:147` always takes the fallback and exports every pending and in-progress trip to finance as cancelled (`:197`).

**F-03-14 and F-03-29 — Promo budget is drainable two different ways.** The `max_uses` check reads at `trips.ts:402-413`, tests at `:415-418`, then increments with `UPDATE promo_codes SET uses_count = uses_count + 1 WHERE code = ?` at `:500` — no `AND (max_uses IS NULL OR uses_count < max_uses)`. Concurrent creates all pass. Separately, `trip_promo` (`migrations/0002_enhancements.sql:65-70`) is INSERTed at `trips.ts:495` and read nowhere, so there is no per-user redemption limit of any kind, and `max_uses IS NULL` means unlimited at both `promo.ts:33` and `trips.ts:418`. And because cancellation never decrements the counter, create-then-cancel is a free burn loop. This is the same class of bug the codebase gets right at `intercity.ts:116-124`, `intercity.ts:150-155` and `trips.ts:1305-1314`.

**F-03-15 — The bid path throws the discount away.** `trips.ts:1299-1310` binds `acceptedPrice = selectedBid.counter_price` into both `accepted_price` and `final_fare` and never consults `trips.discount` or `trips.promo_code`. Completion reads `accepted_price` first (`:969`), so the rider is charged the full bid. The promo was already burned at creation. A rider who applies a 90 EGP promo, sees a 10 EGP estimate and accepts a 100 EGP bid is debited 100.

**F-03-24 — The captain funds the marketing.** The arithmetic ordering is *correct* — discount is applied before commission (`trips.ts:428-429`), which is what stops the platform paying out more than it collects. On fare 100, commission 20%, promo 90 off: rider pays 10, commission 2, captain gets 8, platform nets +2. Reversing the order would cost the platform 70 EGP per ride. Credit where due. But the distributional consequence is unmanaged: the captain drove a 100 EGP journey for 8 EGP, absorbing 80 of the 90 EGP discount. There is no consent, no disclosure in the app, and no `promo_subsidy` line anywhere — `promo_credit` is a legal `type` in the CHECK that nothing ever writes. This needs a product decision (§10), not a patch.

**F-03-17, F-03-18, F-03-19, F-03-23 — The PSP boundary leaks in four directions.** Declined cards are written as `direction='credit'` rows (`payments.ts:234-239`), safe only because every consumer happens to filter on status — and `wallet.ts:59` does not filter on status at all, being saved only by its `type IN (…)` list. `is_refunded` and `is_voided` arrive inside the signed HMAC field set (`paymob.ts:173`, `:175`) and are never read, so a refund callback carries the same `order.id`, hits the `settled` guard at `:166` and is discarded as a duplicate. The HMAC is accepted from the query string with no freshness check. And every rejected-HMAC and amount-mismatch event is written to `audit_log` with `actor_id: "paymob"` against a column declared `REFERENCES users(id)` (`migrations/0002_enhancements.sql:41`) — the INSERT fails the FK, `audit.ts:33-36` correctly swallows it so the request is not broken, and the signal is lost.

**Worth stating: the HMAC verification itself is good.** `paymob.ts:162-183` matches Paymob's documented 20-field transaction-callback order precisely and covers `amount_cents`, `order.id`, `id` and `success`; `:222-223` fails closed when the secret is unset; `:231-235` is a proper constant-time comparison. A forged callback cannot credit an arbitrary wallet or flip a failure into a success. The amount-tamper check at `payments.ts:148` compares integer piastres against the stored intention and refuses to credit on mismatch. Those are the right controls, correctly built. The failures above are all downstream of them.

---

## 5. Benchmark gap

**Uber — immutable double-entry.** Uber's money movement is recorded as balanced journal entries: every trip produces a set of postings that sum to zero across rider, driver, platform-revenue and tax accounts, written as one atomic unit with a shared entry-group identifier. The ledger is append-only; a correction is a new reversing entry, never an UPDATE. Settlement files from each PSP are ingested daily and reconciled line-by-line against the internal ledger, with breaks routed to an ops queue. *(Confident on the double-entry and immutability model; confident on daily PSP reconciliation as standard practice at that scale.)*

Synaptic Go has none of the four: entries are single-sided (§3.2), there is no platform account, rows are mutable with no audit trail (F-03-33), and no PSP settlement file is stored or compared — `payment_ref` holds a Paymob order id and nothing records what Paymob actually remitted.

**inDrive — cash-first commission debt.** In cash-dominant markets inDrive tracks each driver's accrued commission as an explicit debt balance, surfaces it prominently in the driver app, and enforces a threshold: cross it and the driver is taken offline until they settle, typically by topping up through a local payment network. The debt is a first-class product concept with its own screen, its own notifications and its own collection flow. *(Confident on the mechanism; the specific threshold varies by market — assumed.)*

Synaptic Go has the correct *direction* — cash commission is debited from the captain rather than credited (`trips.ts:1013-1035`), and the comment at `:988-990` shows the double-pay trap was consciously avoided. That is genuinely the right model and the hardest part to get right. Everything around it is absent: no threshold, no floor (`:1029` is the only unguarded debit in the codebase), no auto-offline, no dunning, no collection endpoint, and — most damagingly — no display, because `GET /captain/wallet` structurally excludes the very rows that represent the debt (F-03-09). A captain accumulating debt cannot see it, and the first they learn of it is a rejected withdrawal.

**Careem — regional payout expectations.** Captains in the region expect a visible, dated payout cycle with a per-trip earnings breakdown they can audit, and cash-out through the rails they actually use — InstaPay, Vodafone Cash, Fawry, bank transfer.

Synaptic Go promises "every Monday 10:00" as a hardcoded string (`wallet.ts:88`) against a payout state machine with no exit (F-03-32), exposes only two of the four rails its own API accepts (`apps/captain/lib/screens/earnings/wallet_screen.dart:146`, `:165` vs `wallet.ts:95` — Fawry, the largest cash-out network in the country, is unreachable from the UI), and offers no per-trip breakdown anywhere: `/captain/earnings` returns a single `SUM` over a fixed 7-day window (`captain.ts:278-299`).

**Egyptian reality — the specific gaps that matter here.** Cash is the dominant method and it *is* modelled, which puts this codebase ahead of a naive card-only build. But the surrounding assumptions do not hold: riders top up through Paymob/Fawry/Vodafone Cash and the top-up path has the replay defect (F-03-02) and no upper bound (F-03-31); captains distrust opaque deductions and the only commission figure in the captain wallet is rounded to whole pounds (F-03-20) with no per-trip attribution; and an Arabic-keyboard rider literally cannot type an amount into the top-up field, because `double.tryParse` rejects Arabic-Indic digits and the handler returns silently with no error (F-03-21).

**Where Synaptic Go sits.** On the model, roughly at parity with inDrive for cash direction and behind everyone on everything else. On the mechanics, it is pre-alpha: five paths that move real money incorrectly, no reconciliation, no refunds, no immutability. The distance to Uber is a schema change plus a settlement rewrite. The distance to a defensible v1 is smaller than it looks, because the correct patterns already exist in this codebase — they are simply not applied uniformly, and §6 is largely a matter of finishing what the team started.

---

## 6. Improvement plan

Ordered. P0 items are the S1 set and must land before any production traffic; P1 and P2 follow in §7.

### P0.1 — Stop the mint: gate the captain credit on the rider debit

- **Goal.** The platform never pays out money it did not collect.
- **Design.** Two changes in `POST /trips/:id/complete`. First, hoist the settlement in front of the status flip: attempt the rider debit *before* `UPDATE trips SET status='completed'`, and if it fails, refuse the transition with `402 SETTLEMENT_FAILED` and leave the trip `in_progress` so it can be retried or resolved by ops. Second, make the captain-credit block conditional on the debit having settled — for wallet trips, `if (txnStatus !== 'settled') skip the credit and enqueue a settlement-retry row`. A completed trip with an unpaid rider is an accounts-receivable event, not a silent platform loss. The captain must still be made whole, but from a deliberate write-off or a rider debt row, not from an unnoticed accounting hole.
- **Files to change.** `apps/api/src/routes/trips.ts` (951-1088).
- **DB.** New migration `0020_settlement_retry.sql` — `settlement_queue(id TEXT PRIMARY KEY, trip_id TEXT NOT NULL REFERENCES trips(id), reason TEXT NOT NULL, attempts INTEGER NOT NULL DEFAULT 0, last_error TEXT, status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open','resolved','written_off')), created_at TEXT NOT NULL DEFAULT (datetime('now')))`.
- **API contract.** `POST /trips/:id/complete` gains a `402` response `{ error, code: "SETTLEMENT_FAILED", shortfall: <number> }`. Captain app must handle it — see the T10 handoff in §9.
- **Effort.** M.
- **Risk.** A captain who completes a trip for an insolvent rider is now blocked at the completion step, which is worse UX than today's silent failure. Mitigation: allow completion but mark `payment_status='unpaid'`, credit the captain from a named `platform:bad_debt` account, and surface the rider debt. Rollback is a revert — no schema dependency in the hot path.
- **Acceptance criteria.** A wallet trip completed against a rider with insufficient balance produces: no captain credit from thin air, a `settlement_queue` row, and a rider balance unchanged. Sum of captain credits over any period ≤ sum of rider debits + card receipts + written-off debt.
- **Tests.** Integration test: rider balance 0, fare 100 → assert `users.wallet_balance` for the captain is unchanged and a queue row exists. Property test over random (fare, balance) pairs asserting conservation.

### P0.2 — Make the Paymob webhook replay-safe

- **Goal.** N deliveries of the same callback move money exactly once.
- **Design.** Three changes in `payments.ts`. (a) Gate the balance UPDATE on the ledger INSERT: capture `ins.meta.changes` and return `duplicate_ignored` when it is 0 — the pattern already used correctly at `payments.ts:268` and `trips.ts:1028`. (b) Make the settle conditional: `UPDATE payment_intentions SET status='settled', settled_at=? WHERE id=? AND status='pending'`, and treat `changes === 0` as a lost race. (c) Change the idempotency key from `paymob:${orderIdStr}:${txnId}` to `paymob:${orderIdStr}` so a second transaction on the same order cannot open a second credit. Additionally, reject the query-string HMAC in favour of `body.hmac` and enforce a `created_at` freshness window (15 minutes).
- **Files to change.** `apps/api/src/routes/payments.ts` (97-313), `apps/api/src/lib/paymob.ts` (verification entry point).
- **DB.** None.
- **API contract.** Unchanged externally; the webhook keeps returning 200 for duplicates.
- **Effort.** S.
- **Risk.** Tightening the key to order-only means a legitimate second capture on one order is refused — correct, given `lock_order_when_paid: "true"` at `paymob.ts:74`. Rollback: revert; the ledger rows written under the old key remain valid.
- **Acceptance criteria.** 50 concurrent identical callbacks credit the wallet exactly once and leave exactly one ledger row. A callback older than the freshness window is rejected with 401.
- **Tests.** Concurrency test firing N parallel requests against a test D1; assert balance delta == amount and `COUNT(*) == 1`.

### P0.3 — Fix the two intercity money bugs

- **Goal.** Card intercity bookings are charged, and the webhook stops throwing.
- **Design.** (a) Add `'intercity_booking'` to the `wallet_transactions.type` CHECK — or, better, reuse `'trip_payment'` and rely on the new `entry_group_id` (P0.5) for classification; the second option avoids a table rebuild. (b) In `POST /intercity/bookings`, refuse `paymentMethod: "card"` until a payment intention is created and settled — either block the method at the schema (`schemas.ts:122`) as an immediate stopgap, or create the intention inline and hold the seat in a `pending_payment` state with a TTL. (c) Wrap the webhook body in try/catch so a constraint failure returns 200 with an alert rather than driving an infinite retry loop.
- **Files to change.** `apps/api/src/routes/intercity.ts` (95-200), `apps/api/src/routes/payments.ts` (213-227), `apps/api/src/lib/schemas.ts` (122).
- **DB.** Migration `0021_wallet_tx_type_check.sql` — SQLite cannot alter a CHECK in place; requires the 12-step table rebuild (`PRAGMA legacy_alter_table`, create new, copy, drop, rename, recreate indexes). Sequence it with P0.5 so the table is rebuilt once, not twice.
- **API contract.** `POST /intercity/bookings` may return `409 PAYMENT_REQUIRED` for card until the intention settles.
- **Effort.** M.
- **Risk.** The table rebuild is the riskiest DDL in this plan. Mitigation: do it inside P0.5's rebuild, take a D1 export first, and verify row counts and `SUM(amount)` before and after.
- **Acceptance criteria.** No card booking exists in `intercity_bookings` without a settled intention. The intercity webhook branch returns 200 and writes a valid row.
- **Tests.** Insert each `type` value against the new CHECK. End-to-end card booking test asserting no free seats.

### P0.4 — Reconcile the three balances into one

- **Goal.** One definition of a user's balance, used everywhere.
- **Design.** Delete `wallet.ts:58-72`. Introduce a single `getBalance(db, userId)` helper that derives the balance from the ledger with a correct predicate — `status='settled' OR (type='payout' AND status='pending')` — and have `GET /user/wallet`, `GET /captain/wallet` and the payout gate all call it. Add the cash-commission debt as an explicit, separately labelled figure (`owedToPlatform`) rather than folding it invisibly into one number. Delete the `user_credits` read at `user.ts:80-84` or wire the table up; a permanently-zero field in the profile response is worse than no field.
- **Files to change.** `apps/api/src/routes/wallet.ts`, `apps/api/src/routes/user.ts`, `apps/api/src/lib/utils.ts` (new helper), `apps/captain/lib/screens/earnings/wallet_screen.dart`, `apps/rider/lib/screens/wallet/wallet_screen.dart`.
- **DB.** None.
- **API contract.** `GET /captain/wallet` response becomes `{ balance, available, owedToPlatform, currency, weekTrips, weekCommission, nextPayoutWindow }`. `available = max(0, balance)` is the withdrawable figure and is what the app must submit.
- **Effort.** M.
- **Risk.** Captain-visible balances will change — some will drop, correctly, by the amount of commission debt they already owe. This needs a comms plan, not just a deploy. Rollback: keep the old fields in the response for one release.
- **Acceptance criteria.** For every captain, the figure displayed as withdrawable is accepted by the payout endpoint. `owedToPlatform` is non-zero for any captain with an unsettled cash trip.
- **Tests.** Golden-file test over a seeded ledger asserting all three endpoints agree.

### P0.5 — Make it a ledger: entry groups, accounts, integers, immutability

- **Goal.** Every money movement is a balanced set of postings that sums to zero and cannot be silently edited.
- **Design.** Rebuild `wallet_transactions` with `entry_group_id TEXT NOT NULL`, `account TEXT NOT NULL` (`user:<id>` | `platform:commission` | `platform:bad_debt` | `platform:promo_subsidy` | `psp:paymob` | `cash:captain_float`), `amount_piastres INTEGER NOT NULL` as the *only* amount column, `balance_after_piastres INTEGER`, and a `signed` convention that lets `SUM` work directly. Enforce `SUM(amount_piastres) = 0` per `entry_group_id` in the write helper and verify it in the reconciliation job. Make the table append-only — corrections are new reversing groups, never UPDATEs. Write every settlement through a single `postEntryGroup(db, entries[])` helper that uses `DB.batch` so the postings land atomically. Change `user_id` FK to `RESTRICT` and `trip_id` to `RESTRICT`.
- **Files to change.** New `apps/api/src/lib/ledger.ts`; call sites in `trips.ts`, `payments.ts`, `intercity.ts`, `wallet.ts`.
- **DB.** Migration `0022_double_entry_ledger.sql` — new table, backfill from the existing rows into single-sided groups flagged `legacy: true` (they cannot be balanced retroactively; that is the honest record), cut over reads, keep the old table for one release.
- **API contract.** No external change; response shapes are preserved by the helper.
- **Effort.** L.
- **Risk.** This is the largest change in the plan and it touches every money path. Mitigation: land it behind a dual-write flag — write both old and new for one release, run the reconciliation job across both, cut reads over only when they agree for 7 consecutive days.
- **Acceptance criteria.** Every new settlement produces a group summing to zero. A trial balance query returns zero across all accounts for any date range containing only post-cutover entries.
- **Tests.** Property test: for random trip parameters, assert the posted group sums to zero and the account set matches the payment method.

### P0.6 — Cash commission: floor, ceiling, visibility, collection

- **Goal.** Commission debt is bounded, visible and collectable.
- **Design.** Keep the negative balance — it is the correct representation — but bound it. Add `system_config.max_commission_debt_egp` (default 200) and check it at dispatch: a captain over the threshold is not offered trips and sees a blocking screen with a top-up CTA. Surface `owedToPlatform` in the captain wallet (P0.4). Add a settle-debt flow reusing the existing Paymob top-up path.
- **Files to change.** `apps/api/src/routes/trips.ts` (:1029 area), `apps/api/src/lib/nearby.ts` or the dispatch filter, `apps/captain/lib/screens/earnings/wallet_screen.dart`, `apps/api/src/routes/admin.ts` (a debt report).
- **DB.** Migration `0023_commission_debt.sql` — seed the config key; add `idx_users_negative_balance` partial index if D1 supports it, else a plain index on `wallet_balance`.
- **API contract.** `GET /captain/wallet` gains `owedToPlatform`, `debtCeiling`, `blocked: boolean`.
- **Effort.** M.
- **Risk.** Blocking captains at a threshold will reduce supply on day one. Set the ceiling generously, alert at 50%, and ship the settle flow before the block.
- **Acceptance criteria.** No captain accrues debt beyond the ceiling. Every captain with debt can see the figure and settle it in-app.
- **Tests.** Simulate 20 cash trips against a captain with no balance; assert dispatch stops at the ceiling.

### P0.7 — The reconciliation job and the invariant set

- **Goal.** A daily job that proves, or disproves, that money is conserved — and pages someone when it is not.
- **Design.** A cron-triggered Worker that runs each query below and writes results to a `reconciliation_runs` table, alerting on any non-empty result. Every comparison on `REAL` uses a 0.005 tolerance (half a piastre), because `SUM()` over `REAL` drifts — 10,000 × 0.07 sums to 700.000000000091, so equality tests produce false positives until P0.5 makes the integer column authoritative.

**Note on the "money moved" predicate.** It is *not* `status='settled'`. Payout debits move the balance while sitting at `'pending'` (`wallet.ts:113-130`), so the correct predicate is `status='settled' OR (type='payout' AND status='pending')`. That this needs a special case is itself F-03-08.

| # | Invariant | Enforced today? |
|---|---|---|
| INV-1 | `SUM(signed moved amount)` per user `==` `users.wallet_balance` | **No.** Nothing reconciles them. Fails for every card payer. |
| INV-2 | `wallet_balance_piastres == ROUND(wallet_balance*100)` | **No.** Three writers skip it; the column is read nowhere. |
| INV-3 | `amount_piastres == ROUND(amount*100)`, never NULL | **No.** Nullable, no CHECK; `intercity.ts:166`/`:284` omit it. |
| INV-4 | Per completed non-cash trip, `ledger_payout + commission == final_fare` | **At write time only** (`trips.ts:971` defines payout as the residual). Never re-checked. |
| INV-5 | Each completed trip has exactly one settlement group of the shape its payment method requires | **No.** No uniqueness on `(trip_id, type, direction)`. |
| INV-6 | `0 <= commission <= final_fare` | **No.** `trips.commission` is a bare nullable REAL. |
| INV-7 | Stored commission `==` city rule × fare | **No.** Detects F-03-16 and manual edits. |
| INV-8 | `commission_rate ∈ [0,1]` and `default_commission_pct ∈ (1,100]` | **No.** The percent/fraction tripwire for F-03-26. |
| INV-9 | No `wallet_balance < 0` outside the commission-debt facility | **No.** No CHECK; `trips.ts:1029` is unguarded. |
| INV-10 | Every ledger row is attributable to a trip, a PSP ref, or an idempotency key | **No.** Catches F-03-28 and `SET NULL` orphans. |
| INV-11 | Every money-moving row carries an idempotency key | **Partially.** `trips.ts`/`payments.ts` yes; `wallet.ts:125`, `intercity.ts:166`, `:284` no. NULLs bypass the unique index entirely. |
| INV-12 | No duplicate settlement per trip leg | **No.** `INSERT OR IGNORE` protects only where a key is supplied. |
| INV-13 | A ledger row's `user_id` matches its role in the trip | **No.** No FK ties `(user_id, trip_id)` to `(rider_id\|captain_id)`. |
| INV-14 | Cash commission billed `==` cash commission collected | **No.** Quantifies uncollectable revenue booked as earned. |
| INV-15 | Lifetime payouts never exceed lifetime credits | **Only against the denormalised balance** at `wallet.ts:104-111`, which INV-1 shows is not the ledger. |
| INV-16 | No pending payout older than the promised 24h SLA | **No.** Nothing can transition a payout out of `pending` (F-03-32). |
| INV-17 | Reported GMV/commission `==` money actually moved | **No.** The master reconciliation. |
| INV-18 | Ledger rows are immutable | **No — and not detectable.** No `updated_at`, no hash chain, no audit trail. No query can be written; this is why F-03-33 matters. |

The queries. Each was executed against the schema rebuilt from `migrations/` and verified to return exactly the seeded violations.

```sql
-- INV-1  ledger vs denormalised balance
WITH moved AS (
  SELECT user_id, SUM(CASE WHEN direction='credit' THEN amount ELSE -amount END) AS ledger
  FROM wallet_transactions
  WHERE status='settled' OR (type='payout' AND status='pending')
  GROUP BY user_id)
SELECT u.id, u.role, u.wallet_balance, COALESCE(m.ledger,0) AS ledger_sum,
       ROUND(u.wallet_balance - COALESCE(m.ledger,0),2) AS drift_egp
FROM users u LEFT JOIN moved m ON m.user_id = u.id
WHERE ABS(u.wallet_balance - COALESCE(m.ledger,0)) > 0.005;

-- INV-2  integer mirror on users
SELECT id, role, wallet_balance, wallet_balance_piastres,
       CAST(ROUND(wallet_balance*100) AS INTEGER) AS expected_piastres
FROM users
WHERE wallet_balance_piastres IS NULL
   OR wallet_balance_piastres <> CAST(ROUND(wallet_balance*100) AS INTEGER);

-- INV-3  integer mirror on ledger rows
SELECT id, user_id, type, direction, amount, amount_piastres,
       CAST(ROUND(amount*100) AS INTEGER) AS expected
FROM wallet_transactions
WHERE amount_piastres IS NULL
   OR amount_piastres <> CAST(ROUND(amount*100) AS INTEGER);

-- INV-4  payout + commission == fare, per completed non-cash trip
SELECT t.id, t.payment_method, t.final_fare, t.commission,
       COALESCE(p.payout,0) AS ledger_payout,
       ROUND(COALESCE(p.payout,0) + COALESCE(t.commission,0) - COALESCE(t.final_fare,0),2) AS imbalance
FROM trips t
LEFT JOIN (SELECT trip_id, SUM(amount) AS payout FROM wallet_transactions
           WHERE type='commission' AND direction='credit' AND status='settled'
           GROUP BY trip_id) p ON p.trip_id = t.id
WHERE t.status='completed' AND t.payment_method <> 'cash' AND t.captain_id IS NOT NULL
  AND ABS(COALESCE(p.payout,0) + COALESCE(t.commission,0) - COALESCE(t.final_fare,0)) > 0.005;

-- INV-5  exactly one settlement group per completed trip, shaped by payment method
SELECT t.id, t.payment_method, t.billed_to_company, t.final_fare, t.commission,
       (SELECT COUNT(*) FROM wallet_transactions w WHERE w.trip_id=t.id
          AND w.type='trip_payment' AND w.direction='debit')  AS rider_rows,
       (SELECT COUNT(*) FROM wallet_transactions w WHERE w.trip_id=t.id
          AND w.type='commission')                            AS captain_rows
FROM trips t
WHERE t.status='completed' AND (
   (t.payment_method='cash' AND COALESCE(t.commission,0)>0
     AND (SELECT COUNT(*) FROM wallet_transactions w WHERE w.trip_id=t.id
            AND w.type='commission' AND w.direction='debit' AND w.status='settled') <> 1)
OR (t.payment_method='wallet' AND t.billed_to_company=0
     AND (SELECT COUNT(*) FROM wallet_transactions w WHERE w.trip_id=t.id
            AND w.type='trip_payment' AND w.direction='debit') <> 1)
OR (t.payment_method<>'cash' AND t.captain_id IS NOT NULL
     AND (SELECT COUNT(*) FROM wallet_transactions w WHERE w.trip_id=t.id
            AND w.type='commission' AND w.direction='credit' AND w.status='settled') <> 1));

-- INV-6  commission bounds
SELECT id, city, payment_method, final_fare, commission,
       ROUND(commission / NULLIF(final_fare,0),4) AS effective_rate
FROM trips
WHERE status='completed'
  AND (commission IS NULL OR commission < 0
    OR commission > COALESCE(final_fare, estimated_fare, 0) + 0.005
    OR final_fare IS NULL OR final_fare < 0);

-- INV-7  stored commission vs city rule  (expect legitimate hits where a rate changed mid-flight)
SELECT t.id, t.city, t.completed_at, t.final_fare, t.commission,
       COALESCE(pr.commission_rate, 0.2) AS rule_rate,
       ROUND(t.commission / NULLIF(t.final_fare,0),4) AS effective_rate,
       ROUND(t.commission - ROUND(t.final_fare * COALESCE(pr.commission_rate,0.2),2),2) AS delta
FROM trips t LEFT JOIN pricing_rules pr ON pr.city = t.city
WHERE t.status='completed' AND COALESCE(t.final_fare,0) > 0
  AND ABS(t.commission - ROUND(t.final_fare * COALESCE(pr.commission_rate,0.2),2)) > 0.01;

-- INV-8  rate units are unambiguous  (run before and after any pricing migration)
SELECT 'pricing_rules' AS source, city AS k, CAST(commission_rate AS TEXT) AS v,
       'commission_rate must be a 0-1 fraction; >1 means a percent was stored' AS rule
FROM pricing_rules WHERE commission_rate < 0 OR commission_rate > 1
UNION ALL
SELECT 'system_config', key, value,
       'default_commission_pct must be a 0-100 percent; <=1 means a fraction was stored'
FROM system_config WHERE key='default_commission_pct'
  AND (CAST(value AS REAL) < 0 OR CAST(value AS REAL) > 100 OR CAST(value AS REAL) <= 1);

-- INV-9  negative balances
SELECT id, role, name, phone, wallet_balance, wallet_updated_at
FROM users WHERE wallet_balance < 0 ORDER BY wallet_balance ASC;

-- INV-10  unattributable rows
SELECT w.id, w.user_id, w.type, w.direction, w.amount, w.trip_id, w.payment_ref, w.status, w.created_at
FROM wallet_transactions w
WHERE (w.trip_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM trips t WHERE t.id = w.trip_id))
   OR (w.trip_id IS NULL AND w.payment_ref IS NULL AND w.idempotency_key IS NULL);

-- INV-11  rows with no idempotency key, by exposure
SELECT type, direction, status, COUNT(*) AS rows_at_risk, ROUND(SUM(amount),2) AS egp_at_risk
FROM wallet_transactions
WHERE idempotency_key IS NULL
  AND type IN ('payout','refund','adjustment','trip_payment','topup','commission')
GROUP BY type, direction, status ORDER BY egp_at_risk DESC;

-- INV-12  duplicate settlement legs
SELECT trip_id, type, direction, COUNT(*) AS n, ROUND(SUM(amount),2) AS egp,
       GROUP_CONCAT(id) AS row_ids,
       GROUP_CONCAT(COALESCE(idempotency_key,'<null>')) AS keys
FROM wallet_transactions
WHERE trip_id IS NOT NULL AND status='settled'
GROUP BY trip_id, type, direction HAVING COUNT(*) > 1;

-- INV-13  row counterparty matches trip role
SELECT w.id, w.user_id, w.type, w.direction, w.amount, w.trip_id, t.rider_id, t.captain_id
FROM wallet_transactions w JOIN trips t ON t.id = w.trip_id
WHERE (w.type='trip_payment' AND w.direction='debit' AND w.user_id <> t.rider_id)
   OR (w.type='commission' AND (t.captain_id IS NULL OR w.user_id <> t.captain_id));

-- INV-14  cash commission billed but never collected
SELECT t.id, t.captain_id, t.completed_at, t.final_fare, t.commission
FROM trips t
WHERE t.status='completed' AND t.payment_method='cash' AND COALESCE(t.commission,0) > 0
  AND NOT EXISTS (SELECT 1 FROM wallet_transactions w
                  WHERE w.trip_id = t.id AND w.type='commission'
                    AND w.direction='debit' AND w.status='settled');

-- INV-15  lifetime payouts vs lifetime credits
WITH e AS (
  SELECT user_id,
         SUM(CASE WHEN direction='credit' THEN amount ELSE 0 END) AS earned,
         SUM(CASE WHEN type='payout' AND direction='debit' THEN amount ELSE 0 END) AS paid
  FROM wallet_transactions WHERE status IN ('settled','pending') GROUP BY user_id)
SELECT user_id, ROUND(earned,2) AS earned, ROUND(paid,2) AS paid_out,
       ROUND(paid - earned,2) AS overpaid
FROM e WHERE paid > earned + 0.005 ORDER BY overpaid DESC;

-- INV-16  payouts past SLA  (every row here is permanent until F-03-32 is fixed)
SELECT w.id, w.user_id, w.amount, w.note AS method_and_account, w.created_at,
       ROUND(julianday('now') - julianday(w.created_at),1) AS age_days
FROM wallet_transactions w
WHERE w.type='payout' AND w.direction='debit' AND w.status='pending'
  AND julianday('now') - julianday(w.created_at) > 1
ORDER BY age_days DESC;

-- INV-17  master reconciliation: reported vs moved, by payment method
WITH completed AS (
  SELECT id, payment_method, COALESCE(final_fare,0) AS fare, COALESCE(commission,0) AS comm
  FROM trips WHERE status='completed'
    AND completed_at >= :from AND completed_at < :to),
moved AS (
  SELECT w.trip_id,
    SUM(CASE WHEN w.type='trip_payment' AND w.direction='debit'  AND w.status='settled' THEN w.amount ELSE 0 END) AS rider_in,
    SUM(CASE WHEN w.type='commission'   AND w.direction='debit'  AND w.status='settled' THEN w.amount ELSE 0 END) AS comm_collected,
    SUM(CASE WHEN w.type='commission'   AND w.direction='credit' AND w.status='settled' THEN w.amount ELSE 0 END) AS captain_paid
  FROM wallet_transactions w WHERE w.trip_id IS NOT NULL GROUP BY w.trip_id)
SELECT c.payment_method,
       COUNT(*)                                                 AS trips,
       ROUND(SUM(c.fare),2)                                     AS reported_gmv,
       ROUND(SUM(c.comm),2)                                     AS reported_commission,
       ROUND(SUM(COALESCE(m.rider_in,0)),2)                     AS rider_money_in,
       ROUND(SUM(COALESCE(m.comm_collected,0)),2)               AS commission_collected,
       ROUND(SUM(COALESCE(m.captain_paid,0)),2)                 AS captain_credited,
       ROUND(SUM(c.comm) - SUM(COALESCE(m.comm_collected,0)),2) AS commission_reported_but_not_collected
FROM completed c LEFT JOIN moved m ON m.trip_id = c.id
GROUP BY c.payment_method;
```

- **Files to change.** New `apps/api/src/lib/reconcile.ts`; register a third cron trigger in `wrangler.toml`. Proposed CI/cron YAML must not be committed to `.github/workflows/**` in this phase — see §9.
- **DB.** Migration `0024_reconciliation_runs.sql` — `reconciliation_runs(id, ran_at, invariant, violation_count, sample_json, severity)`.
- **API contract.** `GET /admin/reconciliation` (admin-only) returning the latest run.
- **Effort.** M.
- **Risk.** On first run this will return large violation counts — that is the point, and it must not be mistaken for a broken job. Bootstrap by recording the day-one baseline and alerting on *deltas* until the P0 fixes land, then switch to alerting on any non-zero.
- **Acceptance criteria.** The job runs daily, completes inside the Worker CPU limit, and pages on any new violation.
- **Tests.** Each query has a fixture with a seeded violation and asserts exactly one row returned.

### P1.1 — Refunds and reversals

- **Goal.** Money can go back.
- **Design.** Implement `status='reversed'` as a real state written by a reversing entry group. Handle `is_refunded` / `is_voided` / `pending` on the Paymob callback. Build `POST /admin/refunds` (idempotent, reason-coded, audit-logged) and a rider-facing cancellation refund that respects `free_cancel_min`. Wire `cancel_fee_egp` so the configured penalty is actually charged (F-03-25).
- **Files.** `apps/api/src/routes/payments.ts`, `trips.ts` (709-827), `admin.ts`, `apps/api/src/lib/ledger.ts`.
- **DB.** None beyond P0.5. **API.** `POST /admin/refunds`, `POST /trips/:id/cancel` gains `{ fee, refunded }`. **Effort.** L.
- **Risk.** Refund abuse; mitigate with per-user rate limits and reason codes. **Acceptance.** Every capture is reversible in one admin action; a late cancellation charges the configured fee. **Tests.** Refund idempotency under replay.

### P1.2 — Promo integrity

- **Goal.** A campaign budget cannot be exceeded, and the subsidy is visible.
- **Design.** Guard the increment: `UPDATE promo_codes SET uses_count = uses_count + 1 WHERE code = ? AND (max_uses IS NULL OR uses_count < max_uses)` with a `changes === 0` check. Add a per-user redemption table and read `trip_promo` instead of leaving it write-only. Carry `discount` through the bid-accept path (F-03-15). Post the subsidy as a `platform:promo_subsidy` posting so marketing spend appears in the ledger. Decide the captain-subsidy question (§10) and implement whichever answer.
- **Files.** `trips.ts` (402-504, 1299-1310), `promo.ts`. **DB.** `0025_promo_redemptions.sql`. **Effort.** M.
- **Risk.** Changing who funds the discount changes unit economics — model it before shipping. **Acceptance.** N concurrent redemptions of a 1-use code yield exactly one discount. **Tests.** Concurrency test on the counter.

### P1.3 — Payout lifecycle

- **Goal.** A payout request reaches a terminal state.
- **Design.** `POST /admin/payouts/:id/approve|reject`, with rejection reversing the balance deduction via a reversing group. Replace the hardcoded `"every Monday 10:00"` with a real schedule. Expose all four rails the API accepts in the captain UI. Add an amount field so partial withdrawal is possible.
- **Files.** `wallet.ts`, `admin.ts`, `apps/captain/lib/screens/earnings/wallet_screen.dart`. **DB.** none beyond P0.5. **Effort.** M.
- **Acceptance.** No payout older than the SLA sits in `pending`. **Tests.** Approve/reject state-machine coverage.

### P2.1 — Reporting from the ledger

Repoint `admin.ts` analytics and `captain.ts` earnings at the ledger rather than `trips`, add per-trip earnings breakdown to the captain app (gross / commission / net per trip), fix the leaderboard bucket mismatch and the fabricated CSV `cancelled` column, and add a PSP settlement-file ingest that reconciles Paymob's remittance against the internal ledger. **Effort.** L.

### P2.2 — Money presentation

One shared money formatter across both Flutter apps and the admin console; one numeral system per locale; `toStringAsFixed(2)` everywhere including the commission chip; `inputFormatters` accepting Arabic-Indic digits on the top-up field with a visible validation error; real pending/failed states on top-up instead of a liveness probe. **Effort.** M. Coordinate with **T27** and **T14**.

---

## 7. Phasing

| Item | Phase | Effort | Owner type |
|---|---|---|---|
| P0.1 Gate captain credit on rider debit | **P0** | M | backend |
| P0.2 Webhook replay safety | **P0** | S | backend |
| P0.3 Intercity card + CHECK violation | **P0** | M | backend |
| P0.4 One balance definition | **P0** | M | backend + Flutter |
| P0.5 Double-entry ledger rebuild | **P0** | L | backend |
| P0.6 Cash debt floor/ceiling/visibility | **P0** | M | backend + Flutter |
| P0.7 Reconciliation job + invariants | **P0** | M | backend + ops |
| P1.1 Refunds and reversals | P1 | L | backend + admin |
| P1.2 Promo integrity | P1 | M | backend |
| P1.3 Payout lifecycle | P1 | M | backend + admin + Flutter |
| P2.1 Reporting from the ledger | P2 | L | backend + admin |
| P2.2 Money presentation | P2 | M | Flutter + admin |

**Sequencing note.** P0.5 is the spine and P0.1–P0.4 are cheaper to write against the new ledger than the old one. But P0.1, P0.2 and P0.3 are active money leaks and must not wait for an L-sized rebuild. Ship them as point fixes against the current schema first — they are each self-contained — then land P0.5 and refactor them onto `postEntryGroup`. P0.3's CHECK change should be folded into P0.5's table rebuild so the table is rebuilt once.

**Not production-eligible until:** P0.1, P0.2, P0.3, P0.4, P0.6 and P0.7 are live. P0.5 can trail by one release if and only if P0.7 is running and green, because the reconciliation job is what makes the interim safe.

---

## 8. Metrics

| Metric | Definition | Current | Target |
|---|---|---|---|
| Ledger drift | count of users failing INV-1 | unknown — never measured; guaranteed > 0 for every card payer | 0, checked daily |
| Phantom payout rate | captain credits with no corresponding rider debit or card receipt (INV-17) | unknown; structurally unbounded | 0 |
| Uncollected cash commission | `commission_reported_but_not_collected` from INV-17 | unknown | < 2% of cash commission, ageing < 7 days |
| Webhook replay credits | duplicate credits per 1,000 callbacks | unbounded (F-03-02) | 0 |
| Free intercity bookings | card bookings with no settled intention (F-03-05) | unbounded | 0 |
| Captain debt over ceiling | captains with `owedToPlatform` > threshold | unbounded, invisible | 0 |
| Payout SLA breach | payouts `pending` > 24h (INV-16) | 100% — nothing can settle them | < 1% |
| Balance/withdrawal mismatch | payout rejections where the app showed sufficient funds (F-03-09) | ~100% of cash captains | 0 |
| GMV reconciliation gap | \|reported GMV − money moved\| ÷ reported GMV | unknown | < 0.5% |
| Refund coverage | share of captured payments that are reversible in one admin action | 0% | 100% |
| Earnings dispute rate | captain disputes per 1,000 completed trips | not instrumented | measured, then reduced |
| Time to reconstruct a disputed day | ops minutes to produce a defensible per-trip breakdown | not possible (§3, F-03-33) | < 5 minutes, self-serve |

The first thing to instrument is INV-1 and INV-17 — until those two numbers exist, every other metric on this page is an estimate.

---

## 9. Cross-cutting notes

**To T04 (Payments, PSP & Payouts).** The webhook defects are yours as much as mine: HMAC accepted from the query string with no freshness check (`payments.ts:103`), the replay-credit bug (`:175-186`), the TOCTOU settle (`:223-227`), `is_refunded`/`is_voided` signed and ignored (`paymob.ts:173`, `:175`), no rate limit on an unauthenticated endpoint that writes to D1 before rejecting (`:106-113`), amount mismatch returning a retryable 400 (`:162`), no `expires_at` on `payment_intentions`, and the two-INSERT intention creation whose partial failure silently downgrades to a legacy branch that performs **no amount verification at all** (`:54-77` → `:251`). Also: `readPath(obj, "order.id")` returns undefined when Paymob sends `order` as a bare integer (`paymob.ts:176`, `:206-213`) — the doc comment at `:153` anticipates both shapes and the code handles one. `needs-check` against your Paymob dashboard config. The HMAC field list and constant-time comparison are correct; don't rewrite them.

**To T27 (Cross-App Parity).** The money surfaces are among the worst-duplicated in the product. Concrete pairs: `_BalanceCard` is copied class-for-class (`apps/rider/lib/screens/wallet/wallet_screen.dart:332-477` vs `apps/captain/lib/screens/earnings/wallet_screen.dart:600-750`) and has *already drifted* — the captain copy adds `maxLines: 1, overflow: TextOverflow.ellipsis` at `:661-662` that the rider copy lacks, so one truncates and the other overflows. `_Bloom` is byte-identical in both (`rider:480-497` vs `captain:793-810`). `_formatStamp` (`rider:288-297` vs `captain:488-497`), `_iconFor` (`rider:301-322` vs `captain:507-528`) and the `DateFormat` static (`rider:50` vs `captain:26`) are all verbatim copies whose own comments say they must stay identical, with nothing enforcing it. Two localisation keys exist for the same label on the same card (`availableBalance` vs `availableBalanceHero`). The rider surfaces a real `ErrorState` with retry (`rider:142-146`) while the captain swallows the error (`captain:59`) and shows "no transactions yet" to a captain whose request failed. Pull-to-refresh exists only on the rider side. Three different loading treatments across three money screens. And `topup_screen.dart` is the only money surface with hardcoded Arabic strings and bare `TextStyle` instead of `AppStrings`/`AppTokens` (`:117`, `:128`, `:139`, `:161`, `:166`, `:171`, `:189`) — the exact defect `earnings_screen.dart:12-13` documents as already fixed elsewhere. Vocabulary drift: the captain's trip income is `أرباح`/`netForYou` on one screen, `balance` on another, and stored under `type='commission'` in the database, rendered with a percent icon.

**To T10 (Captain App Journey).** P0.1 introduces a `402 SETTLEMENT_FAILED` response on trip completion that the captain app must handle — today a non-2xx there would leave the captain stuck on the trip screen. Also: the payout UI submits the full balance with no amount field and offers only 2 of the 4 rails the API accepts (`wallet_screen.dart:146`, `:165` vs `wallet.ts:95`); Fawry is unreachable.

**To T09 (Rider App Journey).** The top-up flow tells the rider it succeeded based on a liveness probe rather than a balance comparison (`topup_screen.dart:91-96`), shows nothing at all on failure (`:55-57`), surfaces raw exception strings to Arabic-only users (`:71`), renders "جارٍ تأكيد الشحن…" before the card form has loaded (`:124`, `:139`), and silently ignores Arabic-Indic digit input (`:29-31`).

**To T11 (Admin Console).** There is no refund endpoint, no payout approval, and no reconciliation view in 937 lines of `admin.ts`. The analytics page has a fabricated `cancelled` column in the finance CSV (`AnalyticsPage.tsx:147`, `:197`), two GMV figures on one screen computed over different time buckets (`:336` vs `:585`, `admin.ts:106`), a "top earners" leaderboard sorted by trip count (`admin.ts:106`), and `deltas.commission` computed and never rendered.

**To T08 (Data Model & Migrations).** `wallet_transactions.user_id` is `ON DELETE CASCADE` and `trip_id` is `ON DELETE SET NULL` (`migrations/0003_global_transport.sql:29`, `:34`) — deleting a user erases financial history, deleting a trip orphans money rows. Both should be `RESTRICT`. `audit_log.actor_id REFERENCES users(id)` (`migrations/0002_enhancements.sql:41`) makes system actors like `'paymob'` unloggable. `pricing_rules.commission_rate` has no `CHECK (BETWEEN 0 AND 1)`. And migration `0005`'s columns are dead weight that will mislead the next person who reads the schema.

**To T22 (Observability).** The reconciliation job in P0.7 needs somewhere to alert. Rejected-HMAC and amount-mismatch events are currently written to a `console.error` and lost (F-03-23).

**To T23 (Testing/CI).** I have not committed CI YAML — `.github/workflows/**` is off-limits in this phase. The invariant queries in P0.7 are the natural basis for a nightly data-quality job; the fixture-based tests described per item are the minimum bar before any of these fixes ship.

**To T05 (Pricing).** Not my call, but relevant: the fallback to Cairo pricing for an unconfigured city (`trips.ts:24-32`) silently applies Cairo's commission rate to a new governorate, and `pricing?.commission_rate || 0.2` at `:1301` overrides a legitimately-configured 0% rate.

---

## 10. Open questions

**Q1 — Who funds a promo discount?** Today the captain absorbs ~80% of it silently (F-03-24): a 90 EGP discount on a 100 EGP fare takes their payout from 80 to 8, with no consent and no disclosure. Options: **(a)** platform funds it fully — compute the captain's payout on the *pre-discount* fare and post the difference to `platform:promo_subsidy`; **(b)** explicit split with a configured ratio, disclosed in the captain app before accept; **(c)** status quo, disclosed. **Recommendation: (a).** It is the only option that keeps the captain's economics predictable, and predictability is what determines whether they stay. The cost is real and should be a visible marketing line rather than an invisible supply tax. If (a) is unaffordable, (b) with disclosure — never (c) undisclosed.

**Q2 — What is the cash commission debt ceiling, and what happens at it?** Options: **(a)** hard block from dispatch at a fixed EGP figure; **(b)** soft warning then block; **(c)** deduct from the next card trip's payout automatically. **Recommendation: (b) at 200 EGP with an alert at 100**, plus (c) as the passive recovery mechanism. A hard block with no warning will strand captains mid-shift. The number should be tuned against observed daily cash volume once P0.7 gives us the data.

**Q3 — Should a trip complete when the rider cannot pay?** P0.1 as written refuses the transition. The alternative is to complete it, mark `payment_status='unpaid'`, credit the captain from a `platform:bad_debt` account and pursue the rider. **Recommendation: complete it and book the bad debt.** Blocking the captain at the end of a journey they have already driven is the wrong place to enforce collections — the captain is not the party at fault. This makes rider debt a first-class concept, which also needs a policy: block future rides until settled, presumably.

**Q4 — Rider wallet debt: allowed or not?** Today `wallet_balance` for a rider cannot go negative (the debit is guarded) but the trip completes anyway, so the debt exists off-book. Making it on-book requires deciding whether riders may hold a negative balance at all. **Recommendation: yes, bounded at one average fare**, with rides blocked until cleared. Alternative is a pre-authorisation at trip start, which is a larger change and a T04 concern.

**Q5 — Is `user_credits` a real feature or dead schema?** No writer exists (F-03-27). Options: delete the table and the `credits` field from the profile response, or implement it as the referral/goodwill store the `referrals` table implies. **Recommendation: delete it now**, and reintroduce credits as an `account` value in the new ledger (P0.5) if and when a referral programme ships. A permanently-zero field in the API is a bug that looks like a feature.

**Q6 — How far back do we reconcile?** The pre-cutover rows cannot be balanced retroactively (P0.5 flags them `legacy: true`). Options: reconcile from cutover only, or attempt a best-effort historical rebuild. **Recommendation: cutover only, and say so explicitly in the ops runbook.** The system is pre-production; there is no meaningful history to preserve, and pretending the legacy rows balance would be worse than admitting they do not.

**Q7 — Who owns the daily reconciliation break queue?** The job in P0.7 is worthless without a human who is paged and empowered to act. This is an ops-staffing decision, not an engineering one, and it should be settled before launch rather than after the first break.
