# 04 — Payments, PSP Integration & Captain Payouts

> Track: A — Foundation & safety-critical · Reviewer: `chat-20260801-1226-ad01` · Date: 2026-08-01 (UTC)
> Base commit reviewed: `dccc2dadf206ffaba4d35b3343d55ff279bacaf4`

---

## 1. Scope

This document covers everything at the boundary where Synaptic Go touches real money moving in from, or out to, the outside world:

- The Paymob integration surface — `apps/api/src/lib/paymob.ts` and `apps/api/src/routes/payments.ts`: intention creation, the webhook, HMAC verification, idempotency, replay and retry behaviour, stub mode.
- The `payment_intentions` lifecycle and its relationship to `wallet_transactions` and `trips`.
- Payment method coverage for the Egyptian market, and the client-side payment experience in the rider app (3-D Secure / iframe / WebView).
- The captain payout pipeline — what exists, what does not, and what a complete one costs.
- Chargebacks, refunds, reversals and reconciliation.
- PCI scope.

**Explicitly out of scope**, owned by sibling tracks:

| Not covered here | Owner |
|---|---|
| Internal wallet ledger semantics, commission arithmetic, balance-column integrity as a data model problem | **T03** — Money Integrity |
| Who is allowed to call an endpoint (role checks, IDOR on trip/user objects) | **T02** — Authorization |
| JWT/session handling on the authenticated intention endpoint | **T01** — Auth |
| Fare computation, surge, bidding economics | **T05** — Pricing |
| Migration ordering, schema conventions as such | **T08** — Data Model |
| Fraud scoring, velocity limits, stolen-card abuse patterns | **T18** — Fraud & Risk |
| Admin console UX for finance screens | **T11** — Admin Console |

Where a finding sits on a boundary, I have kept it here if the trigger is a PSP interaction and handed it to the sibling track in section 9 otherwise.

A note on the brief. Question 9 states that captain payouts appear "entirely missing" because there is no `routes/payouts.ts`. That is half right and the correction matters: there is no `routes/payouts.ts`, but there **is** a payout endpoint at `POST /captain/wallet/payout` (`apps/api/src/routes/wallet.ts:98`), it is wired to a live button in the captain app, and it **irreversibly debits the captain's balance**. So the situation is worse than "missing". A missing feature takes no money. This one takes money out of a captain's balance and drops it into a state no code path can ever resolve. Section 4 F-04-06 covers it.

---

## 2. What I actually read

Every file below was downloaded at base commit `dccc2dadf206ffaba4d35b3343d55ff279bacaf4` and read from disk with real line numbers. Every `path:line` in this document was verified by re-reading the cited line.

**Read in full, line by line — the core of this track**

| File | Note |
|---|---|
| `apps/api/src/lib/paymob.ts` (235 lines) | Auth-token / order / payment-key flow, HMAC field list, verification, stub mode. Read completely. |
| `apps/api/src/routes/payments.ts` (313 lines) | Intention endpoint and the entire webhook handler. Read completely, twice. This is where the S1s live. |
| `apps/api/src/routes/wallet.ts` (143 lines) | Rider wallet reads, captain balance computation, the payout endpoint. Read completely. |
| `migrations/0011_payment_intentions.sql` (31 lines) | Full DDL for `payment_intentions`; also adds `trips.payment_status`. Read completely. |
| `migrations/0005_integer_currency_and_idempotency.sql` (22 lines) | `idempotency_key` + unique index, piastres columns. Read completely. |
| `apps/api/src/lib/audit.ts` (37 lines) | Audit writer; swallows its own failures. Read completely. |
| `apps/api/src/middleware/rateLimit.ts` (90 lines) | Read the limiter body; confirmed fail-open. |

**Read in the regions that matter, with surrounding context**

| File | What I read |
|---|---|
| `apps/api/src/routes/trips.ts` (1371 lines) | The completion handler `:951`–`:1090` in full — the rider debit, cash-commission debit and captain payout credit. This is the comparison case that proves the webhook bug is a local defect, not a house style. |
| `apps/api/src/index.ts` (372 lines) | Route mounting `:108`–`:122`, CORS `:40`–`:56`, global rate limit `:59`–`:66`, error handler `:232`–`:236`, and the `scheduled` cron handler. |
| `apps/api/src/lib/notifications.ts` (~410 lines) | `sendFcm` `:314`–`:374` and `pushToUser` `:380`–`:409`, to establish whether the webhook can throw after crediting. |
| `migrations/0003_global_transport.sql` (228 lines) | The `wallet_transactions` DDL at `:27`–`:43`, especially the `type` CHECK at `:30`. |
| `apps/rider/lib/services/app_state.dart` | `topUpViaPaymob` `:686`–`:692` and `createTrip` `:488`–`:508`. |
| `apps/rider/lib/screens/wallet/topup_screen.dart` (196 lines) | The WebView + `NavigationDelegate` block `:44`–`:66` and `_verifyTopup` `:88`–`:105`. |
| `apps/rider/lib/screens/ride/payment_methods_screen.dart` (145 lines) | The full method list and the dead "add card" control. |
| `apps/api/wrangler.toml` (180 lines), `apps/api/.dev.vars.example`, `apps/api/worker-configuration.d.ts`, `apps/api/deploy.sh` | Secret declaration and environment configuration. |

**Skimmed for specific questions, not read end to end** — I say so because it matters for how much weight to put on the citation:

`apps/api/src/routes/admin.ts` (937 lines, skimmed for any money-moving or payment-visibility endpoint), `apps/api/src/routes/captain.ts` (700 lines, skimmed for payout/earnings surfaces), `apps/api/src/routes/intercity.ts` (skimmed for the booking payment path `:82`–`:201` and cancellation refund `:225`–`:322`), `apps/api/src/routes/companies.ts` (B2B invoice generation `:167`–`:204`), `apps/api/src/routes/promo.ts`, `apps/api/src/lib/cleanup.ts`, `apps/captain/lib/screens/earnings/wallet_screen.dart` (810 lines, read the payout flow `:82`–`:257`), `apps/captain/lib/screens/earnings/earnings_screen.dart`, `apps/rider/lib/screens/wallet/wallet_screen.dart`, `migrations/0001`, `0002`, `0016`, and `docs/ROADMAP.md`, `docs/IMPROVEMENTS.md`, `docs/CHECKLIST.md`, `docs/API.md`.

**Repo-wide absence searches** were run across `apps/api/src/`, `apps/rider/lib/`, `apps/captain/lib/`, `apps/admin/src/`, `migrations/` and `docs/`. Terms with **zero hits anywhere**: `disbursement`, `chargeback`, `reversal`, `dispute`, `cashout` / `cash_out`, `bank_account`, `iban`, `Meeza`, `etisalat`, `orange`, `inquiry`. Terms with hits only as enum labels or field names, never as an integration: `Fawry`, `InstaPay`, `vodafone`, `3ds`. `reconcil` has exactly one hit and it is a UI comment about chip state (`apps/api/src/routes/captain.ts:432`), not financial reconciliation.

One correction I owe the reader, because it changes a conclusion an earlier pass had reached: `trips.payment_status` **does exist**. It is not in `0001`; it is added by `migrations/0011_payment_intentions.sql:31`. The webhook's `UPDATE trips SET payment_status = 'paid'` at `apps/api/src/routes/payments.ts:202` is therefore valid SQL and does not throw. I checked this specifically because the opposite conclusion would have been a fabricated S1.

---

## 3. How it works today

### 3.1 The intended happy path

```
Rider taps "شحن" in the app
  → POST /payments/paymob/intention        (authenticated)
      → createPaymobIntention()            paymob.ts:102
          → POST accept.paymob.com/api/auth/tokens        paymob.ts:25
          → POST accept.paymob.com/api/ecommerce/orders   paymob.ts:36
          → POST accept.paymob.com/api/acceptance/payment_keys  paymob.ts:63
      → INSERT payment_methods             payments.ts:54   (legacy bookkeeping)
      → INSERT payment_intentions status='pending'  payments.ts:63
      → returns { iframeUrl, clientSecret, orderId, stubbed }
  → Flutter opens iframeUrl in a WebView   topup_screen.dart:44
  → user pays on Paymob's page
  → Paymob POSTs the callback to /payments/paymob/webhook
      → HMAC-SHA512 verify                 payments.ts:104
      → amount tamper check                payments.ts:148
      → credit wallet + mark intention settled   payments.ts:172-227
  → WebView sees a URL containing success=true → app refetches the balance
```

Three architectural facts shape everything below.

**The webhook is the only way money is ever recognised.** There is no polling, no inquiry call, no reconciliation job. If the callback does not arrive, or arrives and throws, the money exists at Paymob and does not exist in Synaptic Go, permanently.

**Nothing is transactional.** D1 statements here are issued as independent `.prepare().run()` calls. There is no `.batch()` anywhere in `payments.ts`. Every multi-statement money mutation is a sequence that can stop halfway.

**The intention row is the only server-side memory of what the user agreed to pay.** Introduced by migration 0011 specifically so the webhook could "verify amount + purpose before touching the wallet" (`migrations/0011_payment_intentions.sql:3-4`). It half-delivers on that promise: amount is checked, currency is not, and purpose is trusted rather than validated.

### 3.2 Intention creation

`apps/api/src/routes/payments.ts:23`. Authenticated via `authMiddleware`. The request body is validated by:

```ts
// apps/api/src/routes/payments.ts:12-18
const intentionSchema = z.object({
  amount: z.number().min(1),
  currency: z.string().default("EGP"),
  paymentMethod: z.enum(["card", "wallet", "cash"]).default("card"),
  purpose: z.enum(["wallet_topup", "trip_payment", "intercity_booking"]).default("wallet_topup"),
  tripId: z.string().optional(),
});
```

Note what the client controls: the amount (no upper bound), the currency (free-form string), the purpose, and the trip id. Nothing here is cross-checked against server state. The `tripId` is never verified to belong to the caller and is never compared against that trip's fare.

Billing data sent to Paymob is largely synthetic — `phone_number` is the constant `"01000000000"` and address fields are `"NA"` (`payments.ts:33-40`). Functional for card payments; it will matter when a method that actually uses the phone number (Vodafone Cash, Fawry reference delivery) is added.

Two rows are written: a legacy `payment_methods` row (`payments.ts:54`) and the `payment_intentions` row that the code itself calls the source of truth (`payments.ts:63`). The legacy row is what keeps the fallback branch at `payments.ts:251` alive.

### 3.3 The webhook

`apps/api/src/routes/payments.ts:97`. **Unauthenticated by design** — correct for a PSP callback, which is why the signature check is load-bearing.

The payload is unwrapped with `const obj = (body?.obj ?? body)` (`payments.ts:99`). Paymob wraps the transaction in `{ type, obj }`, so this is right, and the HMAC field paths are correctly relative to `obj`.

**HMAC verification.** `verifyPaymobHmacAsync` (`paymob.ts:215`) refuses when the secret is absent (`paymob.ts:222`) or the header is missing (`paymob.ts:223`), recomputes over the 20 concatenated fields, and compares with a length-checked constant-time loop (`paymob.ts:231-236`).

