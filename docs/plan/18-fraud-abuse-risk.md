# 18 — Fraud, Abuse & Risk Engine

> Track: C — Feature parity & new capability · Reviewer: chat-20260801-1345-b4d7 · Date: 2026-08-01 (UTC)
> Base commit reviewed: `84c1ce927fe82dc75dd3b4ba4cf2216b792dc304` (`main`)

## 1. Scope

This document covers the platform's exposure to **deliberate abuse by its own users** — riders, captains, and colluding pairs of them — and specifies the defence: location trust, velocity rules, a risk score, the enforcement primitives that make a ban mean something, and the event log without which none of it can be investigated.

Concretely in scope: fake trips, GPS spoofing, promo and referral farming, multi-accounting, cancellation abuse, card testing, wallet-credit laundering, captain account rental, and the ops tooling an analyst needs to act on any of them.

**Explicitly not in scope** (owned elsewhere, and deliberately not re-litigated here):

| Area | Owner |
|---|---|
| Ledger correctness, double-entry, commission arithmetic | T03 |
| PSP integration quality, payout rails, settlement | T04 |
| Pricing and surge model, bidding economics | T05 |
| Dispatch fairness and matching quality | T06 |
| Auth mechanism design (JWT/OTP/session) as such | T01 |
| RBAC and object-level access | T02 |
| Admin console UX and page structure | T11 |
| SOS, ratings, and two-sided accountability | T17 |
| Observability infrastructure and alerting | T22 |
| Privacy/PII retention law | T25 |

Where a finding sits on a boundary — the wallet-credit path, the payout hold, the admin queue — it appears here **as a fraud control**, and is handed to the owning track in §9 with the specific thing they need to know. The money paths are described only as far as an attacker walks them.

**One-sentence verdict.** There is no risk module of any kind in this codebase — no fraud tables across 19 migrations, no velocity rule, no risk score, no device fingerprint, no location plausibility check — and the trip-completion path contains a defect that lets a colluding pair mint money from an empty wallet, so the platform cannot take production traffic in its current state.

## 2. What I actually read

Every file below was downloaded at the pinned base commit and read with real line numbers; every `path:line` in this document was taken from that read, not inferred. Files marked **(delegated)** were read by analysis agents working under my direction; for those, I personally re-opened and verified every line cited in an S1 finding, and spot-checked the S2 citations. Files marked *skimmed* were opened for a specific question only.

**API — middleware and libraries**

| File | Note |
|---|---|
| `apps/api/src/middleware/rateLimit.ts` | Read in full (90 lines). Fixed-window KV limiter, plus the shared `parseBody` zod helper. The whole rate-limit story is these 60 lines. |
| `apps/api/src/middleware/auth.ts` | Read in full (75 lines). JWT verify only — no database read anywhere in the request path. This single fact drives F-18-06. |
| `apps/api/src/lib/turnstile.ts` | Read in full (57 lines). Captcha verification, including the dev-skip branch. |
| `apps/api/src/lib/audit.ts` | Read in full (37 lines). The entire audit facility: one insert, errors swallowed. |
| `apps/api/src/lib/jwt.ts` | (delegated) Token TTLs and claim shape. `ACCESS_TTL = "15m"`. |
| `apps/api/src/lib/utils.ts` | *Skimmed* — `id()`, `nowIso()`, OTP code generation (`crypto.getRandomValues`). |
| `apps/api/src/lib/schemas.ts` | Read the location, trip, promo, device and bid schemas (lines ~59–285). What the server will accept is defined here, and what it refuses to even receive. |
| `apps/api/src/lib/pricing.ts` | *Skimmed* (38 lines) — fare composition, to see whether a floor exists. |
| `apps/api/src/lib/nearby.ts` | (delegated) Cell fan-out for matching; the boundary-echo comment at :90. |
| `apps/api/src/lib/paymob.ts` | (delegated) PSP client and `verifyPaymobHmacAsync` at :215–229. |
| `apps/api/src/lib/cleanup.ts` | (delegated) Scheduled deletion of OTP rows and refresh tokens. |
| `apps/api/src/index.ts` | Read the first 120 lines directly: CORS allowlist, the single global rate limit, and every route mount. |

**API — routes**

| File | Note |
|---|---|
| `apps/api/src/routes/trips.ts` | The centre of this review. Read directly: creation and promo application (315–510), cancel (700–830), `advanceStatus` and completion (880–1060), bid acceptance (delegated, ~1290–1310). 1371 lines total; the dispatch/offer plumbing in the middle was skimmed as it belongs to T06. |
| `apps/api/src/routes/captain.ts` | Read the location ingestion path directly (185–275) plus the online/offline handler. Earnings endpoint skimmed. |
| `apps/api/src/routes/promo.ts` | Read in full (108 lines). Validation, admin create, deactivate — and no redemption. |
| `apps/api/src/routes/devices.ts` | Read in full (41 lines). The entire device story is an FCM token. |
| `apps/api/src/routes/wallet.ts` | Read the payout handler directly (95–142); balance/history endpoints delegated. |
| `apps/api/src/routes/payments.ts` | (delegated) Paymob intention creation, webhook handler, legacy path. |
| `apps/api/src/routes/auth.ts` | (delegated) OTP request/verify, register, login, refresh, admin setup. |
| `apps/api/src/routes/admin.ts` | (delegated) 937 lines; full moderation-action inventory extracted (§4, F-18-11). |
| `apps/api/src/routes/user.ts`, `safety.ts`, `intercity.ts` | (delegated) Profile/credits read, SOS logging, intercity refund path. |

**Durable Objects and shared code**

| File | Note |
|---|---|
| `apps/api/src/durable-objects/GeoCell.ts` | Read in full (82 lines). Presence storage, the 3-minute expiry alarm, `/nearby`. |
| `apps/api/src/durable-objects/TripRoom.ts` | (delegated) The WebSocket `location` message branch at :167–177. |
| `packages/shared/src/index.ts` | Read `TRIP_TRANSITIONS` (40–48), `canTransition` (50–52), `haversineKm` (55–65) directly. |

**Migrations** — all 19 downloaded; read for fraud-relevant DDL:

`0001_init.sql` (users, trips, otp_codes, trip_events), `0002_enhancements.sql` (audit_log :39–51, trip_path_points :14–24, promo_codes :54–63, trip_promo :65–70, referrals :107–116, user_credits :118–122), `0003_global_transport.sql` (device_tokens, wallet_transactions), `0005_integer_currency_and_idempotency.sql`, `0006_otp_attempts_and_idem_index.sql`, `0011_payment_intentions.sql`, `0012`/`0014`/`0015` (identity documents, `national_id_number`), `0016_system_config.sql`, `0018`, `0019`. The remainder were listed and opened only to confirm no fraud table appears in them — **none does**.

**Flutter**

`packages/flutter_shared/lib/services/api_client.dart` read in full (36 lines) — a bare HTTP wrapper with a bearer token and no client attestation of any kind. `apps/captain/lib/services/captain_state.dart` (delegated) for what the location stream actually sends.

**Searches run** (via `github__search_code`, repo-scoped): `promo`, `uses_count`, `referral`, `user_credits`, `logAudit`, `payout`, `refund`, `hmac`, `idempotency`, `rateLimit(`, `fraud`, `risk_score`, `device_fingerprint`, `velocity`, `isMock`, `accuracy`. The last five return **zero hits in the API source** — that absence is finding F-18-10.

## 3. How it works today

### 3.1 The trip state machine

`packages/shared/src/index.ts:40-48` defines the only transition table:

```
searching   → offered, assigned, cancelled
offered     → assigned, searching, cancelled
assigned    → arrived, cancelled
arrived     → in_progress, cancelled
in_progress → completed, cancelled
```

`canTransition` (`:50-52`) is a pure table lookup. It enforces **order** and nothing else: no minimum dwell time in a state, no minimum trip duration, no relationship to physical position. A trip legally goes `assigned → arrived → in_progress → completed` in three HTTP calls issued back to back.

### 3.2 Trip creation

`POST /trips` (`apps/api/src/routes/trips.ts:348-357`) is rate-limited at 10/min keyed by user id (`:351-356`) — the only limiter in the codebase keyed by anything other than IP. The server computes its own route and fare (`:382-397`), which is correct. Then:

- The promo, if supplied, is looked up and the discount computed (`:399-426`).
- `offeredPrice = body.offeredPrice || finalEstimate` (`:438`) — the rider's own number wins when present; `createTripSchema` allows `offeredPrice` down to 1 EGP (`apps/api/src/lib/schemas.ts:59`).
- The row is inserted with `payment_method` taken straight from the body (`:468`).
- If a promo was applied: `INSERT INTO trip_promo` then `UPDATE promo_codes SET uses_count = uses_count + 1` (`:493-503`).

**There is no check that a rider choosing `payment_method: "wallet"` has any wallet balance.** Nothing in `trips.ts` reads `wallet_balance` before line 993, which is inside completion.

### 3.3 Captain location ingestion

`POST /captain/location` (`apps/api/src/routes/captain.ts:190-271`), rate-limited 30/min per user id (`:192-197`). The accepted payload is defined by `captainLocationSchema` (`apps/api/src/lib/schemas.ts:181-187`): `lat`, `lng`, optional `heading`, optional `tripId`, optional `city`. There is no field for accuracy, device timestamp, speed, or a mock-location flag — the server cannot receive that information even if the client wanted to send it.

The handler then, with no validation between read and write:

1. `UPDATE captains SET last_lat = ?, last_lng = ?, ... is_online = 1` binding `body.lat`/`body.lng` (`:205-209`).
2. Computes the presence cell **from the client's own coordinates** — `cellKey(city, body.lat, body.lng)` (`:211`) — and heartbeats that cell (`:213-221`). `GeoCell` stores the record verbatim (`apps/api/src/durable-objects/GeoCell.ts:22-30`).
3. If a `tripId` is supplied and the trip is live, updates `trips.captain_lat/lng` (`:231-235`) and appends a breadcrumb to `trip_path_points` at most once per 30 s (`:238-252`).
4. Broadcasts the position to the trip room (`:254-265`).

