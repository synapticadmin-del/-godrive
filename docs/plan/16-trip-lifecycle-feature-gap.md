# 16 — Trip Lifecycle — Feature Gap vs Uber & inDrive

> Track: C — Feature parity & new capability · Reviewer: `chat-20260801-1334-5c21` · Date: 2026-08-01
> Base commit reviewed: `4330518f5e3031cd9de124773a6e3c4783c6b138`

## 1. Scope

This document takes the feature surface of a mature ride-hailing product and checks it, item by item, against what Synaptic Go actually implements on `main` at the commit above. It produces three things: the **feature register** (§3.6), the **trip state machine as it really behaves** (§3.2), and an ordered plan to close the gap (§6–§7).

Covered here:

- Every capability a rider or captain touches between "I want a ride" and "the money settled and the trip is in history" — booking modes, scheduling, multi-stop, in-trip mutation, cancellation, no-show, completion, rating, history, receipts.
- The trip status enum, its legal transitions, who may trigger each, and which states have no way out.
- Cancellation economics and policy.
- Search, saved places and POI coverage *as they serve trip creation*.
- Scope for a courier/delivery vertical on top of the current trip model.

Explicitly **not** covered — owned by siblings:

| Area | Owner |
|---|---|
| Wallet/ledger correctness, commission accounting, double-spend | **T03** |
| PSP integration, payouts, Paymob | **T04** |
| Fare formula, surge algorithm, bidding economics | **T05** |
| Dispatch/matching quality, geohash fan-out, radius tuning | **T06** |
| Durable Objects, WebSocket transport, event delivery | **T07** |
| Migration hygiene, index strategy, the `*_piastres` duality | **T08** |
| Rider client architecture and screen-level defects | **T09** |
| Captain client architecture | **T10** |
| Safety, SOS, trust primitives | **T17** |
| Intercity/B2B verticals as products | **T20** |
| Rider↔captain duplication and vocabulary drift, systematically | **T27** |

Where this document touches those axes it is because the *lifecycle* depends on them; findings that belong to them are in §9.

I write about competitor behaviour only where I am confident from public product surface; those claims are marked **assumed** where they are inference rather than knowledge.

## 2. What I actually read

Read in full, at the base commit:

| File | Note |
|---|---|
| `apps/api/src/routes/trips.ts` (1371 lines) | The complete endpoint surface. Read closely: create (`:348`–`:600`), cancel (`:709`–`:827`), accept (`:829`), status transitions (`:896`–`:950`), complete (`:951`–`:1089`), rate (`:1090`–`:1143`), bid (`:1144`), bids (`:1212`), accept-bid (`:1262`). |
| `packages/shared/src/index.ts` | `TripStatus`, `TRIP_TRANSITIONS`, `canTransition`, `calculateFare`. The whole state machine is 12 lines. |
| `apps/api/src/lib/schemas.ts` | `createTripSchema` incl. `waypoints`/`scheduledFor`, `cancelTripSchema`, `rateTripSchema`. |
| `apps/api/src/lib/routing.ts` | `getRoute` signature and the OSRM URL it builds. |
| `apps/api/src/lib/pricing.ts` | `pricingFromRow`; what is and is not persisted. |
| `apps/api/src/lib/cleanup.ts` | The only scheduled data cleanup that exists. |
| `apps/api/src/lib/geocode.ts` | Nominatim reverse + search, caching, headers. |
| `apps/api/src/index.ts` | The `scheduled()` cron handler and its SQL. |
| `apps/api/src/durable-objects/OfferScheduler.ts` | Wave rollout, alarms, teardown. |
| `apps/api/src/durable-objects/CaptainInbox.ts` | Offer delivery; absence of any offer TTL. |
| `migrations/0001_init.sql` | `trips`, `ratings` DDL. |
| `migrations/0002_enhancements.sql` | `saved_places` DDL; promo/discount columns. |
| `migrations/0003_global_transport.sql` | `waypoints`, `scheduled_for`, `schedule_status`, `surge_multiplier`, company columns, `scheduled_trip_dispatch`, `intercity_bookings`. |
| `migrations/0004_bidding_system.sql` | `offered_price`, `accepted_price`, `bidding_mode`. |
| `migrations/0016_system_config.sql` | The cancellation constants that nothing reads. |
| `migrations/0005, 0006, 0008, 0010, 0011, 0012, 0018, 0019` | Skimmed for trip-lifecycle columns; `0011` for `payment_status`. |
| `apps/rider/lib/screens/ride/schedule_screen.dart` | Read in full — including the fact that nothing imports it. |
| `apps/rider/lib/screens/ride/rating_sheet.dart` | Read in full. |
| `apps/rider/lib/screens/ride/trip_detail_screen.dart`, `history/history_screen.dart` | The whole post-trip surface. |
| `apps/rider/lib/screens/places/saved_places_screen.dart`, `saved_destinations_sheet.dart` | Place management. |
| `apps/rider/lib/screens/trip/trip_screen.dart` | In-trip action surface per state. |
| `apps/captain/lib/screens/home/active_trip_panel.dart`, `offer_card.dart`, `trips_tab.dart` | Captain-side lifecycle, for parity. |
| `apps/api/src/routes/user.ts`, `search.ts`, `companies.ts` | Saved places CRUD; admin search; B2B invoicing. |
| `docs/API.md`, `docs/BIDDING_SYSTEM.md`, `docs/CHECKLIST.md`, `docs/ROADMAP.md` | The documented intent, to compare against the code. |

Skimmed rather than read line by line: `apps/api/src/routes/admin.ts` (searched for rating/cancel/config handling only), `apps/api/src/routes/captain.ts`, `apps/api/src/routes/payments.ts`, `apps/api/src/routes/safety.ts`, `apps/api/src/routes/intercity.ts`, `apps/api/src/lib/notifications.ts`, `apps/api/src/durable-objects/TripRoom.ts`, `wrangler.toml`.

Every `path:line` below points at this commit. Negative findings ("absent") are backed by named searches; where a search is the only evidence I say so.

## 3. How it works today

### 3.1 The one booking path

There is exactly one way a trip is born: `POST /trips` (`apps/api/src/routes/trips.ts:348`). The handler, in order:

1. **Active-trip guard** (`trips.ts:362-376`) — `SELECT id FROM trips WHERE rider_id = ? AND status NOT IN ('completed','cancelled') LIMIT 1`. If a row exists it returns `409 {code:"ACTIVE_TRIP", tripId}`. Remember this; §4 F-16-01 turns on it.
2. **Pricing** (`trips.ts:379-381`) — city pricing row, else `500 NO_PRICING`.
3. **Route** (`trips.ts:382-386`) — `getRoute(pickup, dropoff, osrmUrl)`. Two points. Nothing else.
4. **Surge** (`trips.ts:387-396`) — a static per-city `surge_multiplier` read off the pricing row and multiplied into the total.
5. **Promo/discount** (`trips.ts:400-428`).
6. **Commission** (`trips.ts:429`) — `finalEstimate * commission_rate`, computed on the *estimate*.
7. **Insert** (`trips.ts:441-481`) — status `searching`, plus `scheduled_for`, `schedule_status`, `waypoints`, `surge_multiplier`, and the B2B columns auto-resolved from `company_employees`.
8. **Scheduled bookkeeping** (`trips.ts:484-490`) — *only if* `scheduledFor` is set, insert a `scheduled_trip_dispatch` row with `status='pending'`.
9. **Dispatch** (`trips.ts:518-586`) — `findNearbyCaptains(..., 10)`, filter by each captain's own radius, hand the ordered list to the `OfferScheduler` DO, FCM-blast the captains.

Step 9 is **not** guarded by `scheduledFor`. Step 8 is the only branch. That single fact is the whole scheduled-rides defect (§4 F-16-02).

### 3.2 The state machine as it really behaves

Seven statuses (`packages/shared/src/index.ts:3-10`) and a 12-line transition table (`:40-48`):

```
searching   → offered, assigned, cancelled
offered     → assigned, searching, cancelled
assigned    → arrived, cancelled
arrived     → in_progress, cancelled
in_progress → completed, cancelled
completed   → ∅
cancelled   → ∅
```

`canTransition` (`:50-52`) is honest and is actually called on the three transitions that matter — cancel (`trips.ts:723`), the arrived/start pair (`trips.ts:906`), and complete (`trips.ts:962`). The guard is real. The problem is not the transitions that are illegal; it is the ones that are legal and never happen.

Who may trigger what, and what can move a trip along:

| Status | Advanced by | Server-side timer that can move it | Stuck? |
|---|---|---|---|
| `searching` | captain `POST /:id/accept`, rider `POST /:id/accept-bid`, `OfferScheduler` → `offered` | **none** | **yes, forever** |
| `offered` | same | **none** — `OfferScheduler.teardown()` (`OfferScheduler.ts:153-157`) deletes the alarm and DO storage, writes nothing to D1 | **yes, forever** |
| `assigned` | captain `POST /:id/arrived` | **none** | **yes, forever** |
| `arrived` | captain `POST /:id/start` | **none** | **yes, forever** |
| `in_progress` | captain `POST /:id/complete` | **none** | **yes, forever** |
| `completed` | — | terminal | no |
| `cancelled` | — | terminal | no |

