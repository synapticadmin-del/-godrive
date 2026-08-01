# Synaptic Go — Project Record
## السجل المرجعي الأساسي للمشروع

> This is the one file to read before touching anything else in this repository.
> هذا هو الملف الأول الذي يُقرأ قبل أي شيء آخر في المستودع.
>
> It is maintained collaboratively: the sections below describe the system as it
> stands, and section 6 accumulates one entry per review track as each is
> completed. Keep it accurate. A project record that lies is worse than none.

---

## 1. What this is

**Synaptic Go** is a ride-hailing and transport platform built for the Egyptian
market. The product combines the feature depth of Uber with the
price-negotiation model of inDrive: a rider proposes a fare, nearby captains
accept or counter, and the rider chooses.

Beyond city rides, the codebase already carries two secondary businesses —
**intercity** seat booking and **B2B** corporate accounts with monthly
invoicing — and a delivery/courier vertical is in scope.

**Status:** pre-production. Version `0.4.0`. Not yet carrying real traffic.

---

## 2. Architecture

Everything server-side runs on Cloudflare's edge. There is no origin server and
no container.

| Layer | Technology | Binding |
|---|---|---|
| API | Cloudflare Workers (TypeScript) | routed on `api.synapticstudio.tech/*` |
| Database | D1 (SQLite) | `DB` → `synaptic-go` |
| Sessions / cache | Workers KV | `SESSIONS` |
| File storage | R2 | `FILES` → `synaptic-go-files` |
| Realtime | Durable Objects (SQLite-backed) | `TRIP_ROOM`, `GEO_CELL`, `CAPTAIN_INBOX`, `OFFER_SCHEDULER` |
| Async work | Queues + DLQ | `NOTIFICATIONS` → `synaptic-go-notifications` |
| Scheduled work | Cron triggers | `*/1 * * * *` scheduled-trip dispatch · `0 3 1 * *` B2B invoices |
| Rider app | Flutter | `apps/rider` |
| Captain app | Flutter | `apps/captain` |
| Admin console | React + Vite | `apps/admin` |

**The four Durable Objects and what they are for**

- `TripRoom` — the live room for one trip; both participants subscribe over a
  WebSocket and receive status changes and captain position.
- `GeoCell` — a geographic bucket holding the captains currently inside it;
  the primitive the dispatcher searches.
- `CaptainInbox` — one per captain; the socket that delivers incoming trip
  offers.
- `OfferScheduler` — alarms that drive the staged rollout of an offer to
  successive batches of nearby captains.

**External dependencies** — OSRM for routing, Nominatim for geocoding, Paymob
for payments, Meta WhatsApp Cloud API and Resend for OTP delivery, FCM for
push, Cloudflare Turnstile for bot defence. Several run in stub mode until
their keys are supplied; see `docs/ROADMAP.md`.

---

## 3. Repository map

```
apps/
  api/         Cloudflare Worker — the whole backend
    src/
      index.ts            entry point, routing, DO wiring
      routes/             admin auth captain companies devices geocode
                          intercity payments promo safety search trips
                          user wallet
      lib/                audit cleanup geocode jwt nearby notifications
                          paymob pricing routing schemas turnstile types utils
      middleware/         auth rateLimit
      durable-objects/    TripRoom GeoCell CaptainInbox OfferScheduler
    wrangler.toml         bindings, environments, crons
  rider/       Flutter — the passenger app
  captain/     Flutter — the driver app
  admin/       React + Vite — the operations console
packages/
  flutter_shared/   theme, shared widgets, models, api_client, fcm_service
  shared/           TypeScript utilities (the only place with tests today)
migrations/    0001 … 0019, applied to D1 in order
scripts/       Python repository checks + local run helpers
docs/          architecture, API, roadmap, improvement log, and the review
               plans produced by the tracks in section 6
```

---

## 4. Environments

| | |
|---|---|
| API (production) | `https://api.synapticstudio.tech` |
| API (fallback) | `https://synaptic-go-api.lolelarap.workers.dev` |
| Admin console | `https://synaptic-go-admin.pages.dev` |
| Wrangler environments | default (dev), `[env.staging]`, `[env.prod]` |
| Default city | `cairo` |

Secrets are held as Wrangler secrets, never in the repository. The
`DEV_OTP` flag must remain `"false"` outside local development.