The breadcrumb insert binds `(id, trip_id, lat, lng, heading, recorded_at)` (`:247-251`). The `speed REAL` column that exists in the table (`migrations/0002_enhancements.sql:20`) is never written, and `recorded_at` is the *server's* clock, not the device's.

### 3.4 Trip completion and money

`POST /trips/:id/complete` (`apps/api/src/routes/trips.ts:951-981`) checks ownership and `canTransition`, then conditionally flips the row to `completed` (`:973-981`), which correctly guards against double completion. Then the money moves:

- **Wallet trips** (`:993-1011`): the rider debit is conditional — `WHERE id = ? AND wallet_balance >= ?` (`:998`). If the rider cannot pay, `changes === 0`, and the code records a `wallet_transactions` row with `status = 'failed'` (`:1003-1010`). **It does not abort, and it does not return an error.**
- **Cash trips** (`:1013-1035`): the captain is debited the commission, guarded by an idempotency key, but with **no balance floor** on the update (`:1029-1033`).
- **Every other case** (`:1036-1054`): the captain is credited `finalFare - commission`, guarded by an idempotency key so it applies once — and **completely independent of whether the rider's debit succeeded**.

### 3.5 Payout

`POST /captain/wallet/payout` (`apps/api/src/routes/wallet.ts:98-142`): checks the balance, debits it immediately under a conditional update (`:113-121`), writes a `payout` transaction with `status = 'pending'` (`:124-130`), and audits the request (`:132-140`). The captain chooses the rail — `bank_transfer`, `vodafone_cash`, `instapay`, `fawry` (`:95`). There is no hold period, no minimum account age, no admin approval gate in the API, and no code path anywhere that reverses a payout.

### 3.6 Identity, rate limiting, and the audit trail

`authMiddleware` (`apps/api/src/middleware/auth.ts:29-65`) verifies the JWT signature and expiry, sets the user on the context, and calls `next()`. **It never touches D1.** Account status is therefore read at exactly one moment in a token's life: when it is issued.

`rateLimit` (`apps/api/src/middleware/rateLimit.ts:16-59`) reads a KV counter, compares, and schedules the increment via `c.executionCtx.waitUntil(...)` (`:49-53`) — the write is not awaited before the request proceeds (`:58`). On any KV read error it calls `next()` and returns (`:31-34`): the limiter **fails open**. The default identity is `cf-connecting-ip` (`:20`).

`logAudit` (`apps/api/src/lib/audit.ts:3-37`) writes one row to `audit_log` (`migrations/0002_enhancements.sql:39-49`) and swallows every error. It is called from admin moderation actions, promo create/deactivate, login success, payout request, SOS, and the payment webhook outcomes. Trip lifecycle events go to a *different* table, `trip_events` (`migrations/0001_init.sql:94-101`), via `logEvent` (`trips.ts:73-86`), which the admin audit endpoint does not read.

### 3.7 What does not exist

Searched and confirmed absent from the entire API source and all 19 migrations: any table or column named for risk, fraud, flag, review, hold, ban, block, fingerprint, or velocity; any device identifier other than the FCM push token; any comparison of two consecutive positions; any per-user promo redemption record; any rider-suspension endpoint; any refund or manual-credit endpoint for a ride.

## 4. Findings

| ID | Sev | Finding | Evidence (`path:line`) | Impact | Confidence |
|---|---|---|---|---|---|
| F-18-01 | S1 | Wallet trip credits the captain even when the rider debit fails — the platform mints money | `apps/api/src/routes/trips.ts:993-1011` vs `:1036-1053` | Unbounded loss; a colluding pair drains the float from an empty wallet | confirmed |
| F-18-02 | S1 | No proximity, duration or distance check on any trip state transition — a complete fake trip is three API calls | `apps/api/src/routes/trips.ts:891-941`, `:951-981`; `packages/shared/src/index.ts:40-48` | Incentive farming, commission-free settlement, laundering vehicle | confirmed |
| F-18-03 | S1 | Captain position is accepted verbatim: no speed, teleport, accuracy, timestamp or mock-location check, and the presence cell is chosen by the client's own coordinates | `apps/api/src/routes/captain.ts:205-221`; `apps/api/src/lib/schemas.ts:181-187`; `apps/api/src/durable-objects/GeoCell.ts:22-30` | Spoofed supply in surge zones, fake trips indistinguishable from real ones, dispatch integrity gone | confirmed |
| F-18-04 | S1 | Self-service payout is instant: no hold period, no admin approval, no minimum account age, no clawback path | `apps/api/src/routes/wallet.ts:98-142` | Fraud proceeds leave the platform before any human can look; recovery is zero | confirmed |
| F-18-05 | S1 | Promo redemption has no per-user cap, no first-trip rule, is consumed at creation and never returned on cancel | `apps/api/src/routes/trips.ts:399-426`, `:493-503`; `migrations/0002_enhancements.sql:54-70` | Whole promo budget consumed by one account; competitor can exhaust a campaign in seconds | confirmed |
| F-18-06 | S1 | A ban does not stop the next request: `authMiddleware` never reads the database, so a suspended captain keeps full access until the access token expires; and there is no endpoint to suspend a rider at all | `apps/api/src/middleware/auth.ts:29-65`; `apps/api/src/lib/jwt.ts:8`; `apps/api/src/routes/admin.ts:289-309` | Enforcement is advisory; the fraudulent trip in flight completes anyway | confirmed |
| F-18-07 | S1 | Nothing durable identifies a person or a handset: phone is not unique, `/register` has no captcha, and an FCM token reassigns itself to whichever account claims it | `apps/api/src/routes/auth.ts:347-384`; `apps/api/src/routes/devices.ts:18-31`; `migrations/0003_global_transport.sql:12-22` | Ban evasion in under a minute; bulk promo farming at SIM cost | confirmed |
| F-18-08 | S1 | `payment_method: "wallet"` is accepted at trip creation with no balance check | `apps/api/src/routes/trips.ts:468` | The precondition that makes F-18-01 free to execute | confirmed |
| F-18-09 | S1 | PSP webhook replay double-credits the wallet: `INSERT OR IGNORE` on the transaction, then an unconditional balance update | `apps/api/src/routes/payments.ts:175-182` | Same callback replayed = balance credited twice; contrast the legacy path at `:268` which checks `changes` | confirmed |
| F-18-10 | S1 | There is no risk subsystem at all: no fraud tables in 19 migrations, no score, no velocity rule, no review queue, no flag | repo-wide search for `fraud`/`risk`/`velocity`/`flag`/`hold` — zero hits in `apps/api/src` and `migrations/` | Nothing detects any of the above; first loss is discovered from a bank statement | confirmed |
| F-18-11 | S2 | Anti-fraud ops tooling is missing: no rider suspension, no payout hold, no manual refund/credit, no unified entity view, no review queue | `apps/api/src/routes/admin.ts` (937 lines; full inventory below) | Analysts cannot act without raw SQL against production D1 | confirmed |
| F-18-12 | S2 | Rate limiter fails open on KV error, does not await its own increment, and defaults to IP identity | `apps/api/src/middleware/rateLimit.ts:28-34`, `:49-53`, `:20` | Burst bypass; on Egyptian CGNAT it punishes neighbours and not attackers | confirmed |
| F-18-13 | S2 | Turnstile silently disables itself when the secret is unset, and records the skip as `verified = 1` | `apps/api/src/lib/turnstile.ts:16-27` | One missing secret in production removes the only bot control, and the audit trail says it passed | confirmed |
| F-18-14 | S2 | Card testing: the payment-intention endpoint has no per-user limit and forwards the PSP's error text verbatim | `apps/api/src/routes/payments.ts:23`, `:91` | ~7,000 card probes/hour/IP with a clean decline oracle; PSP fraud ratio breach | confirmed |
| F-18-15 | S2 | Cash commission is debited with no floor and no collection mechanism | `apps/api/src/routes/trips.ts:1029-1033` | Captain balance goes arbitrarily negative and keeps working; the debt is uncollectable | confirmed |
| F-18-16 | S2 | Client-supplied `offeredPrice`/`counterPrice` accept 1 EGP, below the configured minimum fare | `apps/api/src/lib/schemas.ts:59`, `:77`; `apps/api/src/routes/trips.ts:438` | Near-zero-value fake trips that satisfy trip-count incentives cheaply | confirmed |
| F-18-17 | S2 | The WebSocket location channel bypasses the HTTP limiter and the zod schema entirely | `apps/api/src/durable-objects/TripRoom.ts:167-177` | Any validator added to `POST /captain/location` is bypassable by design | confirmed |
| F-18-18 | S2 | Fraud-relevant events are not in the audit log: promo use, login failure, OTP request, location, device registration, and every trip transition | `apps/api/src/lib/audit.ts:3-37`; `apps/api/src/routes/trips.ts:73-86`; `apps/api/src/routes/admin.ts:219-227` | An investigation started after the loss finds nothing to reconstruct | confirmed |
| F-18-19 | S2 | The scheduled cleanup deletes OTP rows ~24 h after expiry — the record of how a fraudulent account authenticated | `apps/api/src/lib/cleanup.ts:35-41` | Evidence expires faster than fraud is noticed | confirmed |
| F-18-20 | S2 | `DEV_OTP` returns the OTP in the HTTP response | `apps/api/src/routes/auth.ts:122-126` | One environment-variable mistake turns phone verification off platform-wide | confirmed |
| F-18-21 | S2 | `national_id_number` has no uniqueness constraint on either table that stores it | `migrations/0015_captain_onboarding_fields.sql:15`; `migrations/0012_document_identity_fields.sql:11` | The same identity documents onboard unlimited captain accounts — the account-rental enabler | confirmed |
| F-18-22 | S3 | Promo codes may be 3 characters and the validate endpoint is a clean enumeration oracle (404 / 400 / 200) | `apps/api/src/lib/schemas.ts:258-285`; `apps/api/src/routes/promo.ts:27-35` | Codes get discovered and traded on Telegram before the campaign launches | confirmed |
| F-18-23 | S3 | `trip_path_points.speed` exists but is never written, and `recorded_at` is server time | `migrations/0002_enhancements.sql:20`; `apps/api/src/routes/captain.ts:247-251` | Retrospective speed analysis is impossible on historical trips | confirmed |
| F-18-24 | S3 | The referral tables exist with no write path, no self-referral constraint and no unique pair constraint | `migrations/0002_enhancements.sql:107-116` | Harmless today; a loaded gun the day someone wires the feature up | confirmed |
| F-18-25 | S4 | The payout audit entry stores the full `account_info` string in `payload` | `apps/api/src/routes/wallet.ts:139` | Bank/wallet identifiers in a table read by every admin — hand to T25 | confirmed |