`apps/api/src/lib/cleanup.ts:29-75` is the only scheduled cleanup in the system and it deletes expired `otp_codes` and stale `refresh_tokens`. It does not look at `trips`.

So: **five of seven states can be entered and never left by any server-side mechanism.** Every exit is a client action. A captain who accepts and then loses their phone leaves the trip in `assigned` permanently.

### 3.3 Cancellation, as implemented

`POST /:id/cancel` (`trips.ts:709-827`). It is a careful piece of code about *notification* and a complete blank about *policy*:

- Authorises rider, captain, or admin (`:720-722`).
- Checks `canTransition(..., "cancelled")` (`:723-725`).
- Writes `status='cancelled'`, `cancel_reason`, `cancelled_at` (`:727-732`).
- If a rider cancelled an open request, tears down the `OfferScheduler` and fans a `trip.cancelled` push into 25 nearby captains' inboxes so the offer card disappears (`:750-795`) — a genuinely well-reasoned piece of work, with the reasoning in the comments.
- Pushes the other party (`:798-822`).

What it never does: read `system_config`, compute elapsed time, charge anything, count anything, or distinguish who cancelled from where in the lifecycle. `cancelTripSchema` (`schemas.ts:144-146`) is `{ reason?: string ≤200 }` — free text, optional, no enum.

Meanwhile `migrations/0016_system_config.sql:36-37` seeds:

```sql
('free_cancel_min', '3',  'number', 'مهلة الإلغاء المجاني للراكب (دقائق)'),
('cancel_fee_egp',  '15', 'number', 'غرامة الإلغاء المتأخر (ج.م)'),
```

and `apps/api/src/routes/admin.ts:429-430` maps them into the admin console so an operator can edit them. A search for `cancel_fee_egp` / `free_cancel_min` across the repository returns exactly those two sites plus the migration. **Nothing consumes them.** An operator can set the late-cancellation fee to 15 EGP, save it, see it persist, and it will never be charged.

### 3.4 Completion and fare finality

`POST /:id/complete` (`trips.ts:951`), captain-only:

```
finalFare = trip.accepted_price ?? trip.final_fare ?? trip.estimated_fare ?? 0   (:969)
commission = trip.commission ?? 0                                                (:970)
```

The final fare is whatever was agreed *before the wheels turned*. Nothing measures the trip. Actual distance, actual duration, waiting time at pickup, tolls, a detour the rider asked for — none of it reaches the fare. `arrived_at` and `started_at` are both recorded (`migrations/0001_init.sql`), so the waiting interval is *sitting in the database* and is never billed.

Commission is correct on the bidding path — `accept-bid` recomputes it against the accepted price (`trips.ts:1301-1302`). On the direct-accept path the captain takes the offered price and the booking-time commission stands, which is consistent.

### 3.5 After the trip

`GET /trips/history` (`trips.ts:606-613`) is `SELECT * FROM trips WHERE rider_id = ? ORDER BY created_at DESC LIMIT 50` — the raw row, no pagination beyond the fixed 50. `GET /trips/:id` (`trips.ts:647`) adds captain facts and the `trip_events` log.

Both return **totals only**: `estimated_fare`, `final_fare`, `commission`, `discount`, `surge_multiplier`. The fare *components* — base, per-km, per-minute, booking fee — are computed inside `calculateFare` and discarded; only the total is persisted (`trips.ts:441-481`). And `pricing_rules` is mutable with no history table. So the moment an admin edits a city's rate card, the itemised breakdown of every past trip in that city becomes unreconstructible. There is no receipt endpoint (searched `receipt`, `invoice`, `pdf`, `statement` — the only hits are the B2B `company_invoices` rows in `companies.ts:166-239`, which are database records with no document rendering and no email).

Rating: `POST /:id/rate` (`trips.ts:1090`) writes to `ratings` (`migrations/0001_init.sql:105-114`, `UNIQUE(trip_id, from_user_id)`), then recomputes `AVG(score)` over the target's whole history and writes it to `captains.rating_avg`/`rating_count` (`trips.ts:1122-1133`) — three separate D1 statements, not batched. The endpoint *does* support a captain rating a rider (`trips.ts:1103-1107`), but `users` has no rating columns and the aggregate update is guarded to captain targets only, so rider ratings are write-only data. No captain-side rating UI exists. No rating threshold triggers anything anywhere.

### 3.6 The feature register

This is the primary artefact of this document. Status is against the base commit. **Evidence** cites what I read; for absent features it names the searches that came back empty. **Effort** is S (<1 day) / M (1–3 days) / L (>3 days) for a competent engineer who knows this codebase. **Phase** is my recommendation, developed in §7.

| # | Capability | Status | Evidence | Effort | Phase | Rationale |
|---|---|---|---|---|---|---|
| 1 | Immediate point-to-point booking | **implemented** | `trips.ts:348-600` | — | — | The core path works. |
| 2 | Bidding / counter-offer | **implemented** | `trips.ts:1144` bid, `:1212` list, `:1262` accept-bid; `migrations/0004` | — | — | The product's differentiator, and the most complete thing in the lifecycle. |
| 3 | Trip state machine + guards | **partial** | `packages/shared/src/index.ts:40-52`; guards at `trips.ts:723`, `:906`, `:962` | M | P0 | Transitions are guarded; five states have no timeout. See F-16-01. |
| 4 | Scheduled rides | **broken** | `trips.ts:474`, `:484-490`; cron `index.ts:283-330`; UI `schedule_screen.dart` unreferenced | M | P0 | Dispatches at booking time, not scheduled time. See F-16-02. |
| 5 | Cancellation policy & fees | **absent** | `trips.ts:709-827` reads no config; constants at `migrations/0016:36-37`, `admin.ts:429-430` | M | P0 | Config exists, enforcement does not. See F-16-03. |
| 6 | No-show flow (either side) | **absent** | No `no_show` in `TripStatus` (`shared/src/index.ts:3-10`); `intercity_bookings.status` has the value (`0003:103`) but no endpoint writes it | M | P1 | Captain waits, rider never comes, captain gets nothing. |
| 7 | Waiting-time charging | **absent** | `arrived_at`/`started_at` exist (`0001_init.sql`); `trips.ts:969` ignores them; `pricing_rules` has no wait rate | S | P1 | The data is already there; only the rule is missing. |
| 8 | Multi-stop / waypoints | **partial (inert)** | Accepted `schemas.ts:64-73`, stored `trips.ts:475`, routing is two-point `routing.ts:21-30`, no UI in either app (searched `waypoint` across `apps/rider`, `apps/captain` — no hits) | L | P2 | Column, validator and storage exist; nothing consumes them. See F-16-04. |
| 9 | In-trip destination change | **absent** | No such endpoint in `trips.ts`; searched `change_destination`, `update_dropoff` | L | P2 | Requires re-route + re-price + captain consent. |
| 10 | In-trip stop addition | **absent** | `waypoints` is write-once at insert; searched `add_stop` | L | P2 | Depends on #8. |
| 11 | Estimated-vs-final reconciliation | **partial** | `trips.ts:969` fallback chain; no metered recompute | M | P1 | Fare can only change via bidding, never via reality. |
| 12 | Tipping | **absent** | `rateTripSchema` is `{score, comment}` (`schemas.ts:148-151`); no `tip` column; `rating_sheet.dart:7` docstring promises one | M | P1 | The UI already implies it exists. |
| 13 | Rating — rider→captain | **implemented** | `trips.ts:1090-1137`; aggregate `:1122-1133` | — | — | Works, but see #14/#15. |
| 14 | Rating — captain→rider | **partial (dead)** | Endpoint accepts it `trips.ts:1103-1107`; no aggregate for riders; no captain UI (`riderRating` l10n key exists, unused) | M | P1 | Two-sided accountability is half-wired. |
| 15 | Rating comment persistence | **partial (dead)** | Schema accepts `comment` (`schemas.ts:150`); rider app collects it in `rating_sheet.dart:119-130` and never sends it | S | P0 | One-line client fix; the server is ready. |
| 16 | Structured feedback tags / compliments | **absent** | Five chips rendered `rating_sheet.dart:108-116`, no state captured, no `tags` field in schema or DDL | S | P1 | Currently decoration. |
| 17 | Low-rating consequence | **absent** | No threshold logic in `admin.ts`/`captain.ts`; only manual suspend `admin.ts:289-310` | M | P1 | Ratings are collected and mean nothing. |
| 18 | Trip history | **implemented** | `trips.ts:606-613`; `history_screen.dart` | — | — | Fixed `LIMIT 50`, no pagination. |
| 19 | Fare breakdown display | **partial** | `trip_detail_screen.dart:127-146` renders totals; components never persisted | M | P1 | Shows a breakdown it cannot fully justify. |
| 20 | Receipts (download / email) | **absent** | Searched `receipt`, `invoice`, `pdf`, `statement` — only B2B rows `companies.ts:166-239` | M | P1 | Nothing a rider can keep or forward. |
| 21 | Tax invoice (retroactive) | **absent / blocked** | Components discarded (`trips.ts:441-481`); `pricing_rules` mutable, no history table | M | P0 | Not just missing — becoming *unbuildable* for past trips with every rate-card edit. |
| 22 | Re-book from history | **absent** | `history_screen.dart:72-76` opens a read-only detail; searched `rebook`, `repeat_trip` | S | P1 | Cheapest retention feature available. |
| 23 | Saved places (home/work) | **partial** | `saved_places` DDL `0002:72-81` — free-text `label` only; icons matched by literal string `saved_places_screen.dart:191-194`; no count limit (`user.ts:256-273`) | S | P1 | Works, untyped, unbounded. |
| 24 | Recent destinations | **partial** | No table/endpoint; client must derive from `GET /trips/history` | S | P1 | Deduped recents are a two-hour endpoint. |
| 25 | Pickup notes / gate / building | **absent** | Searched `pickup_note`, `gate`, `building`, `notes_for_driver` — no hits; `createTripSchema` has only `pickupAddress` | S | P1 | In Cairo this is the difference between found and not found. |
| 26 | POI coverage (Cairo) | **absent (live-only)** | No `places`/`poi` table in any of the 19 migrations; every lookup is a live Nominatim call `geocode.ts:100-102` | M | P0 | See F-16-05. |
| 27 | Geo provider resilience | **partial** | Nominatim only; KV cache 30d reverse / 7d search (`geocode.ts:82`, `:128`); no rate limit, no retry, no fallback, no commercial provider anywhere (searched `mapbox`, `google`, `here`, `tomtom`) | M | P0 | Licence and rate-limit exposure. See F-16-05. |
| 28 | Airport / venue pickup zones | **absent** | Searched `airport`, `zone`, `venue`, `geofence` — no hits, no geofence table | L | P2 | High-value Cairo surface. |
| 29 | Toll handling | **absent** | Searched `toll`; no column in `pricing_rules` | M | P2 | Ring Road tolls come out of the captain's pocket. |
| 30 | Night / time-of-day pricing | **absent** | `surge_multiplier` is a static per-city column read at `trips.ts:387-396`; no hour logic in `calculateFare` | S | P1 | A scheduled multiplier is a small change. |
| 31 | Corporate ride tagging | **partial** | Auto-resolved from `company_employees` at `trips.ts:432-436`; spend limits + monthly invoice `companies.ts` | M | P2 | Backend is real; rider cannot pick a cost centre, invoices are rows not documents. |
| 32 | Ride for someone else | **absent** | Searched `on_behalf`, `passenger_name`, `contact_override` — no hits; `trips` has `rider_id` only | M | P2 | Common in the region. |
| 33 | Favourite / blocked drivers | **absent** | Searched `favourite`, `favorite`, `preferred_driver`, `blocked_driver` — no tables, no endpoints | M | P2 | Pairs with #17 as the trust loop. |
| 34 | Women-only / female-driver matching | **absent** | Searched `female`, `women_only`, `gender`; `captains` has no gender column | L | P1 | Market-critical in Egypt. See §5. |
| 35 | Pet / luggage / child seat / accessible vehicle | **absent** | Searched `pet`, `child_seat`, `wheelchair`, `luggage`; `vehicle_types` has no modifiers | M | P2 | Vehicle-type extension, not new plumbing. |
| 36 | Ride pooling | **absent** | Searched `pool`, `carpool`; `trip_share_tokens` is safety location-sharing, not pooling | L | P2+ | Wrong bet for a bidding-first product. See §5. |
| 37 | Split fare | **absent** | Searched `split_fare`; no table, no endpoint | L | P2 | Low priority in a cash-dominant market. |
| 38 | Recurring rides | **absent** | Searched `recurring`, `repeat`; `scheduled_trip_dispatch` has no recurrence rule | M | P2 | Depends on #4 being fixed first. |
| 39 | Lost and found | **absent** | Searched `lost`, `found`, `lost_item` — no hits beyond error strings | M | P1 | Ops will need it on day one. |
| 40 | Delivery / courier vertical | **absent** | Searched `delivery`, `courier`, `parcel`, `package` — no hits; `intercity_bookings` is seats only | L | P2 | Scoped in §6 P2.6; coordinate with T20. |
| 41 | Scheduled-ride management UI | **absent** | No list/edit/cancel surface in either app; `schedule_status` never read back | S | P0 | Part of fixing #4. |
| 42 | "No captain found" notification | **absent** | `OfferScheduler.teardown()` `:153-157` writes nothing; no such topic in `notifications.ts` | S | P0 | Part of F-16-01. |

