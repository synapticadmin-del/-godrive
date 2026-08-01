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

<!-- TRACK-ENTRIES:END -->

---

## 7. How to update this file

Sections 1 to 5 describe the system. When a merged change makes any of them
untrue, correct it in the same pull request that caused the drift — this file
is part of the definition of done, not documentation debt to be paid later.

Section 6 is append-only and is written by the review tracks. Its entries are
a historical record: when a track's findings are later resolved, note the
resolution rather than deleting the entry.