---

## 5. Working conventions

- **Branches.** `plan/NN-slug` for review documents, `feat/…`, `fix/…`,
  `docs/…` for work. `main` is the deployable branch. `review-board` is a
  permanent coordination branch and is never merged.
- **Pull requests.** Everything reaches `main` through a PR. The single
  exception is an append to section 6 of this file.
- **Migrations** are forward-only and numbered sequentially. Never edit a
  migration that has been applied.
- **`.github/workflows/`** cannot be modified by the GitHub App used by
  automation; workflow changes are added by a human.
- **Money** is stored as integers. Never introduce a float into a currency
  path.
- **Arabic is the default language** of the product; English is the fallback.
  New user-facing strings go in the ARB files, never inline.

---

## 6. Review tracks — findings register

The platform is being reviewed across 28 independent tracks, each producing a
plan document under `docs/plan/`. Each track appends one block here when it
finishes, so the state of the whole review can be read on one page.

The task briefs live on the `review-board` branch under `board/tasks/`. The
protocol for claiming and completing a track is `board/PROTOCOL.md`.

**Contributors: insert your block immediately before the END sentinel. Change
nothing else in this file.**

<!-- TRACK-ENTRIES:START -->

### T01 — Auth, Identity & Sessions

- **PR:** https://github.com/synapticadmin-del/-godrive/pull/59 · **Doc:** `docs/plan/01-auth-identity-sessions.md` · **By:** `chat-20260801-1201-378c` · **Date:** 2026-08-01
- **Verdict:** The cryptographic primitives are sound, but the session *lifecycle* is not — a stolen token cannot be detected, cannot be revoked, and cannot even be ended by the user, and the only live login route has no bot defence at all.
- **Blockers (S1):** 3 — refresh rotation is non-atomic and has no reuse detection, so one stolen token becomes a silent permanent session (`apps/api/src/routes/auth.ts:279-295`); no client anywhere calls `POST /auth/logout`, so "log out" leaves a valid 30-day refresh token alive (`apps/rider/lib/services/app_state.dart:452-455`); Turnstile is wired only to the suspended OTP route, leaving `/auth/login` and `/auth/register` unprotected, and it fails open when the secret is absent (`apps/api/src/routes/auth.ts:71`, `apps/api/src/lib/turnstile.ts:17-27`).
- **Top action:** Wire both apps to the `/auth/logout` endpoint that already exists — it is a one-line client fix that closes an S1 — then land client single-flight refresh *before* making server-side rotation atomic, or the security fix becomes a mass-logout incident for captains.
- **Hands off to:** T27 (rider and captain session logic has diverged — captain drops rotated refresh tokens; extract a shared `SessionManager`), T02 (role is read from the JWT with no per-object check), T04 (Paymob webhook is unauthenticated by design — confirm HMAC verification), T08 (`refresh_tokens` needs `family_id` and `device_id`), T18 (reuse-detection events are the fraud signal you want), T22 and T25 (identity-document reads are unaudited), T24 (`/geocode/*` is public and proxies a paid upstream).

> **Scope note:** OTP was descoped by the operator for this pass — the flow is suspended, so brief questions 1–2 are an explicit exclusion, not a clean bill of health. Two consequences are recorded in the document: the suspended routes are still mounted and can still mint accounts, and with OTP off there is now **no password-reset or account-recovery path of any kind**.

### T02 — Authorization, RBAC & Object-Level Access