## 4. Findings

| ID | Sev | Finding | Evidence (`path:line`) | Impact | Confidence |
|---|---|---|---|---|---|
| F-16-01 | **S1** | A trip that no captain accepts is never expired, and the active-trip guard then locks the rider out of the product permanently | `trips.ts:362-376`, `cleanup.ts:29-75`, `OfferScheduler.ts:153-157`, `shared/src/index.ts:40-48` | Rider cannot book again — ever — without admin intervention | confirmed |
| F-16-02 | **S1** | Scheduled rides dispatch at booking time, not at the scheduled time; the cron only notifies admins | `trips.ts:484-490` vs `:518-521`, `index.ts:283-330`, `schemas.ts:63` | The feature does the opposite of its name, and every use of it triggers F-16-01 | confirmed |
| F-16-03 | **S1** | The cancellation policy is configured, admin-editable, and never enforced | `migrations/0016:36-37`, `admin.ts:429-430`, `trips.ts:709-827` | Unlimited free cancellation at any state incl. `arrived`; captains absorb all deadhead cost | confirmed |
| F-16-04 | S2 | Multi-stop is accepted and stored but never routed, priced, or displayed | `schemas.ts:64-73`, `trips.ts:475`, `routing.ts:21-30` | An API client can book a 3-stop trip and pay the 2-point fare | confirmed |
| F-16-05 | S2 | Nominatim is the sole geo provider, with no rate limit, no fallback, and no local POI table | `geocode.ts:39-40`, `:48`, `:100-102`, `:108`; no `places` table in 19 migrations | Address search degrades to raw coordinates under load; licence exposure | confirmed |
| F-16-06 | S2 | Fare components are never persisted and `pricing_rules` has no history, so itemised receipts cannot be produced retroactively | `trips.ts:441-481`, `lib/pricing.ts:10-21`, no pricing-history table | Every rate-card edit permanently destroys the breakdown of past trips | confirmed |
| F-16-07 | S2 | No receipt exists in any form for a rider; B2B invoices are database rows with no document | searched `receipt`/`invoice`/`pdf`; `companies.ts:166-239` | Riders cannot expense a trip; companies cannot file | confirmed |
| F-16-08 | S2 | Two-sided accountability is half-wired: captain→rider ratings are accepted and discarded, and no rating threshold does anything | `trips.ts:1103-1107`, `:1121`; no rider aggregate columns; `admin.ts:289-310` manual only | Bad riders are invisible; bad captains keep driving | confirmed |
| F-16-09 | S2 | Waiting time and no-show are unhandled although the timestamps to compute them are already stored | `arrived_at`/`started_at` in `0001_init.sql`; `trips.ts:969` | Captain absorbs every minute of waiting and every no-show | confirmed |
| F-16-10 | S2 | The rating comment is collected from the rider and never sent; the five feedback chips are decoration | `rating_sheet.dart:119-130`, `:108-116` vs `schemas.ts:148-151` | Qualitative feedback is silently dropped at the client | confirmed |
| F-16-11 | S3 | `ScheduleScreen` is complete, polished, and unreachable — nothing imports it | `schedule_screen.dart` (single reference: its own declaration) | Scheduling has no entry point even if the backend were fixed | confirmed |
| F-16-12 | S3 | `trips.schedule_status` is written `'pending'` once and never read or updated; `scheduled_trip_dispatch.status='failed'` is in the CHECK constraint and never written | `trips.ts:474`, `migrations/0003:52`, `:62`, `index.ts:308` | No way to query which scheduled rides failed | confirmed |
| F-16-13 | S3 | No re-book from history, no deduplicated recent destinations, no pickup notes | `history_screen.dart:72-76`; no recents endpoint; searched `pickup_note`/`gate` | The three cheapest retention/precision features are all missing | confirmed |
| F-16-14 | S3 | Rating aggregate update is three unbatched D1 statements (insert, AVG, update) | `trips.ts:1111-1133` | Concurrent ratings race; a partial failure leaves `rating_avg` stale | confirmed |
| F-16-15 | S3 | `saved_places` has no type field and no count limit | `0002:72-81`, `user.ts:256-273`, `saved_places_screen.dart:191-194` | Home/Work detected by Arabic string match; a rider can create unbounded rows | confirmed |
| F-16-16 | S3 | `cancelTripSchema.reason` is optional free text with no enum | `schemas.ts:144-146` | No cancellation analytics, no repeat-offender signal, no way to tell "captain never came" from "changed my mind" | confirmed |
| F-16-17 | S4 | Night/time-of-day pricing absent; `surge_multiplier` is a static per-city constant | `trips.ts:387-396` | No demand shaping across the day | confirmed |
| F-16-18 | S4 | `GET /trips/history` is a fixed `LIMIT 50` with no pagination | `trips.ts:606-613` | A frequent rider cannot reach older trips | confirmed |