On the brief's question 1 — the concatenation order. The `HMAC_FIELDS` array at `paymob.ts:162-183` is:

```
amount_cents, created_at, currency, error_occured, has_parent_transaction, id,
integration_id, is_3d_secure, is_auth, is_capture, is_refunded,
is_standalone_payment, is_voided, order.id, owner, pending,
source_data.pan, source_data.sub_type, source_data.type, success
```

This **matches Paymob's documented lexicographic field order for the transaction-processed callback**, and the code is correct. What is wrong is the docstring immediately above it (`paymob.ts:149-156`), which describes a *different* list — it omits `is_3d_secure` / `is_auth` / `is_capture` and invents `is_hmac_attributed_transaction` and three `currency_ops.*` fields. The code is right and the comment is wrong, which is the more dangerous way round: the next engineer to touch this will "fix" the array to match the comment and silently break every webhook.

On the "raw body vs re-serialised object" part of question 1: for Paymob the concern does not apply as posed. Paymob does not sign the raw body; it signs a concatenation of selected field values. Hashing a re-parsed object is the correct implementation of *that* scheme. There is a residual risk in how absent values are rendered — `String(value ?? "")` at `paymob.ts:189` maps both `null` and `undefined` to the empty string, and Paymob's Python backend renders a null `source_data.pan` differently. I could not verify Paymob's exact null rendering from the code alone, so this is `needs-check` rather than a finding.

Comparison is constant-time in the sense that matters (`paymob.ts:234` XOR-accumulates over the full string); it early-returns on a length mismatch, which leaks only the length of a hex digest of fixed size. Not a finding.

**After verification**, the handler resolves the intention by `order_id` (`payments.ts:131`), checks the amount (`payments.ts:148`), checks whether the intention is already settled (`payments.ts:166`), and then branches on purpose to credit the wallet, mark a trip paid, or write an audit row.

### 3.4 The current payment state machine, as implemented

This is what the code actually does, not what it ought to do. "Ledger" means a `wallet_transactions` row.

| # | Transition | Trigger | `payment_intentions` | `wallet_transactions` | Other rows | Gap |
|---|---|---|---|---|---|---|
| 1 | — → `pending` | `POST /payments/paymob/intention` | INSERT, `status='pending'`, `settled_at` NULL (`payments.ts:63`) | none | `payment_methods` INSERT (`payments.ts:54`) | no expiry recorded |
| 2 | `pending` → *(authorised)* | rider completes 3-D Secure at Paymob | **not represented** | none | none | the authorised/captured distinction does not exist in this system |
| 3 | `pending` → `settled` (top-up) | webhook, `success=true`, `purpose='wallet_topup'` | UPDATE `status='settled'`, `settled_at` (`payments.ts:223`) | INSERT OR IGNORE `topup`/`credit`/`settled` with idempotency key (`payments.ts:175`) | `users.wallet_balance` **+=** amount (`payments.ts:182`) | balance move not gated on the insert result — **F-04-01** |
| 4 | `pending` → `settled` (trip) | webhook, `success=true`, `purpose='trip_payment'` | UPDATE `status='settled'` (`payments.ts:223`) | INSERT `trip_payment`/`debit`/`settled`, **no idempotency key** (`payments.ts:207`) | `trips.payment_status='paid'` (`payments.ts:202`) | no fare comparison, no ownership check — **F-04-03** |
| 5 | `pending` → *throw* (intercity) | webhook, `success=true`, `purpose='intercity_booking'` | **never updated** | INSERT rejected by CHECK constraint → exception | none | handler 500s, Paymob retries forever — **F-04-02** |
| 6 | `pending` → `failed` | webhook, `success=false` | UPDATE `status='failed'` (`payments.ts:229`) | INSERT `topup`/**`credit`**/`failed`, no idempotency key (`payments.ts:234`) | push notification | a *credit* row for money never received; unbounded duplicates — **F-04-16** |
| 7 | `settled` → `settled` | duplicate webhook after step 3 completed | unchanged | none | none | correct, when the first delivery fully completed |
| 8 | `pending` → *(refunded)* | Paymob refund callback | **no transition exists** | none | none | swallowed at `payments.ts:166` — **F-04-04** |
| 9 | `pending` → *(expired)* | time passes | **no transition exists** | none | none | intentions are immortal — **F-04-14** |
| 10 | any → *(reconciled)* | webhook never arrived | **no transition exists** | none | none | no sweep, no inquiry — **F-04-05** |

Rows 2, 8, 9 and 10 are the shape of the problem: a production payment system needs authorise/capture, refund, expiry and reconciliation, and this one has none of the four. The states that exist are `pending`, `settled`, `failed` — and `status` has no CHECK constraint (`migrations/0011_payment_intentions.sql:16`), so those three values are a convention rather than a guarantee.

### 3.5 The captain payout path, as implemented

```
Captain taps "اسحب الآن"  (captain wallet_screen.dart:242)
  → POST /captain/wallet/payout { amount, method, account_info }
      → SELECT users.wallet_balance                 wallet.ts:104
      → guard: balance >= amount, else 400          wallet.ts:109
      → UPDATE users SET wallet_balance = wallet_balance - ?
            WHERE id = ? AND wallet_balance >= ?    wallet.ts:113
      → if changes === 0 → 409                      wallet.ts:119
      → INSERT wallet_transactions
            type='payout', direction='debit', status='pending'   wallet.ts:124
      → logAudit 'wallet.payout.request'            wallet.ts:132
      → 200 { message: "تم تقديم طلب السحب وسيُعالج خلال 24 ساعة" }
```

And then nothing. There is no endpoint, no cron, no admin screen and no script anywhere in the repository that reads `wallet_transactions WHERE type='payout' AND status='pending'`. The concurrency guard at `wallet.ts:113-121` is genuinely well written. It guards the entrance to a room with no exit.

---

## 4. Findings

| ID | Sev | Finding | Evidence (`path:line`) | Impact | Confidence |
|---|---|---|---|---|---|
| F-04-01 | **S1** | Webhook credits the wallet with an unguarded `UPDATE`, then marks the intention settled 40 lines later. A retry after any mid-handler abort re-credits. | `apps/api/src/routes/payments.ts:175-186`, `:223` | Duplicate wallet credit — money created from nothing, at the one endpoint an attacker can make fire repeatedly | confirmed |
| F-04-02 | **S1** | `purpose='intercity_booking'` inserts a `wallet_transactions.type` value the CHECK constraint forbids. Handler throws 500; intention never settles; Paymob retries indefinitely. | `apps/api/src/routes/payments.ts:213-220` vs `migrations/0003_global_transport.sql:30` | Every intercity card payment is captured by Paymob and never recognised. Rider is charged and gets nothing | confirmed |
| F-04-03 | **S1** | Trip fare bypass: `amount` and `tripId` are both client-supplied and neither is checked against the trip's fare or owner before `payment_status='paid'`. | `apps/api/src/routes/payments.ts:12-18`, `:200-206` | Rider pays 1 EGP and the trip is marked fully paid | confirmed |
| F-04-04 | **S1** | No refund, reversal or chargeback handling exists. A refund callback is swallowed by the settled-status dedupe; the wallet is never debited back. | `apps/api/src/routes/payments.ts:166-168`; 0 hits repo-wide for `chargeback`/`reversal`/`dispute` | Refunded rider keeps the balance; a paid-out captain keeps the money. Unbounded loss | confirmed |
| F-04-05 | **S1** | No reconciliation whatsoever: no Paymob transaction-inquiry call, no stale-intention sweep, no cron, no admin view. | 0 hits for `inquiry`/`reconcil`(financial); `apps/api/src/index.ts:267-370` cron handler | A dropped webhook loses the payment permanently and silently. No one finds out | confirmed |
| F-04-06 | **S1** | Payout debits the captain's balance into a `status='pending'` row that no code path can ever action. No disbursement API, no bank-account storage, no admin approval. | `apps/api/src/routes/wallet.ts:113-130`; 0 hits for `disbursement`/`bank_account`/`iban` | Captain earnings vanish from the balance and are never paid. Direct financial liability | confirmed |
| F-04-07 | S2 | Two contradictory captain balances: the app displays a computed net that ignores cash-commission debits; the payout endpoint validates against `users.wallet_balance`. | `apps/api/src/routes/wallet.ts:58-72` vs `:104-111`; debit written at `apps/api/src/routes/trips.ts:1020-1033` | Cash-heavy captains see an inflated balance and get "insufficient funds" on withdrawal | confirmed |
| F-04-08 | S2 | Currency is client-supplied, unvalidated, and never compared at settlement — the webhook's SELECT does not even read the column. | `apps/api/src/routes/payments.ts:14`, `:131-143`, `:148` | Amount check is unit-blind; the stored currency is decorative | confirmed |
| F-04-09 | S2 | Stub mode is reachable in production. No environment declares the Paymob vars, no deploy-time assertion, and the client ignores the `stubbed` flag. | `apps/api/src/lib/paymob.ts:117-127`; `apps/api/wrangler.toml` (no Paymob keys in any env); `apps/rider/lib/services/app_state.dart:686-692` | Users complete a fake payment journey believing they paid | confirmed |
| F-04-10 | S2 | The rider's payment-method choice never reaches the server — `createTrip` hardcodes `'cash'`. | `apps/rider/lib/services/app_state.dart:504`; UI at `apps/rider/lib/screens/ride/payment_methods_screen.dart:40-95` | Card and wallet trip payment are unreachable in the shipped app; the wallet-debit branch is dead code | confirmed |
| F-04-11 | S2 | Payout debits `wallet_balance` but not `wallet_balance_piastres`; the integer ledger drifts on every withdrawal. | `apps/api/src/routes/wallet.ts:113-117` (compare `apps/api/src/routes/trips.ts:998`, which writes both) | The column intended as the authoritative integer balance becomes wrong | confirmed |
| F-04-12 | S2 | Cash-commission debit has no balance floor, unlike the rider debit 30 lines above it; nothing blocks a captain in debt from working. | `apps/api/src/routes/trips.ts:1029-1033` vs `:997-1001` | Captain balances go negative with no recovery mechanism | confirmed |
| F-04-13 | S2 | Webhook has no IP allow-list; only a global 120/min soft limit that fails **open** on KV error. | `apps/api/src/index.ts:59-66`; `apps/api/src/middleware/rateLimit.ts:28-34` | Unlimited HMAC-guessing and replay attempts when KV degrades; F-04-01 becomes remotely triggerable | confirmed |
| F-04-14 | S2 | Intentions never expire: no `expires_at`, no status CHECK, no sweep. A stale intention can settle after its trip ended or was cancelled. | `migrations/0011_payment_intentions.sql:8-19`; no cleanup in `apps/api/src/lib/cleanup.ts` | Payments land against dead trips; `pending` rows accumulate forever | confirmed |
| F-04-15 | S2 | No operational surface for payments: no `payment_intentions` view, no manual credit, no refund, no payout queue in admin. | `payment_intention` has 0 hits outside `payments.ts` and migration 0011; `apps/api/src/routes/admin.ts` (skimmed in full) | Every incident requires direct D1 SQL against production | confirmed |
| F-04-16 | S2 | Failed payments insert a `direction='credit'` row with no idempotency key — a credit for money never received, duplicated on every retry. | `apps/api/src/routes/payments.ts:234-239`, `:288-293` | Ledger pollution; any sum that does not filter on `status` over-counts | confirmed |
| F-04-17 | S2 | No recovery for an interrupted payment: nothing checks for pending intentions on app launch in either app. | `apps/rider/lib/screens/wallet/topup_screen.dart:44-105`; no pending-intention call in rider or captain bootstrap | App-kill mid-3DS leaves the rider with no way to learn what happened | likely |
| F-04-18 | S3 | Egyptian method coverage is one live method. Card is a dead button; Fawry, Meeza, InstaPay, Vodafone/Etisalat/Orange Cash are absent as payment methods. | `apps/rider/lib/screens/ride/payment_methods_screen.dart:40-95`, `:84-89`; 0 hits for `Meeza`/`etisalat`/`orange` | Excludes most of the addressable Egyptian market | confirmed |
| F-04-19 | S3 | Paymob integration ID is a hardcoded constant with a comment promising an env override that does not exist. | `apps/api/src/lib/paymob.ts:20`, `:135`; no `PAYMOB_INTEGRATION_ID` anywhere | Cannot add a second payment method without a code deploy | confirmed |
| F-04-20 | S3 | `paymob.ts` docstrings contradict the code: it claims the Intention API but implements the legacy three-step flow, and the HMAC comment lists different fields than the array below it. | `apps/api/src/lib/paymob.ts:4-8` vs `:22-80`; `:149-156` vs `:162-183` | The next engineer "fixes" the code to match the comment and breaks every webhook | confirmed |
| F-04-21 | S3 | `idempotency_key` is nullable under a plain UNIQUE index, so SQLite never dedupes NULL keys — and four of six ledger inserts in `payments.ts` pass no key at all. | `migrations/0005_integer_currency_and_idempotency.sql:4-5`; `apps/api/src/routes/payments.ts:207`, `:216`, `:234`, `:288` | `INSERT OR IGNORE` gives false confidence on exactly the paths that lack a key | confirmed |
| F-04-22 | S3 | Docs overclaim. ROADMAP calls Paymob "حقيقي" (real) and IMPROVEMENTS ticks payment integration complete; `docs/API.md` documents no payment endpoint at all. | `docs/ROADMAP.md:12`; `docs/IMPROVEMENTS.md:44`, `:60`; `docs/API.md` (155 lines, no payment section) | Planning is being done against a payments layer that does not exist as described | confirmed |
| F-04-23 | S3 | `nextPayoutWindow` is the hardcoded string `"every Monday 10:00"` presented to captains as a schedule. | `apps/api/src/routes/wallet.ts:88`; rendered at `apps/captain/lib/screens/earnings/wallet_screen.dart:336-369` | A promise to captains that no scheduler backs | confirmed |
| F-04-24 | S3 | The intention amount is unbounded (`min(1)`, no max) while the unused `topUpSchema` in the same codebase caps at 50 000. | `apps/api/src/routes/payments.ts:13` vs `apps/api/src/routes/wallet.ts:12-14` (defined, never referenced) | No ceiling on a single top-up; dead code implies a control that is not applied | confirmed |
| F-04-25 | S4 | Synthetic billing data sent to Paymob — every payment carries phone `01000000000` and `"NA"` address fields. | `apps/api/src/routes/payments.ts:33-40` | Degrades Paymob-side fraud scoring; blocks methods that need a real MSISDN | confirmed |
| F-04-26 | **positive** | PCI scope is correctly avoided: no PAN, CVV or expiry ever touches the Worker, the Flutter apps or the logs. Card entry happens entirely in Paymob's iframe. | No card-field handling in `apps/api/src/**` or `apps/rider/lib/**`; only `source_data.pan` (already masked by Paymob) is read, at `apps/api/src/lib/paymob.ts:179` | SAQ-A scope maintained — this is the strongest thing about the integration | confirmed |