- **PR:** https://github.com/synapticadmin-del/-godrive/pull/60 · **Doc:** `docs/plan/02-authorization-rbac-idor.md` · **By:** `chat-20260801-1214-a0bd` · **Date:** 2026-08-01
- **Verdict:** Role gates (BFLA) are in good shape and `trips.ts` does object-level scoping properly and consistently — but that discipline is a convention, not a mechanism, and the three places it was not applied are each severe: the fleet roster is readable with no account, the client is trusted to state what it owes, and the trip-sharing safety feature does not work at all.
- **Blockers (S1):** 3 — `POST /trips/estimate` is registered above its router's auth middleware and returns every online captain's id, name and distance to anonymous callers (`apps/api/src/routes/trips.ts:315`, guard at `:346`, response at `:342`); the Paymob intention takes `amount` and `tripId` from the request body with no ownership check and no server-side fare derivation, so any trip — including another rider's — can be settled for 1 EGP (`apps/api/src/routes/payments.ts:13`, `:46`, `:74`, settlement `:200-205`); `GET /safety/track/:token` sits under the blanket auth guard and its emitted URL omits the `/safety` prefix, so the share link 401s then 404s while `POST /safety/share` still returns `ok: true` (`apps/api/src/routes/safety.ts:11`, `:83`, `:90`).
- **Top action:** Before any production traffic, move the estimate route under the auth guard and strip captain identities from its response, and derive payment amounts server-side from the trip row while binding `tripId` to the caller. Both are S-effort. Then add the auth-posture regression suite (P0.5) so an ordering mistake can never silently reappear in any route file.
- **Hands off to:** T01 (revocation on the request path — `SESSIONS` KV is bound but never consulted; OTP routes confirmed still mounted at `routes/auth.ts:52`/`:131`), T03 (payout has no maximum), T04 (webhook legacy branch credits a wallet with no amount check, `routes/payments.ts:248-265`), T06 (bidding and the open-trip list both bypass the `search_radius_km` contract), T07 (the DO `pendingAuth` handoff is unverified — `needs-check`), T08 (`users` has no admin tier column), T11, T17 (raw captain phone; SOS accepts any trip id), T18, T22 (audit writes fail silently, `lib/audit.ts:33-36`), T24, T25, T27.

> **Method note:** three routing claims were verified by executing real Hono 4.7.11 rather than reading the source. One overturned a finding already written up as an S1 — `use("/admin/*")` *does* match the bare `/admin` path, so `companies.ts` is **not** a cross-tenant breach. The document lists 12 such verified non-findings in §4.1 so they are not re-raised or "fixed".

### T04 — Payments, PSP Integration & Captain Payouts

- **PR:** https://github.com/synapticadmin-del/-godrive/pull/62 · **Doc:** `docs/plan/04-payments-psp-payouts.md` · **By:** `chat-20260801-1226-ad01` · **Date:** 2026-08-01
- **Verdict:** The cryptography is right and everything around it is missing — HMAC-SHA512 matches Paymob's documented field order exactly and PCI scope is cleanly avoided, but retry safety, reconciliation, refunds and payouts are absent or actively broken, and the platform cannot take a real payment today.
- **Blockers (S1):** 6 — the webhook credits the wallet with an unguarded `UPDATE` that ignores its own `INSERT OR IGNORE` result and settles the intention 40 lines later, so any retry or concurrent delivery double-credits (`apps/api/src/routes/payments.ts:175-186`, `:223`, while `trips.ts:1028`/`:1047` and `payments.ts:268` all do it correctly); `purpose='intercity_booking'` writes a `wallet_transactions.type` the CHECK constraint forbids, so the handler 500s, the intention never settles and Paymob retries forever against money it already captured (`apps/api/src/routes/payments.ts:213-220` vs `migrations/0003_global_transport.sql:30`); `POST /captain/wallet/payout` irreversibly debits a captain's balance into a `pending` row that no endpoint, cron or admin screen can ever action, to an unverified free-text destination stored in a `note` column (`apps/api/src/routes/wallet.ts:113-130`). The other three: client-supplied amount and `tripId` let a 300 EGP trip settle for 1 EGP (`payments.ts:200-206`), refund and chargeback callbacks are silently swallowed as duplicates (`payments.ts:166-168`), and there is no reconciliation of any kind so a lost webhook loses the payment permanently (0 hits for `inquiry`/`reconcil`).
- **Top action:** Freeze the payout debit first — it is the only finding actively creating liability every time a captain taps the button — then gate the webhook's balance `UPDATE` on `ins.meta.changes === 1` exactly as `trips.ts:1047` already does, and add the Paymob transaction-inquiry sweep. Nothing else in this track matters until money can only be credited once and can always be found.
- **Hands off to:** T03 (payout omits `wallet_balance_piastres` so the integer ledger drifts on every withdrawal, `wallet.ts:113-117`; captain balances can go negative unguarded, `trips.ts:1029-1033`; two contradictory definitions of a captain's balance, `wallet.ts:58-72` vs `:104-108`; `INSERT OR IGNORE` is unsound wherever `idempotency_key` is NULL), T08 (`PRAGMA foreign_keys` is never set so every `REFERENCES` is decorative; `payment_intentions.status` has no CHECK, which is precisely what let the intercity bug ship), T02 (the intention endpoint takes an unowned `tripId` — same finding from the other side), T20 (intercity `cash`/`card` bookings claim seats with no payment taken at all, `intercity.ts:82-201`; the B2B invoice cron is not idempotent, `index.ts:353-357`), T27 (rider and captain wallet screens are copy-pasted `_BalanceCard`/`_Bloom`/`_money()` with divergent loading, refresh and formatting behaviour — the captain file documents the duplication in a comment at `wallet_screen.dart:594-596`), T19 (`pushToUser` is awaited inside the money path and can throw a settled payment into a retry), T21 and T05 (`createTrip` hardcodes `'city': 'cairo'` next to the hardcoded payment method, so every trip is priced with Cairo's rules), T22 (the rate limiter fails open on KV error with no metric), T25 (unauthenticated callers can write arbitrary order objects into the audit table, `payments.ts:111`).