### F-16-01 — The permanent lockout (S1)

This is the most serious defect in the lifecycle and it is the compound of three individually defensible decisions.

**One.** Booking is guarded against concurrent trips (`trips.ts:362-376`):

```sql
SELECT id FROM trips WHERE rider_id = ? AND status NOT IN ('completed','cancelled') LIMIT 1
```

A hit returns `409 {code:"ACTIVE_TRIP", tripId}`. Sensible on its own — one rider, one live trip.

**Two.** No trip ever expires. `OfferScheduler` runs waves of three captains every 15 seconds (`OfferScheduler.ts:62-63`); when the list is exhausted it calls `teardown()` (`:153-157`), which deletes its alarm and its own storage **and writes nothing to D1**. `cleanup.ts:29-75` never touches `trips`. So a trip that nobody accepts stays `searching`/`offered` for the lifetime of the database.

**Three.** The rider is never told. There is no "no captain found" notification topic in `notifications.ts`; the only scheduled-trip topic in the system goes to admins (`index.ts:322`).

Compose them: **a rider requests a ride at a quiet hour, nobody accepts, and that rider can never book again.** The status stays `searching` forever, the guard fires forever, and the error the client surfaces is a generic English string.

The server does try to help — it returns the offending `tripId` in the 409 body precisely so the client can recover. T09's review of the rider app (recorded in `PROJECT.md`) establishes that the client throws that away: `bootstrap()` never asks for an active trip and the 409 is reduced to an error string. So there is no in-app recovery path in either direction. The rider's account is bricked by a normal, correct use of the product.

Then F-16-02 makes it *routine* rather than unlucky: every scheduled ride is dispatched at 22:00 for a 07:00 pickup, finds nobody, and locks the account overnight.

The fix is small and it is server-side, which is why it is P0.1: a sweeper that expires `searching`/`offered` trips past a TTL, plus a `GET /trips/active` endpoint. Both are hours of work. Neither needs a migration.

### F-16-02 — Scheduled rides dispatch at booking time (S1)

`POST /trips` branches on `scheduledFor` exactly once, at `trips.ts:484-490`, to insert a `scheduled_trip_dispatch` row. The dispatch block at `trips.ts:518-586` — `findNearbyCaptains`, radius filter, `OfferScheduler`, FCM blast — runs **unconditionally**.

So booking a ride for tomorrow morning pushes an offer to ten captains *now*, with a pickup they cannot serve. Captains see phantom offers; the trip burns its entire wave rollout hours early; and the rider is left in `searching` (F-16-01).

The cron that is supposed to do this work does not. `index.ts:283-330` selects due dispatches:

```sql
SELECT ... FROM scheduled_trip_dispatch d JOIN trips t ON t.id = d.trip_id
WHERE d.status = 'pending' AND d.scheduled_for <= ? AND t.status = 'searching'
```

then marks them `dispatched` and **pushes a notification to every admin user** (`:316-326`). That is all it does. It never calls `findNearbyCaptains`, never touches `OfferScheduler`, never notifies a captain. The comment at `:313-316` asserts that trip creation already drives matching — which is true, and is exactly the bug: matching ran at the wrong time. There is also no `LIMIT` on that query.

Supporting defects in the same feature: `schemas.ts:63` validates `scheduledFor` as an ISO datetime with **no minimum lead time and no check that it is in the future** — a past timestamp is accepted and dispatched on the next tick. `trips.schedule_status` is written `'pending'` and never updated (F-16-12). And the rider-facing entry point, `ScheduleScreen`, is never imported by anything (F-16-11), so today the only way to reach this code path is a direct API call.

The feature is not "incomplete". It is wired backwards, and it is the single most reliable way to trigger F-16-01.

### F-16-03 — The cancellation policy that isn't (S1)

Covered factually in §3.3. Why it is S1 rather than S2:

This is a **bidding-first marketplace**. A captain bids, wins, drives fifteen minutes across Cairo to a pickup, reaches `arrived` — and the rider cancels for free, with a one-word optional reason. The captain earns nothing and has no recourse. There is no fee, no grace-period boundary, no count of how often this rider does it, and no reason taxonomy that would even let ops see the pattern (F-16-16). Symmetrically, a captain can abandon an assigned trip with the same zero consequence.

Two-sided marketplaces do not survive this. Captain supply is the scarce side in Egypt, and unlimited free late cancellation is a direct tax on the scarce side. The platform cannot open to real traffic with this gap — which is the S1 bar.

The aggravating factor is that it looks solved. The constants are seeded, they are in the admin console (`admin.ts:429-430`), an operator will set them and believe a policy is live. A dormant setting that an operator trusts is worse than a missing one.

### F-16-04 — Multi-stop is a phantom (S2)

`createTripSchema` accepts a `waypoints` array of `{lat, lng, address?}` (`schemas.ts:64-73`). `POST /trips` serialises it into the `trips.waypoints` column (`trips.ts:475`). And that is the end of its life. `getRoute` (`routing.ts:21-30`) builds:

```
{osrm}/route/v1/driving/{pickup.lng},{pickup.lat};{dropoff.lng},{dropoff.lat}?overview=full&geometries=geojson
```

Two coordinate pairs, always. The waypoints are not in the URL, so distance, duration, geometry and therefore fare are all computed for a straight A→B trip. Neither app has any waypoint UI (searched `waypoint` across `apps/rider` and `apps/captain` — no hits), and the captain's navigation row (`active_trip_panel.dart:399-424`) offers only pickup or dropoff.

Today the blast radius is limited because no client can produce a waypoint. But the endpoint is public and authenticated: anyone who reads the schema can book a three-stop trip and pay the two-point price, and the captain will be asked to drive it. It is S2 now and becomes S1 the day a client ships a UI for it.

### F-16-05 — Nominatim as the only geographic dependency (S2)

`geocode.ts` calls `https://nominatim.openstreetmap.org/reverse` (`:39-40`) and `/search` (`:100-102`) with a proper `User-Agent` (`:48`, `:108`) and `accept-language=ar,en`. KV caching is real and well-judged — 30 days for reverse keyed on 4-decimal coordinates (~11 m), 7 days for search keyed on the lowercased query (`:82`, `:128`), which will absorb most repeat traffic.

What is missing is everything that matters on a cache miss: no rate limiter, no retry or backoff, no circuit breaker, and no fallback provider. On failure `reverseGeocode` returns the raw coordinate string and `searchPlaces` returns `[]` (`:53-54`, `:114`). Searches for `mapbox`, `google`, `here`, `tomtom` find no commercial provider configured anywhere.

Nominatim's usage policy caps absolute use at roughly one request per second and explicitly excludes heavy commercial use; a ride-hailing launch in Cairo is precisely the case it excludes. There is also no local POI table — no `places` or `poi` in any of the 19 migrations — so every landmark lookup is a live upstream call, and Nominatim's Arabic coverage of Cairo POIs is thin. A launch-day burst of first-time pickup points will produce 429s that degrade silently into raw coordinates in the rider's address field.

### F-16-06 / F-16-07 — Receipts are not just missing, they are becoming impossible (S2)

`calculateFare` produces base, distance, time and booking-fee components; `POST /trips` persists only the post-surge, post-discount **total** (`trips.ts:441-481`). Reconstructing a breakdown later needs `distance_km`, `duration_min` and *the rate card that applied at the time* — and `pricing_rules` is mutable with no history table.

So this is a decaying asset: every admin edit to a city's pricing silently invalidates the itemisation of every historical trip in that city. Building receipts in six months will not recover the trips taken before then.

There is no per-trip receipt endpoint at all, and the B2B path stops at a `company_invoices` row with a trip count and a total (`companies.ts:166-204`); the portal returns JSON (`:218-239`). Nothing is rendered, nothing is emailed. Egypt's e-invoicing regime expects itemised documents for corporate billing, so the B2B vertical is not merely inconvenient today — it is not filing-ready. I mark the specific ETA compliance requirement **needs-check** with T25, but the engineering conclusion stands regardless: persist the components now, because the data is being destroyed continuously.

### F-16-08 — Accountability points one way (S2)

The rate endpoint already computes the correct target for either direction (`trips.ts:1103-1107`): a captain calling it produces a row with `to_user_id = rider_id`. But the aggregate update is guarded to captain targets (`:1121`), `users` has no `rating_avg`/`rating_count`, and no captain screen calls it — the `riderRating` localisation key exists in the captain's ARB files and is used by zero widgets. So captain→rider ratings are accepted, stored, and never surface anywhere.

On the other side, no rating value triggers anything: no auto-flag, no review queue, no deactivation. The only lever is a manual `POST /admin/captains/:id/suspend` (`admin.ts:289-310`). A captain sitting at 1.8 stars keeps receiving offers until a human notices in a dashboard.

The result is a product that asks both sides for a rating after every trip and does nothing with either. That is worse than not asking: it trains users that feedback is theatre.

### F-16-09 — The clock is running and nobody is billing it (S2)

`arrived_at` and `started_at` are both stored (`migrations/0001_init.sql`). `arrived → in_progress` is a guarded transition (`trips.ts:906`). The delta between those two timestamps is exactly the captain's waiting time, and it is never read. `pricing_rules.per_min` applies to *driving* duration inside `calculateFare`, not to waiting.