### F-18-01 — The platform mints money on wallet trips

This is the most serious defect found in this review, and it is four lines apart in one function.

On completion of a wallet trip, the rider debit is written defensively (`apps/api/src/routes/trips.ts:997-1001`):

```sql
UPDATE users SET wallet_balance = wallet_balance - ?, ... WHERE id = ? AND wallet_balance >= ?
```

If the rider's balance is insufficient the update matches zero rows. The code notices — `txnStatus` becomes `'failed'` (`:1003`) — and records a failed transaction row with an Arabic note meaning *"debit failed — insufficient balance"* (`:1009`). It then **carries on**. No error is returned, the trip stays `completed`, and execution falls through to `:1012`.

At `:1036` the `else` branch runs for every non-cash trip, including the wallet trip whose debit just failed, and credits the captain (`:1040-1053`):

```sql
INSERT OR IGNORE INTO wallet_transactions (... 'commission', 'credit' ...)
UPDATE users SET wallet_balance = COALESCE(wallet_balance, 0) + ? ...
```

The idempotency key `trip_payout:{tripId}` makes this credit apply exactly once — it is *reliably* wrong rather than intermittently wrong.

The attack needs no spoofing and no stolen card. Two accounts, one rider and one approved captain:

1. Rider creates a trip with `paymentMethod: "wallet"` and an empty wallet. Nothing checks (F-18-08, `:468`).
2. Captain accepts, then calls `arrived`, `start`, `complete` — three calls, no position required (F-18-02).
3. Rider is charged nothing. Captain's wallet grows by `fare − commission`.
4. Captain calls `POST /captain/wallet/payout` and takes it out to Vodafone Cash immediately (F-18-04).

At a 60 EGP fare and 20% commission that is 48 EGP created per cycle. The rider's create-trip limiter is 10/min per user (`:351-356`), so one pair yields roughly **28,800 EGP/hour**, and the pair count is bounded only by how many SIMs someone buys (F-18-07). The platform's own `wallet_transactions` table records the loss faithfully as a `failed` debit beside a `settled` credit — the evidence is sitting there, and nothing reads it.

Two independent fixes are required, and both belong in P0: refuse to complete a wallet trip whose debit fails (`P0.1`), and refuse to create a wallet trip that the rider cannot fund (`P0.2`).

### F-18-02 — A fake trip is three HTTP calls

`advanceStatus` (`apps/api/src/routes/trips.ts:891-941`) is the shared handler behind `arrived` and `start`. It checks that the caller owns the trip (`:903-905`) and that the transition is legal (`:906-911`), then writes the new status. `complete` (`:951-981`) does the same. Nowhere in any of the three does the server compare the captain's last known position against `trips.pickup_lat/lng` or `dropoff_lat/lng` — a comparison it could make today, since it already stores `captains.last_lat/last_lng` (`apps/api/src/routes/captain.ts:205-209`) and ships a `haversineKm` helper (`packages/shared/src/index.ts:55-65`).

Nor is there a temporal floor. `arrived_at`, `started_at` and `completed_at` can be within the same second. A 12 km Cairo trip that completes in 800 ms is accepted, stored, and paid.

What this unlocks, beyond F-18-01: any incentive scheme keyed on trip count (the obvious launch lever in a new market), commission-free settlement between colluding parties, rating inflation, and a plausible-looking trip history that makes a laundering account look legitimate.

The fix is not expensive. The server already has both coordinates and a distance function; §6 P0.3 specifies the geofence and the minimum-plausibility gate.

### F-18-03 — Position is whatever the phone says it is

The captain app takes a `Position` from the geolocator stream and forwards two doubles. Accuracy is discarded; the `isMock` flag Android exposes on every fix is discarded. The server could not use them regardless: `captainLocationSchema` (`apps/api/src/lib/schemas.ts:181-187`) has no field to receive them, so both ends would need to change.

The handler writes `body.lat`/`body.lng` into `captains` (`captain.ts:205-209`) with nothing in between. There is no read of the previous fix, no elapsed-time arithmetic, no speed ceiling. A captain in Heliopolis can report Maadi — about 16 km — on the next heartbeat, implying roughly 11,000 km/h, and the server records it without comment.

The presence cell compounds it: `cellKey(city, body.lat, body.lng)` (`:211`) derives the Durable Object name from the same untrusted numbers. **The client chooses which supply pool it appears in.** A spoofing captain sitting at home inserts himself into whichever cell has surge, is offered those trips by dispatch, and — because of F-18-02 — can complete them without moving.

Both symptoms have one cause: no server-side notion of a *previous* fix. §6 P0.4 specifies the validator, its thresholds, and every call site that must adopt it, including the WebSocket path (F-18-17) that would otherwise route straight around it.

### F-18-04 — The exit is wide open and instant

`POST /captain/wallet/payout` (`apps/api/src/routes/wallet.ts:98-142`) is well written for what it does: it checks the balance, debits under a conditional update that cannot go negative (`:113-117`), returns 409 on a concurrent change (`:119-121`), and audits the request with IP and user agent (`:132-140`). The transaction lands as `status = 'pending'` and the response promises processing within 24 hours.

The fraud problem is what surrounds it. There is no hold period between a trip completing and its proceeds becoming withdrawable; no minimum account age or trip history; no admin endpoint anywhere in `admin.ts` to review, approve, or reject a pending payout; and no reversal path — `wallet_transactions` permits a `reversed` status in its CHECK constraint but no code ever writes it.

Every other finding in this document is survivable if the money can be frozen before it leaves. This is the one that converts a bug into a permanent loss, which is why the 24-hour hold in P0.5 is the highest-leverage single control in the plan: it is a few hours of work and it puts a human between every fraud path and the exit.

### F-18-05 — One rider can spend the entire promo budget

`uses_count` is incremented at **creation** (`trips.ts:493-503`) and never decremented anywhere — `grep` over the cancel handler (`:709-830`) finds no reference to `promo_codes` or `trip_promo`. So create-then-cancel burns a slot per cycle, and a competitor can exhaust a 1,000-use launch campaign in a few minutes for free.

Meanwhile `trip_promo` is keyed by `trip_id` alone (`migrations/0002_enhancements.sql:65-70`) — there is no `user_id` column, so "has this rider used this code before?" is a question the schema cannot answer. The only gate is the global `uses_count < max_uses` (`trips.ts:415-419`), and on a code created with `max_uses` null it is unlimited by construction. There is no first-trip-only flag on `promo_codes` (`:54-63`).

The check-then-increment is also two statements with no transaction (`:402-418` then `:499-503`), so concurrent creates race past a cap of 1. That race is the least of it: the per-user hole is wide enough that nobody needs to bother.

### F-18-06 — A ban is a suggestion for the next fifteen minutes

`authMiddleware` (`apps/api/src/middleware/auth.ts:29-65`) verifies the token cryptographically and sets the user. There is no D1 read in the request path, so `users.status` is consulted exactly once — when the token is minted. With `ACCESS_TTL = "15m"` (`apps/api/src/lib/jwt.ts:8`), a captain suspended mid-fraud keeps working for up to fifteen minutes, averaging about seven and a half.

`POST /admin/captains/:id/suspend` (`apps/api/src/routes/admin.ts:289-309`) sets `captains.approval_status = 'suspended'`, `is_online = 0`, and `users.status = 'suspended'`, and audits it. It does not revoke refresh tokens. The refresh path does re-check status, so the captain cannot mint a *new* access token — but the live one keeps completing trips, and `complete` never looks at `user.status`.

Worse in practice: **there is no rider suspension endpoint at all.** `admin.ts` exposes suspend/approve for captains only. A rider running promo abuse or chargeback fraud cannot be stopped from the console; the only lever is a manual SQL write against production D1.

And the status vocabulary has no `banned` — `users.status` is constrained to `active`/`suspended`/`pending` (`migrations/0001_init.sql:10`), so the schema cannot distinguish "under investigation" from "permanently barred", and any admin can silently reverse either by approving.

### F-18-07 — Nothing durable identifies a person or a phone

Three gaps compose into unlimited multi-accounting:

**Phone is not unique.** `users.phone` carries an index (`migrations/0011_payment_intentions.sql:28`) but no UNIQUE constraint. `POST /auth/register` checks only `WHERE email = ?` (`apps/api/src/routes/auth.ts:363`) before inserting an `active` account.

**`/register` has no captcha.** `POST /auth/request-otp` calls `verifyTurnstile` (`auth.ts:70-79`); the email/password register path at `:347-384` does not. Its only defence is `rateLimit({prefix:"register", limit:10, windowSec:60})` (`:347`) — keyed by IP, so ten accounts per minute per exit address, and Egyptian mobile CGNAT gives an attacker a new one on demand.

**The device is a push token.** `device_tokens` stores `token`, `platform`, `app_role` (`migrations/0003_global_transport.sql:12-22`) and nothing hardware-derived. The upsert is `ON CONFLICT(token) DO UPDATE SET user_id = excluded.user_id` (`apps/api/src/routes/devices.ts:21-25`) — the row follows whichever account presents the token last, so even the weak signal it carries is erasable by reinstalling the app.