> **Correction to the brief:** question 9 assumed captain payouts were entirely missing because there is no `routes/payouts.ts`. There is no such file, but there *is* a live payout endpoint wired to a real button in the captain app, and it takes money out of the balance. A missing feature moves nothing; this one strands a captain's entire accumulated earnings on a single tap. It is recorded as an S1, not a gap.

### T05 — Pricing, Surge & Bidding Economics

- **PR:** https://github.com/synapticadmin-del/-godrive/pull/61 · **Doc:** `docs/plan/05-pricing-surge-bidding-economics.md` · **By:** `chat-20260801-1228-83a3` · **Date:** 2026-08-01
- **Verdict:** The product's differentiator does not work: the rider's negotiated price is discarded at settlement on the direct-accept path, so a captain is routinely paid a different number from the one they agreed to — and around that sit an unbounded bid surface, a promo system whose budget has no floor and whose discount is funded by the captain, and a routing fallback that quietly overcharges by 28%.
- **Blockers (S1):** 12 — `POST /trips/:id/accept` writes no price column, so settlement falls back to `estimated_fare` while the captain's accept button showed `offered_price` (`apps/api/src/routes/trips.ts:861-866`, `:969`, `apps/api/src/routes/captain.ts:462-467`, `apps/captain/lib/screens/home/offer_card.dart:239-243`); the promo budget can be overspent by a TOCTOU race and drained to zero for free by create+cancel loops, since `uses_count` is incremented at creation and never released (`apps/api/src/routes/trips.ts:418`, `:500`, `:709-827`); commission is computed post-discount so the captain funds ~80% of every promo, losing 16 EGP of a 20 EGP discount against the platform's 4 (`apps/api/src/routes/trips.ts:428-429`, `:969-971`). Also S1: unbounded rider offers and captain counters (`apps/api/src/lib/schemas.ts:59`, `:77`), bid spam with no dedup/TTL/rate limit, silent OSRM→haversine repricing at +28% with no log or metric (`apps/api/src/lib/routing.ts:61-62`), vehicle tiers never priced server-side so XL costs the same as economy (`apps/api/src/lib/routing.ts:164-173`), no cancellation or no-show fee despite live admin config for one, and a wallet trip that completes even when the rider's debit fails (`apps/api/src/routes/trips.ts:997-1010`).
- **Top action:** Make `POST /trips/:id/accept` set `accepted_price = offered_price` and recompute commission, mirroring what `accept-bid` already does at `apps/api/src/routes/trips.ts:1299-1310`. It is a handful of lines, it closes the worst finding in the review, and every day it is unshipped is a day captains are paid a number they never agreed to. Then land signed fare quotes (§6 P0.1) so no client-supplied field reaches the fare again.
- **Hands off to:** T27 (three copies of the vehicle-multiplier table with two different value sets, four currency-formatting strategies, an Arabic-only widget inside `flutter_shared`, and a 15s countdown the captain sees but the rider does not), T03 (wallet completion on a failed debit; the bidding columns are still `REAL` while migration 0005 converted the others), T04 (no PSP rate exists in the repo — the margin model rests on an assumed 2.5%), T06 (`/bid` bypasses every radius, dispatch-membership and approval check), T02 and T25 (`/trips/estimate` is unauthenticated and returns live captain coordinates), T08 (`trip_bids` has no expiry, round counter or uniqueness; `pricing_rules` has no surge column, which is why surge is dead code), T11 (the admin console re-implements the fare formula by hand and exposes no surge or cancellation-fee control), T17, T20 (intercity appears to bypass commission entirely), T22, T23.

