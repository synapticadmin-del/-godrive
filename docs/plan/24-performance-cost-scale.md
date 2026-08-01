# 24 — Performance, Cost & Scale

> Track: D — Engineering excellence & production readiness · Reviewer: `chat-20260801-1416-2cd9` · Date: 2026-08-01 (UTC)
> Base commit reviewed: `0f432702a3755f7bd738b8b7ee15230cf05c4686` (`main`)

---

## 1. Scope

This document models what Synaptic Go costs to run on Cloudflare, and where it
stops working as volume grows. It covers:

- a unit cost model per 1,000 completed trips, extrapolated to 1k / 10k / 50k trips per day;
- the query-level behaviour of the heaviest endpoints (round-trips, index coverage, payload);
- D1's hard limits and the date the platform hits them;
- location write amplification — the classic ride-hailing cost sink;
- Durable Object invocation and duration billing, including hibernation;
- admin console polling cost;
- Flutter client startup, size and jank as they affect user-perceived performance;
- the scale-out path off D1 and the metric that should trigger it.

**Explicitly out of scope**, owned elsewhere:

| Not covered here | Owner |
|---|---|
| Realtime correctness — WS protocol, reconnect semantics, message ordering | **T07** |
| Dispatch/matching quality and fairness of the offer waves | **T08** |
| Security of the rate limiter, auth, and the `DEV_OTP` exposure | **T02** / **T05** |
| Design-system and screen-level UI work | **T12** / **T28** |
| Rider ↔ captain ↔ admin duplication and vocabulary drift | **T27** |
| Observability tooling choice and dashboards | **T22** |

I cost these axes where they touch money; I do not redesign them.

A note on method: every number below is derived from a model committed at
`docs/plan/assets/24-cost-model.py` in this PR. It is runnable. If you disagree
with an assumption, change the constant at the top and re-run it rather than
arguing with the total.

---

## 2. What I actually read

All files read at commit `0f432702`. Line numbers cited throughout are from this
snapshot.

**Infrastructure config**

| File | Note |
|---|---|
| `apps/api/wrangler.toml` | Read in full. All bindings, both cron triggers, queue consumer settings, three environments. |
| `apps/api/package.json` | Skimmed — dependency surface only. |

**API — routes**

| File | Note |
|---|---|
| `apps/api/src/index.ts` | Read in full. Route mounting, global rate limit, cron handlers, queue consumer. |
| `apps/api/src/routes/captain.ts` | Read in full. The `/location` handler (`:190-271`) is the single most important handler in this document. |
| `apps/api/src/routes/admin.ts` | Read in full. Stats, analytics, trips, captains, documents, search. |
| `apps/api/src/routes/trips.ts` | Read in full. Trip creation, dispatch fanout, lifecycle transitions, bidding. |
| `apps/api/src/routes/payments.ts`, `wallet.ts`, `safety.ts`, `search.ts`, `geocode.ts` | Read for query patterns and write counts. |

**API — libraries and middleware**

| File | Note |
|---|---|
| `apps/api/src/lib/nearby.ts` | Read in full. The 9-cell neighbourhood fanout. |
| `apps/api/src/lib/routing.ts` | Read. OSRM call shape — the `overview=full` geometry that lands in D1. |
| `apps/api/src/lib/cleanup.ts`, `notifications.ts`, `pricing.ts`, `audit.ts`, `utils.ts` | Read for write amplification and queue behaviour. |
| `apps/api/src/middleware/rateLimit.ts` | Read in full. KV read + KV write per limited request. |
| `apps/api/src/middleware/auth.ts` | Read — confirmed pure JWT verify, no DB touch per request. |

**Durable Objects** — all four read in full:
`TripRoom.ts`, `GeoCell.ts`, `CaptainInbox.ts`, `OfferScheduler.ts`.

**Migrations** — read in full: `0001_init.sql`, `0003_global_transport.sql`,
`0011_payment_intentions.sql`, `0016_system_config.sql`, `0018_captain_search_radius.sql`,
`0019_trips_captain_status_index.sql`. **Six of nineteen.** Index claims about
tables created in the thirteen migrations I did not pull (`audit_log`,
`trip_path_points`, `trip_bids`, `driver_documents`, `device_tokens` partially)
are marked `needs-check` rather than asserted.

**Admin console**

| File | Note |
|---|---|
| `apps/admin/src/lib/usePolling.ts` | Read in full. Correctly visibility-aware. |
| `apps/admin/src/pages/DashboardPage.tsx`, `LiveMapPage.tsx`, `CaptainsPage.tsx` | Read for poll intervals and per-tick endpoint counts. |
| `apps/admin/src/pages/AnalyticsPage.tsx`, `TripsPage.tsx`, `AuditLogPage.tsx` | Read for client-side filtering and payload consumption. |
| `apps/admin/src/lib/api.ts`, `App.tsx`, `package.json` | Skimmed — bundle and fetch shape. |

**Flutter clients**

| File | Note |
|---|---|
| `apps/captain/lib/services/captain_state.dart` | Read the location, polling and lifecycle sections closely (47 KB file; I did not read every UI helper). |
| `apps/rider/lib/services/app_state.dart`, `location_service.dart` | Read for startup path and network chattiness. |
| `apps/rider/lib/services/trip_ws.dart`, `apps/captain/lib/services/trip_ws.dart`, `offers_ws.dart` | Read in full — ping intervals and backoff. |
| `apps/rider/lib/main.dart`, `apps/captain/lib/main.dart` | Read in full. |
| `apps/rider/pubspec.yaml`, `apps/captain/pubspec.yaml` | Read in full. |

**Existing docs**: `docs/COST.md` read in full (it is 27 lines) and is refuted
below in §4 F-24-20.

**Not read, and it matters**: the splash screen implementations, the map screen
widgets themselves, and the thirteen migrations listed above. Anything depending
on those is labelled `needs-check`.

**External sources**: Cloudflare's published pricing and limits pages for
Workers, D1, Durable Objects, KV, R2 and Queues, retrieved 2026-08-01. Rates are
tabulated in §3.6 with source URLs.

---

## 3. How it works today

### 3.1 The deployed shape

One Worker (`synaptic-go-api`) serves `api.synapticstudio.tech/*`
(`wrangler.toml:67-69`). It binds one D1 database (`wrangler.toml:7-11`), one KV
namespace `SESSIONS` (`:13-16`), one R2 bucket `FILES` (`:18-21`), four Durable
Object classes (`:23-29`), and a `NOTIFICATIONS` queue with a DLQ, batching at
100 messages / 5 s with 3 retries (`:46-55`). Two cron triggers fire: one
**every minute** for scheduled-trip dispatch, one monthly for B2B invoicing
(`:61-65`).

All three environments — top-level, `[env.prod]` and `[env.staging]` — point at
the **same D1 `database_id`** for the first two (`wrangler.toml:10` and `:109`)
and share the worker name. That is a deployment-safety problem owned by T26, but
it is also a cost problem: staging traffic bills against production.

### 3.2 The location path — the hot loop

This is where the money goes. One captain location update:

| Step | Where | Cost incurred |
|---|---|---|
| 1. GPS fix emitted | `captain_state.dart:620-626` — `distanceFilter: 50` idle, `10` on trip | — |
| 2. `POST /captain/location` | `captain.ts:190` | 1 Worker request |
| 3. Rate-limit check | `rateLimit.ts:29` KV `get`, `rateLimit.ts:50` KV `put` | **1 KV read + 1 KV write** |
| 4. `UPDATE captains SET last_lat…` | `captain.ts:205-209` | **1 D1 row written — unconditional** |
| 5. GeoCell heartbeat | `captain.ts:211-221` → `GeoCell.ts:30` `storage.put` | **1 DO request + 1 DO storage write** |
| 6. `SELECT * FROM trips` | `captain.ts:224-228` — only if `tripId` present | 1 D1 read |
| 7. `UPDATE trips SET captain_lat…` | `captain.ts:231-235` | **1 D1 row written** |
| 8. `SELECT recorded_at FROM trip_path_points … LIMIT 1` | `captain.ts:238-243` | 1 D1 read |
| 9. `INSERT trip_path_points` | `captain.ts:246-251`, gated 30 s at `captain.ts:245` | 1 D1 row written, ~1 in 15 |
| 10. TripRoom broadcast | `captain.ts:254-265` | **1 DO request** |