### F-04-01 — The webhook can credit the same payment twice · S1

This is the most serious finding in this track, and it is worth being precise about why, because the code *looks* defended.

The handler checks whether the intention is already settled:

```ts
// apps/api/src/routes/payments.ts:166-168
if (intention.status === "settled") {
  return c.json({ status: "duplicate_ignored" }, 200);
}
```

Then it writes the ledger row defensively, keyed on the Paymob transaction:

```ts
// apps/api/src/routes/payments.ts:174-180
const idempotencyKey = `paymob:${orderIdStr}:${txnId}`;
await c.env.DB.prepare(
  `INSERT OR IGNORE INTO wallet_transactions (..., idempotency_key, status, created_at)
   VALUES (?, ?, 'topup', 'credit', ?, ?, ?, ?, 'settled', datetime('now'))`,
).bind(id("wt"), intention.user_id, amountEgp, amountCents, orderIdStr, idempotencyKey).run();
```

And then it moves the balance:

```ts
// apps/api/src/routes/payments.ts:182-186
await c.env.DB.prepare(
  `UPDATE users SET wallet_balance = COALESCE(wallet_balance, 0) + ?, wallet_balance_piastres = ... + ?, wallet_updated_at = ? WHERE id = ?`,
).bind(amountEgp, amountCents, nowIso(), intention.user_id).run();
```

**The `UPDATE` does not look at whether the `INSERT OR IGNORE` inserted anything.** The ledger is protected by the unique index; the balance is not protected by anything. They are two independent statements and only one of them is idempotent.

That this is a defect rather than a house convention is settled by the rest of the same codebase. The legacy fallback branch forty lines further down does it correctly:

```ts
// apps/api/src/routes/payments.ts:268-270
if (ins.meta && ins.meta.changes === 0) {
  return c.json({ status: "duplicate_ignored" }, 200);
}
```

So does the trip-completion handler, twice:

```ts
// apps/api/src/routes/trips.ts:1047-1052
if (ins.meta && ins.meta.changes === 1) {
  await c.env.DB.prepare(
    `UPDATE users SET wallet_balance = COALESCE(wallet_balance, 0) + ?, ...`,
  ).bind(captainPayout, payoutPiastres, nowIso(), trip.captain_id).run();
}
```

Three sibling paths gate the balance move on `changes`. The one path that accepts money from the outside world does not.

**How it fires in production.** The status guard at `:166` and the settle at `:223` are 57 lines apart, and between them the handler performs several awaited operations including a fan-out push notification (`payments.ts:189-196`). Two independent triggers:

1. *Concurrent delivery.* Paymob retries on timeout without waiting for the original to fail. Two deliveries in flight both read `status='pending'` at `:166`, both reach `:182`, and both add the amount. The ledger holds one row; the balance holds two credits.

2. *Any abort between `:186` and `:227`.* If the handler dies after crediting but before settling, the intention stays `pending` and the next retry credits again — sequentially, no race required. The realistic abort is `pushToUser` at `:189`. `sendFcm` swallows its own failures (`notifications.ts:364-373`), but the `logNotification` call *inside* that catch block (`notifications.ts:366`) is itself an awaited D1 write with no protection — if it throws, the exception propagates out of `sendFcm`, out of the `Promise.all` in `pushToUser` (`notifications.ts:394`), out of the handler, into `app.onError` (`index.ts:233`), and returns a 500. Paymob sees a non-2xx and retries. Cloudflare CPU-limit termination produces the same outcome.

The fix is one line — gate the `UPDATE` on `ins.meta.changes === 1`, exactly as `trips.ts:1047` already does — plus reordering the settle. See P0.1.

### F-04-02 — Every intercity card payment throws a 500 · S1

```ts
// apps/api/src/routes/payments.ts:213-220
} else if (intention.purpose === "intercity_booking") {
  await c.env.DB.prepare(
    `INSERT INTO wallet_transactions (id, user_id, type, direction, amount, amount_piastres, payment_ref, status, created_at)
     VALUES (?, ?, 'intercity_booking', 'debit', ?, ?, ?, 'settled', datetime('now'))`,
  )...
```

The column it writes `'intercity_booking'` into is constrained:

```sql
-- migrations/0003_global_transport.sql:30
type TEXT NOT NULL CHECK (type IN ('topup','trip_payment','refund','commission','payout','adjustment','promo_credit')),
```

`'intercity_booking'` is not in that list. Unlike foreign keys — which D1 leaves unenforced, as no `PRAGMA foreign_keys` is set anywhere in this repo — **CHECK constraints are always enforced by SQLite**. The insert raises, the handler has no try/catch around it, and `app.onError` (`index.ts:233`) converts it to a 500.

The consequences compound. The throw happens *before* `UPDATE payment_intentions SET status='settled'` at `:223`, so the intention stays `pending` forever. Paymob receives a non-2xx and retries on its schedule; every retry re-throws. The rider has been charged by Paymob, holds a booking that the payment system never acknowledged, and the intention will sit in `pending` until someone reads the D1 table by hand.

Two things make this worse than a single broken branch. First, it is silent — `logAudit` swallows its own errors (`audit.ts:33-36`) and the exception only reaches `console.error`. Second, it is the *third* branch of the purpose switch, so it will pass any smoke test that only exercises wallet top-up.

Note also that `purpose` is client-supplied (`payments.ts:16`), so this branch is reachable on demand by any authenticated user, independent of whether the intercity feature is live.

### F-04-03 — A trip can be marked paid for one pound · S1

The intention endpoint accepts an arbitrary `amount` and an arbitrary `tripId` from the client (`payments.ts:12-18`). Neither is validated against server state: `tripId` is not checked for ownership, and `amount` is not checked against the trip's fare.

At settlement, the only comparison performed is intention-to-callback:

```ts
// apps/api/src/routes/payments.ts:148
if (amountCents !== intention.amount_piastres) { ...reject... }
```

That check is correctly written and defeats callback tampering. It does not defeat *intention* tampering, because both sides of the comparison originate from the same client-supplied number. Having passed it:

```ts
// apps/api/src/routes/payments.ts:200-206
if (intention.trip_id) {
  await c.env.DB.prepare(
    `UPDATE trips SET payment_status = 'paid' WHERE id = ?`,
  ).bind(intention.trip_id).run();
}
```

No comparison to `trips.final_fare`, `accepted_price` or `estimated_fare`. No check that the trip belongs to the payer. No check that the trip is in a state where payment is meaningful. A rider creates an intention for their own 300 EGP trip with `amount: 1`, pays one pound through the real Paymob flow, and the trip is marked fully paid.

The exposure today is bounded by F-04-10 — the rider app hardcodes `paymentMethod: 'cash'` (`app_state.dart:504`), so this branch is not reachable through the shipped UI. It is reachable through the API with any valid token, and it becomes the default path the moment card payment for trips is switched on. Fixing F-04-10 without fixing this ships the hole.