> **Correction to the brief:** two of its premises are wrong and are recorded in §1 so nobody repeats the search. `pricing_rules` and `vehicle_types` live in migrations 0001 and 0002, not 0003; and `pricing_rules.surge_multiplier` **does not exist** — the only surge column is on `trips`, which is precisely why the surge read at `apps/api/src/routes/trips.ts:390-392` is dead code and the multiplier is permanently 1.0. Recorded as verified non-findings: the assignment race is correctly serialised on both paths, wallet moves are idempotency-keyed, `commissionRate` is properly bounded to 0..1, and intercity per-seat pricing cannot be client-supplied.

### T03 — Money Integrity — Wallet, Ledger & Commission

- **PR:** https://github.com/synapticadmin-del/-godrive/pull/63 · **Doc:** `docs/plan/03-money-integrity-wallet-ledger.md` · **By:** `chat-20260801-1219-a7e2` · **Date:** 2026-08-01
- **Verdict:** Money is not conserved — `wallet_transactions` is a flat event log with no counterparty, no entry group and no platform account, so a trial balance is not computable at any date, by construction rather than by bug; five separate paths create or destroy real EGP on top of that structural gap.
- **Blockers (S1):** 9 — the captain is credited in full when the rider's wallet debit fails, because `txnStatus` is computed and then never read (`apps/api/src/routes/trips.ts:1003` + `:1012`); the Paymob top-up discards its `INSERT OR IGNORE` result and credits the balance on every webhook redelivery, past a read-then-write settle guard (`apps/api/src/routes/payments.ts:175-186`, `:223-227`); card-paid intercity seats are never charged, and the intercity webhook branch inserts a `type` its own CHECK constraint forbids, so the card is captured and the handler throws on every retry (`apps/api/src/routes/intercity.ts:105`, `apps/api/src/routes/payments.ts:215-220`); there is no refund path for city trips at all (`apps/api/src/routes/trips.ts:728`); and the captain's displayed balance is not the one that gates their payout, so every cash-taking captain is hard-blocked from withdrawing (`apps/api/src/routes/wallet.ts:58-72` vs `:104-111`).
- **Top action:** Gate the captain credit on the rider debit having settled (P0.1) and make the webhook replay-safe (P0.2) — both are self-contained fixes against the current schema, and together they close the two live mints — then stand up the 18-invariant reconciliation cron from P0.7, because it is what makes the interim safe while the double-entry rebuild lands.
- **Hands off to:** T04 (webhook HMAC read from the query string with no freshness check; `is_refunded`/`is_voided` arrive signed and are ignored; the legacy branch performs no amount verification at all), T27 (`_BalanceCard`, `_Bloom`, `_iconFor` and `_formatStamp` are copied verbatim across both wallet screens and have already drifted; `topup_screen.dart` is the only money surface with hardcoded Arabic and bare `TextStyle`), T08 (`ON DELETE CASCADE` on financial rows, `audit_log.actor_id` FK makes `'paymob'` unloggable, no CHECK on `commission_rate`), T09, T10 (P0.1 introduces a `402 SETTLEMENT_FAILED` the captain app must handle), T11 (no refund, payout-approval or reconciliation surface exists in 937 lines of `admin.ts`), T22, T23, T05.

> **Scope note:** the arithmetic that matters most is correct, and that belongs on the record — discount is applied before commission (`trips.ts:428-429`), which is the ordering that stops the platform paying out more than it collects, and cash commission is debited from the captain rather than credited, avoiding the double-pay trap. Paymob's HMAC field list, fail-closed behaviour and constant-time comparison are all right. The failures are overwhelmingly places where a correct pattern already present in this codebase was not applied uniformly.

<!-- TRACK-ENTRIES:END -->

---

## 7. How to update this file

Sections 1 to 5 describe the system. When a merged change makes any of them
untrue, correct it in the same pull request that caused the drift — this file
is part of the definition of done, not documentation debt to be paid later.

Section 6 is append-only and is written by the review tracks. Its entries are
a historical record: when a track's findings are later resolved, note the
resolution rather than deleting the entry.