Cost to the attacker: an Egyptian prepaid SIM, a few pounds. Cost to defend after launch: much higher, because the linkage data for accounts created before the fingerprint exists can never be backfilled. This is the strongest argument for shipping P0.6 before the first marketing campaign rather than after the first loss.

### F-18-09 — Webhook replay double-credits

The Paymob HMAC verification itself is sound: `verifyPaymobHmacAsync` (`apps/api/src/lib/paymob.ts:215-229`) uses SHA-512 over the canonical field list with a timing-safe comparison and fails closed when `PAYMOB_HMAC` is unset. Forgery is not the issue; **replay** is.

In the intention path the transaction row is written with `INSERT OR IGNORE ... idempotency_key` (`apps/api/src/routes/payments.ts:175-180`) and the balance is then updated **unconditionally** (`:182`). A duplicate delivery — Paymob retries on any non-2xx, and the same signed body can simply be posted again — is ignored by the insert and applied by the update. The legacy path four hundred lines below gets it right (`:268`): it checks `ins.meta.changes === 0` and returns early. The fix is to copy that guard upward.

### F-18-11 — The console cannot fight fraud

Every mutating admin action, extracted from `apps/api/src/routes/admin.ts` and `promo.ts`:

| Endpoint | Method | Mutates | Audited | Path:line |
|---|---|---|---|---|
| `/admin/captains/:id/approve` | POST | `captains.approval_status`, `users.status` | yes | `admin.ts:261-287` |
| `/admin/captains/:id/suspend` | POST | `captains.approval_status`, `is_online`, `users.status` | yes | `admin.ts:289-310` |
| `/admin/documents/:id/review` | POST | `driver_documents.status`, `captains.approval_status` | yes | `admin.ts:821-864` |
| `/admin/captains/:id/documents/:docId/reject` | POST | `driver_documents.status` | yes | `admin.ts:867-890` |
| `/admin/pricing/:city` | PUT | `pricing_rules` | yes | `admin.ts:349-415` |
| `/admin/system-config` | PUT | `system_config` | yes | `admin.ts:488-543` |
| `/admin/document-types` | POST/PUT/DELETE | `document_types` | yes | `admin.ts:698-819` |
| `/promos/` | POST | `promo_codes` | yes | `promo.ts:60-92` |
| `/promos/:code/deactivate` | POST | `promo_codes.active` | yes | `promo.ts:94-108` |

That is the complete list — everything else under `/admin` is read-only. The moderation surface is captain onboarding and pricing configuration. What an anti-fraud analyst needs and cannot do: suspend a rider, hold or reject a payout, freeze a wallet, force re-verification, force-cancel a live trip, adjust a fare, issue a refund or goodwill credit, flag an account for review, or open a single view showing one entity's devices, IPs, trips, and money movements together. Each of those is currently a hand-written SQL statement against production.

### 4.1 The fraud surface, scenario by scenario

The ten scenarios the brief asks about, each traced against the code above. "Cost" is the plausible monthly exposure at launch scale (roughly 2,000 trips/day, 60 EGP average fare), stated as an order of magnitude rather than a forecast.

| # | Attack | Possible today? | Cost if unaddressed | What detects it today | Control | Effort |
|---|---|---|---|---|---|---|
| a | Captain + accomplice run fake trips to farm incentives | **Yes, trivially** — three calls, no position needed (F-18-02); on wallet it also mints money (F-18-01) | 200k–800k EGP/month once an incentive scheme exists | Nothing | P0.1–P0.3 geofence + completion guard; P1.2 velocity rules | M |
| b | GPS spoofing to sit in a surge cell or simulate a drive | **Yes** — client picks its own cell (F-18-03) | Dispatch integrity collapse; surge economics unusable | Nothing | P0.4 location validator; P1.4 mock-location signal | M |
| c | Bulk rider accounts for first-ride promos | **Yes** — phone not unique, no captcha on `/register` (F-18-07) | Entire acquisition budget; typically the first attack a new market sees | Nothing | P0.6 device fingerprint + phone uniqueness; P0.7 promo caps | M |
| d | Promo code shared far beyond intent | **Yes** — no per-user cap, no first-trip rule (F-18-05) | 100% of any campaign, in hours | `uses_count` only, and only if `max_uses` was set | P0.7 per-user redemption ledger | S |
| e | Referral self-dealing | **Not yet** — tables exist, no write path (F-18-24) | 0 today; high the day it ships | N/A | P1.6 constraints before the feature lands | S |
| f | Captain cancels after arriving to collect a fee | **No** — there is no cancellation fee anywhere in `trips.ts:709-830` | 0 today | N/A | Design the fee *with* the abuse control (P2.3); hand to T16 | M |
| g | Rider claims the trip never happened, forces a refund | **Partly** — no refund endpoint exists (F-18-11), so disputes go straight to the card scheme, and the platform has almost no evidence to contest with (F-18-23) | Chargeback fees plus PSP ratio risk | Nothing | P0.8 evidence log; P1.7 dispute pack | M |
| h | Card testing against the payment endpoint | **Yes** — no per-user limit, PSP error text forwarded (F-18-14) | PSP fraud-ratio breach; account termination is the real risk | Nothing | P0.9 per-user limit + generic errors | S |
| i | Wallet-credit laundering between colluding accounts | **Yes** — stolen card → top-up → fake trip → captain wallet → instant payout (F-18-01, F-18-04) | Direct 1:1 loss on every stolen card, minus commission | Nothing | P0.5 payout hold; P1.1 risk score on payout | M |
| j | Captain account rental to unverified drivers | **Yes** — no identity uniqueness (F-18-21), no re-verification, no session binding | Regulatory and safety exposure; the failure mode that ends a licence | Nothing | P1.5 periodic selfie check + device binding | L |

Two entries deserve emphasis. Scenario (f) is *not possible* only because the product has no cancellation fee yet — when T16 adds one, it arrives on a platform with no abuse control, so the control must ship with the feature, not after. Scenario (g) is worse than it looks: the absence of a refund endpoint does not mean disputes do not happen, it means they happen at the card scheme where the platform loses by default for want of evidence.

## 5. Benchmark gap

**Uber.** Device fingerprinting is the foundation — Uber's own engineering writing describes an in-house device-identity service, and the acquisition of dozens of anti-fraud signals per request is well documented publicly (confident). Trip-level anomaly detection scores fare-to-distance-to-duration coherence and flags impossible geometry (confident). Driver account sharing is countered with periodic real-time ID checks — a selfie matched against the licence photo before going online, in-market since 2016 and widely reported (confident). Incentive programmes are settled on a delay with a dedicated investigations function (confident). Synaptic Go has none of the four.

**inDrive.** The closest analogue: bid-based pricing, cash-heavy, emerging markets with exactly Egypt's risk profile. Their public engineering and PR material describes ML-based anti-fraud on trip and driver behaviour and periodic driver verification (assumed in detail, confident in existence). The structural lesson from the bid model is the one that matters here: when the price is negotiated rather than computed, the platform loses the fare as an integrity signal, so **the GPS trace and the device identity have to carry the whole weight**. Synaptic Go has adopted the bid model (`accepted_price` wins at completion, `trips.ts:969`) without adopting either compensating control.

**Careem.** Regionally relevant for cash: cash-trip commission is collected against a captain wallet that goes negative and blocks going online past a threshold (assumed — the mechanism is visible to drivers, the thresholds are not public). Synaptic Go implements the negative wallet (`trips.ts:1029-1033`) but not the block, so the debt accrues with nothing at the end of it (F-18-15).

**Payments industry.** Velocity rules and hold periods are the two primitives every acquirer expects a marketplace to operate (confident). Synaptic Go has neither. A 24-hour payout hold is the cheapest control in this document and the one with the largest single effect on realised loss.

**Where Synaptic Go actually sits.** Not "behind on sophistication" — *absent*. The comparison is not between a simple rule engine and an ML model; it is between zero controls and any controls. That is the honest framing for the P0 list: nothing below is state of the art, and all of it is table stakes.

One genuine strength worth recording: `wallet_transactions` already carries an `idempotency_key` with a unique index (`migrations/0005_integer_currency_and_idempotency.sql`, index `idx_wt_idem`) and the completion path uses it correctly for both the payout and the commission debit (`trips.ts:1039`, `:1019`). The money-movement layer is more disciplined than the fraud layer; the plan below leans on that discipline rather than replacing it.

## 6. Improvement plan

Ordered by the ratio of loss prevented to effort spent. P0 items are the S1 set; nothing in P0 requires new infrastructure, and all of it is a Worker, a migration, or both.

### P0.1 — Fail the completion when the rider debit fails
- **Goal** — the platform stops creating money it never received.
- **Design** — in `POST /trips/:id/complete`, for `payment_method = 'wallet'` and not company-billed, treat `debitRes.meta.changes === 0` as terminal: do not credit the captain, do not leave the trip `completed`. Return `402 PAYMENT_REQUIRED` with code `INSUFFICIENT_RIDER_BALANCE`, revert the status write (or, better, order the operations so the status flip happens last), and record a `trip_events` row of type `completion_blocked`. The captain's app should surface "collect in cash" as the fallback and allow a one-way switch of `payment_method` to `cash`, which routes into the existing commission-debit branch.
- **Files to change** — `apps/api/src/routes/trips.ts` (reorder `:973-1054`; guard at `:1003`), `apps/captain/lib/...` trip completion screen (fallback UI), `packages/flutter_shared` error mapping for the new code.
- **DB** — none.
- **API contract** — `POST /trips/:id/complete` gains a `402` response: `{ error, code: "INSUFFICIENT_RIDER_BALANCE", shortfall: <number> }`. New optional body field `{ "fallbackToCash": true }` completes the trip on the cash branch instead.
- **Effort** — S.
- **Risk** — a rider whose balance legitimately disappeared mid-trip now blocks the captain's completion; the cash fallback is what prevents that becoming a support incident. Rollback is reverting one commit.
- **Acceptance criteria** — completing a wallet trip for a rider with zero balance returns 402, leaves `trips.status = 'in_progress'`, and creates **no** `wallet_transactions` credit row for the captain.
- **Tests** — integration test: rider balance 0, full trip flow, assert 402 and assert `SELECT count(*) FROM wallet_transactions WHERE trip_id = ? AND direction = 'credit'` is 0. Second test with `fallbackToCash` asserting the commission debit path runs exactly once.