The endpoint is rate-limited to **30 requests / 60 s per captain**
(`captain.ts:192-197`). That ceiling — not the client — sets the worst case.

Two things deserve emphasis. First, steps 3, 4 and 5 run on **every** ping with
no trip gate: an online-but-idle captain who will not take a trip for an hour
still writes a D1 row, a KV entry and a DO storage record on every 50 m of
movement. Second, the read at step 8 exists to *avoid* a write at step 9 — that
trade is economically correct given D1 reads cost $0.001/M against writes at
$1.00/M, and it should be kept.

### 3.3 The Durable Objects

| DO | WebSocket API | Alarm | Billing consequence |
|---|---|---|---|
| `TripRoom` | **Hibernation** — `ctx.acceptWebSocket` (`TripRoom.ts:105`), `webSocketMessage` (`:140`), `webSocketClose` (`:184`) | none | Idle sockets do **not** bill duration |
| `CaptainInbox` | **Hibernation** on the captain socket — `ctx.acceptWebSocket` (`CaptainInbox.ts:45`), `:76`, `:117` | none | Correct — *except* the relay, below |
| `CaptainInbox` (relay) | **Legacy** — `upstream.accept()` (`CaptainInbox.ts:175`) + `addEventListener("message")` (`:178`) | none | Pins the instance in memory; bills wall-clock |
| `GeoCell` | no WebSocket | **self-rescheduling 60 s** — set at `GeoCell.ts:34`, re-armed at `:79` inside `alarm()` (`:68`) | Wakes every cell every minute while any captain is present |
| `OfferScheduler` | no WebSocket | single-shot 15 s waves — `setAlarm` at `OfferScheduler.ts:126`, `WAVE_SIZE = 3` (`:62`), `WAVE_DELAY_MS = 15_000` (`:63`) | Terminates after the last wave; bounded |

**Hibernation is implemented, and that is the single best cost decision in the
codebase.** It converts what would be a $79–$670/month idle-WebSocket bill at
500 concurrent connections into approximately zero (§4 F-24-06 has the
arithmetic). The gap is the relay path and a correctness bug it created.

Dispatch fans out to **nine** GeoCell DOs — the pickup cell plus its eight
neighbours (`nearby.ts:40-53`), queried in parallel (`nearby.ts:71-88`). One
`POST /trips` therefore costs roughly 9 GeoCell + 1 OfferScheduler + up to 10
CaptainInbox + 2 TripRoom ≈ 22 DO subrequests. Against the paid-plan subrequest
ceiling that is safe; against the bill it is a 9× multiplier on every dispatch.

### 3.4 The admin console

Three pages poll, via a hook that correctly suspends on `document.hidden`
(`usePolling.ts:34-42`) and resumes with an immediate refetch (`:38-41`):

| Page | Interval | Endpoints per tick | `path:line` |
|---|---|---|---|
| Dashboard | **8 s** | `/admin/stats` + `/admin/live-trips` | `DashboardPage.tsx:49` |
| Live map | **8 s** | `/admin/live-trips` + `/admin/online-captains` | `LiveMapPage.tsx:156` |
| Captains | **10 s** | `/admin/captains` | `CaptainsPage.tsx:235` |

`GET /admin/stats` issues **five sequential** D1 statements (`admin.ts:14`, `:18`,
`:26`, `:35`, `:39`). Of those, `admin.ts:30` wraps the indexed column —
`WHERE datetime(created_at) >= datetime(?)` — which makes `idx_trips_created`
(`migrations/0001_init.sql:92`) unusable and forces a full scan.
`GET /admin/live-trips` filters `status NOT IN ('completed','cancelled')`
(`admin.ts:58`) — a negation, also a full scan.

So a single Dashboard tick scans the `trips` table roughly three times, and a
Live-map tick once more. **`env.DB.batch()` is used exactly once in the entire
API** (`admin.ts:506`); every other multi-statement handler pays one network
round-trip per statement against a database that is single-threaded and allows
six concurrent connections per Worker invocation.

`GET /admin/captains` performs an `UPDATE captains SET is_online = 0 …`
(`admin.ts:237`) — **a write on a GET**, polled every ten seconds, against
columns with no index.

### 3.5 The clients

Captain location is **distance-driven, not timer-driven**: `distanceFilter: 50`
when idle (`captain_state.dart:621`), `10` on a trip (`:625`). The stream is
stopped when the app is backgrounded. Offers are polled at 8 s when the
WebSocket is down and 60 s when it is up (`captain_state.dart:758`, `:763`), and
an approval poll runs every 30 s (`:107`). Both apps ping their sockets every
25 s (`offers_ws.dart:73`, `rider/.../trip_ws.dart:76`) with proper exponential
backoff capped at 16 s plus jitter (`offers_ws.dart:90-92`) — that is correctly
built and worth saying so.

Both apps `await Firebase.initializeApp()` before `runApp`
(`rider/lib/main.dart:20`, `captain/lib/main.dart:20`), and both wrap
`MaterialApp` in a root-level `Consumer` (`captain/lib/main.dart:47`), so every
`notifyListeners()` — including one per offers poll — diffs the whole tree.

### 3.6 Cloudflare rates used

Workers Paid plan, retrieved 2026-08-01.

| Service | Metric | Included / month | Overage |
|---|---|---|---|
| Workers | requests | 10 M | $0.30 / M |
| Workers | CPU time | 30 M CPU-ms | $0.02 / M CPU-ms |
| D1 | rows read | 25 B | $0.001 / M |
| D1 | rows written | 50 M | **$1.00 / M** |
| D1 | storage | 5 GB | $0.75 / GB-mo |
| Durable Objects | requests | 1 M | $0.15 / M |
| Durable Objects | duration | 400,000 GB-s | $12.50 / M GB-s |
| Durable Objects | storage writes | 50 M | $1.00 / M |
| KV | reads | 10 M | $0.50 / M |
| KV | writes | 1 M | **$5.00 / M** |
| Queues | operations | 1 M | $0.40 / M (**3 ops per message**) |
| R2 | storage / egress | 10 GB | $0.015 / GB-mo / egress free |