Nor is there a no-show path. `TripStatus` has no such value (`shared/src/index.ts:3-10`); `intercity_bookings.status` includes `no_show` (`migrations/0003:103`) but no endpoint ever writes it. A captain whose rider never appears has two options: sit indefinitely, or cancel — for free, with no record, absorbing the loss (F-16-03).

This is the cheapest S2 in the document to fix. The timestamps exist; only the rule and a config value are missing.

### F-16-10 — The rating sheet drops what it collects (S2)

`rateTripSchema` accepts `comment` up to 500 characters (`schemas.ts:150`). The rider's rating sheet renders a comment field (`rating_sheet.dart:119-130`) and five Arabic quality chips (`:108-116`). `_submit()` sends only the star score. The chips have no backing state at all; the comment is read into a controller and abandoned.

A rider types a paragraph about a bad trip, taps submit, gets a success state, and nothing was transmitted. The server side is already built — this is a client fix measured in minutes, which is why it sits in P0 despite being S2.

## 5. Benchmark gap

**Uber** is the checklist source: scheduled rides with a reserved-driver guarantee, multi-stop, in-trip destination change, waiting-time fees after a free window, tiered cancellation fees with a grace period, two-way ratings with structured tags, emailed itemised receipts, Uber for Business with cost centres, lost and found, and a deep vehicle-option matrix (pet, car seat, WAV, XL). Against that surface Synaptic Go implements the booking spine and the bidding layer, and essentially nothing of the surrounding lifecycle. The gap is not in the middle of the trip — dispatch, realtime, and the negotiation are the most developed parts of this codebase — it is at both ends: **before** (scheduling, places, notes, options) and **after** (waiting/no-show, cancellation economics, ratings that bite, receipts).

**inDrive** is the more instructive comparison, because it is the model this product has chosen. inDrive is deliberately narrow: no pooling, no elaborate vehicle matrix, thin corporate tooling. What it does have, and Synaptic Go does not, is the **negotiation-integrity layer** that a bidding product cannot skip. When the price is agreed between two people rather than set by an algorithm, the platform's whole job is making that agreement stick: the fare the rider accepted must be the fare they are shown throughout (T09 found the rider app displays `estimated_fare` while the server holds `accepted_price`), and the cost of abandoning an agreement must be non-zero on both sides (F-16-03). Copying Uber's pooling or split-fare would be the wrong call here — §3.6 rows 36 and 37 are correctly deprioritised. Copying Uber's cancellation economics is not optional; it is the load-bearing part of the model this product picked.

**Careem** sets the regional bar and is the closest analogue for Egypt specifically. Three things it does that matter here:

1. **Cash-first design.** Cash is the dominant payment method and the whole lifecycle is built around it. Synaptic Go handles the cash commission correctly at completion (`trips.ts:1015-1032`, debiting commission from the captain rather than crediting a payout) — genuinely good work — but cash makes cancellation and no-show fees *harder*, since there is no card to charge. This needs a wallet-debt design decision, raised in §10 Q2.
2. **Corporate accounts as a real product**, with itemised invoices employees can file. Synaptic Go has the data model (`company_id`, `cost_center`, spend limits, monthly generation) and stops before the document (F-16-07).
3. **Delivery as a second vertical on the same driver supply.** Nothing in the schema supports a parcel (§6 P2.6).

One market-specific item deserves separate weight: **female-driver / women-only matching** (§3.6 row 34). Egypt has a real, well-documented segment of women who will not use a service without it, and both Uber and Careem ship variants of it regionally. It is absent — `captains` has no gender column, `createTripSchema` has no preference field. I have placed it in P1 rather than P2 despite the L effort, because it is a demand-side unlock rather than a polish item. That is a product call, not an engineering one, so it is also §10 Q4.

Where Synaptic Go is genuinely ahead of its own maturity level: the offer-cancellation fan-out (`trips.ts:750-795`) is more carefully reasoned than most production dispatch code, the cash-commission handling is correct, and the bidding flow with per-captain server-routed ETAs is a real differentiator. The lifecycle gaps are not a symptom of a weak codebase — they are the parts nobody has reached yet.

## 6. Improvement plan

### P0.1 — Trip expiry sweeper and active-trip recovery

- **Goal** — no rider is ever locked out of booking, and no trip lives forever in a non-terminal state.
- **Design** — extend the existing every-minute cron (`index.ts:267`) with a sweeper that runs before the scheduled-dispatch block:
  - `searching`/`offered` older than `trip_search_ttl_min` (default 10) → `cancelled`, `cancel_reason='no_captain_found'`, push `trip.no_captain` to the rider.
  - `assigned`/`arrived` with no status change for `trip_stale_assign_min` (default 30) → flag into an admin review queue; do not auto-cancel (a captain may be mid-pickup with bad signal).
  - `in_progress` longer than `trip_max_duration_min` (default 240) → flag for admin; never auto-complete, because completion moves money.
  Add `GET /trips/active` returning the rider's current non-terminal trip, and make the `409 ACTIVE_TRIP` response the client's recovery path.
- **Files to change** — `apps/api/src/index.ts` (sweeper), `apps/api/src/lib/cleanup.ts` (house the query), `apps/api/src/routes/trips.ts` (new `GET /active`), `apps/api/src/lib/notifications.ts` (new topic).
- **DB** — none for the sweeper. Three rows into `system_config` via `migrations/0020_trip_lifecycle_config.sql`.
- **API contract** — `GET /trips/active` → `200 {trip: TripWithCaptain|null}`.
- **Effort** — S.
- **Risk** — an over-aggressive TTL cancels trips that would have been accepted. Mitigate by making the TTL config-driven and starting at 10 minutes; rollback is setting it to a very large number, no deploy needed.
- **Acceptance criteria** — a trip with no acceptance is `cancelled` within TTL+60s; the rider receives a push; a rider who force-quits mid-search can book again after TTL without admin help; `GET /trips/active` returns the live trip.
- **Tests** — unit on the sweeper query per status; integration: create → no accept → assert cancelled + notification; regression: an accepted trip is never swept.

### P0.2 — Make scheduled rides dispatch at the scheduled time

- **Goal** — a ride booked for 07:00 is offered to captains near 07:00, not at booking.
- **Design** — three changes:
  1. In `POST /trips`, wrap the dispatch block (`trips.ts:518-586`) in `if (!body.scheduledFor)`. A scheduled trip is created in a new `scheduled` status and inserts its `scheduled_trip_dispatch` row as today.
  2. In the cron (`index.ts:283-330`), replace the admin-notification body with the real dispatch: move the trip `scheduled → searching`, then run the same `findNearbyCaptains` → radius filter → `OfferScheduler` → FCM sequence. Extract that sequence from `trips.ts` into `lib/dispatch.ts` so both callers share one implementation. Add `LIMIT 200` to the due query and process in batches.
  3. Fire dispatch at `scheduled_for − lead_time_min` (default 15), not at `scheduled_for`, so a captain is assigned before the rider is standing outside.
- **Files to change** — `apps/api/src/routes/trips.ts`, `apps/api/src/index.ts`, new `apps/api/src/lib/dispatch.ts`, `packages/shared/src/index.ts` (add `scheduled` to `TripStatus` and `TRIP_TRANSITIONS`: `scheduled → searching, cancelled`).
- **DB** — `migrations/0020`: add `system_config` rows `schedule_lead_time_min=15`, `schedule_min_lead_min=30`, `schedule_max_days=30`. No trips-table change; `schedule_status` starts being maintained (`pending`/`dispatching`/`dispatched`/`failed`).
- **API contract** — `POST /trips` gains validation: `scheduledFor` must be ≥ `schedule_min_lead_min` in the future and ≤ `schedule_max_days` out, else `400 INVALID_SCHEDULE`. New `GET /trips/scheduled` (list) and `POST /trips/:id/cancel` already covers cancelling one.
- **Effort** — M.
- **Risk** — the shared `dispatch.ts` extraction touches the hottest path in the product. Land the extraction as a pure refactor in its own PR with the immediate path unchanged, then switch the cron over.
- **Acceptance criteria** — booking for T+2h pushes no captain offer at booking; at T−15m captains are offered; `schedule_status` reflects the true state; a past or <30min-out `scheduledFor` is rejected; a scheduled trip that finds nobody is expired by P0.1 and the rider is told.
- **Tests** — integration with a fake clock across the boundary; assert zero FCM sends at booking time.

### P0.3 — Cancellation policy engine

- **Goal** — cancelling has defined, symmetric, explainable consequences.
- **Design** — a `resolveCancellation(trip, actor, now)` helper returning `{fee, chargeTo, reasonCode, graceRemaining}`:
  - Rider cancels in `searching`/`offered`, or within `free_cancel_min` of `assigned_at` → free.
  - Rider cancels after the grace window in `assigned`, or at any point in `arrived` → `cancel_fee_egp`, credited to the captain (not the platform — the captain bore the cost).
  - Captain cancels in `assigned`/`arrived` → free to the rider, recorded against the captain's reliability counter.
  - Admin cancels → always free, always logged.
  Read the values from `system_config` (they already exist). Record every cancellation in a `trip_cancellations` row with an **enum** reason. Cash trips cannot be charged at cancel time, so the fee becomes a wallet debit that may go negative and is netted against the next completion — see §10 Q2.