### F-04-04 — Money can flow back out of Paymob and the ledger never notices · S1

There is no refund concept in the payment layer. Repo-wide, `chargeback`, `reversal` and `dispute` return zero hits; `refund` appears only in the intercity wallet-cancellation path (`intercity.ts:279-293`), as a permitted `wallet_transactions.type` value, and as the Paymob HMAC field name `is_refunded`.

That last one is the sharp edge. `is_refunded` is read as part of the signature computation (`paymob.ts:173`) and then never consulted as a fact. Paymob delivers refunds and voids as callbacks against the same order. Trace one against this handler: it verifies the HMAC, resolves the intention, and hits

```ts
// apps/api/src/routes/payments.ts:166-168
if (intention.status === "settled") {
  return c.json({ status: "duplicate_ignored" }, 200);
}
```

The refund is classified as a duplicate and discarded with a 200. The wallet keeps the credit, and Paymob has returned the funds to the cardholder. The platform is now short the full amount, with no ledger entry and no signal.

The captain-side version is worse because it involves a second party. A rider pays by card, the captain completes the trip and is credited (`trips.ts:1041-1052`), the captain withdraws, and the rider then charges back. Nothing debits the captain, nothing flags the trip, nothing alerts operations. This is the standard first attack on a new ride-hailing platform and the system currently has no defence and no detection.

### F-04-05 — If the webhook is lost, the money is lost · S1

The webhook is the sole recognition mechanism. Confirmed absences: no call to Paymob's transaction-inquiry endpoint anywhere (`inquiry` — 0 hits); no reconciliation job (`reconcil` — one hit, a UI comment at `captain.ts:432`); and the `scheduled` handler (`index.ts:267-370`) runs exactly three jobs — a daily OTP/refresh-token cleanup, scheduled-trip dispatch, and monthly B2B invoicing. None touches payments.

So a webhook lost to a network partition, a Cloudflare incident, a deploy window, or — routinely — the 500s from F-04-02 leaves `payment_intentions.status = 'pending'` forever. The rider's card was charged. The balance never moves. The rider contacts support, and support has no endpoint to query and no endpoint to remediate (F-04-15); the only recourse is manual SQL against production D1.

The gap has a precise shape. Paymob exposes a transaction-inquiry API for exactly this purpose, and the industry-standard pattern is a sweep that re-queries any intention still `pending` after N minutes and settles it from the authoritative PSP answer. P0.4 specifies it.

### F-04-06 — Captain payouts are a hole that money falls into · S1

The brief expected to find nothing. What exists is worse than nothing.

`POST /captain/wallet/payout` (`wallet.ts:98`) validates the amount, then performs a real, conditional, correctly-guarded debit:

```ts
// apps/api/src/routes/wallet.ts:113-117
const updateRes = await c.env.DB.prepare(
  `UPDATE users SET wallet_balance = wallet_balance - ?, wallet_updated_at = ? WHERE id = ? AND wallet_balance >= ?`,
).bind(body.amount, nowIso(), user.id, body.amount).run();
```

and records the request:

```ts
// apps/api/src/routes/wallet.ts:124-130
`INSERT INTO wallet_transactions
  (id, user_id, type, direction, amount, amount_piastres, note, status, created_at)
 VALUES (?, ?, 'payout', 'debit', ?, ?, ?, 'pending', datetime('now'))`
```

The destination account is stored as an unstructured string concatenation, `` `${body.method}:${body.account_info}` `` (`wallet.ts:129`), in the `note` column. There is no `bank_accounts` table, no IBAN column, no wallet-number column, and no verification of any kind — the only validation is `z.string().min(3)` (`wallet.ts:96`). A typo in a Vodafone Cash number is unrecoverable and undetectable.

Then the money stops. No endpoint reads `type='payout' AND status='pending'`. There is no admin approve, reject, mark-paid or batch action anywhere in `admin.ts`. There is no PSP disbursement call — `disbursement` has zero hits repo-wide. The four `method` values (`bank_transfer`, `vodafone_cash`, `instapay`, `fawry`, at `wallet.ts:95`) are enum labels with no integration behind any of them.

The captain sees the balance drop, reads "سيُعالج خلال 24 ساعة" (`wallet.ts:142`), and waits for a transfer that no code will ever initiate. Meanwhile the captain app sends the **entire** balance on every request (`apps/captain/lib/screens/earnings/wallet_screen.dart:242-246`) — there is no partial-amount control — so a single tap moves a captain's whole accumulated earnings into this state.

The ledger row does at least exist, so the debt is recoverable by hand. But as a production posture this is the single most dangerous thing in the track: it manufactures an unbounded, silent, growing liability to the people the business depends on most.

### F-04-07 — The captain's balance means two different things · S2

`GET /captain/wallet` computes the number the app displays:

```sql
-- apps/api/src/routes/wallet.ts:58-61
SELECT COALESCE(SUM(amount), 0) AS total_credits FROM wallet_transactions
WHERE user_id = ? AND direction = 'credit' AND type IN ('commission','payout','adjustment')
```
minus payout debits (`wallet.ts:65-70`), yielding `balance: net` (`wallet.ts:72`, `:84`).

The payout endpoint validates against a different quantity entirely — the `users.wallet_balance` column (`wallet.ts:104-108`).

These diverge structurally, not occasionally. The displayed figure sums only `direction='credit'`, so **cash-trip commission debits are invisible to it**. Those debits are real and they hit the column (`trips.ts:1020-1033`). A captain working mostly cash trips accrues commission debt in `users.wallet_balance` while the displayed balance keeps climbing on the credit side alone.

The captain app then sends the displayed figure as the withdrawal amount (`wallet_screen.dart:242-246`), so the request is rejected with `INSUFFICIENT_BALANCE` (`wallet.ts:110`) against a number the captain has never been shown. From their side: the app says 800 EGP, the withdraw button says insufficient funds, and no screen explains the difference. Combined with F-04-12 the real column can be negative while the display is positive.

### F-04-08 — Currency is theatre · S2

`currency: z.string().default("EGP")` (`payments.ts:14`) — free-form, client-supplied, no enum, no length bound. It is stored on the intention (`payments.ts:64`).

Meanwhile `paymobOrder` hardcodes `currency: "EGP"` (`paymob.ts:43`) and so does the payment key (`paymob.ts:72`), so the value never reaches Paymob. And at settlement the webhook's SELECT does not retrieve the column at all:

```ts
// apps/api/src/routes/payments.ts:131-133
`SELECT id, user_id, order_id, amount_piastres, purpose, trip_id, status FROM payment_intentions WHERE order_id = ? LIMIT 1`
```

The brief's question 3 asks whether amount *and currency* are verified against the intention. Amount: yes, and well. Currency: it is stored, never sent, never read, and never compared. The amount comparison at `:148` is therefore a bare integer comparison with no unit attached on either side — correct today only because EGP is the sole currency in play, and silently wrong the day a second one appears.

### F-04-09 — Production can run in stub mode · S2