### P0.2 — Verify funding at trip creation
- **Goal** — a wallet trip is only created when it can be paid for.
- **Design** — in `POST /trips`, when `paymentMethod === 'wallet'`, read the rider's balance and reject if it is below `finalEstimate` plus a 20% headroom for surge and waiting time. Return the shortfall so the app can send the rider to top-up.
- **Files to change** — `apps/api/src/routes/trips.ts:438-481`.
- **DB** — none.
- **API contract** — `POST /trips` gains `402` `{ code: "INSUFFICIENT_BALANCE", required, available }`.
- **Effort** — S.
- **Risk** — the headroom rejects a few legitimate marginal trips; make the multiplier a `system_config` key rather than a constant.
- **Acceptance criteria** — creating a wallet trip with a balance below the estimate returns 402 and writes no `trips` row.
- **Tests** — boundary tests at exactly the estimate, at estimate × 1.2, and one below.

### P0.3 — Geofence and plausibility-gate the trip state transitions
- **Goal** — a trip cannot be walked through its lifecycle from a sofa.
- **Design** — a shared `assertCaptainNear(env, captainUserId, target, radiusM)` helper reading `captains.last_lat/last_lng/last_seen_at`. Applied at three points: `arrived` requires the captain within **250 m** of pickup with a fix no older than **90 s**; `in_progress` requires the same at pickup; `completed` requires within **500 m** of dropoff *or* an accumulated `trip_path_points` distance of at least **60%** of `trips.distance_km`. Additionally reject `completed` when `started_at` is less than **60 s** ago, and when the trip has fewer than two path points for any trip whose estimate exceeds 2 km. Every rejection writes a `risk_events` row (P0.8) rather than only a 400 — a captain who trips this repeatedly is the signal, not the noise.
- **Files to change** — new `apps/api/src/lib/tripGeofence.ts`; `apps/api/src/routes/trips.ts:891-941` (`advanceStatus`) and `:951-981` (`complete`).
- **DB** — none beyond P0.8's `risk_events`.
- **API contract** — `400` `{ code: "CAPTAIN_NOT_AT_PICKUP" | "CAPTAIN_NOT_AT_DROPOFF" | "TRIP_TOO_SHORT" | "STALE_POSITION", distanceM, requiredM }`.
- **Effort** — M.
- **Risk** — the real one: a captain in an urban canyon or a parking garage with a poor fix is blocked from completing a legitimate trip. Mitigate with the generous radii above, the path-distance alternative for completion, and an explicit `POST /trips/:id/complete/override` that requires a reason string, always writes a `risk_events` row, and is reviewed. Thresholds live in `system_config` so they can be relaxed without a deploy.
- **Acceptance criteria** — a captain 5 km from pickup cannot mark `arrived`; a trip completed 10 s after `start` is rejected; every rejection appears in `risk_events`.
- **Tests** — unit tests on the helper with fabricated coordinate pairs; integration tests for each of the three transitions; one test asserting the override path is logged.

### P0.4 — Server-side location plausibility validator
- **Goal** — the server stops believing coordinates it has no reason to believe.
- **Design** — a pure function in a new `apps/api/src/lib/locationTrust.ts`:

```ts
export type Fix = { lat: number; lng: number; atMs: number };
export type Incoming = {
  lat: number; lng: number;
  accuracyM?: number; isMock?: boolean; deviceAtMs?: number;
};
export type Verdict =
  | { ok: true; flags: string[] }
  | { ok: false; code: LocationRejectCode; detail: Record<string, number | string> };
```

Checks, in order, with thresholds tuned for Cairo:

| Check | Threshold | On breach |
|---|---|---|
| Coordinate sanity | lat/lng inside the operating bbox (Egypt: lat 22–32, lng 24–37) | reject `OUT_OF_REGION` |
| Mock location | `isMock === true` | reject `MOCK_LOCATION` + `risk_events` |
| Accuracy | `accuracyM > 150` for path points; `> 500` for presence | drop the point / flag `LOW_ACCURACY` |
| Device clock skew | `abs(deviceAtMs − serverNow) > 30 s` | flag `CLOCK_SKEW`; reject above 300 s |
| Duplicate | elapsed since previous fix `< 1 s` | reject `TOO_FREQUENT` |
| Implied speed | `haversineKm(prev, now) / elapsedH > 150 km/h` | reject `IMPOSSIBLE_SPEED` + `risk_events` |
| Sustained speed | rolling 5-fix mean `> 110 km/h` | flag `SUSTAINED_SPEED` |
| Stale baseline | elapsed `> 600 s` | accept, reset baseline, flag `BASELINE_RESET` |

  150 km/h is deliberately loose — it accommodates the Ring Road, a passenger on the Cairo–Alexandria Desert Road, and GPS jitter, while still catching teleports by three orders of magnitude. Tighten with production data, not before.
  The previous fix comes from `captains.last_lat/last_lng/last_seen_at`, already read in the same handler; the DO path keeps its own `prevFix` in storage.
- **Files to change** — new `apps/api/src/lib/locationTrust.ts`; `apps/api/src/lib/schemas.ts:181-187` (add `accuracy`, `isMock`, `deviceAt` to `captainLocationSchema`); `apps/api/src/routes/captain.ts:198-270` (validate before `:205`, before the cell heartbeat at `:211`, and before the path insert at `:246`); `apps/api/src/durable-objects/TripRoom.ts:167-177` (validate before storing/broadcasting — closes F-18-17); the captain Flutter location service to send the three new fields.
- **DB** — migration `0020_location_trust.sql`: `ALTER TABLE trip_path_points ADD COLUMN accuracy_m REAL;` `ADD COLUMN is_mock INTEGER NOT NULL DEFAULT 0;` `ADD COLUMN device_at TEXT;` `ADD COLUMN speed_kph REAL;` and populate `speed_kph` from the validator's computed value so F-18-23 stops being true going forward.
- **API contract** — `POST /captain/location` gains `422` `{ code: "IMPOSSIBLE_SPEED" | "MOCK_LOCATION" | ..., detail }`. Old clients that omit the new fields keep working: absent `isMock`/`accuracy` are treated as unknown and flagged, not rejected, for one release cycle.
- **Effort** — M.
- **Risk** — rejecting real fixes from cheap Android handsets with poor GNSS. Ship in shadow mode first: run the validator, write `risk_events`, reject nothing. Turn on enforcement per-code once the false-positive rate is visible.
- **Acceptance criteria** — a scripted 16 km jump in 5 s is rejected; a mock-location fix is rejected; a normal Cairo drive produces zero rejections over a 30-minute trace.
- **Tests** — unit tests per threshold with fabricated fix pairs; a replay test over a recorded genuine trace asserting no rejections.

### P0.5 — Payout hold and admin release
- **Goal** — fraud proceeds cannot leave the platform before a human can look.
- **Design** — a payout request enters `status = 'held'` when any of: the account is younger than **7 days**, the requested amount exceeds **2,000 EGP**, the captain's risk score is **≥ 50** (P1.1), or any trip funding the balance completed within the last **24 hours**. Otherwise `pending` as today. A new admin queue lists held payouts with the entity's recent trips and risk events; an admin releases or rejects, and a rejection returns the amount to the wallet under a new idempotency key. The 24-hour rolling hold is the single most valuable line in this plan.
- **Files to change** — `apps/api/src/routes/wallet.ts:98-142`; `apps/api/src/routes/admin.ts` (three new endpoints); `apps/admin/src` queue page.
- **DB** — migration `0021_payout_holds.sql`: add `'held'` and `'rejected'` to the `wallet_transactions.status` CHECK, plus `held_reason TEXT`, `released_by TEXT REFERENCES users(id)`, `released_at TEXT`; index on `(status, created_at)`.
- **API contract** — `GET /admin/payouts?status=held`, `POST /admin/payouts/:id/release`, `POST /admin/payouts/:id/reject { reason }`. The captain-facing response gains `status: "held"` and an ETA string.
- **Effort** — M.
- **Risk** — captain dissatisfaction; a held payout on payday is a support call. Publish the hold rule in the captain app rather than making it feel arbitrary.
- **Acceptance criteria** — a payout requested within 24 h of the funding trip lands `held`; release moves it to `pending` and writes an audit row naming the admin; reject restores the balance exactly once under replay.
- **Tests** — each hold trigger; a double-release attempt asserting idempotency.

### P0.6 — Device fingerprint and identity uniqueness
- **Goal** — one handset and one identity cannot silently become fifty accounts.
- **Design** — a client-generated, install-scoped UUID persisted in the OS keystore (Android Keystore / iOS Keychain, both surviving app reinstall on modern OS versions), sent as an `X-Device-Id` header on every authenticated request and recorded on login. Deliberately not an SDK and deliberately not a hardware ID: no `AAID`/`IDFV` collection, no privacy exposure beyond an opaque random value, nothing that needs a vendor contract. Its power is not certainty but **linkage** — twenty accounts sharing one device id is the signal. Pair it with a `UNIQUE` index on `users.phone` and on `captains.national_id_number`.
- **Files to change** — `packages/flutter_shared/lib/services/api_client.dart` (inject the header — the file is a bare wrapper today, `:10-13`); a new keystore-backed device-id service in `flutter_shared`; `apps/api/src/middleware/auth.ts` (read the header onto the context); `apps/api/src/routes/auth.ts` (record on login/register); `apps/api/src/routes/devices.ts` (stop letting a token migrate silently — log it as a `risk_events` row when `user_id` changes).
- **DB** — migration `0022_device_identity.sql`: new `device_identities (device_id TEXT, user_id TEXT, first_seen_at TEXT, last_seen_at TEXT, login_count INTEGER, PRIMARY KEY (device_id, user_id))`, index on `device_id`; `CREATE UNIQUE INDEX idx_users_phone_unique ON users(phone) WHERE phone IS NOT NULL;` `CREATE UNIQUE INDEX idx_captains_nid_unique ON captains(national_id_number) WHERE national_id_number IS NOT NULL;`
- **API contract** — `X-Device-Id` header, optional for one release then required for account creation.
- **Effort** — M.
- **Risk** — the unique indexes will fail to create if duplicates already exist; run the dedupe query first and resolve manually. A user who wipes their phone gets a new id — expected, and why this is a linkage signal rather than an enforcement gate.
- **Acceptance criteria** — the same install registering two accounts produces two `device_identities` rows with one `device_id`; a second account with an existing phone number is rejected at registration.
- **Tests** — migration test against a seeded duplicate; integration test asserting header capture on login.