- **Files to change** — `apps/api/src/routes/trips.ts:709-827`, new `apps/api/src/lib/cancellation.ts`, `apps/api/src/lib/schemas.ts` (reason enum), rider `trip_screen.dart` and captain `active_trip_panel.dart` (confirmation sheet showing the fee before it is charged).
- **DB** — `migrations/0021_cancellations.sql`:
  ```sql
  CREATE TABLE trip_cancellations (
    id TEXT PRIMARY KEY,
    trip_id TEXT NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
    cancelled_by TEXT NOT NULL REFERENCES users(id),
    actor_role TEXT NOT NULL CHECK (actor_role IN ('rider','captain','admin')),
    from_status TEXT NOT NULL,
    reason_code TEXT NOT NULL,
    reason_note TEXT,
    fee_piastres INTEGER NOT NULL DEFAULT 0,
    charged INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
  );
  CREATE INDEX idx_tc_user_time ON trip_cancellations(cancelled_by, created_at);
  ```
  Plus `users.cancel_count_30d` maintained by the sweeper, for repeat-offender handling.
- **API contract** — `POST /trips/:id/cancel` body becomes `{reasonCode: enum, note?: string}`; response gains `{fee, charged, graceRemaining}`. New `GET /trips/:id/cancellation-quote` so the client can show the fee *before* confirming.
- **Effort** — M.
- **Risk** — charging a fee wrongly is worse than not charging. Ship in shadow mode first: compute and record `fee_piastres`, set `charged=0`, review a week of real data, then enable charging by config flag.
- **Acceptance criteria** — the quote endpoint matches what is charged; grace window honoured to the second; captain cancellations never charge the rider; every cancellation produces exactly one `trip_cancellations` row; repeat offenders are queryable.
- **Tests** — a table-driven matrix over {actor} × {status} × {inside/outside grace} asserting fee and recipient; idempotency on double-cancel.

### P0.4 — Persist fare components (stop destroying receipt data)

- **Goal** — every trip stores enough to reproduce its own itemised fare forever.
- **Design** — persist the `FareEstimate` breakdown as a JSON column on `trips` at creation, and snapshot the applied `pricing_rules` row id + values. This is P0 not because receipts are urgent but because the data is being lost continuously; every day of delay is unrecoverable history.
- **Files to change** — `apps/api/src/routes/trips.ts:441-481`, `apps/api/src/lib/pricing.ts`.
- **DB** — `migrations/0022_fare_breakdown.sql`: `ALTER TABLE trips ADD COLUMN fare_breakdown TEXT;` and `ALTER TABLE trips ADD COLUMN pricing_snapshot TEXT;` Optionally a `pricing_rules_history` table so future edits are versioned rather than destructive.
- **API contract** — `GET /trips/:id` returns `fareBreakdown` when present.
- **Effort** — S.
- **Risk** — none material; additive columns, nullable, old rows stay null.
- **Acceptance criteria** — a new trip's `fare_breakdown` sums to `estimated_fare`; editing a city's pricing does not change any stored breakdown.
- **Tests** — property test that components sum to the total across randomised distance/duration/surge/discount.

### P0.5 — Client fixes that cost minutes

- **Goal** — stop discarding data the server already accepts.
- **Design** — (a) send `comment` from `rating_sheet.dart:119-130`; (b) give the five chips state and send them once P1.3 adds the field; (c) wire `ScheduleScreen` to a real entry point on the booking sheet; (d) honour the `409 ACTIVE_TRIP` `tripId` by routing to that trip.
- **Files to change** — `apps/rider/lib/screens/ride/rating_sheet.dart`, `apps/rider/lib/services/app_state.dart`, the booking sheet that owns the schedule entry point.
- **DB / API** — none.
- **Effort** — S.
- **Risk** — none.
- **Acceptance criteria** — a typed comment appears in `ratings.comment`; scheduling is reachable from the booking flow; a 409 lands the rider in their live trip.
- **Tests** — widget test asserting the comment reaches the request body.

### P1.1 — Waiting time and no-show

- **Goal** — the captain is paid for waiting, and a rider who never appears has a defined outcome.
- **Design** — add `no_show` as a terminal status reachable only from `arrived`, and only after `no_show_min` (default 8) has elapsed since `arrived_at`, captain-initiated. Waiting fee = `max(0, (started_at − arrived_at) − free_wait_min) × wait_per_min`, computed at completion from timestamps already stored, added to the final fare and surfaced in the breakdown. A no-show charges the same fee as a late cancellation, credited to the captain.
- **Files to change** — `packages/shared/src/index.ts` (status + transitions), `apps/api/src/routes/trips.ts` (complete + new `POST /:id/no-show`), `apps/api/src/lib/pricing.ts`, captain `active_trip_panel.dart` (a countdown then a no-show action).
- **DB** — `migrations/0023`: `system_config` rows `free_wait_min=5`, `wait_per_min_piastres=100`, `no_show_min=8`; `ALTER TABLE trips ADD COLUMN waiting_fee_piastres INTEGER NOT NULL DEFAULT 0;`
- **API contract** — `POST /trips/:id/no-show` → `200 {trip}` / `409` if too early.
- **Effort** — M.
- **Risk** — GPS-less "arrived" claims let a captain start the clock early. Gate `arrived` on proximity to pickup (T06 owns the geofence primitive) and cap the waiting fee.
- **Acceptance criteria** — waiting fee matches the timestamp delta; no-show impossible before the threshold; both appear in the breakdown.
- **Tests** — boundary tests either side of the free window and the no-show threshold.

### P1.2 — Receipts

- **Goal** — a rider can produce a document for any completed trip; a company can file its month.
- **Design** — `GET /trips/:id/receipt` rendering server-side HTML from `fare_breakdown` (P0.4), with a print stylesheet — HTML rather than PDF, because PDF generation on Workers means an extra dependency for no user-visible gain. Share/print from the client's native sheet. For B2B, extend the monthly generation to render the same template over the month's trips.
- **Files to change** — new `apps/api/src/routes/receipts.ts`, `apps/api/src/routes/companies.ts`, rider `trip_detail_screen.dart` (a share action).
- **DB** — none (P0.4 supplies the data).
- **API contract** — `GET /trips/:id/receipt?format=html` → `200 text/html`; `GET /companies/portal/invoices/:id/document`.
- **Effort** — M.
- **Risk** — receipts for trips predating P0.4 cannot be itemised; render those as total-only with an explicit note rather than inventing components.
- **Acceptance criteria** — receipt totals reconcile with `final_fare` to the piastre; a pre-P0.4 trip renders without fabricated numbers.
- **Tests** — golden-file render; reconciliation assertion across a sample of trips.

### P1.3 — Make ratings mean something

- **Goal** — two-way accountability with consequences.
- **Design** — add `users.rating_avg`/`rating_count` and update them for rider targets on the same path that already handles captains; batch the insert+AVG+update into one `db.batch()` to close F-16-14. Add a `tags` column and accept a bounded enum from both apps. Add a captain-side rating sheet. Add a nightly job: any captain with ≥20 ratings and `rating_avg < review_threshold` (default 4.2) enters an admin review queue; below `suspend_threshold` (default 3.5), auto-suspend with notification.
- **Files to change** — `apps/api/src/routes/trips.ts:1090-1137`, `apps/api/src/routes/admin.ts`, `apps/api/src/lib/schemas.ts`, `apps/captain/lib/screens/home/active_trip_panel.dart` (post-trip sheet), `apps/rider/lib/screens/ride/rating_sheet.dart`.
- **DB** — `migrations/0024`: `ALTER TABLE users ADD COLUMN rating_avg REAL; ALTER TABLE users ADD COLUMN rating_count INTEGER NOT NULL DEFAULT 0; ALTER TABLE ratings ADD COLUMN tags TEXT;` plus thresholds in `system_config`.
- **API contract** — `POST /trips/:id/rate` accepts `{score, comment?, tags?: string[]}`; `GET /admin/review-queue`.
- **Effort** — M.
- **Risk** — auto-suspension on thin data. Require a minimum rating count and make both thresholds config-driven.
- **Acceptance criteria** — a captain can rate a rider and the rider's aggregate moves; the three writes are atomic; a captain crossing the threshold appears in the queue within 24h.
- **Tests** — concurrency test issuing simultaneous ratings and asserting the aggregate is exact.

### P1.4 — Booking precision: notes, recents, re-book, typed places