```ts
// apps/api/src/lib/paymob.ts:117-127
if (!apiKey || !iframeId) {
  const stubKey = `stub_pk_${id()}`;
  const stubOrder = `PM_${merchantRef}_${Date.now().toString(36)}`;
  return { iframeUrl: `https://accept.paymob.com/api/acceptance/iframes/${iframeId ?? "stub"}?payment_token=${stubKey}`, paymentKey: stubKey, orderId: stubOrder, stubbed: true };
}
```

The trigger is *absence of configuration*, and absence is the current state: `wrangler.toml` declares no Paymob variable in the default, `[env.prod]` or `[env.staging]` sections; they are expected to arrive via `wrangler secret put`. Nothing verifies that they did. `deploy.sh` runs a migration and `wrangler deploy` with no secret check, and there is no startup assertion or health-check field that reports PSP configuration status.

A production deploy that misses one secret therefore boots healthy and serves stub intentions. The rider app makes it worse by discarding the `stubbed` flag the API honestly returns (`payments.ts:87`): `topUpViaPaymob` reads only `iframeUrl` (`app_state.dart:686-692`), so the WebView opens on a stub URL with no warning.

The saving grace is that stub intentions cannot settle while `PAYMOB_HMAC` is also unset, since verification refuses outright (`paymob.ts:222`). The dangerous configuration is the partial one — HMAC present, API key or iframe ID missing or typo'd — which yields live webhook processing over intentions that no real Paymob order backs.

### F-04-10 — The rider's payment-method choice is decorative · S2

`payment_methods_screen.dart` presents three options: cash, wallet (with live balance), and card — where card's only control raises a snackbar reading "سيتم تفعيل الدفع بالبطاقة قريبًا" (`payment_methods_screen.dart:84-89`).

The selection is local widget state and never leaves the device:

```dart
// apps/rider/lib/services/app_state.dart:496-507
return _post('/trips', {
  'pickupLat': pickupLat, ...
  'city': 'cairo',
  'paymentMethod': 'cash',
  ...
```

`createTrip` has no payment-method parameter, and `paymentMethod` has exactly one occurrence in the entire rider app — that hardcoded literal. Every trip the shipped app creates is a cash trip.

The consequences ripple backwards through the server. The wallet-debit branch at `trips.ts:993` requires `payment_method === "wallet"` and is therefore unreachable from the app; the captain-credit branch at `trips.ts:1036` is likewise unreachable, so **every completed trip takes the cash path** and debits commission from the captain (`trips.ts:1020-1033`). A rider who tops up their wallet can never spend it on a ride. This single literal is why the wallet exists as an inbound-only funnel.

(`'city': 'cairo'` on the line above is the same class of bug in a different track — noted for T21 in section 9.)

### F-04-11 — Payouts desynchronise the integer ledger · S2

```ts
// apps/api/src/routes/wallet.ts:113-115
`UPDATE users SET wallet_balance = wallet_balance - ?, wallet_updated_at = ? WHERE id = ? AND wallet_balance >= ?`
```

`wallet_balance_piastres` is absent. Every other balance mutation in the codebase writes both columns — `trips.ts:998`, `trips.ts:1030`, `trips.ts:1049`, `payments.ts:183`, `payments.ts:273`. The payout path is the sole exception, and the inserted ledger row *does* carry `amount_piastres` (`wallet.ts:129`), so the two representations disagree from the first withdrawal onward.

Migration 0005 introduced the integer columns explicitly "for zero-floating-point financial accounting" (`migrations/0005_integer_currency_and_idempotency.sql:7`). Any future migration to integer-authoritative money will read `wallet_balance_piastres` and inherit a number that is too high by the sum of every payout ever made.

### F-04-12 — Captains can go into unbounded debt · S2

Within the same handler, thirty lines apart, the rider debit is floored and the captain debit is not:

```ts
// apps/api/src/routes/trips.ts:997-1001 — rider, guarded
`UPDATE users SET wallet_balance = wallet_balance - ?, ... WHERE id = ? AND wallet_balance >= ?`

// apps/api/src/routes/trips.ts:1029-1033 — captain, unguarded
`UPDATE users SET wallet_balance = COALESCE(wallet_balance, 0) - ?, ... WHERE id = ?`
```

There is no DB-level floor either: `users.wallet_balance REAL NOT NULL DEFAULT 0` carries no CHECK constraint. Since F-04-10 forces every trip down the cash path, every completed trip debits commission from the captain, and a captain who never tops up goes negative on their first trip and keeps going. Nothing gates going online on balance — the online handler checks approval status and coordinates only.

This is T03's column to own, but it lands here too: it is the input to the payout eligibility rules in P1.7, and it is half of the divergence in F-04-07.

### F-04-13 — The webhook is protected by one soft, fail-open limit · S2

Mounted plainly at `app.route("/payments", paymentRoutes)` (`index.ts:115`) behind one global middleware:

```ts
// apps/api/src/index.ts:59-66
app.use("*", rateLimit({ prefix: "global", limit: 120, windowSec: 60 }));
```

There is no IP allow-list — the brief's question 3 — and Paymob publishes callback source ranges that could support one. Worse, the limiter fails open:

```ts
// apps/api/src/middleware/rateLimit.ts:28-34
try { const raw = await c.env.SESSIONS.get(key); count = raw ? Number(raw) || 0 : 0; }
catch { await next(); return; }
```

A KV degradation removes rate limiting from the whole API, including this endpoint. Fail-open is defensible for a login form; on the endpoint that credits wallets it converts F-04-01 from a retry hazard into a remotely-driven one.

120/min is also the wrong number in both directions: too permissive for an endpoint that should only ever be called by one upstream, and potentially too strict during a genuine Paymob retry burst, since the limit is shared with all other traffic from the same source IP.

### F-04-14 — Intentions are immortal · S2

The DDL (`migrations/0011_payment_intentions.sql:8-19`) has `created_at` and `settled_at` and no expiry column; `status` has no CHECK constraint; `cleanup.ts` removes only OTP codes and refresh tokens (`cleanup.ts:35-57`) and never touches `payment_intentions`.

Meanwhile the Paymob payment key is minted with `expiration: 3600` (`paymob.ts:69`). So Paymob's side of the contract expires in an hour and Synaptic Go's side never does. The webhook does not consult `created_at`, the trip's status, or anything else temporal before settling.

Answering the brief's question 5 directly: **yes, an intention can be paid after its trip has ended or been cancelled.** Nothing in the handler reads `trips.status`. A `trip_payment` intention created before a cancellation settles happily afterwards, marking a cancelled trip `payment_status='paid'` (`payments.ts:202`).

### F-04-15 — Operations have no way to see or fix a payment · S2

`payment_intention` appears nowhere outside `payments.ts` and migration 0011 — no admin route, no admin console page, no query. So there is no list of stuck payments, no way to answer "did this rider's payment arrive", and no way to retry one.

There is also no remediation. `admin.ts` contains no endpoint that credits, debits, adjusts, comps or refunds a wallet. The only programmatic refund in the entire system is the intercity booking cancellation (`intercity.ts:279-293`), which is scoped to intercity seats before departure. For a double-charged rider — the exact outcome of F-04-01 — the available remedy is direct SQL against production D1.

For a platform about to take real money in a market where payment disputes are common, this is the gap that turns every one of the findings above into a multi-hour manual incident.

### F-04-16 — Failed payments are recorded as credits · S2

```ts
// apps/api/src/routes/payments.ts:234-239
`INSERT INTO wallet_transactions (id, user_id, type, direction, amount, payment_ref, status, created_at)
 VALUES (?, ?, 'topup', 'credit', ?, ?, 'failed', datetime('now'))`
```

Two problems. The row is `direction='credit'` for money that was never received — safe only as long as every consumer filters on `status`, and `GET /user/wallet` returns all rows to the client for display (`wallet.ts:26-31`). And there is **no `idempotency_key`**, so Paymob's retries of a failed transaction append a new row each time; the same omission repeats at `:288-293`, and the `trip_payment` and `intercity_booking` inserts at `:207` and `:216` also pass no key. Per F-04-21, a NULL key never dedupes, so `INSERT OR IGNORE` would not have helped these paths even if they had used it.

### F-04-17 — An interrupted payment has no recovery path · S2

This answers the brief's question 7. The rider app opens the Paymob iframe in an in-app WebView and decides the outcome by matching the redirect URL:

```dart
// apps/rider/lib/screens/wallet/topup_screen.dart:48-58
onNavigationRequest: (request) {
  if (request.url.contains('success=true')) {
    // Don't trust the redirect URL alone: the payment is only real
    // once the backend webhook has credited the wallet. Verify by
    // refetching the balance before showing a confirmed success.
    _verifyTopup(appState, navigator);
```

The comment shows the right instinct and the implementation does not quite deliver it. `_verifyTopup` calls `fetchWallet()` and treats a successful *response* as confirmation (`topup_screen.dart:88-105`); it does not compare the balance before and after, so a webhook that has not yet arrived is indistinguishable from one that has. The failure is soft — the user sees "سيتم تحديث رصيدك بعد تأكيد الدفع" and the screen pops with `false` — so this is a correctness gap rather than a false success.

The real gap is the interrupted case. If the user kills the app while the iframe is open, nothing recovers. Neither app's bootstrap queries pending intentions — and there is no endpoint to query even if it wanted to (F-04-15). The rider relaunches to a normal home screen with no indication that a payment is in flight, and if the webhook was also lost (F-04-05) nothing in the system will ever notice. There is also no FCM handler that refreshes the wallet on the `wallet.topup.success` topic the webhook publishes (`payments.ts:189-196`), so even the successful path depends on the user happening to navigate back to the wallet screen.

Marked `likely` rather than `confirmed` on one point only: I read both apps' bootstrap paths and found no pending-payment check, but I did not read every widget in both apps, so I cannot state categorically that no screen anywhere performs one. Everything else in this finding is confirmed from the cited lines.

---

## 5. Benchmark gap

Confidence marking: **confident** = documented public behaviour or something I have verified directly; **assumed** = industry-standard inference I could not source precisely.

### 5.1 Against Paymob's own documented contract

| Paymob capability | Documented behaviour | Synaptic Go | Gap |
|---|---|---|---|
| Transaction-processed callback | POSTs the transaction wrapped in `{ type, obj }`, HMAC-SHA512 over 20 concatenated fields in fixed lexicographic order (**confident** — the field list is reproduced correctly at `paymob.ts:162-183`) | Implemented correctly | none — the strongest part of the integration |
| Callback retries | Retries non-2xx responses (**confident**) | Retries are the trigger for F-04-01 and F-04-02 | idempotency is incomplete at the balance layer |
| Transaction-inquiry API | Query a transaction's authoritative state by merchant order id (**confident** — this is a standard Accept endpoint) | Not called anywhere; 0 hits for `inquiry` | **no reconciliation fallback** — F-04-05 |
| Refund / void API | Refunds and voids are initiated by the merchant and reported back as callbacks (**confident**) | No refund initiation, no refund handling | **F-04-04** |
| Intention API (unified checkout) | The current-generation flow: one call returns a client secret; supports multiple methods behind one integration | Docstring claims it (`paymob.ts:4-8`); code implements the legacy three-step auth → order → payment-key flow (`paymob.ts:22-80`) | on the older API; each additional method needs another integration ID and a code change (F-04-19) |
| Multiple integration IDs | One per method (card, Fawry, wallets), selected per transaction | Single hardcoded constant `3990172` (`paymob.ts:20`) | cannot route to a second method without a deploy |
| Callback source IPs | Publishes callback source ranges for allow-listing (**confident**) | No IP restriction (`index.ts:59-66`) | F-04-13 |

The honest summary: the *cryptography* is right and the *operational envelope around it* — retry safety, reconciliation, refunds, method routing — is missing. That is an unusual profile. Most teams get the envelope roughly right and botch the HMAC; this one is the reverse, which means the remaining work is well-defined rather than subtle.

### 5.2 Payment method coverage for Egypt

This directly answers the brief's question 8.

| Method | Egyptian relevance | Status in Synaptic Go | Evidence |
|---|---|---|---|
| Cash | Still the dominant ride-hailing tender (**confident**) | Works, and is the *only* method any trip can use — hardcoded (F-04-10) | `app_state.dart:504` |
| Card (via Paymob iframe) | Growing, urban, card-holding segment | Top-up only, and the "add card" control is a snackbar. Trip payment by card is unreachable | `payment_methods_screen.dart:84-89` |
| Wallet (internal) | Retention and commission-settlement mechanism | Can be topped up; **cannot be spent on a ride** | `app_state.dart:504` vs `trips.ts:993` |
| Fawry | Very large cash-collection network; the standard way the unbanked pay online (**confident**) | Absent as a payment method. Appears once, as a payout-method enum label | `wallet.ts:95` |
| Vodafone Cash | The largest mobile-money wallet in Egypt (**confident**) | Absent as a payment method; payout enum label only | `wallet.ts:95` |
| Etisalat Cash / Orange Cash | Meaningful secondary wallets (**confident**) | 0 hits repo-wide | — |
| Meeza | The national card scheme; mandated acceptance in many public contexts (**confident**) | 0 hits repo-wide | — |
| InstaPay | Instant bank-to-bank rails, rapidly growing (**confident**) | Absent as a payment method; payout enum label only | `wallet.ts:95` |

One live inbound method (card, top-up only) plus cash. For the Egyptian market that is roughly the smallest viable surface, and it excludes the unbanked segment that Fawry and the mobile wallets exist to serve. Paymob supports all of these behind additional integration IDs, so the blocker is F-04-19's hardcoded constant plus the absent routing, not a new PSP relationship.

### 5.3 Against Uber, Careem and inDrive

| Dimension | Uber / Careem | inDrive | Synaptic Go | Position |
|---|---|---|---|---|
| Captain payout cadence | Weekly automatic disbursement, plus **instant cash-out on demand for a fee** — a documented retention lever (**confident** for existence, **assumed** on fee specifics) | Cash-first; the captain keeps the fare and settles commission to the platform (**confident** on the model) | A request endpoint that debits the balance and pays nobody (F-04-06) | worse than either; the string `"every Monday 10:00"` is hardcoded (F-04-23) |
| Payout destination | Verified bank account or mobile wallet, collected during onboarding with validation | Wallet top-up to cover commission | Free-text string in a `note` column, no validation (`wallet.ts:129`) | absent |
| Commission model | Deducted before payout; captain sees net | Captain pre-pays or tops up commission balance | Cash trips debit commission post-hoc, unguarded, can go negative (F-04-12) | closest to inDrive but without the balance discipline that model requires |
| Reconciliation | Continuous PSP-state reconciliation; payments desk tooling | Smaller PSP surface, so less to reconcile | None (F-04-05) | absent |
| Refunds / disputes | Self-service refunds, chargeback representment | Minimal; cash reduces exposure | None (F-04-04) | absent |
| Method breadth | Card, wallets, Fawry, cash, corporate billing | Deliberately narrow, cash-centric | Card top-up + cash | narrow, but not *deliberately* — the wallet exists and cannot be spent |

**The strategic reading.** inDrive's architecture is a legitimate and much cheaper target: keep cash as the tender, use the wallet purely for commission settlement, and keep the PSP surface small. Synaptic Go is accidentally close to it — every trip is cash today (F-04-10) — but it lacks the two controls that make the model safe: a balance floor with an online-gate (F-04-12), and a working way to move money to and from the captain (F-04-06).

The decision this forces is in section 10, Q1. Committing to the inDrive shape would make several S1s cheaper to close, because the trip-payment branch and its fare-bypass (F-04-03) could be deleted rather than fixed. Committing to the Uber shape means building the payout pipeline properly and treating instant cash-out as the captain-retention lever it is in this market.

---

## 6. Improvement plan

Ordered by the sequence I would actually execute. P0 items are prerequisites for taking a single real payment.

### P0.1 — Make the credit path idempotent and correctly ordered

- **Goal** — one payment credits a wallet exactly once, no matter how many times Paymob delivers the callback.
- **Design** — three changes to the primary intention branch. (a) Claim the intention before touching money, with a conditional update that only the first delivery can win: `UPDATE payment_intentions SET status='settling' WHERE id=? AND status='pending'`, and return `duplicate_ignored` when `changes === 0`. (b) Gate the balance move on the ledger insert, exactly as `trips.ts:1047` already does — `if (ins.meta.changes === 1) { UPDATE users ... }`. (c) Move the `pushToUser` call after the final `status='settled'` write and wrap it in try/catch so a notification failure can never roll the handler into a retry. Apply the same `changes === 1` gate to the legacy branch's balance move for symmetry.
- **Files to change** — `apps/api/src/routes/payments.ts` (`:166-186`, `:189-196`, `:223-227`, `:272-276`).
- **DB** — `migrations/0020_payment_intention_hardening.sql`: `CREATE UNIQUE INDEX IF NOT EXISTS idx_wt_idem_notnull ON wallet_transactions(idempotency_key) WHERE idempotency_key IS NOT NULL;` and a status CHECK via table rebuild, allowing `pending`, `settling`, `settled`, `failed`, `expired`, `refunded`.
- **API contract** — unchanged.
- **Effort** — S.
- **Risk** — low. The `settling` state adds a way to get stuck if the handler dies mid-flight; P0.4's sweep is what unsticks it, so ship them together or make the claim expire after 15 minutes.
- **Acceptance criteria** — replaying an identical callback 50 times concurrently produces exactly one ledger row and one balance increment; killing the handler after the credit and replaying produces no second increment; the intention ends `settled` in both cases.
- **Tests** — a concurrency test firing N parallel identical callbacks and asserting `SUM(amount)`; a fault-injection test that throws from `pushToUser`; a unit test asserting the balance `UPDATE` is not reached when `changes === 0`.

### P0.2 — Fix the intercity CHECK violation and make purpose branches fail safe

- **Goal** — no purpose branch can throw a 500 into Paymob's retry loop.
- **Design** — add `'intercity_booking'` to the `wallet_transactions.type` CHECK (SQLite requires a table rebuild: create new table with the widened CHECK, copy, drop, rename, recreate indexes). Then wrap the whole purpose switch in try/catch: on error, mark the intention `status='error'`, write an audit row, and **return 200** so Paymob stops retrying while the sweep in P0.4 picks it up. A PSP retry loop is not an error-recovery mechanism.
- **Files to change** — `apps/api/src/routes/payments.ts:172-247`.
- **DB** — `migrations/0021_wallet_txn_type_widen.sql`.
- **API contract** — unchanged.
- **Effort** — S.
- **Risk** — medium: the table rebuild touches the ledger. Take a D1 export first, run the copy in one batch, and verify `COUNT(*)` and `SUM(amount)` match before dropping. Rollback is the export.
- **Acceptance criteria** — an `intercity_booking` callback settles and writes a ledger row; a deliberately-broken branch returns 200 with the intention marked `error`; no payment path can return 5xx to Paymob.
- **Tests** — one test per purpose value asserting a 2xx and the expected rows; a test asserting the CHECK accepts all seven-plus-one type values.

### P0.3 — Bind intentions to server-side truth

- **Goal** — the amount a rider pays is decided by the server, never proposed by the client.
- **Design** — for `purpose='trip_payment'`, stop accepting `amount`: load the trip, assert `trip.rider_id === user.id`, assert the trip is in a payable state, and derive the amount from `accepted_price ?? final_fare ?? estimated_fare`. For `intercity_booking`, derive from the booking row the same way. Keep a client-supplied amount only for `wallet_topup`, and bound it — `z.number().int().min(1).max(50000)` in piastres, adopting the ceiling the unused `topUpSchema` at `wallet.ts:12-14` already implies. Replace `currency: z.string()` with `z.literal("EGP")`, select `currency` in the webhook's intention query, and compare it alongside the amount. At settlement, re-verify the trip's fare before writing `payment_status='paid'`.
- **Files to change** — `apps/api/src/routes/payments.ts:12-18`, `:23-49`, `:131-143`, `:148`, `:200-206`; delete the dead `topUpSchema` at `apps/api/src/routes/wallet.ts:12-14`.
- **DB** — none.
- **API contract** — `POST /payments/paymob/intention` — `amount` becomes **required only for `wallet_topup`** and is ignored (400 if present) for other purposes; `currency` restricted to `"EGP"`. Request: `{ purpose, amount?, tripId?, bookingId? }`. Response gains `amountPiastres` (server-derived) so the client can display the authoritative figure. **Breaking** for any client sending `amount` with a trip purpose — no shipped client does, per F-04-10.
- **Effort** — M.
- **Risk** — low. Ownership assertion could reject legitimate B2B flows where the payer is not the rider; check `billed_to_company` before rejecting.
- **Acceptance criteria** — an intention for another user's trip is rejected 403; a `trip_payment` intention's amount always equals the trip fare in piastres; a non-EGP currency is rejected at creation; settlement rejects a fare mismatch.
- **Tests** — attempt to pay a 300 EGP trip with `amount: 1` and assert rejection; attempt to create an intention against another rider's trip; assert a top-up above the ceiling is rejected.

### P0.4 — Reconciliation sweep against Paymob's inquiry API

- **Goal** — no payment is lost because a callback was lost.
- **Design** — add `paymobInquireTransaction(env, merchantOrderId)` to `lib/paymob.ts` calling Paymob's transaction-inquiry endpoint with a fresh auth token. Add a cron branch that selects intentions in `pending`/`settling`/`error` older than 10 minutes and younger than 7 days, inquires each, and routes the authoritative answer through the *same* settlement function the webhook uses — extracted from the handler so there is exactly one code path that can move money. Cap the batch (100 per tick), and after 7 days mark `expired` and alert.
- **Files to change** — `apps/api/src/lib/paymob.ts` (new function), `apps/api/src/routes/payments.ts` (extract `settleIntention(env, intention, txn)`), `apps/api/src/index.ts` (cron branch in the existing `scheduled` handler at `:267`).
- **DB** — `migrations/0022_payment_intention_recon.sql`: add `last_checked_at TEXT`, `check_attempts INTEGER NOT NULL DEFAULT 0`, `expires_at TEXT`; `CREATE INDEX idx_pi_status_created ON payment_intentions(status, created_at)`.
- **API contract** — none externally. Internally, `settleIntention` becomes the single money-moving entry point.
- **Effort** — M.
- **Risk** — the sweep and a late webhook could settle concurrently; P0.1's `settling` claim is what makes that safe, which is why P0.1 ships first. Watch Paymob rate limits; the batch cap and `last_checked_at` backoff cover it.
- **Acceptance criteria** — a payment whose callback is discarded is settled within 15 minutes by the sweep, with the same rows the webhook would have written; a genuinely-failed payment is marked `failed`, not credited; no intention stays `pending` beyond 7 days.
- **Tests** — integration test with the webhook suppressed, asserting eventual settlement; a test asserting the sweep is idempotent against an already-settled intention.

### P0.5 — Refund and chargeback handling

- **Goal** — money leaving Paymob is reflected in the ledger, and the people who were paid from it are flagged.
- **Design** — read `is_refunded`, `is_voided` and `has_parent_transaction` from the callback *before* the settled-status dedupe at `payments.ts:166`, and route them to a reversal handler instead of discarding them. The handler writes a `refund`/`debit` ledger row keyed `paymob:refund:{txnId}`, debits the wallet (permitting a negative balance — the debt is real), sets the intention `refunded`, and, when the intention had a `trip_id` whose captain was already credited, writes a `clawback_pending` flag and raises an ops alert rather than silently debiting the captain. Add `POST /admin/payments/:intentionId/refund` to initiate merchant-side refunds through Paymob.
- **Files to change** — `apps/api/src/routes/payments.ts:116-171` (classify before dedupe), new `apps/api/src/lib/reversals.ts`, `apps/api/src/routes/admin.ts`.
- **DB** — `migrations/0023_reversals.sql`: `refunds` table (`id`, `intention_id`, `paymob_txn_id` UNIQUE, `amount_piastres`, `reason`, `initiated_by`, `status`, `created_at`) and `trips.clawback_status TEXT`.
- **API contract** — `POST /admin/payments/:intentionId/refund` → `{ amountPiastres?, reason }` → `{ ok, refundId, status }`. Admin role required.
- **Effort** — L.
- **Risk** — captain clawback is a policy decision, not just code; defaulting to *flag, do not auto-debit* keeps the code from making a business decision. Ensure a refund callback cannot be replayed into multiple debits — the unique `paymob_txn_id` is what enforces that.
- **Acceptance criteria** — a refund callback produces exactly one debit row and sets the intention `refunded`; a refund on a trip whose captain was paid raises an alert and flags the trip; replaying the refund callback changes nothing.
- **Tests** — replay a refund callback ten times; refund a trip with a paid captain and assert the flag; assert `is_voided` is handled distinctly from `is_refunded`.

### P0.6 — Stop payouts until the pipeline exists

- **Goal** — no further captain money enters a state nothing can resolve.
- **Design** — the smallest safe change: keep `POST /captain/wallet/payout` accepting requests but **stop debiting the balance**. Record the request as a `payout_requests` row in `requested` state and leave `users.wallet_balance` untouched until an admin marks it paid. Add the missing `wallet_balance_piastres` decrement to the eventual debit. Then add the minimum ops surface: `GET /admin/payouts?status=` and `POST /admin/payouts/:id/{approve,reject,mark_paid}`, where `mark_paid` is the only action that debits — atomically, with the ledger row and the balance move gated together. Reconcile existing stranded `pending` payout rows manually before deploying.
- **Files to change** — `apps/api/src/routes/wallet.ts:98-143`, `apps/api/src/routes/admin.ts`, and the captain UI at `apps/captain/lib/screens/earnings/wallet_screen.dart:242-257` to reflect request-vs-paid states.
- **DB** — `migrations/0024_payout_requests.sql`: `payout_requests` (`id`, `captain_id`, `amount_piastres`, `method`, `destination_id`, `status` CHECK in (`requested`,`approved`,`rejected`,`paid`,`failed`), `requested_at`, `decided_at`, `decided_by`, `paid_at`, `psp_reference`, `failure_reason`).
- **API contract** — `POST /captain/wallet/payout` response gains `status: "requested"` and drops the "24 hours" promise until it is true. New admin endpoints as above.
- **Effort** — M.
- **Risk** — captains lose the appearance of instant withdrawal. That is the point; the appearance was false.
- **Acceptance criteria** — a payout request leaves the balance unchanged; only `mark_paid` moves money, and it moves both balance columns; no payout row can be paid twice.
- **Tests** — double-`mark_paid` produces one debit; a rejected request never touches the balance.

### P1.7 — Full captain payout pipeline

- **Goal** — captains are paid automatically, on a schedule they can see, to a destination they verified.
- **Design** — four parts. **(a) Destination collection**: a `payout_destinations` table with type (`bank`/`vodafone_cash`/`instapay`), the account identifier, and a verification state; verify with a micro-deposit or an OTP to the wallet MSISDN; require a verified destination before any payout. **(b) Eligibility**: minimum threshold (default 100 EGP, in `system_config`), non-negative balance, no unresolved clawback flag, captain in good standing; hold trip earnings for a 48-hour dispute window before they become eligible. **(c) Batching**: a weekly cron selects eligible captains, creates a `payout_batch` with its `payout_requests`, and either calls Paymob's disbursement API per item or generates a bank batch file to R2 for manual upload — whichever the PSP relationship supports. **(d) State machine and ledger**: `requested → approved → submitted → paid | failed`, with a ledger row on `submitted` (debit, `pending`) that flips to `settled` on `paid` and reverses on `failed`. Every state change is audited. Add instant cash-out as a fee-bearing variant once the batch path is stable — it is the strongest retention lever in this market.
- **Files to change** — new `apps/api/src/routes/payouts.ts`, new `apps/api/src/lib/payouts.ts`, `apps/api/src/index.ts` (cron), `apps/api/src/routes/admin.ts`, captain app earnings and wallet screens, admin console.
- **DB** — `migrations/0025_payouts.sql`: `payout_destinations`, `payout_batches`, and the extension of `payout_requests` with `batch_id`, `fee_piastres`, `psp_reference`.
- **API contract** — `GET/POST/DELETE /captain/payout-destinations`, `POST /captain/payout-destinations/:id/verify`, `GET /captain/payouts`, `POST /captain/payouts` (request), `GET /admin/payout-batches`, `POST /admin/payout-batches/:id/submit`.
- **Effort** — L (2–3 weeks including PSP disbursement onboarding, which is usually the long pole commercially).
- **Risk** — highest-value target in the system. Require re-authentication to add a destination, enforce a cooling-off period before paying to a newly-added one, and rate-limit destination changes. Every mutation audited.
- **Acceptance criteria** — a captain with a verified destination above threshold is paid within one batch cycle without manual intervention; failures return the balance and notify; no payout can be issued to an unverified destination; batch totals reconcile against ledger sums to the piastre.
- **Tests** — end-to-end batch against a PSP sandbox; failure-path reversal; destination-change cooling-off; a reconciliation test asserting `SUM(payout debits) == SUM(batch items paid)`.

### P1.8 — Broaden Egyptian payment methods

- **Goal** — accept money from riders who do not hold a card.
- **Design** — make the integration ID configurable (`PAYMOB_INTEGRATION_IDS` as a JSON map from method to ID, read into `createPaymobIntention`), then add Fawry, Vodafone Cash and Meeza as first-class methods. Fawry needs reference-code display, a longer intention TTL, and a real MSISDN in the billing block (replacing the `01000000000` placeholder at `payments.ts:33`). Add a `payment_methods` catalogue endpoint so the client renders live methods rather than a hardcoded list, and wire `paymentMethod` through `createTrip` — fixing F-04-10 — but only after P0.3 lands.
- **Files to change** — `apps/api/src/lib/paymob.ts:20`, `:102-144`; `apps/api/src/routes/payments.ts`; `apps/rider/lib/services/app_state.dart:496-507`, `:686-692`; `apps/rider/lib/screens/ride/payment_methods_screen.dart`.
- **DB** — `migrations/0026_payment_method_catalogue.sql`.
- **API contract** — `GET /payments/methods` → `[{ code, label_ar, label_en, enabled, requires_msisdn }]`; `POST /payments/paymob/intention` gains `method`.
- **Effort** — L.
- **Risk** — each method has its own callback quirks; onboard one at a time behind a config flag. Fawry's long TTL interacts with P0.4's expiry — set expiry per method.
- **Acceptance criteria** — a rider without a card completes a top-up via Fawry; disabling a method in config removes it from the client immediately.
- **Tests** — one sandbox end-to-end per method; a test that an intention for a disabled method is rejected.

### P1.9 — Operational surface for payments

- **Goal** — support resolves a payment problem without opening a SQL console.
- **Design** — `GET /admin/payments` filtered by status, date and user, joining intention to ledger rows and trip; a detail view showing the callback history; `POST /admin/payments/:id/recheck` to force an inquiry; and a manual adjustment endpoint requiring a reason, writing an `adjustment` ledger row and an audit entry. Add a daily digest listing intentions stuck beyond one hour.
- **Files to change** — `apps/api/src/routes/admin.ts`, admin console pages.
- **DB** — none beyond P0.4's columns.
- **API contract** — `GET /admin/payments`, `GET /admin/payments/:id`, `POST /admin/payments/:id/recheck`, `POST /admin/wallet/:userId/adjust` → `{ amountPiastres, direction, reason }`.
- **Effort** — M.
- **Risk** — a manual adjustment endpoint is a money-moving endpoint; admin-only, reason mandatory, fully audited, and consider a second-approver rule above a threshold.
- **Acceptance criteria** — support can answer "did this payment arrive" in one screen; every adjustment has an actor and a reason.
- **Tests** — RBAC tests; audit-completeness assertion on every adjustment.

### P1.10 — Client-side payment resilience

- **Goal** — a rider who is interrupted mid-payment always learns the outcome.
- **Design** — add `GET /payments/intentions?status=pending` and call it on app resume; if a recent pending intention exists, show "we are confirming your payment" and poll the inquiry-backed status. Stop treating the `success=true` redirect as the source of truth: `_verifyTopup` should compare the balance before and after, or better, poll intention status until terminal. Surface the `stubbed` flag as a visible non-production banner. Replace raw API error strings in the snackbar with mapped messages.
- **Files to change** — `apps/rider/lib/screens/wallet/topup_screen.dart:44-105`, `apps/rider/lib/services/app_state.dart:686-692`, rider bootstrap; mirror in the captain app if it gains top-up.
- **DB** — none.
- **API contract** — `GET /payments/intentions?status=` → `[{ id, amountPiastres, purpose, status, createdAt }]`.
- **Effort** — M.
- **Risk** — polling costs requests; cap at 60 seconds with backoff, then fall back to the push notification.
- **Acceptance criteria** — killing the app mid-payment produces a status prompt on next launch; a stub-mode payment is visibly labelled.
- **Tests** — widget test for the resume path; a test asserting `stubbed: true` renders the banner.

### P2.11 — Consolidate money movement behind one module

- **Goal** — one audited code path can change a balance.
- **Design** — extract every balance mutation — `payments.ts:182`, `:272`, `trips.ts:998`, `:1030`, `:1049`, `wallet.ts:113`, `intercity.ts:149-170`, `:283-292` — into `lib/ledger.ts` exposing `applyLedgerEntry({ userId, type, direction, amountPiastres, idempotencyKey, tripId, note })`, which writes the ledger row and moves both balance columns together, gated on the insert result, with the floor policy expressed per entry type. Forbid direct `UPDATE users SET wallet_balance` outside the module with a lint rule. This structurally prevents F-04-01, F-04-11 and F-04-12 from recurring.
- **Files to change** — new `apps/api/src/lib/ledger.ts` plus all sites above.
- **DB** — none.
- **Effort** — L.
- **Risk** — broad refactor of money code; land it behind comprehensive tests after P0 has stabilised, never before.
- **Acceptance criteria** — zero direct balance updates outside `lib/ledger.ts`; both balance columns provably always move together.
- **Tests** — a repo-wide assertion test that `wallet_balance =` appears only in the ledger module.

### P2.12 — Documentation and configuration truth

- **Goal** — the docs stop describing a system that does not exist.
- **Design** — correct the `paymob.ts` docstrings (F-04-20) so the comment matches `HMAC_FIELDS`; document the payment endpoints in `docs/API.md`, which currently has none; correct `docs/ROADMAP.md:12` and `docs/IMPROVEMENTS.md:44,:60`; add a startup assertion that logs loudly when Paymob secrets are absent, and expose PSP configuration status in the health endpoint; add a deploy-time secret check to `deploy.sh`.
- **Files to change** — `apps/api/src/lib/paymob.ts:4-8`, `:149-156`; `docs/API.md`; `docs/ROADMAP.md`; `docs/IMPROVEMENTS.md`; `apps/api/src/index.ts` (health); `apps/api/deploy.sh`.
- **DB** — none.
- **Effort** — S.
- **Risk** — none. Do not expose secret *values* in the health endpoint, only a configured/not-configured boolean.
- **Acceptance criteria** — health reports PSP configuration; a deploy missing a Paymob secret fails loudly.
- **Tests** — a test asserting the health payload contains no secret material.

---

## 7. Phasing

**P0 — before any production traffic.** Everything in the S1 set. The platform must not accept a real card payment until P0.1 through P0.6 have landed. P0.6 in particular should ship *first* if any captain currently has a live payout button, because it is actively creating liability.

**P1 — first 30 days.** Payout pipeline, method breadth, ops tooling, client resilience.

**P2 — next 90 days.** Structural consolidation and documentation truth.

| Item | Phase | Effort | Owner type | Blocks |
|---|---|---|---|---|
| P0.6 — freeze the payout debit | P0 | M | backend + Flutter | — (do first) |
| P0.1 — idempotent credit path | P0 | S | backend | P0.4 |
| P0.2 — CHECK fix + fail-safe branches | P0 | S | backend + ops (migration) | — |
| P0.3 — server-derived amounts | P0 | M | backend | P1.8 |
| P0.4 — reconciliation sweep | P0 | M | backend | P1.9 |
| P0.5 — refunds and chargebacks | P0 | L | backend + admin | P1.7 clawback |
| P1.7 — full payout pipeline | P1 | L | backend + Flutter + ops | — |
| P1.8 — Egyptian method breadth | P1 | L | backend + Flutter | needs P0.3 |
| P1.9 — payments ops surface | P1 | M | backend + admin | needs P0.4 |
| P1.10 — client resilience | P1 | M | Flutter | needs P0.4 |
| P2.11 — ledger module consolidation | P2 | L | backend | after P0 stable |
| P2.12 — docs and config truth | P2 | S | backend | — |

Rough shape: P0 is about two engineer-weeks of backend work plus a migration window; P1 is dominated by P1.7, whose long pole is commercial PSP disbursement onboarding rather than code.

---

## 8. Metrics

Nothing here is instrumented today — there is no payment metric of any kind in the codebase, which is itself why several of these findings could persist unnoticed. Every metric below is new.

| Metric | Definition | Current | Target |
|---|---|---|---|
| Double-credit rate | ledger credits ÷ distinct settled intentions | unknown, structurally > 1 (F-04-01) | exactly 1.000 |
| Webhook success rate | 2xx ÷ total callbacks received | unknown; 0% for `intercity_booking` (F-04-02) | > 99.9% |
| Stuck intention count | `pending`/`settling` older than 15 min | unmeasured, unbounded | < 5 at any time, none over 1 hour |
| Reconciliation recovery | payments settled by sweep rather than callback | n/a — no sweep | tracked; a rising trend means callback delivery is degrading |
| Time to settlement | p50/p95 from intention creation to `settled` | unmeasured | p95 < 90 s |
| Payment success rate | settled ÷ created intentions | unmeasured | > 92% for card (**assumed** industry norm for the market) |
| Method mix | share of successful payments per method | 100% card top-up, all trips cash | Fawry + wallets > 30% of top-ups within 90 days |
| Payout latency | request → `paid` | **infinite** (F-04-06) | p95 < 7 days for batch; < 30 min for instant |
| Stranded payout value | `SUM(amount)` where `type='payout' AND status='pending'` | unmeasured and growing | 0 |
| Balance-column drift | count where `ROUND(wallet_balance*100) != wallet_balance_piastres` | non-zero and growing (F-04-11) | 0 |
| Negative captain balances | count and total where `wallet_balance < 0` | unmeasured, structurally possible (F-04-12) | tracked with an ops alert threshold |
| Refund/chargeback rate | reversals ÷ settled payments | **undetectable** (F-04-04) | measurable, then < 0.5% |
| Unreconciled Paymob delta | Paymob settlement report total − ledger settled total, daily | unmeasured | 0 to the piastre |

The last one is the one that matters most. A daily three-way tie-out between Paymob's settlement report, `payment_intentions` and `wallet_transactions` is the control that would have caught F-04-01, F-04-02 and F-04-05 on day one, and it should exist before the platform takes real money rather than after.

---

## 9. Cross-cutting notes

Findings outside this track's axis, addressed to their owners. I have not fixed any of them here.

**To T03 — Money Integrity, Wallet, Ledger & Commission**
- `wallet_balance` and `wallet_balance_piastres` drift permanently on every payout (`wallet.ts:113-117` omits the piastres column). Detail in F-04-11; the fix belongs in your track's column semantics.
- `trips.estimated_fare_piastres`, `final_fare_piastres` and `commission_piastres` are written by the migration 0005 backfill and by **no application code thereafter** — the trip INSERT and the completion UPDATE at `trips.ts:973-977` never populate them. Every trip created since 0005 has stale integer columns.
- Captain balances can go negative without limit (`trips.ts:1029-1033`, no floor, no CHECK on the column) and nothing gates going online on balance. F-04-12.
- Two contradictory definitions of a captain's balance (`wallet.ts:58-72` computed vs `wallet.ts:104-108` column). F-04-07. This is a ledger-semantics decision, not a payments one.
- The `INSERT OR IGNORE` idiom used throughout is unsound where `idempotency_key` is NULL, because SQLite treats NULLs as distinct under a UNIQUE index (`migrations/0005:4-5`). A partial unique index plus a NOT NULL discipline is the fix. F-04-21.

**To T08 — Data Model, Migrations & Integrity**
- `PRAGMA foreign_keys` is never set, so every `REFERENCES` clause in the schema — including `wallet_transactions.user_id` and `.trip_id` — is decorative. Worth a schema-wide decision.
- `payment_intentions.status` has no CHECK constraint (`migrations/0011:16`) while `wallet_transactions` has CHECKs on both `type` and `status`. That inconsistency is what let F-04-02 ship: the constrained column threw and the unconstrained one silently accepted anything.

**To T02 — Authorization & Object-Level Access**
- `POST /payments/paymob/intention` accepts an arbitrary `tripId` with no ownership check (`payments.ts:17`, `:74`). I have treated the fare-bypass consequence as mine (F-04-03), but the missing object-level check is a pattern your track should sweep for.

**To T20 — Intercity, B2B & New Verticals**
- Intercity bookings with `paymentMethod: 'cash'` or `'card'` are confirmed with **no payment taken and no intention created** (`intercity.ts:82-201` branches only on `wallet`). Seats can be claimed for free.
- The monthly B2B invoice cron has no idempotency guard on `INSERT INTO company_invoices` (`index.ts:353-357`), and the manual endpoint (`companies.ts:167-204`) can duplicate it. The cron path also writes no audit row.

**To T27 — Cross-App Parity**
- The rider and captain wallet screens are line-for-line duplicates of `_BalanceCard`, `_Bloom`, `_money()`, `_formatStamp()` and the transaction row, copy-pasted rather than shared. The captain file even documents the duplication in a comment at `apps/captain/lib/screens/earnings/wallet_screen.dart:594-596`. None of it lives in `packages/flutter_shared`.
- Divergences despite the duplication: the rider uses skeleton loaders and the captain a bare spinner; the rider has pull-to-refresh and the captain does not; the rider's balance is reactive from `AppState` while the captain's is local state; empty states differ in whether a subtitle is shown.
- Money formatting is inconsistent *within* the rider app: `_money()` drops trailing zeros in ledger rows, the hero card always shows two decimals, and `payment_methods_screen.dart:66` uses `toStringAsFixed(0)` — displaying a 50.75 EGP balance as "51 ج.م" — and hardcodes `'ج.م'` instead of using `strings.egp`.

**To T21 — Maps & Geo / T05 — Pricing**
- `createTrip` hardcodes `'city': 'cairo'` (`app_state.dart:503`) alongside the hardcoded payment method. Since `pricing_rules` is keyed by city, every trip is priced with Cairo's rules regardless of where the rider is.

**To T22 — Observability**
- `logAudit` swallows its own exceptions (`audit.ts:33-36`). Defensible for audit, but it means an audit-table failure is invisible — and audit rows are the only record of webhook rejections (`payments.ts:106-112`).
- The global rate limiter fails open on KV error (`rateLimit.ts:28-34`) with no metric emitted, so a KV degradation silently removes rate limiting API-wide.

**To T19 — Notifications**
- `pushToUser` is awaited inside the money path and can throw out of `sendFcm`'s catch block via the `logNotification` call at `notifications.ts:366`. Notification delivery should never be able to fail a financial transaction; it belongs on the queue that already exists for exactly this purpose.

**To T25 — Privacy & Compliance**
- The rejected-webhook audit payload logs `obj?.order` wholesale (`payments.ts:111`), which can be a full order object from an unverified caller. Worth bounding what an unauthenticated party can write into the audit table.
- PCI: no card data reaches the Worker, the apps or the logs — see F-04-26. This is a genuine strength and should be stated in any compliance narrative, along with the caveat that adopting a non-iframe method later would change the SAQ level.

---

## 10. Open questions

**Q1 — Which payment architecture is the target: Uber's or inDrive's?**
Every trip today is cash (F-04-10), the wallet cannot be spent on a ride, and captains settle commission from their balance. That is inDrive's model, reached by accident rather than decision.
*Options.* **(a) Commit to cash-first, inDrive-style.** The wallet exists only to hold commission; the trip-payment branch and its fare-bypass (F-04-03) get deleted rather than fixed; the PSP surface stays small. Cheapest and closes S1s by removing code. **(b) Commit to Uber-style multi-tender.** Card and wallet become real trip tenders; P0.3 and P1.8 are mandatory; the payout pipeline becomes urgent because captains no longer hold cash. **(c) Hybrid** — cash-first now, card-for-trips later behind a flag.
*Recommendation:* **(c)**, sequenced explicitly. Ship P0 with trip payment disabled at the API rather than merely unreachable from the client, so the fare-bypass cannot be exercised at all, then enable card-for-trips only after P0.3 and P1.8. The current state — a hole that is unreachable only because a client-side literal happens to say `'cash'` — is the worst of all three.

**Q2 — Do we hold captain earnings before they become withdrawable?**
No hold exists today; the credit is immediate at trip completion (`trips.ts:1041-1052`). With refunds and chargebacks unimplemented (F-04-04), an immediate payout is unrecoverable.
*Options.* No hold (best captain experience, highest loss exposure); 48-hour hold on card-paid trips only; 7-day hold on everything (safest, worst experience).
*Recommendation:* **48-hour hold on card-funded earnings, no hold on cash-trip settlement**, since cash carries no chargeback risk. This is P1.7's eligibility rule and it should be a `system_config` value, not a constant.

**Q3 — What happens to a captain already paid for a trip that is later refunded?**
Undefined today, and the code cannot even detect the situation.
*Options.* Automatic clawback from the next payout; platform absorbs the loss; case-by-case review.
*Recommendation:* **flag and review, with automatic clawback only above a threshold and only from future earnings, never driving a balance negative.** P0.5 implements the flag so the decision can be made with data rather than in the abstract. Whichever is chosen must appear in the captain terms before the first payout runs.

**Q4 — Which methods do we launch with, and does Paymob cover them all?**
Card alone excludes the unbanked majority (F-04-18). Fawry, Vodafone Cash and Meeza all sit behind Paymob integration IDs, so the work is configuration and callback handling rather than a new PSP.
*Recommendation:* **card + Fawry + Vodafone Cash at launch, Meeza and InstaPay in the following quarter.** Fawry first among the additions — it reaches the largest excluded segment for the least integration effort. This needs a commercial answer from Paymob on per-method fees before the order is fixed.

**Q5 — Manual payout batches or PSP disbursement API?**
No pipeline exists (F-04-06). Manual bank-file upload is faster to build and does not need new PSP terms; automated disbursement is the only thing that scales past a few hundred captains.
*Recommendation:* **build P1.7's state machine and batching now, with a pluggable execution step**, starting on manual file generation and swapping in the disbursement API when commercial terms land. The state machine is the expensive part and it is identical either way.

**Q6 — Do we offer instant cash-out, and at what fee?**
Uber and Careem both use fee-bearing instant payout as a retention lever (**confident** it exists; **assumed** on fee levels). For captains operating day to day on fuel costs, same-day access to earnings is a strong differentiator in this market.
*Recommendation:* **not at launch; plan for it as a fast follow to P1.7.** Price it to cover the disbursement fee plus a margin, cap daily frequency, and require a verified destination with the cooling-off period from P1.7.

**Q7 — Who owns the daily payment tie-out, and from what date?**
Section 8's last metric — Paymob settlement report versus ledger — is the control that catches everything this review found, but it needs a named owner and a defined response when the delta is non-zero.
*Recommendation:* **operations owns it, from the first day of real traffic, with a non-zero delta treated as a P1 incident.** Build the report as part of P1.9 rather than after the first discrepancy.
