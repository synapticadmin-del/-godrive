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

<!-- TRACK-ENTRIES:END -->

---

## 7. How to update this file

Sections 1 to 5 describe the system. When a merged change makes any of them
untrue, correct it in the same pull request that caused the drift — this file
is part of the definition of done, not documentation debt to be paid later.

Section 6 is append-only and is written by the review tracks. Its entries are
a historical record: when a track's findings are later resolved, note the
resolution rather than deleting the entry.