- **Goal** — the rider is found on the first attempt and books a repeat trip in two taps.
- **Design** — add `trips.pickup_note` (≤200 chars, shown to the captain on the offer card and the active-trip panel); add `saved_places.place_type` enum (`home`/`work`/`other`) with a uniqueness constraint on home/work per user and a cap of 20 saved places; add `GET /user/recent-destinations` returning deduplicated recent dropoffs; add a re-book action on the history row that pre-fills the booking sheet.
- **Files to change** — `apps/api/src/routes/trips.ts`, `apps/api/src/routes/user.ts`, `apps/api/src/lib/schemas.ts`, rider `history_screen.dart`, `saved_places_screen.dart`, booking sheet; captain `offer_card.dart`, `active_trip_panel.dart`.
- **DB** — `migrations/0025`: `ALTER TABLE trips ADD COLUMN pickup_note TEXT; ALTER TABLE saved_places ADD COLUMN place_type TEXT NOT NULL DEFAULT 'other';`
- **API contract** — `createTripSchema` gains `pickupNote?`; `GET /user/recent-destinations?limit=5`.
- **Effort** — M.
- **Risk** — low. Cap the note length and strip newlines before it reaches a push payload.
- **Acceptance criteria** — the note reaches the captain's screen; recents deduplicate within ~50 m; re-book pre-fills both endpoints; a user cannot hold two `home` places.
- **Tests** — dedup clustering unit test; end-to-end re-book.

### P1.5 — Geo resilience and a Cairo POI table

- **Goal** — address search that survives launch day.
- **Design** — a `places` table seeded with a few thousand Cairo POIs (airports, malls, hospitals, universities, metro stations, major landmarks) with Arabic and English names, searched **first** with trigram-ish `LIKE` matching before any upstream call; a token-bucket rate limiter in KV in front of Nominatim; exponential backoff plus a circuit breaker that trips to local-only; and a provider interface with a commercial fallback (Mapbox or Google) behind a config flag for when volume justifies it. Also add `accept-language` handling that prefers the app's current locale.
- **Files to change** — `apps/api/src/lib/geocode.ts`, new `apps/api/src/lib/places.ts`, `apps/api/src/routes/search.ts`.
- **DB** — `migrations/0026_places.sql` with `places(id, name_ar, name_en, category, lat, lng, city, popularity)` plus a seed script under `docs/plan/assets/`.
- **API contract** — `GET /search/places?q=` returns local hits first, marked by source.
- **Effort** — M (L including seed curation).
- **Risk** — a stale POI table returns wrong coordinates; add an admin edit surface and a `verified_at` column.
- **Acceptance criteria** — the top 200 Cairo destinations resolve with zero upstream calls; Nominatim traffic stays under 1 rps; a forced upstream outage still returns local results.
- **Tests** — a fixture set of 50 Arabic queries with expected coordinates; load test asserting the rate cap.

### P1.6 — Night pricing and lost-and-found

- **Goal** — demand shaping across the day, and an ops path for left items.
- **Design** — a `pricing_schedules` table of `(city, day_of_week, start_hour, end_hour, multiplier)` consulted at booking, replacing the static `surge_multiplier` read at `trips.ts:387-396` (coordinate with T05, which owns the pricing model). Lost-and-found: a `trip_reports` table with type `lost_item`, reachable from a completed trip in history, landing in the admin queue and opening the existing chat channel with the captain for a bounded window.
- **Effort** — S (night pricing) + M (lost and found).
- **Risk** — schedule overlaps; enforce non-overlapping windows in a CHECK or at write time.
- **Acceptance criteria** — a trip booked at 02:00 picks up the night multiplier; a lost-item report reaches the admin queue and the captain.

### P1.7 — Female-driver matching

- **Goal** — serve a segment that will not otherwise use the product.
- **Design** — `users.gender` (nullable, self-declared, verified against the captain's ID document during onboarding — T25 owns the privacy posture), a `femaleOnly` boolean on `createTripSchema`, and a filter inside the shared dispatch path (P0.2's `lib/dispatch.ts`) so both immediate and scheduled bookings honour it. A rider-side toggle in the booking sheet, visible only where supply exists.
- **DB** — `migrations/0027`: gender on `users`, `female_only` on `trips`.
- **Effort** — L (mostly onboarding, verification and policy, not dispatch).
- **Risk** — thin female-captain supply means long searches; gate the toggle behind a supply check per city and be explicit in the UI about longer waits.
- **Acceptance criteria** — a female-only request is never offered to a male captain; the toggle is hidden where supply is below threshold.

### P2.1 — Multi-stop, properly

- **Goal** — the stored `waypoints` column finally means something.
- **Design** — extend `getRoute` to accept an ordered coordinate list and build the multi-point OSRM URL; accumulate per-leg distance and duration; price the whole polyline; add rider UI to add up to three stops; add captain sequencing that advances leg by leg with a per-leg arrival. Add a `trip_legs` table so each leg's actual timing is recorded.
- **Effort** — L. **Risk** — touches routing, pricing and both apps at once; ship behind a flag, backend first.
- **Acceptance criteria** — a 3-stop trip's fare equals the sum of its legs; the captain's navigation advances per leg.

### P2.2 — In-trip destination change and stop addition

- **Goal** — the most-requested mid-trip action in every ride-hailing product.
- **Design** — `POST /trips/:id/destination` valid only in `in_progress`, re-routes from the captain's current position, re-prices the remainder, and requires captain acknowledgement before it binds. Depends on P2.1's leg model and on T07 for the realtime handshake.
- **Effort** — L. **Risk** — a re-price mid-trip is a money event; it needs the same idempotency discipline as completion (T03).

### P2.3 — Ride options matrix

Pet, luggage, child seat, accessible vehicle — as flags on `vehicle_types` plus captain-declared capabilities, filtered in dispatch. **Effort** — M. Cheap once P1.7 has established a capability filter in the dispatch path.

### P2.4 — Ride for someone else, favourite drivers, recurring rides

Three independent M-sized features sharing one prerequisite: a stable dispatch-preferences structure. Recurring rides in particular must wait for P0.2 — building recurrence on top of a scheduler that dispatches at the wrong time would multiply the defect.

### P2.5 — Corporate depth

Rider-selectable cost centre at booking, self-serve enrolment, and itemised invoice documents (the last falls out of P1.2). **Effort** — M. Coordinate with T20.

### P2.6 — Delivery / courier vertical

- **Goal** — a second demand stream on the same captain supply.
- **Design** — the current trip model is closer than it looks. A parcel trip is a trip with: no passenger, a `recipient` (name + phone, distinct from `rider_id`), item metadata (size class, weight class, declared value, a photo in R2), proof of handover (a code or a signature at both ends), and a different fare curve. The genuinely new pieces are the two-sided handover proof, the recipient — who is not a platform user and needs a tokenised tracking link rather than an account — and the liability model for damaged or lost goods, which is a legal question before it is an engineering one. Reuse: dispatch, realtime, chat, ratings, cancellation. Replace: pricing curve, the in-trip screen on both sides, and history presentation.
- **DB sketch** — `trip_type` enum on `trips` (`ride`/`parcel`), plus `parcel_details(trip_id, recipient_name, recipient_phone, size_class, weight_class, declared_value_piastres, pickup_proof, dropoff_proof, photo_key)`.
- **Effort** — L (multiple sprints). **Owner** — coordinate with T20; this section is scope, not a commitment.

## 7. Phasing

**P0 — before any production traffic.** The S1 set plus the two items whose cost rises every day they wait (fare-component persistence, because history is being destroyed; and the client fixes, because they are free).

| Item | Phase | Effort | Owner type |
|---|---|---|---|
| P0.1 Trip expiry sweeper + `GET /trips/active` | P0 | S | backend |
| P0.2 Scheduled rides dispatch at the right time | P0 | M | backend |
| P0.3 Cancellation policy engine (shadow → enforce) | P0 | M | backend + Flutter |
| P0.4 Persist fare components + pricing snapshot | P0 | S | backend |
| P0.5 Client fixes (comment, schedule entry, 409 recovery) | P0 | S | Flutter |
| P1.1 Waiting time + no-show | P1 | M | backend + Flutter |
| P1.2 Receipts (rider HTML + B2B document) | P1 | M | backend |
| P1.3 Two-way ratings with consequences | P1 | M | backend + Flutter + admin |
| P1.4 Pickup notes, recents, re-book, typed places | P1 | M | backend + Flutter |
| P1.5 Geo resilience + Cairo POI table | P1 | M–L | backend + ops |
| P1.6 Night pricing + lost and found | P1 | S + M | backend + admin |
| P1.7 Female-driver matching | P1 | L | backend + Flutter + ops |
| P2.1 Multi-stop end to end | P2 | L | backend + Flutter |
| P2.2 In-trip destination change | P2 | L | backend + Flutter |
| P2.3 Ride options matrix | P2 | M | backend + Flutter |
| P2.4 Ride for someone else / favourites / recurring | P2 | M each | backend + Flutter |
| P2.5 Corporate depth | P2 | M | backend + admin |
| P2.6 Delivery vertical | P2+ | L | all |

P0 is roughly **two engineer-weeks** (one backend, one Flutter, overlapping) and it is the difference between "cannot open the doors" and "can take real traffic". Everything in P0 except P0.3 is additive and reversible.

The sequencing logic: **P0 stops the platform hurting its own users** (lockouts, phantom offers, uncompensated captains, data destruction). **P1 makes the trip economics and the feedback loop real** — this is the set that decides whether captains stay. **P2 is competitive surface** — the features a rider notices in a comparison, but none of which matter if P0 and P1 are missing.