### P0.7 — Promo redemption ledger
- **Goal** — one code, one rider, one use, and only for those it was meant for.
- **Design** — record redemptions per user, enforce the cap inside a single conditional statement, and release the slot when the trip is cancelled. Add eligibility columns so a first-ride code means what it says.
- **Files to change** — `apps/api/src/routes/trips.ts:399-426`, `:493-503`, and the cancel handler `:709-830` (release); `apps/api/src/routes/promo.ts:10-51` (mirror the eligibility checks in `/validate` so the preview cannot lie); `apps/api/src/lib/schemas.ts:258-285` (min length 6, generated codes).
- **DB** — migration `0023_promo_integrity.sql`:

```sql
ALTER TABLE promo_codes ADD COLUMN per_user_limit INTEGER NOT NULL DEFAULT 1;
ALTER TABLE promo_codes ADD COLUMN first_trip_only INTEGER NOT NULL DEFAULT 0;
ALTER TABLE promo_codes ADD COLUMN min_fare REAL;
ALTER TABLE promo_codes ADD COLUMN max_discount REAL;
CREATE TABLE promo_redemptions (
  id TEXT PRIMARY KEY,
  code TEXT NOT NULL REFERENCES promo_codes(code),
  user_id TEXT NOT NULL REFERENCES users(id),
  trip_id TEXT NOT NULL REFERENCES trips(id),
  discount REAL NOT NULL,
  status TEXT NOT NULL DEFAULT 'reserved'
    CHECK (status IN ('reserved','consumed','released')),
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE UNIQUE INDEX idx_promo_redeem_trip ON promo_redemptions(trip_id);
CREATE INDEX idx_promo_redeem_user ON promo_redemptions(code, user_id, status);
```

  Reserve at creation, consume at completion, release at cancellation. `max_discount` also caps the percent path, which today multiplies an unbounded estimate (`trips.ts:421-424`).
- **API contract** — `POST /promos/validate` gains `{ valid: false, code: "PROMO_ALREADY_USED" | "PROMO_NOT_ELIGIBLE" }`.
- **Effort** — M.
- **Risk** — the reserve/release state machine leaks slots if a cancel path is missed; a nightly reconciliation job that releases reservations on trips that ended more than an hour ago covers it.
- **Acceptance criteria** — a rider cannot use the same code twice; cancelling returns the slot; a `first_trip_only` code is refused to a rider with a completed trip.
- **Tests** — the double-use case, the cancel-release case, the eligibility case, and a concurrency test firing two creations with the same code and asserting exactly one reservation.

### P0.8 — The fraud event log
- **Goal** — the data needed to investigate must exist before the fraud happens. This cannot be retrofitted.
- **Design** — one append-only table for risk signals, plus the request context that makes any of it attributable.

```sql
-- migration 0024_risk_events.sql
CREATE TABLE risk_events (
  id TEXT PRIMARY KEY,
  occurred_at TEXT NOT NULL DEFAULT (datetime('now')),
  event_type TEXT NOT NULL,          -- location.impossible_speed, trip.geofence_fail,
                                     -- promo.reuse_attempt, payout.held, auth.otp_fail,
                                     -- device.token_reassigned, payment.decline, ...
  severity INTEGER NOT NULL DEFAULT 10,
  subject_type TEXT NOT NULL,        -- user | captain | trip | device | promo | payout
  subject_id TEXT NOT NULL,
  actor_user_id TEXT,
  trip_id TEXT,
  device_id TEXT,
  ip TEXT,
  user_agent TEXT,
  detail TEXT,                       -- JSON: thresholds, measured values
  score_delta INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX idx_risk_subject ON risk_events(subject_type, subject_id, occurred_at);
CREATE INDEX idx_risk_type_time ON risk_events(event_type, occurred_at);
CREATE INDEX idx_risk_device ON risk_events(device_id, occurred_at);

CREATE TABLE auth_attempts (
  id TEXT PRIMARY KEY,
  at TEXT NOT NULL DEFAULT (datetime('now')),
  channel TEXT NOT NULL,             -- otp_request | otp_verify | password | refresh
  identifier TEXT NOT NULL,          -- phone or email, normalised
  user_id TEXT,
  success INTEGER NOT NULL,
  failure_code TEXT,
  ip TEXT, device_id TEXT, user_agent TEXT
);
CREATE INDEX idx_auth_ident_time ON auth_attempts(identifier, at);
CREATE INDEX idx_auth_ip_time ON auth_attempts(ip, at);
```

  Minimum events to emit from day one, each one currently invisible (F-18-18): every auth attempt success **and failure**; every OTP request with its target; account creation with device id and IP; every trip state transition with the captain's position at that moment and the elapsed time since the previous state; every promo reservation, consumption, release and refusal; every payment intention and its outcome; every wallet movement already covered by `wallet_transactions` cross-referenced by `trip_id`; every payout request, hold, release and rejection; every device-token reassignment; every location rejection from P0.4; every geofence failure from P0.3.
  Also add request context to `audit_log` usage: the admin actions pass `ip` but never `user_agent` (`admin.ts:278`, `:306`) — pass both, and add a request id.
  Retention: `risk_events` and `auth_attempts` for **13 months**; `trip_path_points` for **13 months**; and change the OTP cleanup (`apps/api/src/lib/cleanup.ts:35-41`) so the *attempt* survives in `auth_attempts` even when the code row is deleted (F-18-19). Confirm the retention window with T25 before shipping.
- **Files to change** — new `apps/api/src/lib/risk.ts` with `recordRiskEvent()`; call sites across `trips.ts`, `captain.ts`, `auth.ts`, `promo.ts`, `payments.ts`, `wallet.ts`, `devices.ts`; `apps/api/src/lib/cleanup.ts`.
- **DB** — `0024_risk_events.sql` as above.
- **API contract** — none (internal), plus `GET /admin/risk-events?subject_id=` in P1.3.
- **Effort** — M.
- **Risk** — D1 write volume. Location rejections are the only high-cardinality source; sample them at 1-in-10 per captain per hour after the first event in each window.
- **Acceptance criteria** — a fake-trip run end to end produces a reconstructible timeline from `risk_events` alone: account creation, device, positions, transitions, money.
- **Tests** — an integration test that executes the fraud scenario and asserts the expected event rows exist in order.

### P0.9 — Close the cheap abuse holes
- **Goal** — remove the four one-line-ish gaps that need no design.
- **Design** — (a) fix the webhook replay by checking `changes` before the balance update, copying the pattern already at `payments.ts:268`; (b) add `rateLimit({prefix:"pay-intent", limit:5, windowSec:300, keyFn: user id})` to the intention endpoint and replace the forwarded PSP message at `:91` with a generic `PAYMENT_FAILED`; (c) make `verifyTurnstile` fail closed when `TURNSTILE_SECRET_KEY` is missing and `ENVIRONMENT === 'production'`, and stop writing `verified = 1` for a skip (`turnstile.ts:16-27`); (d) call `verifyTurnstile` on `/auth/register` (`auth.ts:347`); (e) refuse `DEV_OTP` in production (`auth.ts:122-126`); (f) raise `offeredPrice`/`counterPrice` minimums to the city's configured minimum fare (`schemas.ts:59`, `:77`); (g) add the missing balance floor to the cash commission debit (`trips.ts:1029-1033`) and block going online below −200 EGP.
- **Files to change** — as listed inline.
- **DB** — none.
- **API contract** — payment errors become generic; `POST /trips` rejects sub-minimum offers with `400 OFFER_BELOW_MINIMUM`.
- **Effort** — S (all seven together).
- **Risk** — (c) will take the API down at boot if the secret is genuinely missing in production, which is the intended behaviour; verify the secret is set before deploying.
- **Acceptance criteria** — a replayed webhook credits once; six intention calls in five minutes get 429; a production boot without the Turnstile secret fails loudly.
- **Tests** — replay test, limiter test, and a config test asserting the production guard.

### P1.1 — Risk scoring in the Worker
- **Goal** — one number per entity that decides what happens next.
- **Design** — no ML, no external service: a bounded additive score, 0–100, recomputed on demand from `risk_events` over a rolling 30-day window and cached in KV for five minutes.

| Signal | Weight | Source |
|---|---|---|
| Mock location detected | +40 | `risk_events` P0.4 |
| Impossible speed rejection | +15 each, cap +45 | P0.4 |
| Geofence failure on a transition | +10 each, cap +30 | P0.3 |
| Trip shorter than 90 s with fare > 40 EGP | +15 | completion |
| Same rider–captain pair, 3+ trips in 24 h | +20 | trip query |
| More than 12 completed trips in an hour | +25 | trip query |
| Wallet debit failures on completed trips | +35 | P0.1 |
| Account younger than 7 days | +10 | `users.created_at` |
| Device shared with 3+ accounts | +25 | `device_identities` |
| Promo refusals (reuse attempts) | +5 each, cap +20 | P0.7 |
| Payment declines in 24 h ≥ 3 | +20 | P0.9 |
| 50+ completed trips, no prior flags | −15 | trip history |
| Identity documents approved | −10 | `driver_documents` |

  Tiers and actions: **0–24 allow**; **25–49 challenge** (Turnstile on sensitive actions, re-OTP before payout); **50–74 hold** (payouts held, promos refused, dispatch priority reduced — do not silently stop offering trips, that is unexplainable to an honest captain); **75–89 review** (queued for an analyst, payouts frozen, new trips allowed); **90+ block** (cannot go online, cannot create trips, existing trip allowed to finish safely).
  Deliberately transparent and rule-based: every score decomposes into the events that produced it, which is what an analyst needs and what an appeal requires.