Sources: `developers.cloudflare.com` pricing pages for
[Workers](https://developers.cloudflare.com/workers/platform/pricing/),
[D1](https://developers.cloudflare.com/d1/platform/pricing/),
[Durable Objects](https://developers.cloudflare.com/durable-objects/platform/pricing/),
[KV](https://developers.cloudflare.com/kv/platform/pricing/),
[Queues](https://developers.cloudflare.com/queues/platform/pricing/),
[R2](https://developers.cloudflare.com/r2/pricing/).

Two asymmetries drive everything that follows: **KV writes cost 10× KV reads**,
and **D1 writes cost 1,000× D1 reads per row**. A design that writes casually is
punished; a design that reads casually is punished only at scan volume — which
the admin console then supplies.

### 3.7 The cost model

Assumptions, all changeable at the top of `docs/plan/assets/24-cost-model.py`:

| # | Assumption | Value | Basis |
|---|---|---|---|
| A1 | Trip duration | 20 min | assumed |
| A2 | Average speed on trip | 20 km/h | Cairo city traffic, assumed |
| A3 | On-trip fixes | `min(30/min × 20, 6,667 m ÷ 10 m)` = **600** | `captain.ts:194`, `captain_state.dart:625` |
| A4 | Idle minutes per trip minute | 1.0 (50 % utilisation) | assumed |
| A5 | Idle fixes | `6,667 m ÷ 50 m` = **133** | `captain_state.dart:621` |
| A6 | Path points | `20 min ÷ 30 s` = **40** | `captain.ts:245` |
| A7 | Captains offered per trip | 10 | `trips.ts:568`, `:575` |
| A8 | Admin operators | 2, eight hours/day, dashboard + live map open | assumed |
| A9 | Commission per trip | 15 % of EGP 80 ≈ **$0.24** | assumed; EGP 50 / USD |

**Per completed trip:**

| Unit | Count | Formula |
|---|---|---|
| D1 rows written | **1,409** | `600×2 (captains+trips) + 133×1 + 40 path + 36 lifecycle` |
| D1 rows read | 1,220 | `600×2 + 20 lifecycle` |
| DO requests | 1,374 | `600×2 + 133 + 9 nearby + 1 sched + 10 inbox + 21 room` |
| DO storage writes | 740 | `733 GeoCell puts + 7 room state` |
| KV writes | **763** | one `put` per rate-limited request (`rateLimit.ts:50`) |
| KV reads | 763 | one `get` per rate-limited request (`rateLimit.ts:29`) |
| Worker requests | 833 | pings + lifecycle + client polls |
| Queue operations | 54 | 18 messages × 3 ops |

**Monthly cost, as the code stands:**

| Line item | 1,000 trips/day | 10,000 trips/day | 50,000 trips/day |
|---|---:|---:|---:|
| Workers base | $5.00 | $5.00 | $5.00 |
| Worker requests | $4.76 | $72.26 | $372.26 |
| Worker CPU | $3.40 | $39.40 | $199.40 |
| **D1 rows read** | **$448.08** | **$4,705.77** | **$12,936.83** |
| D1 rows written | $0.00 | $372.80 | $2,064.00 |
| D1 storage | $0.00 | $3.75 | $3.75 (capped — see F-24-02) |
| DO requests | $6.03 | $61.70 | $309.07 |
| DO duration | $0.00 | $0.00 | $0.00 |
| DO storage writes | $0.00 | $172.10 | $1,060.50 |
| KV reads | $6.45 | $109.50 | $567.50 |
| **KV writes** | **$109.50** | **$1,140.00** | **$5,720.00** |
| Queues | $0.25 | $6.08 | $32.00 |
| **TOTAL / month** | **$583** | **$6,688** | **$23,270** |
| Infra per trip | $0.0194 | $0.0223 | $0.0155 |
| **As % of commission** | **8.1 %** | **9.3 %** | **6.5 %** |

The headline is not the total — 6–9 % of commission is survivable. The headline
is **what** the total is made of. The largest single line at every tier is D1
rows read, and almost none of it is riders or captains: it is two admin
operators with a dashboard open.

---

## 4. Findings

| ID | Sev | Finding | Evidence (`path:line`) | Impact | Confidence |
|---|---|---|---|---|---|
| F-24-01 | **S1** | Admin polling scans the whole `trips` table ~4× every 8 s; ~300–470 B D1 rows read/month for two operators | `DashboardPage.tsx:49`, `LiveMapPage.tsx:156`, `admin.ts:30`, `admin.ts:58` | Largest single line item at every tier: $448 → $12,937/mo | confirmed |
| F-24-02 | **S1** | D1 10 GB ceiling is reached in ~144 days at 10k trips/day, ~29 days at 50k. No retention or archival exists | `trips.ts:447`+`:472`, `routing.ts:30`, `captain.ts:246-251` | Platform stops accepting writes. Hard stop, not a slowdown | confirmed |
| F-24-03 | **S1** | The KV rate limiter writes on every limited request; KV writes are $5/M | `rateLimit.ts:29`, `rateLimit.ts:50-51` | $110 → $5,720/mo. The limiter costs more than what it protects | confirmed |
| F-24-04 | **S1** | Location ping writes 2 D1 rows unconditionally, with no trip gate, at up to 30/min/captain | `captain.ts:205-209`, `captain.ts:231-235`, `captain.ts:192-197` | 1,409 D1 writes per completed trip; 97 % of all writes | confirmed |
| F-24-05 | **S2** | `TripRoom` registers sockets for hibernation but tracks them in an in-memory `Map`; after eviction the handler drops messages | `TripRoom.ts:105` vs `:110`, `:123`, `:151` | Silent realtime failure on long trips. Cost fix caused a correctness bug | confirmed |
| F-24-06 | **S2** | `CaptainInbox` relay uses legacy `upstream.accept()`, defeating hibernation for that instance | `CaptainInbox.ts:175`, `:178` | Wall-clock duration billing on the pending-auth path | confirmed |
| F-24-07 | **S2** | `datetime()` wrappers on indexed columns make 5 hot queries non-sargable | `admin.ts:30`, `:91`, `:117`, `:165`, `:237` | `idx_trips_created` (`0001_init.sql:92`) is dead on every analytics query | confirmed |
| F-24-08 | **S2** | Missing indexes on `captains(is_online, approval_status)`, `trips(completed_at)`, `trips(company_id)`, `users(role)` | `admin.ts:36`, `:40`, `:99-107`; `index.ts:344`; `safety.ts:29` | Full scans on the most-polled endpoints | confirmed |
| F-24-09 | **S2** | `SELECT *` ships the full OSRM polyline to list views that never render it | `admin.ts:314`+`:320` (200 rows), `captain.ts:463` (20 rows, mobile) | Widest payload in the system, 100 % wasted. Costs the user's data bundle | confirmed |
| F-24-10 | **S2** | `DB.batch()` is used once in the whole API; every other handler pays one round-trip per statement | `admin.ts:506` is the only call site | 5 sequential RTTs on the most-polled endpoint, against a 6-connection cap | confirmed |
| F-24-11 | **S2** | `GET /admin/captains` performs an `UPDATE` — a write on a read path, polled every 10 s | `admin.ts:237`, `CaptainsPage.tsx:235` | 360 unindexed full-table write-scans/hour/tab | confirmed |
| F-24-12 | **S2** | Per-minute cron re-runs a full `users` scan *inside* its loop; SOS fanout awaits serially | `index.ts:316` inside loop at `:295`; `safety.ts:29-30` | Cron cost scales with due-trip count; SOS latency scales with admin count | confirmed |
| F-24-13 | **S3** | Dispatch fans out to 9 GeoCell DOs per booking | `nearby.ts:40-53`, `:71-88` | 9× DO request multiplier on every trip and every cancel | confirmed |
| F-24-14 | **S3** | `GeoCell` self-reschedules a 60 s alarm while any captain is present | `GeoCell.ts:34`, `:68`, `:79` | One DO wake per active cell per minute, indefinitely | confirmed |
| F-24-15 | **S3** | `SELECT * FROM trip_events` has no `LIMIT`; captain offers filter by radius *after* `LIMIT` | `trips.ts:663`; `captain.ts:428`, `:490` | Unbounded growth on trip detail; empty offer lists in busy cities | confirmed |
| F-24-16 | **S3** | Root-level `Consumer<CaptainState>` rebuilds the whole tree on every poll tick | `captain/lib/main.dart:47`, `captain_state.dart:971` | Map jank every 8 s on low-end devices | likely |
| F-24-17 | **S3** | `await Firebase.initializeApp()` blocks before `runApp` in both apps | `rider/lib/main.dart:20`, `captain/lib/main.dart:20` | ~100–250 ms added to every cold start | likely |
| F-24-18 | **S3** | D1 is single-threaded per database; no replica region serves Africa/MENA | Cloudflare D1 limits; `wrangler.toml:7-11` | Cairo → WEUR RTT paid per statement, multiplied by F-24-10 | confirmed |
| F-24-19 | **S4** | `webview_flutter` (~3–6 MB) is carried by the rider app for the Paymob iframe alone | `rider/pubspec.yaml:36` | APK size; `url_launcher` is already a dependency | likely |
| F-24-20 | **S2** | `docs/COST.md` is wrong on both mechanism and magnitude | `COST.md:9` vs model; `COST.md:23` vs `captain.ts:205` | Budget planning is built on a 3–6× underestimate | confirmed |

---

### F-24-01 — Two admin tabs cost more than every rider and captain combined

This is the finding I did not expect, and it is the most important one here.

The Dashboard polls every 8 s (`DashboardPage.tsx:49`) and fires two endpoints
per tick. `GET /admin/stats` runs five sequential statements (`admin.ts:14`,
`:18`, `:26`, `:35`, `:39`). Two of them scan the entire `trips` table: the
`GROUP BY status` at `admin.ts:19`, and the today-window query at `admin.ts:30`
whose `WHERE datetime(created_at) >= datetime(?)` wrapper renders
`idx_trips_created` (`migrations/0001_init.sql:92`) unusable. `GET /admin/live-trips`
adds a third, because `status NOT IN ('completed','cancelled')` (`admin.ts:58`)
is a negation no index can serve. The Live-map page polls the same
`/admin/live-trips` on its own 8 s timer (`LiveMapPage.tsx:156`).

The arithmetic, for one operator with Dashboard and Live map open:

```
3,600 s ÷ 8 s                    =    450 ticks / hour / page
450 × 2 pages                    =    900 ticks / hour
~4 full trips scans per tick     =  3,600 table scans / hour
× 365,000 rows (1 yr @ 1k/day)   =  1.31 billion rows read / hour
× 8 h/day × 30 d × 2 operators   =    629 billion rows / month
```

At $0.001 per million that is roughly $448/month at the *smallest* tier, rising
to $12,937 at 50k trips/day where the table is capped at 10 M rows. Riders and
captains together contribute under $20 of D1 reads at the same tier.

The fix is not to stop polling. It is that **nobody reads platform-wide counters
at 8-second resolution.** A 30 s KV cache on `/admin/stats`, sargable date
predicates, and the two missing `captains` indexes remove ~99 % of this line
item for about a day of work.

To be fair to the code: `usePolling` is genuinely well built — it suspends on
`document.hidden` and refetches on return (`usePolling.ts:34-42`). The cost is
not carelessness in the hook; it is the absence of a cache behind it.

### F-24-02 — D1 fills up, and then the platform stops

Every trip row stores `route_geometry` — the **full, unsimplified** OSRM polyline.
`routing.ts:30` requests `?overview=full&geometries=geojson`, and `trips.ts:472`
writes `JSON.stringify(est.geometry)` into the row created at `trips.ts:447`. A
typical Cairo trip produces a few hundred to a few thousand coordinate pairs:
call it 2–5 KB per trip, and it is only ever read by one endpoint
(`trips.ts:670`, the single-trip detail view). On top of that,
`trip_path_points` accumulates one row per 30 s of driving (`captain.ts:245-251`)
— 40 rows per trip, roughly 5 KB more.

D1's hard ceiling is **10 GB per database**, and there is no retention job
anywhere in the codebase (`cleanup.ts` handles stale records, not archival).

| `route_geometry` | Per-trip footprint | 1k trips/day | 10k trips/day | 50k trips/day |
|---|---|---|---|---|
| 2 KB | ~7.3 KB | 3.9 years | **144 days** | **29 days** |
| 5 KB | ~10.3 KB | 2.8 years | **102 days** | **20 days** |

At 50,000 trips/day the platform exhausts its database inside a month of
launching. This does not degrade gracefully — writes fail, and trips stop being
created.

There is a second-order effect: because every full-table scan in F-24-01 reads
rows that are 7–10 KB wide instead of ~500 bytes, the scans are also far slower
than they need to be, pushing the heaviest queries toward D1's 30-second
statement limit as the table grows.

The fix is three-part and none of it is hard: move `route_geometry` to R2
(zero egress, $0.015/GB-mo) keyed by trip id; simplify the polyline before
storing it (Douglas–Peucker at ~10 m tolerance typically cuts 80–90 %); and add
a retention job that moves trips older than 90 days, with their path points, to
R2 as newline-delimited JSON.

### F-24-03 — The rate limiter is the second-largest line item

`rateLimit.ts:29` reads the counter from KV and `rateLimit.ts:50-51` writes it
back with a TTL, on every request the middleware guards. KV writes are **$5.00
per million** — the most expensive per-operation unit in the entire stack, ten
times a KV read and five times a D1 row write.

Because `POST /captain/location` is rate-limited (`captain.ts:192-197`) and it is
by far the highest-volume endpoint, the limiter inherits the location firehose:
763 KV writes per completed trip. At 10,000 trips/day that is 229 M KV writes a
month, or **$1,140** — more than D1 writes, DO requests, DO storage and Queues
put together.

The irony is that this protects an endpoint whose real cost problem (F-24-04) it
does nothing about; it merely caps it at 30/min and charges $5/M for the
privilege.

Three options, in ascending order of effort: use Cloudflare's native
[Rate Limiting binding](https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/),
which is not metered per operation; or move the counter into the `GeoCell` DO
that the same request already contacts (`captain.ts:211-221`), making it free
alongside an existing write; or drop rate limiting on `/captain/location`
specifically and enforce cadence client-side, accepting the abuse risk. I
recommend the second — the DO round-trip already exists, so the counter is
genuinely free.

### F-24-04 — 1,409 database writes to complete one trip

`captain.ts:205-209` updates `captains.last_lat/last_lng/last_seen_at` on every
ping. `captain.ts:231-235` updates `trips.captain_lat/captain_lng` on every ping
during an active trip. Neither is gated by time or distance on the server, and
the first is not gated by trip state at all — an idle captain cruising for fares
writes a D1 row every 50 m of movement.

Per completed trip that is 600 × 2 + 133 = 1,333 writes of pure last-known
position, against 76 writes that represent actual business state. **97 % of the
platform's write volume is telemetry that is overwritten seconds later.**

The position already has an authoritative real-time home: the `GeoCell` DO
(`captain.ts:211-221` → `GeoCell.ts:30`), which is what dispatch actually reads
(`nearby.ts:74-77`). The D1 columns are a redundant mirror kept for display.

The fix: drop both `UPDATE`s from the ping path; serve live position from
`GeoCell` and `TripRoom`; flush `captains.last_*` to D1 at most once every 60 s
via `ctx.waitUntil`, or only on the online/offline transition. Keep the 30 s
path-point sampling — that is the one write here with lasting value, and batch
it via `DB.batch()` in groups of ten. Expected: **1,409 → ~110 writes per trip.**

### F-24-05 — Hibernation is registered but the session map is not

`TripRoom.ts:105` calls `ctx.acceptWebSocket(server)`, which correctly opts the
socket into hibernation. But the per-socket metadata is stored in an in-memory
`Map` at `TripRoom.ts:110` and `:123`, and `webSocketMessage` looks it up at
`TripRoom.ts:151`.

An in-memory `Map` does not survive eviction. Once the DO hibernates and wakes on
an incoming frame, `this.sessions.get(ws)` returns `undefined` and the message is
dropped — silently. The author clearly anticipated this for the outbound path:
`broadcast()` falls back to iterating `ctx.getWebSockets()` at `TripRoom.ts:280-282`
for sockets missing from the map. The inbound handler never got the same
treatment.

The symptom in production is a long or quiet trip where the rider's chat messages
and the captain's location frames stop being processed after a few minutes of
inactivity, with no error anywhere. This is a realtime-correctness bug that T07
owns, but it belongs here because it was *caused* by the cost optimisation, and
the fix must not be "remove hibernation".

The correct pattern is `ws.serializeAttachment()` at accept time and
`ws.deserializeAttachment()` in the handler, so metadata survives eviction with
the socket.

### F-24-06 — Hibernation saves $670/month, and one line partly undoes it

Modelling 500 concurrent captain sockets, one DO instance each, at Cloudflare's
128 MB (0.125 GB) duration unit:

```
Without hibernation, 8 h/day:
  500 × 0.125 GB × (8 × 3600 × 30) s   = 54,000,000 GB-s
  (54,000,000 − 400,000) × $12.50/M    = $670.00 / month

With hibernation (~0.02 % duty cycle at a 25 s ping):
  500 × 0.125 GB × 5.76 s × 30         =     10,800 GB-s
  under the 400,000 GB-s allowance     =      $0.00 / month
```

The codebase gets this right (`TripRoom.ts:105`, `CaptainInbox.ts:45`) and
deserves the credit. The exception is `CaptainInbox.ts:175`, where the relay to
the real inbox uses `upstream.accept()` with an `addEventListener` at `:178`.
An active outbound WebSocket prevents hibernation, so the pending-auth instance
bills wall-clock for as long as any client is proxying through it.

Simplest fix: after first-message authentication, send the client a redirect
frame and have it reconnect directly to its own inbox, deleting the relay
entirely.

### F-24-07 · F-24-08 · F-24-10 — The query layer leaves easy money on the table

Five hot queries wrap an indexed column in `datetime()` — `admin.ts:30`, `:91`,
`:117`, `:165` and `:237` — which prevents SQLite from using
`idx_trips_created` (`migrations/0001_init.sql:92`). The predicate is already
comparing ISO-8601 strings, which sort lexicographically; the wrapper buys
nothing and costs a full scan each time. Normalising the bound parameter in JS
and comparing the bare column fixes all five.

Four indexes are simply absent, each behind a polled endpoint:
`captains(is_online, approval_status)` for `admin.ts:36` and `admin.ts:932`;
`trips(status, completed_at)` for the top-captains join at `admin.ts:99-107`;
`trips(company_id)` for the monthly invoice scan at `index.ts:344`; and
`users(role)` for `safety.ts:29`, `index.ts:316` and `admin.ts:15`. Verified
absent across the six migrations I read; the remaining thirteen are
`needs-check`, though none of these tables is created there.

And `DB.batch()` — which turns N round-trips into one — appears exactly once in
roughly 6,400 lines of API code, at `admin.ts:506`. That single call site is a
working template for the five-statement `/admin/stats` handler and the
four-statement analytics handler. This matters more than it looks: D1 permits
six concurrent connections per Worker invocation and executes one query at a
time per database, so sequential awaits serialise against a single-threaded
backend across a Cairo→Western-Europe round-trip (F-24-18).

### F-24-09 · F-24-11 — Payload and write-on-read

`admin.ts:314` builds `SELECT * FROM trips` and executes it at `:322` with
`LIMIT 200` (`:320`). The row includes `route_geometry`; the consuming component
declares twelve fields (`TripsPage.tsx:11-25`) and that is not one of them. The
same pattern at `captain.ts:463` ships twenty full trip rows, geometry included,
to a **mobile client on Egyptian cellular data** — where, as the brief puts it,
bytes are money for the user too. The correct pattern already exists eighty
lines earlier in the same file at `captain.ts:372-375`, which enumerates
seventeen explicit columns.

Separately, `GET /admin/captains` runs `UPDATE captains SET is_online = 0 …`
(`admin.ts:237`) before its `SELECT`. A GET that writes is surprising on its own;
polled every ten seconds (`CaptainsPage.tsx:235`) against columns with no index
(F-24-08), it is 360 full-table write-scans per hour per open tab. The staleness
sweep belongs in the existing per-minute cron (`index.ts:270-271`), not on a read
path.

### F-24-20 — `docs/COST.md` is refuted

`COST.md:9` budgets **$100–200/month** for 500–1,000 daily trips. The model puts
the as-built figure at **$583/month** at 1,000 trips/day — a 3–6× underestimate.
The document is also wrong on mechanism:

- *"Location every 4–5s on trip only"* (`COST.md:23`) — location is
  **distance-driven**, not time-driven (`captain_state.dart:621`, `:625`), and it
  is emphatically **not** "on trip only": `captain.ts:205-209` writes on every
  ping with no trip gate, so idle online captains generate D1 and KV writes too.
- *"Path samples to D1 every 30–60s"* (`COST.md:24`) — **confirmed correct**,
  enforced at `captain.ts:245`.
- *"Unthrottled GPS writes"* is listed as a cost driver to watch (`COST.md:18`),
  which is right — but the guardrail described was never implemented server-side.

After the P0 fixes in §6 the original budget becomes achievable: **$20/month at
1,000 trips/day**, comfortably inside the stated $50–100 launch envelope. The
document should be rewritten against the model rather than deleted.

---

## 5. Benchmark gap

Ride-hailing at scale is a location-write problem before it is anything else.
The industry converged on a small number of mechanisms; Synaptic Go currently
implements about half of them.

**Location ingestion.** Uber's architecture writes driver positions to an
in-memory geospatial index (the H3-based system that replaced their earlier
supply-positioning service), not to the transactional store; the durable trip
record gets a *sampled, simplified* path after the fact. This is well documented
in Uber's engineering publications — I am confident about the mechanism, less so
about current sampling rates. Synaptic Go has the right instinct — `GeoCell`
*is* an in-memory geospatial index — but it writes to D1 in parallel on every
ping (`captain.ts:205-209`) instead of treating the DO as authoritative. The
platform is paying for both architectures at once.

**Sampling and simplification.** Every mature player simplifies before
persisting: Douglas–Peucker or equivalent, then store. Synaptic Go stores the
raw `overview=full` OSRM polyline (`routing.ts:30` → `trips.ts:472`) and raw
30-second samples. *Assumed*: I have not verified competitor tolerances.

**Adaptive cadence.** inDrive and Careem, like Uber, vary reporting frequency by
state — parked drivers report rarely, drivers on a live trip report frequently,
drivers approaching a pickup report most frequently of all. Synaptic Go does
have two tiers (`distanceFilter: 50` idle, `10` on trip —
`captain_state.dart:621`, `:625`), which is genuinely better than a naive fixed
timer and stops the radio waking for a parked captain. What it lacks is a
*server-side* floor: the server accepts and writes whatever arrives, up to 30/min.

**Operational dashboards.** No dispatch console at scale recomputes
platform-wide aggregates per operator per tick against the live transactional
table. The standard answers are a materialised counters table updated on trip
transitions, a short-TTL cache, or a streamed feed. Synaptic Go recomputes from
scratch every 8 seconds (`admin.ts:14-40`, `DashboardPage.tsx:49`). This is the
single widest gap against industry practice in this document.

**Where Synaptic Go is genuinely ahead.** WebSocket hibernation
(`TripRoom.ts:105`, `CaptainInbox.ts:45`) is a more efficient realtime substrate
than the connection-server fleets the incumbents built, and it comes free with
the platform. Backoff with jitter (`offers_ws.dart:90-92`) is correct. Stopping
the GPS stream on background is correct. The visibility-aware poll hook is
correct. The bones are good; the accounting on top of them is not.

**Cost per trip, in context.** At $0.0194 (1k/day) to $0.0155 (50k/day) against
an assumed $0.24 commission, infrastructure is 6–9 % of revenue. Public
commentary on mature ride-hailing puts infrastructure in the low single digits
of net revenue — *assumed*, as the comparison basis is rarely stated precisely.
After the P0 work below, Synaptic Go lands at **0.3–0.8 %**, which is
comfortably better than the benchmark because the serverless model has no idle
fleet to pay for.

---

## 6. Improvement plan

Ordered by monthly saving per unit of effort. Savings are quoted at 10,000
trips/day, the tier where the platform is a real business.

### P0.1 — Cache and repair the admin aggregate endpoints

- **Goal** — the dispatch dashboard stops being the most expensive component in the platform.
- **Design** — three layers. (1) Wrap `/admin/stats` and `/admin/live-trips` in a KV cache with a 30 s TTL keyed by endpoint; the poll cadence stays at 8 s for UI smoothness but only one tick in four reaches D1. (2) Make the date predicates sargable: normalise `from`/`to` to full ISO instants in JS and compare the bare column (`created_at >= ? AND created_at < ?`) so `idx_trips_created` is used. (3) Collapse the five sequential statements in `/admin/stats` into one `env.DB.batch([...])`, using `admin.ts:506` as the template. Replace the `status NOT IN (…)` negation at `admin.ts:58` with a positive `status IN ('searching','offered','assigned','arrived','in_progress')`.
- **Files to change** — `apps/api/src/routes/admin.ts` (`:13-50`, `:52-62`, `:64-217`), new `apps/api/src/lib/cache.ts`.
- **DB** — none.
- **API contract** — unchanged. Add `Cache-Control: max-age=30` and an `x-cache: hit|miss` response header for observability.
- **Effort** — **M** (1–3 days).
- **Risk** — operators see counters up to 30 s stale. Mitigate by exempting `/admin/live-trips` from the cache if dispatchers object, and keep the fix to (2) and (3) which are pure wins. Rollback is deleting the cache wrapper.
- **Acceptance criteria** — a Dashboard tab open for one hour issues ≤ 130 D1 statements (from ~2,700); `EXPLAIN QUERY PLAN` on the today-window query shows `USING INDEX idx_trips_created`; no endpoint response changes shape.
- **Tests** — unit test asserting cache hit/miss behaviour across TTL; a query-plan assertion test for each of the five repaired statements; a load test replaying one hour of two-operator polling and counting D1 statements.
- **Saving** — **~$4,660/month.**

### P0.2 — Take live position out of D1

- **Goal** — writing a captain's position costs one DO storage write, not three D1 rows.
- **Design** — delete the unconditional `UPDATE captains` (`captain.ts:205-209`) and the per-ping `UPDATE trips` (`captain.ts:231-235`) from the request path. `GeoCell` becomes the single source of truth for live position — it already is, for dispatch (`nearby.ts:74-77`). Add a throttled flush: if the captain's last D1 write is older than 60 s, write `captains.last_*` inside `ctx.waitUntil()` so it never blocks the response. Keep the 30 s path-point gate, but accumulate points in the `TripRoom` DO and flush them to D1 in batches of ten via `DB.batch()`. Serve `trips.captain_lat/lng` reads from `TripRoom` state (`TripRoom.ts:86`) instead of the trips row.
- **Files to change** — `apps/api/src/routes/captain.ts` (`:190-271`), `apps/api/src/durable-objects/TripRoom.ts`, `apps/api/src/durable-objects/GeoCell.ts`, plus any reader of `trips.captain_lat` (`admin.ts` live map, `trips.ts` detail).
- **DB** — none required. Optionally migration `0020_drop_trip_captain_latlng.sql` once readers are migrated.
- **API contract** — unchanged for clients. Internally, `GET /admin/live-trips` sources captain position from the DO layer.
- **Effort** — **M** (1–3 days).
- **Risk** — live-map position becomes eventually consistent; a DO eviction could lose ≤ 60 s of last-known position. Acceptable — the position is superseded within seconds by definition. Rollback: restore the two `UPDATE`s behind a feature flag.
- **Acceptance criteria** — D1 rows written per completed trip ≤ 150 (from 1,409), measured over 100 synthetic trips; live map position lag ≤ 5 s at p95; no regression in dispatch match rate.
- **Tests** — an integration test driving 600 pings through one trip and asserting the D1 write count; a DO eviction test asserting position recovery.
- **Saving** — **~$370/month D1 writes + ~$140/month DO storage writes**, and it is the prerequisite for P0.3's ceiling.

### P0.3 — Get the rate-limit counter off KV

- **Goal** — stop paying $5 per million to count requests.
- **Design** — move the counter for high-volume endpoints into the DO the request already contacts. `POST /captain/location` already calls `GeoCell` (`captain.ts:211-221`); increment a per-captain counter in that same DO round-trip, returning `429` from the DO when the window is exceeded. For endpoints with no natural DO, adopt Cloudflare's native Rate Limiting binding, which is not metered per operation. Keep the existing KV limiter only for genuinely low-volume routes (auth, OTP), where its cost is negligible and its behaviour is proven.
- **Files to change** — `apps/api/src/middleware/rateLimit.ts`, `apps/api/src/durable-objects/GeoCell.ts`, `apps/api/wrangler.toml` (add the binding).
- **DB** — none.
- **API contract** — unchanged; `429` semantics and headers preserved.
- **Effort** — **S** (< 1 day) for the native binding on hot routes; **M** if the DO counter is chosen.
- **Risk** — the DO counter is per-cell, so a captain crossing a cell boundary gets a fresh window. Bound the abuse by keying the counter on `userId` inside the cell and accepting the seam, or use the native binding, which has no such issue. Rollback is a one-line middleware swap.
- **Acceptance criteria** — KV writes per completed trip ≤ 40 (from 763); rate-limit rejections still fire at the documented threshold under a burst test.
- **Tests** — a burst test asserting `429` at the 31st request in a window; a cost assertion counting KV operations over a synthetic trip.
- **Saving** — **~$1,080/month.**

### P0.4 — Stop D1 from filling up

- **Goal** — the database never reaches its 10 GB ceiling.
- **Design** — three moves. (1) Simplify the route polyline before persisting: run Douglas–Peucker at ~10 m tolerance on `est.geometry` before `JSON.stringify` at `trips.ts:472`, or request `overview=simplified` from OSRM at `routing.ts:30`. (2) Move the geometry out of the row entirely: write it to R2 at `trips/{id}/route.json` and store only the key. R2 is $0.015/GB-mo with free egress against D1's $0.75/GB-mo. (3) Add a retention cron: trips completed more than 90 days ago, and their `trip_path_points`, are exported to R2 as NDJSON and deleted from D1.
- **Files to change** — `apps/api/src/lib/routing.ts` (`:30`, `:56`), `apps/api/src/routes/trips.ts` (`:447`, `:472`, `:670`), `apps/api/src/lib/cleanup.ts`, `apps/api/src/index.ts` (cron registration).
- **DB** — migration `0021_route_geometry_to_r2.sql`: add `route_geometry_key TEXT`, backfill, drop `route_geometry` in a later migration once readers are cut over.
- **API contract** — `GET /trips/:id` unchanged externally; internally it fetches geometry from R2 when the key is present.
- **Effort** — **L** (> 3 days), mostly backfill and verification.
- **Risk** — historical trips lose inline geometry if the backfill is incomplete; run it idempotently and keep the column until the R2 copy is verified for every row. Retention deletion is irreversible — export first, verify object count, then delete.
- **Acceptance criteria** — average `trips` row < 1 KB; projected time-to-10 GB at 50k trips/day exceeds 3 years; `GET /trips/:id` p95 unchanged.
- **Tests** — a migration test asserting geometry round-trips through R2; a retention dry-run reporting row and byte counts without deleting.
- **Saving** — small directly (~$4/month), but it is the difference between the platform running and stopping. Also compounds P0.1 by shrinking scanned rows ~10×.

### P0.5 — Add the four missing indexes

- **Goal** — the polled endpoints stop scanning whole tables.
- **Design** — one migration:
  ```sql
  CREATE INDEX idx_captains_online_approval ON captains(is_online, approval_status);
  CREATE INDEX idx_trips_status_completed_at ON trips(status, completed_at);
  CREATE INDEX idx_trips_company           ON trips(company_id);
  CREATE INDEX idx_users_role              ON users(role);
  ```
- **Files to change** — new `migrations/0020_perf_indexes.sql`.
- **DB** — as above.
- **API contract** — none.
- **Effort** — **S** (< 1 day).
- **Risk** — four more indexes to maintain on write; negligible against the read saving. Index creation locks briefly — run in a maintenance window once the table is large.
- **Acceptance criteria** — `EXPLAIN QUERY PLAN` shows an index for `admin.ts:36`, `admin.ts:99-107`, `index.ts:344` and `safety.ts:29`.
- **Tests** — query-plan assertions in CI for each of the four.
- **Saving** — folded into P0.1; independently prevents the analytics page from degrading with table growth.

### P1.1 — Fix the hibernation session bug

- **Goal** — realtime messages survive DO hibernation.
- **Design** — replace the in-memory `sessions` Map with `ws.serializeAttachment({role, userId, tripId})` at accept time (`TripRoom.ts:110`, `:123`) and `ws.deserializeAttachment()` in `webSocketMessage` (`:151`) and `webSocketClose` (`:184`). Keep the `getWebSockets()` fallback in `broadcast()` (`:280-282`) — it becomes the normal path.
- **Files to change** — `apps/api/src/durable-objects/TripRoom.ts`; mirror in `CaptainInbox.ts` if it shares the pattern.
- **DB** — none. **API contract** — none.
- **Effort** — **S**. **Risk** — low; attachments are the documented pattern. Rollback is trivial.
- **Acceptance criteria** — a socket idle for 10 minutes still delivers a `location` frame and a chat message after wake.
- **Tests** — a DO test that forces eviction between connect and message. **Coordinate with T07.**

### P1.2 — Remove the non-hibernating relay

- **Goal** — no DO instance bills wall-clock.
- **Design** — after first-message auth in the pending-auth inbox, return a redirect frame and have the client reconnect directly to its own inbox; delete the `upstream.accept()` relay (`CaptainInbox.ts:167-196`).
- **Files to change** — `apps/api/src/durable-objects/CaptainInbox.ts`, `apps/captain/lib/services/offers_ws.dart`.
- **Effort** — **M**. **Risk** — an extra reconnect on login; the client already has backoff. **Acceptance** — no outbound WebSocket remains open inside any DO. **Tests** — assert reconnect-and-authenticate completes < 2 s.

### P1.3 — Trim payloads and page properly

- **Goal** — responses carry only what the client renders.
- **Design** — replace `SELECT *` at `admin.ts:314` with the twelve fields `TripsPage.tsx:11-25` declares, and at `captain.ts:463` with the seventeen-column pattern already used at `captain.ts:372-375`. Move the client-side date and text filters (`TripsPage.tsx:65-91`) into SQL parameters. Replace `LIMIT 200` with keyset pagination (`WHERE created_at < ? LIMIT 50`). Add `LIMIT` to `trips.ts:663`. Apply the radius filter before the `LIMIT` at `captain.ts:428` and `:490`.
- **Files to change** — `apps/api/src/routes/admin.ts`, `captain.ts`, `trips.ts`; `apps/admin/src/pages/TripsPage.tsx`.
- **DB** — none. **API contract** — `GET /admin/trips` gains `from`, `to`, `search`, `cursor`; returns `{ trips, nextCursor }`.
- **Effort** — **M**. **Risk** — admin UI must handle cursors. **Acceptance** — trip-list response < 40 KB for 50 rows; captain offers response < 8 KB.
- **Tests** — a payload-size assertion in CI; a pagination test walking three pages.

### P1.4 — Move the staleness sweep off the read path

- **Goal** — GETs stop writing.
- **Design** — delete the `UPDATE` at `admin.ts:237`; move it into the existing per-minute cron (`index.ts:270-271`). Hoist the loop-invariant admin query at `index.ts:316` out of its loop, and replace the serial `await` fanout at `safety.ts:30` with the notification queue so SOS returns immediately.
- **Effort** — **S**. **Risk** — captain staleness updates once a minute instead of on dashboard load; that is more correct, not less. **Acceptance** — no `UPDATE`/`INSERT` executes on any `GET` route; SOS p95 response < 200 ms.

### P2.1 — Client-side performance pass

- **Goal** — faster cold start, smaller binary, no map jank.
- **Design** — move `Firebase.initializeApp()` off the pre-`runApp` path (`rider/lib/main.dart:20`, `captain/lib/main.dart:20`) into a post-first-frame init. Narrow the root `Consumer<CaptainState>` (`captain/lib/main.dart:47`) to scoped `Selector`s, or split the notifier so an offers poll does not diff the map subtree. Replace `webview_flutter` (`rider/pubspec.yaml:36`) with the already-present `url_launcher` for the Paymob flow. Bundle the font subset instead of letting `google_fonts` fetch at runtime. Trim `_bidTripIds` when offers refresh (`captain_state.dart:1021`).
- **Effort** — **M** per app. **Risk** — payment flow change needs QA on both platforms.
- **Acceptance** — cold start to first frame < 1.2 s on a 2 GB Android device; APK ≥ 3 MB smaller; no dropped frames on the map during a 5-minute drive.
- **Tests** — device measurement, not estimation — these numbers are currently `needs-check`.

### P2.2 — Prepare the scale-out path

- **Goal** — know the trigger, not just the option. See §10 Q2.
- **Design** — instrument the four metrics in §8; when D1 size exceeds 6 GB **or** p95 statement duration exceeds 500 ms **or** sustained write QPS exceeds 300, execute the migration decided in Q2. Adopt D1 read replication (Sessions API) before any of that — it is free and helps the read-heavy admin path immediately, though no replica region serves Africa/MENA.
- **Effort** — **L**. **Risk** — the whole point is to do this before it is urgent.

---

## 7. Phasing

| Item | Phase | Effort | Owner type | Saving / mo @ 10k trips/day |
|---|---|---|---|---|
| P0.1 Cache + repair admin aggregates | **P0** | M | backend | **$4,660** |
| P0.2 Live position out of D1 | **P0** | M | backend | **$510** |
| P0.3 Rate-limit counter off KV | **P0** | S–M | backend | **$1,080** |
| P0.4 D1 storage ceiling (geometry → R2, retention) | **P0** | L | backend + ops | survival |
| P0.5 Four missing indexes | **P0** | S | backend | folded into P0.1 |
| P1.1 Hibernation session attachments | P1 | S | backend | correctness |
| P1.2 Remove non-hibernating relay | P1 | M | backend | ~$20 |
| P1.3 Payload trim + keyset pagination | P1 | M | backend + admin | egress + UX |
| P1.4 Sweep off read path; SOS via queue | P1 | S | backend | latency |
| P2.1 Flutter cold start / size / jank | P2 | M ×2 | Flutter | user-perceived |
| P2.2 Scale-out triggers + read replication | P2 | L | backend + ops | future |

**P0 is four to six engineering days and takes the bill from $6,688 to $274 a
month at 10,000 trips/day.** Modelled end state:

| Tier | As built | After P0 | Saving | Per trip |
|---|---:|---:|---:|---:|
| 1,000 trips/day | $583 | **$20** | 96.5 % | $0.0007 |
| 10,000 trips/day | $6,688 | **$274** | 95.9 % | $0.0009 |
| 50,000 trips/day | $23,270 | **$1,772** | 92.4 % | $0.0012 |

Infrastructure falls from 6–9 % of commission to **0.3–0.5 %**.

---

## 8. Metrics

Instrument these before starting P0, so the change is provable rather than
asserted. Cloudflare Workers Analytics Engine is already available; nothing here
needs a third-party vendor (tooling choice is T22's).

| Metric | How | Current | Target |
|---|---|---|---|
| D1 rows read / day | Cloudflare D1 analytics | ~15.7 B @ 10k trips/day | < 200 M |
| D1 rows written / completed trip | counter per trip id | **1,409** | **< 150** |
| KV writes / completed trip | counter | **763** | **< 40** |
| D1 database size | `PRAGMA page_count × page_size`, daily | unknown — measure today | < 6 GB, alarm at 8 GB |
| p95 D1 statement duration | Analytics Engine, per endpoint | unknown | < 200 ms |
| D1 statements per admin dashboard load | request-scoped counter | **6** (5 + 1) | **1** cached, 2 on miss |
| Admin API requests / operator / hour | Worker analytics by route | **1,800** | < 500 |
| DO duration GB-s / day | Cloudflare DO analytics | ~360 (hibernating) | keep < 13,000 |
| Infra cost per completed trip | monthly bill ÷ completed trips | **$0.0223** | **< $0.002** |
| Cold start to first frame (p50/p95) | Flutter device trace | `needs-check` | < 1.2 s p95 on 2 GB device |
| Trip-list response bytes | response-size histogram | `needs-check`, est. 400–500 KB | < 40 KB |

The one to put on a wall is **infra cost per completed trip**. It is the only
number that stays meaningful as volume changes, and it makes regressions
obvious.

---

## 9. Cross-cutting notes

**→ T07 (Realtime — Durable Objects & WebSockets).** `TripRoom` registers
sockets for hibernation (`TripRoom.ts:105`) but stores session metadata in an
in-memory `Map` (`:110`, `:123`) that `webSocketMessage` reads at `:151`. After
eviction the lookup returns `undefined` and inbound frames are silently dropped.
`broadcast()` already works around this at `:280-282`. This is your bug, but do
not fix it by removing hibernation — that would cost $670/month at 500
connections. Use `serializeAttachment`. Also yours: `CaptainInbox.ts:175` uses
legacy `upstream.accept()`, which prevents hibernation for that instance.

**→ T08 (Dispatch & matching).** The radius filter runs in JavaScript *after*
the SQL `LIMIT` at `captain.ts:428` and `:490`, so a captain in a busy city can
see an empty offer list while matching trips exist beyond the first 30 rows. The
9-cell fanout (`nearby.ts:40-53`) is correct for coverage but costs 9 DO
subrequests per dispatch — if you change the cell precision, tell me, because it
moves the DO request line in the cost model.

**→ T02 / T05 (Security).** Two things. `wrangler.toml:77-85` documents that a
bare `wrangler deploy` publishes the top-level block over production because it
shares the worker name and D1 id with `[env.prod]`. And `admin.ts:241` returns
`c.*` including `national_id_number`, `birth_date` and licence fields for 200
captains per request to any admin session — that is a PII exposure as much as a
payload problem.

**→ T22 (Observability).** None of the metrics in §8 is currently instrumented.
`[observability]` is enabled in `wrangler.toml:93-94`, which is the substrate,
but there are no custom counters. The per-trip cost metric needs a request-scoped
counter keyed by trip id.

**→ T26 (Release engineering).** `[env.staging]` (`wrangler.toml:157-168`) points
at `staging-d1-database-id-placeholder` — staging is not actually isolated, and
the top-level and prod blocks share one database id (`:10`, `:109`).

**→ T27 (Cross-app parity).** The two apps have drifted in ways that cost money
asymmetrically. The captain app runs a 30 s approval poll (`captain_state.dart:107`)
and an 8/60 s offers poll (`:758`, `:763`); the rider app has no equivalent
polling layer. Both ship duplicate `trip_ws.dart` implementations
(`apps/rider/lib/services/trip_ws.dart`, `apps/captain/lib/services/trip_ws.dart`)
with the same 25 s ping and the same backoff — the same logic maintained twice,
which means a cadence fix has to be made twice and will eventually be made once.
Both pubspecs carry the same heavy dependency set. If you unify the WebSocket
service into `packages/flutter_shared`, the cadence constants become a single
tunable and this document's client-side numbers become enforceable in one place.
Note also that the rider app carries `webview_flutter` (`rider/pubspec.yaml:36`)
and the captain app does not.

**→ T25 (Privacy / legal).** The 90-day retention job proposed in P0.4 is a cost
measure, but retention periods for trip paths and captain location history are a
compliance decision. Coordinate — I picked 90 days as an engineering default,
not a legal one.

---

## 10. Open questions

**Q1 — Do dispatchers actually need 8-second refresh?**
Options: (a) keep 8 s with a 30 s cache — counters lag, live trips do not;
(b) raise to 30 s uniformly; (c) replace polling with a WebSocket feed from a
dispatch DO. **Recommendation: (a) now, (c) in P2.** The cache is a day of work
and captures ~99 % of the saving; the event-driven feed is the right end state
but not urgent once the cost is gone.

**Q2 — What is the migration target when D1 stops being viable?**
D1 is 10 GB per database, single-threaded per database, with no replica region
serving Africa or MENA. Options: (a) **shard by city** — natural for an Egyptian
operator, keeps everything on Cloudflare, and the 50,000-database limit is not a
constraint; (b) **Hyperdrive + managed Postgres** — no size ceiling, real
concurrency, but adds a vendor, a region choice and egress; (c) stay on D1 and
lean on retention. **Recommendation: (a) shard by city**, triggered at 6 GB or
p95 statement duration above 500 ms, whichever comes first. Cairo alone will hit
it first, so the shard key earns its keep immediately.

**Q3 — Is 30 requests/minute the right server-side ceiling for location?**
It currently permits 600 pings on a 20-minute trip. A 5-second floor would cap
it at 240 and change nothing a rider can perceive. **Recommendation: enforce a
5 s server-side floor** and keep the client's distance filter as the primary
gate. Needs a product call on whether captain-marker smoothness matters more
than the ~60 % write reduction.

**Q4 — What is the retention period for trip paths?**
Engineering wants 90 days in D1 with older data in R2. Legal may require longer
for dispute resolution, or shorter for privacy. **Recommendation: 90 days hot,
2 years cold in R2, then delete** — but this is T25's call, not mine.

**Q5 — Should the Worker be pinned near D1?**
Cairo traffic is served by Cloudflare's CAI colo; D1's primary can only be
hinted to one of six regions, none in Africa or MENA — `weur` is nearest. Every
sequential statement pays that round-trip, which is why F-24-10 matters. Options:
(a) Smart Placement, letting Cloudflare co-locate the Worker with D1;
(b) an explicit `weur` placement hint; (c) leave it at the edge and fix the
round-trip *count* instead. **Recommendation: (c) first — batching is a bigger
win than placement — then measure, then (a).** Enabling Smart Placement before
fixing the sequential awaits would mask the problem while still paying for it.
Current p50/p95 latency figures are `needs-check`: nothing is instrumented yet.

---

*Model and assumptions: `docs/plan/assets/24-cost-model.py`. Base commit
`0f432702a3755f7bd738b8b7ee15230cf05c4686`. Reviewer `chat-20260801-1416-2cd9`.*