One ordering constraint worth stating: **P0.2 before any recurrence work**, and **P0.4 before P1.2**, because a receipt cannot be built from data that was never stored.

## 8. Metrics

Nothing in this list is instrumented today — T22 notes there is no analytics SDK in the rider app at all — so every "current" below is unmeasured unless stated.

| Metric | Definition | Current | Target |
|---|---|---|---|
| Locked-out riders | Distinct riders with a non-terminal trip older than 1h | unknown; structurally unbounded | 0 |
| Search abandonment | `searching`/`offered` trips expired with no captain ÷ all requests | unmeasurable (never expire) | <8%, and 100% notified |
| Scheduled-ride fulfilment | Scheduled trips reaching `assigned` by `scheduled_for` | ~0 by design (dispatch fires early) | >90% |
| Phantom offer rate | Offers sent >30 min before pickup ÷ all offers | 100% of scheduled-trip offers | 0 |
| Cancellation rate by actor and state | `trip_cancellations` grouped by `actor_role` × `from_status` | not recorded | rider-after-`arrived` <2% |
| Cancellation fee leakage | Fees owed under policy ÷ fees actually charged | 0% charged | >95% (post shadow mode) |
| Captain deadhead loss | Uncompensated `assigned`→`cancelled` distance | not recorded | <1 km per 100 trips |
| Waiting time paid | Waiting minutes billed ÷ waiting minutes elapsed | 0% | >90% beyond the free window |
| Rating coverage | Trips rated by rider / by captain | rider partial; captain 0% | >60% / >40% |
| Rating actionability | Captains crossing review threshold who are actually reviewed | no threshold exists | 100% within 24h |
| Receipt availability | Completed trips with a reproducible itemised receipt | 0% | 100% of post-P0.4 trips |
| Geo upstream dependency | Place lookups served locally ÷ all lookups | 0% (KV cache aside) | >70% after P1.5 |
| Nominatim error rate | 4xx/5xx ÷ upstream calls | unmeasured | <1%, and never user-visible |
| Re-book share | Trips created from a history re-book | 0 (no such action) | >15% of repeat riders |
| Stuck-trip admin interventions | Manual status fixes per week | unmeasured | 0 |

## 9. Cross-cutting notes

**T27 — Cross-app parity.** The two apps have drifted badly around the trip lifecycle specifically:
- `trip_chat_screen.dart` exists in both and they are not the same product. The captain's has a WebSocket subscription plus a 6-second poll, a typing indicator, reverse-ordered scrolling, `AlignmentDirectional` bubbles (RTL-correct) and a sending spinner; the rider's fetches once in `initState` and never again, with hardcoded `centerLeft`/`centerRight` alignment. A captain's reply is invisible to the rider until they leave and re-enter. **The captain's implementation is the better one — parity work here must pull the rider up, not average the two.**
- Trip-state vocabulary diverges for the same status: `assigned` is "كابتن في الطريق" to the rider and "في الطريق إليك" to the captain; `arrived` is "وصل الكابتن" versus "انتظار الراكب". One status, four strings.
- The captain has no scheduled-trip surface of any kind, and no rating-the-rider surface despite the `riderRating` key existing in its ARB files.

**T05 — Pricing.** Three lifecycle-driven pricing requirements land in your model: waiting-time rate (P1.1), a time-of-day schedule to replace the static per-city `surge_multiplier` read at `trips.ts:387-396` (P1.6), and per-leg pricing for multi-stop (P2.1). Also: `trips.ts:429` computes commission from the estimate at booking, while `accept-bid` correctly recomputes from the accepted price (`:1301-1302`) — consistent today, but any future path that changes the fare after creation must recompute too.

**T06 — Dispatch.** P0.2 proposes extracting the dispatch sequence (`trips.ts:518-586`) into `lib/dispatch.ts` shared by the immediate and cron paths. That is your surface; I would rather you own the extraction than have me specify it. Also, `arrived` is captain-asserted with no proximity check — a geofence primitive there would underpin the waiting-time clock in P1.1.

**T03 / T08 — Money and data.** Cancellation fees and waiting fees are new money movements and must use the same `idempotency_key` discipline as completion (`trips.ts:1019`). Separately: `trips.ts:974` writes only the REAL `final_fare`, leaving `final_fare_piastres` from migration 0005 unmaintained — the integer columns are backfilled once and then drift. Any new fee column should be piastres-only.

**T07 — Realtime.** Two lifecycle events have no transport: "no captain found" (P0.1) and the captain's acknowledgement of an in-trip destination change (P2.2). Also the rider app ignores five of the seven event types `TripRoom` emits.

**T09 — Rider app.** Your finding that `bootstrap()` never requests an active trip and that the `409 ACTIVE_TRIP` `tripId` is discarded is the client half of my F-16-01; the server half (no expiry) is mine and P0.1 fixes it. Neither fix alone is sufficient — please land them together. `ScheduleScreen` also needs an entry point (F-16-11).

**T10 — Captain app.** The captain has no cancel affordance at any state (`active_trip_panel.dart:441-475`) even though the API permits it; and there is no waiting-time or no-show surface for P1.1 to attach to.

**T17 — Safety and trust.** Ratings currently have no consequence path (F-16-08); the review queue proposed in P1.3 is the natural place for your trust signals to land. Note `trip_share_tokens` exists for location sharing — it is not pooling, despite the name overlap.

**T18 — Fraud.** `trip_cancellations` (P0.3) with an enum reason is the signal you need for cancellation abuse; `users.cancel_count_30d` is proposed there. Bid declines are currently a client-local `Set` and never reach the server, discarding a second useful signal.

**T20 — Verticals.** §6 P2.6 scopes the courier vertical against the current trip model. The B2B invoice document (P1.2) overlaps your track; take it if it fits better there.

**T25 — Privacy and compliance.** Two items: whether Egyptian e-invoicing obligations apply to B2B trip invoices (marked `needs-check` in F-16-06/07), and the privacy posture for self-declared gender in P1.7.

**T14 — Localisation.** Cancellation reason codes (P0.3), rating tags (P1.3) and the no-captain-found notification (P0.1) all introduce new user-visible strings; they should enter the ARB pipeline rather than becoming more inline literals.

## 10. Open questions

**Q1 — Should a rider be allowed more than one active trip?**
Today the answer is no, enforced by `trips.ts:362-376`, and that guard is what turns a stuck trip into a lockout. Options: (a) keep the guard and rely on P0.1's expiry; (b) drop the guard entirely; (c) keep it for immediate trips but allow N concurrent *scheduled* trips.
**Recommendation: (c).** One live ride at a time is correct, but a rider should be able to hold several future bookings — that is the whole point of scheduling, and it is a real limitation once P0.2 lands.

**Q2 — How do we charge a cancellation or no-show fee on a cash trip?**
There is no card to charge. Options: (a) don't charge cash riders — simple, but that is most of the market and the policy becomes decorative; (b) a negative wallet balance netted against the next trip; (c) block new bookings until the debt is settled.
**Recommendation: (b) with a cap**, escalating to (c) past a threshold. Coordinate with T03: this makes `wallet_balance` legitimately negative, which the ledger must model deliberately rather than by accident.

**Q3 — Who receives the cancellation fee?**
Options: platform, captain, or split. **Recommendation: the captain**, in full, for late rider cancellations. The captain bore the deadhead cost; routing the fee to the platform would read as rent-seeking to the scarce side of the marketplace. The platform's interest is served by the deterrent, not the revenue.

**Q4 — Is female-driver matching a launch feature or a fast-follow?**
It is an L, and it depends on female captain supply that may not exist yet. Options: (a) P0 — delays launch; (b) P1 — my placement; (c) P2 — treats it as polish.
**Recommendation: (b)**, with the toggle gated behind a per-city supply threshold so it appears only where it can actually be honoured. Shipping it with no supply is worse than not shipping it.

**Q5 — Multi-stop: build it, or remove the column?**
The `waypoints` column, its validator and its storage all exist and none of it works (F-16-04). Leaving a half-wired money-affecting feature in a public API is a liability. Options: (a) build it (P2.1, L); (b) reject `waypoints` with a `501` until it is built; (c) leave as is.
**Recommendation: (b) now, (a) in P2.** A one-line rejection closes the exposure today and costs nothing.

**Q6 — Does the negotiated price bind the platform to a metered reconciliation?**
In a bidding product the rider and captain agree a price up front, which is arguably *better* than a meter — no surprises. But it means a trip that runs 40 minutes longer than estimated pays the same. Options: (a) the agreed price is final, always (current behaviour); (b) agreed price plus waiting time only (P1.1's proposal); (c) full metered reconciliation with a variance band.
**Recommendation: (b).** It preserves the product's core promise while compensating the one delay the captain cannot control. (c) would reintroduce exactly the fare anxiety that bidding exists to remove.

**Q7 — Is the courier vertical a P2 feature or a separate product track?**
§6 P2.6 scopes it as an extension of the trip model, which is technically accurate but understates the operational load: different liability, different support flows, different captain onboarding.
**Recommendation: treat it as a separate track owned with T20**, starting only after P1 is complete. Adding a second vertical on top of a lifecycle that cannot yet expire a trip or charge a cancellation fee would compound both problems.