- **Files to change** — new `apps/api/src/lib/riskScore.ts`; call sites in `wallet.ts` (payout), `trips.ts` (create, complete), `captain.ts` (online).
- **DB** — migration `0025_risk_scores.sql`: `risk_scores (subject_type, subject_id, score, tier, computed_at, breakdown TEXT, PRIMARY KEY (subject_type, subject_id))`.
- **API contract** — internal; surfaced via P1.3.
- **Effort** — M.
- **Risk** — false positives blocking honest captains. Ship in shadow for two weeks: compute and store, act on nothing, review the distribution, then enable tiers upward from `hold`.
- **Acceptance criteria** — the F-18-01 fraud scenario scores ≥ 75 within three cycles; a seeded honest captain over 200 trips stays under 25.
- **Tests** — fixture-driven scoring tests per signal; a replay of seeded honest and fraudulent histories.

### P1.2 — Velocity rules
- **Goal** — catch the patterns a single request cannot show.
- **Design** — evaluated on trip completion and on payout request, each emitting a `risk_events` row rather than blocking directly (the score decides the action):

| Rule | Threshold | Rationale |
|---|---|---|
| Trips completed per captain per hour | > 12 | Cairo traffic makes 12 legitimate short trips an hour near the ceiling |
| Same rider–captain pair | ≥ 3 completed in 24 h, or ≥ 8 in 7 days | The strongest collusion signal available |
| Fare-to-distance ratio | outside 0.4× – 3× the city median for the vehicle type | Catches inflated and nominal fares alike |
| Trip duration vs routed duration | < 25% of estimate | The three-calls-in-a-second fake trip |
| Distance travelled vs routed distance | < 60% with fewer than 3 path points | Completion without a journey |
| Night-time concentration | > 60% of a captain's trips between 01:00 and 05:00 local, with ≥ 10 trips | Farming happens when nobody is watching |
| New-account trip burst | ≥ 5 completed trips in the first 24 h of a captain account | Rented or throwaway accounts |
| Promo redemptions per device | ≥ 3 distinct accounts on one `device_id` | Multi-accounting made visible |
| Payout amount vs 30-day earnings | > 150% | Balance that did not come from driving |

- **Files to change** — new `apps/api/src/lib/velocity.ts`; called from `trips.ts` completion and `wallet.ts` payout.
- **DB** — none beyond `risk_events`; add index `idx_trips_pair ON trips(rider_id, captain_id, completed_at)`.
- **API contract** — none.
- **Effort** — M.
- **Risk** — every threshold here is a guess until there is production data. Log the measured distribution for two weeks before enforcing, and keep all thresholds in `system_config`.
- **Acceptance criteria** — each rule fires on a seeded matching fixture and stays silent on a seeded honest one.
- **Tests** — one fixture pair per rule.

### P1.3 — The analyst queue
- **Goal** — an analyst can see one entity's whole story and act on it in one place.
- **Design** — a review queue over `risk_events` and `risk_scores`, and an entity page showing identity, devices, IPs, risk timeline, trips with their path traces, and money movements side by side. Actions available inline: suspend or reinstate (rider **and** captain), hold or release a payout, force document re-verification, flag for watch, and add an analyst note. Every action audited with actor, IP, user agent, and reason.
- **Files to change** — `apps/api/src/routes/admin.ts` (queue and action endpoints); `apps/admin/src` (queue page, entity page).
- **DB** — migration `0026_review_queue.sql`: `review_cases (id, subject_type, subject_id, status CHECK IN ('open','investigating','actioned','dismissed'), opened_at, opened_reason, assigned_to, closed_at, resolution, notes)`.
- **API contract** — `GET /admin/review-cases`, `POST /admin/review-cases/:id/assign|resolve`, `GET /admin/entities/:type/:id/profile`, `POST /admin/users/:id/suspend` (closes the rider gap in F-18-06), `POST /admin/users/:id/reinstate`.
- **Effort** — L.
- **Risk** — scope creep into a full case-management system; keep it to a list, a profile, and six actions. Coordinate with T11, who owns the console's shape.
- **Acceptance criteria** — an analyst moves from a queue item to a suspension in two clicks, and the action appears in `audit_log` with a reason.
- **Tests** — endpoint tests per action; an authorisation test asserting non-admins are refused.

### P1.4 — Make the ban bite immediately
- **Goal** — enforcement takes effect on the next request, not in fifteen minutes.
- **Design** — a KV deny-list: `revoked:user:{id}` written on suspension with a TTL slightly longer than the access-token lifetime, checked in `authMiddleware`. One KV read per request, which is the cost of the current architecture's speed; Cloudflare KV is eventually consistent, so the realistic worst case is a few seconds of propagation rather than fifteen minutes — an honest improvement, not a guarantee, and it should be described that way. Also revoke refresh tokens on suspension, and add a `banned` value to the `users.status` CHECK so "permanently barred" is representable.
- **Files to change** — `apps/api/src/middleware/auth.ts:49-61`; `apps/api/src/routes/admin.ts:289-309`; new suspension endpoint from P1.3.
- **DB** — migration `0027_ban_status.sql` rebuilding the `users.status` CHECK to include `'banned'` (SQLite requires the table-rebuild dance — coordinate with T08).
- **API contract** — none.
- **Effort** — S.
- **Risk** — a KV read on every authenticated request adds latency and cost; measure before and after, and skip the check for read-only endpoints if the numbers demand it.
- **Acceptance criteria** — a suspended captain's next `complete` call returns 401 within seconds.
- **Tests** — suspend mid-session, assert the next call fails.

### P1.5 — Captain liveness and account-rental defence
- **Goal** — the person driving is the person who was approved.
- **Design** — a periodic selfie challenge before going online: required on first online of the day for captains with a risk score ≥ 25, weekly otherwise, and immediately after a device change. Store in R2 alongside the existing document flow (`driver_documents` already has the storage and review pattern), and compare manually at first — automated face matching is a P2 decision and a T25 privacy conversation, not a launch requirement. Bind the captain's session to a `device_id` and raise a risk event when an approved captain goes online from a new device.
- **Files to change** — `apps/api/src/routes/captain.ts` (online handler), new selfie-check endpoints; captain Flutter app; `apps/admin/src` review view.
- **DB** — migration `0028_liveness_checks.sql`: `liveness_checks (id, captain_user_id, r2_key, requested_at, submitted_at, reviewed_by, status, device_id)`.
- **API contract** — `POST /captain/liveness/request`, `POST /captain/liveness/submit`, `GET /admin/liveness?status=pending`.
- **Effort** — L.
- **Risk** — friction at exactly the moment a captain wants to earn; keep it under 20 seconds and never mid-trip. Biometric handling has legal weight — clear it with T25 first.
- **Acceptance criteria** — a captain with a new device is challenged before going online; an unsubmitted challenge blocks online status.
- **Tests** — the challenge trigger matrix.

### P1.6 — Referral constraints before the feature ships
- **Goal** — the referral system arrives with its abuse controls already attached.
- **Design** — add the constraints now, while the tables are empty and free to change: `CHECK (referrer_id != referred_id)`, `UNIQUE (referred_id)` (a person can only be referred once, ever), reward status advancing only after the referred user's **third completed, non-cancelled, non-refunded** trip, a per-referrer monthly cap, and a device-id check refusing a referral where referrer and referred share a device.
- **Files to change** — none yet (no write path exists); the constraints go in the migration so whoever implements the feature inherits them.
- **DB** — migration `0029_referral_integrity.sql` rebuilding `referrals` with the constraints above.
- **API contract** — none yet.
- **Effort** — S.
- **Risk** — none today; the table is empty.
- **Acceptance criteria** — the constraints exist and are tested against attempted self-referral inserts.
- **Tests** — migration-level constraint tests.

### P1.7 — Dispute evidence pack
- **Goal** — win chargebacks instead of conceding them.
- **Design** — a single endpoint assembling everything the platform knows about a disputed trip: rider and captain identity, device ids, the full `trip_path_points` trace with timestamps, state-transition times, the fare breakdown, the payment reference, and any risk events. Rendered as a PDF-ready JSON payload for the finance team.
- **Files to change** — `apps/api/src/routes/admin.ts`; `apps/admin/src` trip page.
- **DB** — none (this is why P0.8 must ship first).
- **API contract** — `GET /admin/trips/:id/evidence`.
- **Effort** — S.
- **Risk** — none.
- **Acceptance criteria** — the pack for a completed trip contains a coherent, timestamped location trace.
- **Tests** — snapshot test on a seeded trip.

### P2.1 — Behavioural scoring from history
Once six months of `risk_events` exist, replace fixed weights with empirically fitted ones and add features the rule engine cannot express: route-shape similarity across a captain's trips (fake trips repeat the same trace), rider–captain graph clustering, and time-of-day deviation from a captain's own baseline. Still no external ML service — the whole model can be a scored SQL query evaluated on a cron. **Effort L.**

### P2.2 — Cash-settlement enforcement
Give the negative captain wallet a consequence: a settlement flow (Fawry/InstaPay), a threshold beyond which the captain cannot go online, and a weekly reconciliation. Coordinate with T04 — the payout rails and the settlement rails are the same integration. **Effort M.**

### P2.3 — Cancellation policy with its abuse control
When T16 introduces a cancellation fee, it must arrive with: a geofence on "arrived" before a no-show fee can be charged (P0.3 provides it), a per-captain cap on fee-bearing cancellations per day, a rider appeal path, and a velocity rule on arrive-then-cancel patterns. **Effort M.**

## 7. Phasing

| Item | Phase | Effort | Owner type |
|---|---|---|---|
| P0.1 Fail completion on failed debit | P0 | S | backend |
| P0.2 Verify wallet funding at creation | P0 | S | backend |
| P0.3 Geofence trip transitions | P0 | M | backend + Flutter |
| P0.4 Location plausibility validator | P0 | M | backend + Flutter |
| P0.5 Payout hold and admin release | P0 | M | backend + admin |
| P0.6 Device fingerprint + identity uniqueness | P0 | M | Flutter + backend |
| P0.7 Promo redemption ledger | P0 | M | backend |
| P0.8 Fraud event log | P0 | M | backend |
| P0.9 Cheap abuse holes (7 fixes) | P0 | S | backend |
| P1.1 Risk scoring | P1 | M | backend |
| P1.2 Velocity rules | P1 | M | backend |
| P1.3 Analyst queue and entity view | P1 | L | admin + backend |
| P1.4 Immediate ban enforcement | P1 | S | backend |
| P1.5 Liveness and rental defence | P1 | L | Flutter + backend + ops |
| P1.6 Referral constraints | P1 | S | backend |
| P1.7 Dispute evidence pack | P1 | S | backend + admin |
| P2.1 Behavioural scoring | P2 | L | backend + data |
| P2.2 Cash settlement enforcement | P2 | M | backend + ops |
| P2.3 Cancellation policy controls | P2 | M | backend + Flutter |

**P0 is roughly three to four engineer-weeks** and is not negotiable before production traffic: P0.1 and P0.2 stop the platform creating money, P0.3 and P0.4 stop the fake trip, P0.5 stops the exit, P0.6 stops the account farm, P0.7 stops the promo drain, P0.8 makes everything after it investigable, and P0.9 is a day of small mercies.

If only one thing ships, ship **P0.1**. If only two, add **P0.5** — a 24-hour hold buys the time in which every other control can be added later.

## 8. Metrics

Instrument these with P0.8; none can be measured today because the events do not exist.

| Metric | Definition | Current | Target |
|---|---|---|---|
| Money-minting incidents | Completed wallet trips with a `failed` rider debit and a `settled` captain credit | Unknown, structurally possible | **0** — alert on any occurrence |
| Fake-trip rate | Completed trips failing two or more velocity rules ÷ completed trips | Unmeasurable | < 0.5% by day 30 |
| Location rejection rate | Rejected fixes ÷ total fixes, split by reason | 0 (no validator) | Impossible-speed < 0.1%; mock-location trending to 0 after enforcement |
| Mock-location captains | Distinct captains with a mock event in 7 days | Unknown | < 0.2% of active captains |
| Promo efficiency | Discount spent on riders with ≥ 2 completed trips ÷ total discount | Unmeasurable | > 85% |
| Promo reuse refusals | `PROMO_ALREADY_USED` per day | N/A | Falls after week 1 — a rising line means farming |
| Multi-account density | Mean accounts per `device_id`, p99 | Unmeasurable | p99 ≤ 3 |
| Payout hold rate | Held ÷ requested | 0 | 5–15% (near 0 means the rules are asleep; above 25% means they are wrong) |
| Fraud loss rate | Confirmed fraud value ÷ GMV | Unknown | < 0.3% by day 90 |
| Time to enforce a ban | Suspension timestamp → first rejected request | Up to 15 min | < 10 s after P1.4 |
| Chargeback rate | Disputed ÷ card transactions | Unknown | < 0.5% (PSP thresholds bite near 1%) |
| Analyst time per case | Queue open → resolution | N/A (no queue) | < 10 min median |
| Investigability | Fraud incidents with a complete reconstructible timeline | ~0% | 100% |

The last row is the one to watch during P0. Every other metric depends on it.

## 9. Cross-cutting notes

- **T03 (Money integrity)** — F-18-01 is yours as much as mine: `trips.ts:993-1053` credits a captain against a debit that never landed, and `wallet_transactions` records the imbalance as a `failed` row next to a `settled` one. There is no reconciliation job comparing the two directions. Also F-18-15: the cash commission debit at `:1029-1033` has no floor, unlike every other balance update in the file.
- **T04 (Payments and payouts)** — P0.5 (hold, release, reject) and P2.2 (cash settlement) land in your surface. F-18-09, the webhook replay double-credit at `payments.ts:175-182`, is a money bug I found through the fraud lens; the correct pattern already exists in the same file at `:268`. There is also no admin endpoint that ever moves a `pending` payout to a terminal state — the captain-facing promise of "within 24 hours" is currently unimplemented on the operator side.
- **T05 (Pricing and bidding)** — `offeredPrice` and `counterPrice` accept 1 EGP (`schemas.ts:59`, `:77`) and `accepted_price` wins at completion (`trips.ts:969`), so the configured minimum fare is not enforced on the bid path. Adopting inDrive's negotiation model removes the fare as an integrity signal; that raises the cost of every control in this document, and is worth stating explicitly in your economics section.
- **T06 (Dispatch)** — F-18-03 is a dispatch-integrity problem before it is a fraud problem: the presence cell is derived from client-supplied coordinates at `captain.ts:211`, so supply distribution is attacker-controllable. Any fairness or ETA work rests on positions the server has no reason to trust.
- **T07 (Realtime)** — `TripRoom.ts:167-177` accepts a `location` message over the WebSocket with no schema validation, no rate limit and no persistence. Any validator added to the HTTP path is bypassable through it; P0.4 requires a change in your file.
- **T08 (Data model)** — this plan proposes migrations `0020` through `0029`; please sequence them. Three carry schema risk: the unique indexes on `users.phone` and `captains.national_id_number` (P0.6) will fail against existing duplicates, and adding `'banned'` to the `users.status` CHECK (P1.4) needs SQLite's table-rebuild. Separately, `PRAGMA foreign_keys` appears never to be set, so the `REFERENCES` clauses across the schema are decorative.
- **T10 (Captain app)** — P0.4 and P0.6 need client work: send `accuracy`, `isMock` and a device timestamp with every fix, and attach a keystore-backed `X-Device-Id` on every request. The `Position` object already carries the first two and they are discarded before the HTTP call.
- **T11 (Admin console)** — F-18-11 is the inventory: nine mutating endpoints, none of them anti-fraud. P1.3 adds a queue and an entity profile; that is your surface, and I have specified the endpoints rather than the pages deliberately.
- **T16 (Trip lifecycle)** — scenario (f) is impossible today only because no cancellation fee exists. When you add one, P2.3 must ship with it.
- **T17 (Safety and trust)** — ratings are a fraud signal as well as a trust signal; colluding pairs produce perfect mutual ratings. Consider surfacing rating-pattern anomalies into `risk_events`.
- **T22 (Observability)** — `risk_events` needs alerting: any money-minting occurrence, any mock-location detection, and a payout-hold rate outside 5–15% should page someone.
- **T23 (Testing)** — the fraud scenarios in §4.1 make good end-to-end test fixtures; the F-18-01 scenario in particular should be a permanent regression test.
- **T25 (Privacy)** — three items need your review before they ship: the 13-month retention on `risk_events`, `auth_attempts` and `trip_path_points`; the liveness selfies in P1.5, which are biometric data with specific legal weight; and F-18-25, where the payout audit row stores the full bank/wallet `account_info` in `audit_log.payload` (`wallet.ts:139`), a table every admin can read.
- **T27 (Cross-app parity)** — the fraud surface is asymmetric between the two apps and that asymmetry is itself a finding. The captain app is the one that reports position and the one that will carry the mock-location signal, the liveness challenge and the device binding; the rider app carries none of it. Both must send `X-Device-Id` from the shared `api_client.dart` (`:10-13`) — if only one does, multi-accounting simply migrates to the unfingerprinted side, and rider-side promo farming is precisely where it will go. The shared client is the right place for that header, and the two apps must adopt it in the same release.

## 10. Open questions

1. **Does a promo campaign exist for launch, and how big is the budget?**
   Options: (a) launch with no promos until P0.7 ships; (b) launch with promos capped at a budget you can afford to lose entirely. Recommendation: **(a)**. Promo farming is the first attack every new market sees, and the control is a week of work.

2. **Payout hold: 24 hours, or T+1 business day?**
   Options: (a) rolling 24 h; (b) daily batch at a fixed hour; (c) instant under a small threshold, hold above it. Recommendation: **(c)** — instant under 500 EGP for accounts older than 30 days with a clean score, held otherwise. It preserves the experience for the captains who earn the platform its reputation.

3. **How much location friction is acceptable?**
   Rejecting a real fix costs a real captain a real fare. Options: (a) shadow mode for two weeks, then enforce; (b) enforce immediately on mock-location only; (c) enforce everything now. Recommendation: **(a) plus (b)** — mock-location is unambiguous and can be enforced on day one; speed and accuracy thresholds need production data first.

4. **Selfie liveness before launch, or after?**
   Options: (a) before, as an onboarding step; (b) after, triggered by risk; (c) never, accept the rental risk. Recommendation: **(b)**, with the caveat that account rental is the failure mode most likely to attract regulatory attention rather than merely cost money. Confirm the legal position with T25 first.

5. **Who runs the review queue on day one?**
   A queue with nobody reading it is worse than no queue, because it looks like a control. Options: (a) an ops person part-time; (b) the on-call engineer; (c) delay P1.3 until someone owns it. Recommendation: **(a)** with a daily service level — the queue should be small at launch volumes.

6. **Is `PRAGMA foreign_keys` intentionally unset?**
   It changes what the schema actually guarantees, and several controls here assume referential integrity. Recommendation: enable it in a controlled migration with T08, or document the decision explicitly so nobody plans around a guarantee that does not exist.

7. **What is the acceptable fraud loss rate?**
   Nobody gets to zero. Recommendation: budget **0.3% of GMV** for the first 90 days and measure against it. A stated number turns every argument about friction into an arithmetic question instead of an opinion.
