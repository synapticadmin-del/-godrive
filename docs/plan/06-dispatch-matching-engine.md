# 06 — Dispatch & Matching Engine

> Track: A — Foundation & safety-critical · Reviewer: chat-20260801-1230-7b4e · Date: 2026-08-01 (UTC)
> Base commit reviewed: `f906e0b06240ea84b20ef5c7b5633fd9abe02f8b` (`main`)

## 1. Scope

This document covers the path a trip takes from `POST /trips` to a captain
tapping accept: geospatial indexing of captain positions, candidate discovery,
candidate ranking, the staged offer rollout, the accept race, online-state and
location-freshness integrity, fairness between captains, scheduled-trip
dispatch, the no-supply path, reassignment after a captain cancels, and the
Durable Object footprint that all of this runs on.

It covers the dispatch-relevant slice of three surfaces: the API
(`apps/api/src/routes/trips.ts`, `apps/api/src/routes/captain.ts`, the four
Durable Objects), the captain app's supply-side behaviour (location cadence,
online state, offer receipt, decline), and the rider app's demand-side
behaviour only where it changes time-to-match or strands a request.

**Explicitly not covered here:**

| Out of scope | Owner |
|---|---|
| Fare maths, surge coefficients, bid pricing economics | T05 |
| WebSocket/Durable Object transport correctness, `TripRoom`, hibernation semantics | T07 |
| Object-level authorisation and IDOR generally | T02 |
| Migration hygiene, index strategy beyond dispatch queries | T08 |
| Rider and captain end-to-end journeys as product experiences | T09, T10 |
| Duplicated screens and cross-app vocabulary drift | T27 |
| Notification transport, FCM delivery reliability, DLQ behaviour | T19 |
| OSRM routing accuracy and geocoding quality | T21 |

Where a dispatch finding has a consequence in one of those tracks it appears in
§9 with the track named, not fixed here.

One structural note before the evidence: the offer rollout introduced by PR #14
is real and correctly implemented **inside its own Durable Object**, but it is
not the only channel that carries an offer to a captain. Two other channels
deliver the same trip to a wider audience at t=0. Most of what follows is
downstream of that fact.

## 2. What I actually read

Every file below was downloaded at commit `f906e0b0` and read from disk with
real line numbers. Line citations throughout this document refer to that
snapshot.

**API — Durable Objects**

| File | Lines | Note |
|---|---|---|
| `apps/api/src/durable-objects/GeoCell.ts` | 82 | Read in full. Captain presence per geohash cell; heartbeat, offline, nearby, expiry alarm. |
| `apps/api/src/durable-objects/OfferScheduler.ts` | 158 | Read in full. The staged wave rollout, its alarm, and teardown. |
| `apps/api/src/durable-objects/CaptainInbox.ts` | 255 | Read in full. Per-captain WebSocket inbox, pending-auth proxy handshake, broadcast. |
| `apps/api/src/durable-objects/TripRoom.ts` | 290 | Skimmed — read for `broadcastTrip` semantics only; T07 owns it. |

**API — routes and lib**

| File | Lines | Note |
|---|---|---|
| `apps/api/src/routes/trips.ts` | 1371 | Read the dispatch-relevant regions in full: `filterByCaptainRadius` (46–71), `POST /estimate` (315–344), `POST /` create+dispatch (348–600), `POST /:id/cancel` (709–827), `POST /:id/accept` (829–889), bidding (1143–1370). Skimmed the rest. |
| `apps/api/src/routes/captain.ts` | 700 | Read `POST /online` (131–188), `POST /location` (190–240), search-radius write (306–320), `GET /nearby-requests` (328–438), `GET /offers` (439–498). Skimmed onboarding/documents. |
| `apps/api/src/index.ts` | 372 | Read the `scheduled()` cron handler in full (266–336); skimmed routing setup. |
| `apps/api/src/lib/nearby.ts` | 105 | Read in full. Neighbourhood cell derivation and the parallel merge. |
| `apps/api/src/lib/pricing.ts` | 38 | Read in full — `cellKey` lives here (36–38). |
| `apps/api/src/lib/routing.ts` | 173 | Skimmed — OSRM call shape and fallback, for the latency budget. |
| `apps/api/src/lib/utils.ts` | 241 | Skimmed — `resolveSearchRadiusKm`, `canTransition`, `nowIso`. |
| `apps/api/src/lib/notifications.ts` | 408 | Skimmed — `pushToUser` shape, for the latency budget. |
| `apps/api/src/lib/types.ts` | 102 | Skimmed — `DbTrip`, `DbCaptain`, `TripStatus`. |
| `apps/api/src/lib/schemas.ts` | 331 | Skimmed — `createTripSchema`, `captainLocationSchema`, `captainOnlineSchema`. |
| `apps/api/wrangler.toml` | 180 | Read DO bindings (23–41), cron triggers (62–66), prod overrides (120–140). |
| `packages/shared/src/index.ts` | — | Read `encodeGeohash` (129) and `geohashCellSpan` (181–191); the cell geometry in §3 is derived from these. |

**Migrations** — `0008_rejection_reason_and_online_guard.sql` (6), `0009_captain_city.sql` (17),
`0018_captain_search_radius.sql` (20), `0019_trips_captain_status_index.sql` (33). All four read in full.

**Captain app** (read by a subagent under my direction, every claim line-cited and spot-checked by me against the backend contract)

`apps/captain/lib/services/captain_state.dart` (1189) — location stream, online toggle, offers poll, decline, lifecycle.
`apps/captain/lib/services/offers_ws.dart` — offers socket, backoff, heartbeat.
`apps/captain/lib/widgets/offer_card.dart` — countdown, accept, 409 handling, counter-offer.
`apps/captain/lib/screens/home/nearby_requests_screen.dart` (366) — the mounted browse surface.
`apps/captain/lib/screens/home/available_trips_tab.dart` (303) — **dead file, never mounted**.
`apps/captain/lib/services/fcm_service.dart`, `apps/captain/lib/screens/home/main_shell.dart` — skimmed.

**Rider app** (same arrangement)

`apps/rider/lib/screens/trip/trip_screen.dart` — searching panel, WS, poll, cancel.
`apps/rider/lib/screens/home/home_screen.dart` — nearby-cars probe.
`apps/rider/lib/screens/home/fare_estimate_sheet.dart` — booking call and its error path.
`apps/rider/lib/screens/ride/captain_bids_sheet.dart` — bid list poll.
`apps/rider/lib/services/app_state.dart`, `apps/rider/lib/services/trip_ws.dart` — skimmed.

**Not read, and it matters:** there are no tests anywhere near dispatch. I
searched for a test directory under `apps/api` and found nothing exercising
`GeoCell`, `OfferScheduler`, the accept race, or `findNearbyCaptains`. Every
behaviour below was established by reading code, not by running it. Anything I
could not establish that way is labelled `needs-check` and never assumed safe.

## 3. How it works today

### 3.1 The cell grid

Captain positions are bucketed by `cellKey(city, lat, lng)` —
`` `${city}:${encodeGeohash(lat, lng, 5)}` `` (`apps/api/src/lib/pricing.ts:36-38`).
The key names a `GeoCell` Durable Object instance via
`idFromName` (`apps/api/src/routes/captain.ts:172-173`, `apps/api/src/lib/nearby.ts:74`).

Geohash precision 5 is 25 bits, interleaved longitude-first, giving 13
longitude bits and 12 latitude bits (`packages/shared/src/index.ts:181-191`).
That is `180 / 2^12 = 0.043945°` of latitude and `360 / 2^13 = 0.043945°` of
longitude. At Cairo's latitude (~30.04°N) one cell is therefore about
**4.89 km north-south by 4.24 km east-west**, and the 3×3 neighbourhood spans
roughly **14.7 km × 12.7 km**, reaching **~9.7 km from the pickup to the far
corner**.

Two comments in the codebase state this reach as "~7km"
(`apps/api/src/routes/trips.ts:525`, `migrations/0018_captain_search_radius.sql:5`).
Both understate it by about 40%. This matters for §3.4.

Note that the city string is part of the key. Two captains 500 m apart on
opposite sides of the Cairo/Giza administrative line, whose apps report
different `city` values, occupy **different DO namespaces entirely** and can
never see each other's trips regardless of geography.

### 3.2 Getting into a cell

There are exactly two writers of captain presence, and both live in
`apps/api/src/routes/captain.ts`:

- `POST /captain/online` (131–188) — writes `is_online`, `last_lat/lng`,
  `last_seen_at`, `city` to D1 (164–169), then POSTs `/heartbeat` to the cell
  when going online or `/offline` when going offline (171–185).
- `POST /captain/location` (190–240) — writes the same D1 columns and forces
  `is_online = 1` (205–209), then POSTs `/heartbeat` to the cell (211–221).
  Rate limited to **30 requests per 60 s per captain** (192–197).

`GeoCell` stores one record per captain keyed `captain:<userId>` with a
server-side `lastSeen: Date.now()` (`GeoCell.ts:22-30`). There is no validation
that the heartbeating user is approved, is not mid-trip, or that the claimed
lat/lng is anywhere near their previous one.

Expiry is two-tier and the tiers disagree:

- `/nearby` skips any record older than `maxAgeMs`, defaulting to **120 000 ms**
  (`GeoCell.ts:49`, applied at 56). No caller ever overrides it —
  `findNearbyCaptains` builds the URL without the parameter
  (`apps/api/src/lib/nearby.ts:76`).
- The expiry alarm deletes records older than **180 000 ms**
  (`GeoCell.ts:73`) and re-arms itself at +60 s while any captain remains
  (`GeoCell.ts:77-80`).

So a captain is a **candidate** for 120 s after their last heartbeat, and a
**resident** of the cell for 180 s. The 60 s window between is a record that
exists, costs storage and alarm wakeups, and can never be matched.

### 3.3 Candidate discovery

`findNearbyCaptains(env, city, lat, lng, limit)` (`apps/api/src/lib/nearby.ts:62-105`)
derives the 9 neighbourhood keys via `neighbourhoodCellKeys` (40–53), which steps
one full cell span in each direction with a `1e-7` nudge to avoid landing back in
the origin cell (23, 47–48). This is a genuine improvement over the previous
fixed-150 m ring the comment describes (28–33), and it is correct: a full-span
step always lands inside the adjacent cell regardless of where the rider sits
within their own.

All 9 cells are queried in parallel, each failure swallowed so one bad cell
cannot blind the neighbourhood (71–87). Results merge by `userId`, closest
reading wins (92–100), then sort by distance and slice to `limit` (102–104).

Each cell is asked for `limit` captains, so up to `9 × limit` records are
fetched to return `limit`. At the dispatch call site that is up to 90 fetched
for 10 returned.

**There is no distance cutoff anywhere in this function.** A captain 9.7 km away
in a corner cell is a valid candidate and will be returned if the neighbourhood
is otherwise empty.

### 3.4 Ranking

`GeoCell` sorts by `distanceKm` ascending (`GeoCell.ts:61`), computed as
`haversineKm` — **straight-line** (`GeoCell.ts:57`). `findNearbyCaptains` merges
and sorts by the same field (`apps/api/src/lib/nearby.ts:103`).

That is the entire ranking function. There is no routed distance, no ETA, no
traffic, no rating, no acceptance rate, no idle time, no completion rate, and no
vehicle-type match. The trip carries a `vehicle_type_id`
(`apps/api/src/routes/trips.ts:471`) and it is never read again on the dispatch
path — a motorcycle captain is offered a 4-seater booking.

In Cairo, straight-line distance and drive time diverge badly: the Nile, the
Ring Road, and the one-way system mean a captain 1.2 km away across the river
can be 20 minutes out while one 3 km away on the same corniche is 6 minutes out.
Dispatch ranks the first one higher, every time.

### 3.5 The radius filter

After discovery, `filterByCaptainRadius` (`apps/api/src/routes/trips.ts:46-71`)
loads `search_radius_km` for the candidate set in one `IN` query (53–58) and
drops any candidate whose `distanceKm` exceeds their own configured radius
(64–66). On error it fails open and returns everyone (67–70).

`0018_captain_search_radius.sql:18-20` adds the column and backfills every
captain to **15 km**. Since the neighbourhood can only reach ~9.7 km (§3.1), the
default radius **never excludes anybody**. The filter only has an effect for
captains who have manually lowered their radius in the app. This is not wrong,
but the migration's stated purpose — stopping captains being notified about
trips outside their range — is only achieved for the minority who changed the
setting.

### 3.6 Create → dispatch

`POST /trips` (`apps/api/src/routes/trips.ts:348-600`), in order:

1. Reject if the rider already has a trip whose status is not `completed` or
   `cancelled` (362–376) → `409 ACTIVE_TRIP` carrying the existing `tripId`.
2. Resolve pricing, route via OSRM, apply surge and promo (378–428).
3. Resolve B2B company binding (432–436).
4. `INSERT` the trip with status `'searching'` (441–481).
5. If `scheduledFor` was supplied, insert a `scheduled_trip_dispatch` row
   (483–491).
6. `findNearbyCaptains(..., 10)` in parallel with the audit write (518–521).
7. `filterByCaptainRadius` (531).
8. **If any candidate survives**: flip status to `'offered'` (537–539), log the
   candidate list (540–542), hand the first 10 to a per-trip `OfferScheduler`
   (561–571), then `await` an FCM push to **all 10** (574–585).
9. Re-read the trip, broadcast to the trip room, respond (588–599).

If no candidate survives, none of step 8 happens. The trip stays `'searching'`
and the response carries `nearbyCaptains: []`. Nothing else is scheduled.

### 3.7 The wave rollout

`OfferScheduler` is one DO per trip, `idFromName(tripId)`
(`apps/api/src/routes/trips.ts:561-563`). `WAVE_SIZE = 3`,
`WAVE_DELAY_MS = 15_000` (`OfferScheduler.ts:62-63`).

`/schedule` stores the candidate list and fires wave 0 immediately
(`OfferScheduler.ts:69-81`). `pushWave` slices `[waveIndex, waveIndex+3)`,
pushes to each captain's `CaptainInbox` best-effort (109–121), advances the
index, and arms an alarm at +15 s if candidates remain, otherwise tears down
(123–130). The alarm re-reads trip status from D1 and stops the rollout the
moment the trip leaves `searching`/`offered` (134–151) — this guard is correct
and closes the obvious race with cancellation.

With the maximum 10 candidates the schedule is: wave 1 at t=0 (3 captains),
wave 2 at t=15 s, wave 3 at t=30 s, wave 4 at t=45 s (1 captain). **Total time
to exhaust the candidate list: 45 seconds.**

Then `teardown()` runs (`OfferScheduler.ts:129`) — `deleteAlarm()` plus
`deleteAll()` (154–157). The DO erases itself the instant the last wave is
pushed. There is no expiry alarm, no unfulfilled marker, no notification. See
§4 F-06-04.

### 3.8 The other two channels

The wave rollout governs one delivery channel. Two others carry the same offer
to a wider audience with no staging at all:

**FCM.** Immediately after scheduling the waves, `POST /trips` pushes to
`nearby.captains.slice(0, 10)` — every candidate, at t=0
(`apps/api/src/routes/trips.ts:574-585`). The comment at 572–573 is explicit
that this is deliberate ("push is what wakes a captain whose app is closed, so
it still reaches everyone who could accept"). The intent is sound; the effect is
that captains 4–10, who are not supposed to see this trip for 15 to 45 seconds,
get a phone notification about it immediately.

**The offers poll.** `GET /captain/offers` (`apps/api/src/routes/captain.ts:439-498`)
returns open trips filtered only by city (462–467) and the captain's own radius
(483–491). It does not consult the candidate list, the wave index, or the
`OfferScheduler` at all. Any online captain in the city whose radius covers the
pickup sees the trip on their next poll — 8 s if their socket is down, 60 s if
it is up (`captain_state.dart:758,763`).

The consequence is in §4 F-06-06.

### 3.9 The accept path

`POST /trips/:id/accept` (`apps/api/src/routes/trips.ts:829-889`):

1. Load the captain row; reject unless `approval_status === 'approved'` or admin
   (834–839).
2. Reject if `!captain.is_online` and not admin (842–844) — the PR #4 online
   guard, and it is real.
3. Reject unless trip status is `searching` or `offered` (846–852).
4. Reject if this captain already has a trip in `assigned`/`arrived`/`in_progress`
   (854–859).
5. **The lock:** a conditional `UPDATE ... WHERE id = ? AND status IN
   ('searching','offered')` (861–866), followed by a check on
   `updateRes.meta.changes === 0` → `409 TRIP_TAKEN` (868–870).

Step 5 is correct. D1 is SQLite with a single writer; the `WHERE` clause makes
the transition atomic and `changes === 0` is the reliable signal that another
captain got there first. **Two captains cannot both win a trip.** This is the
one part of the dispatch path I would ship as-is.

What the accept path does *not* do: it never checks that this captain was ever a
candidate, was in a wave that has fired, is within any distance of the pickup,
or is in the same city. See F-06-12.

### 3.10 Supply-side freshness

The captain app pushes location on a `Geolocator` position stream with
`distanceFilter = 50` m when idle and `10` m on-trip
(`apps/captain/lib/services/captain_state.dart:619-626`), calling
`POST /captain/location` on each fix (673–683). **There is no periodic timer.**

On `AppLifecycleState.paused`/`inactive`/`hidden` the app cancels the position
stream and the offers poll outright (`captain_state.dart:1083-1090`), and
`_startLocationStream` refuses to start while paused (638–639).

Neither of these paths calls `POST /captain/online {online:false}`. The D1
`is_online` column stays `1`. Consequences in F-06-02 and F-06-03.

### 3.11 Scheduled trips

`wrangler.toml:62-66` sets `crons = ["*/1 * * * *", "0 3 1 * *"]` and the
handler is `apps/api/src/index.ts:267-336`. The scheduled-trip block (283–331)
selects due rows joined to trips `WHERE d.status = 'pending' AND d.scheduled_for
<= ? AND t.status = 'searching'` (285–294), marks them `'dispatched'` (307–311),
and then **pushes a notification to admins** (316–327).

That is the whole handler. It never calls `findNearbyCaptains`, never creates an
`OfferScheduler`, never touches a `CaptainInbox`, and never flips the trip to
`'offered'`. See F-06-01.

### 3.12 Cancellation and reassignment

`POST /trips/:id/cancel` (`apps/api/src/routes/trips.ts:709-827`) sets the trip
to `'cancelled'` (727–731) after a `canTransition` guard (723–725), then
branches on `cancelledByRider = user.id === trip.rider_id` (739).

When a **rider** cancels an open request the handler does the right thing: it
tears down the `OfferScheduler` (756–763) and fans a `trip.cancelled` event out
to a *wider* neighbourhood than dispatch used — limit 25 vs 10 (768–774) — so
no captain is left holding a card for a dead trip (775–793). The reasoning in
the comment (741–752) is sound and the wider sweep is the right call.

When a **captain** cancels, none of that runs. The trip is simply `'cancelled'`
and the rider is pushed a "sorry, cancelled" notification (812–820). There is no
re-dispatch. See F-06-05.

## 4. Findings

| ID | Sev | Finding | Evidence (`path:line`) | Impact | Confidence |
|---|---|---|---|---|---|
| F-06-01 | S1 | Scheduled trips are dispatched at **booking** time, not at the scheduled time; the cron only notifies admins and its `WHERE` can never match | `apps/api/src/routes/trips.ts:483-491`, `518-586`; `apps/api/src/index.ts:283-331` | A trip booked at 22:00 for 07:00 is offered to captains at 22:00 with no date shown. Accepted overnight, or never dispatched at all. The feature is non-functional. | confirmed |
| F-06-02 | S1 | A stationary online captain stops being a dispatch candidate after 120 s — location is pushed only on 50 m of movement, with no periodic heartbeat | `apps/captain/lib/services/captain_state.dart:619-626`, `673-683`; `apps/api/src/durable-objects/GeoCell.ts:49,56` | The captain most likely to accept — parked, waiting, engine off — is exactly the one who disappears. Supply collapses to only moving captains. | confirmed |
| F-06-03 | S1 | Backgrounding the captain app cancels the GPS stream and the offers poll entirely, while D1 keeps `is_online = 1` | `apps/captain/lib/services/captain_state.dart:1083-1090`, `638-639`; `apps/api/src/routes/captain.ts:164-169` | Checking WhatsApp for two minutes removes a captain from dispatch with no indication. The app still shows "online". | confirmed |
| F-06-04 | S1 | An unmatched trip never leaves `searching`/`offered`. No timeout, no unfulfilled state, no rider notification — and it blocks the rider from booking again | `apps/api/src/durable-objects/OfferScheduler.ts:102-105`, `123-130`; `apps/api/src/routes/trips.ts:362-376`; `apps/rider/lib/screens/trip/trip_screen.dart:460-471`; `apps/rider/lib/screens/home/fare_estimate_sheet.dart:217-223` | Zero-supply request = permanent spinner, then a permanent lockout from the product. The rider cannot book again until someone cancels a trip they may not be able to reach. | confirmed |
| F-06-05 | S1 | A captain cancelling after accepting kills the trip outright — no re-dispatch, no return to the queue | `apps/api/src/routes/trips.ts:709-737`, `753` | Every captain cancellation becomes a lost booking and a rider who must start over, at the moment they are already waiting. | confirmed |
| F-06-06 | S2 | The staged wave rollout is defeated by two parallel channels: FCM blasts all 10 candidates at t=0, and `GET /captain/offers` hands the trip to **every** online captain in the city within radius | `apps/api/src/routes/trips.ts:574-585`; `apps/api/src/routes/captain.ts:462-491`; `apps/captain/lib/services/captain_state.dart:758,763` | PR #14's stated goal — stop the ~10-captain sprint — is not achieved. The race is now larger than before, because the poll has no candidate list at all. | confirmed |
| F-06-07 | S2 | Losing captains are never told the trip was taken; accept fans out nothing | `apps/api/src/routes/trips.ts:861-889` | Dead cards sit on screens until tapped. The captain learns by failing. Rider-cancel gets a proper fanout; accept does not. | confirmed |
| F-06-08 | S2 | Ranking is straight-line haversine only — no ETA, rating, acceptance rate, idle time, or vehicle-type match | `apps/api/src/durable-objects/GeoCell.ts:57,61`; `apps/api/src/lib/nearby.ts:103`; `apps/api/src/routes/trips.ts:471` | Nearest-by-crow-flies is the wrong captain across a river or a one-way system. `vehicle_type_id` is stored and never read. | confirmed |
| F-06-09 | S2 | Decline is client-local only; the server never learns a captain rejected | `apps/captain/lib/services/captain_state.dart:1041-1044`; `apps/captain/lib/widgets/offer_card.dart:117-126` | Three instant declines still cost the rider the full 15 s wave delay. No rejection analytics, no wave acceleration, and declined trips resurface after a force-quit. | confirmed |
| F-06-10 | S2 | No fairness mechanism anywhere: no cooldown after decline, no round-robin, no idle-time weighting, no cherry-picking control | absence across `GeoCell.ts`, `nearby.ts`, `OfferScheduler.ts`, `trips.ts:518-586` | The nearest captain to a hotspot receives wave 1 of every trip, indefinitely. Captains 200 m further away idle. High-value trips get skimmed with zero consequence. | confirmed |
| F-06-11 | S2 | `GET /captain/offers` applies `LIMIT 20` **before** the radius filter is applied in JS | `apps/api/src/routes/captain.ts:462-467`, `483-491` | With more than 20 open trips in a city, a captain can see an empty queue while a trip 800 m away exists — it was ranked 21st by recency and never loaded. | confirmed |
| F-06-12 | S2 | Accept never verifies candidacy, distance, or city — any approved, online captain can take any open trip | `apps/api/src/routes/trips.ts:829-870` | A captain in Alexandria can accept a Cairo trip via a direct API call. Dispatch's ranking becomes advisory. | confirmed |
| F-06-13 | S2 | The FCM fanout to 10 captains is `await`ed inside the request path | `apps/api/src/routes/trips.ts:574-585` | The rider's booking response is blocked on up to 10 external HTTP pushes. This is the largest single controllable component of booking latency. | confirmed |
| F-06-14 | S2 | `CaptainInbox` has no persistence or replay — an offer pushed while the socket is down is gone | `apps/api/src/durable-objects/CaptainInbox.ts:35-39`, `236-254` | A captain reconnecting 3 s after wave 1 never learns wave 1 happened. Recovery depends entirely on the 8/60 s poll and FCM. | confirmed |
| F-06-15 | S3 | The neighbourhood reaches ~9.7 km, not the "~7 km" the comments claim; the 15 km default radius therefore never filters anything | `apps/api/src/lib/nearby.ts:40-53`; `packages/shared/src/index.ts:181-191`; `migrations/0018_captain_search_radius.sql:5,18-20`; `apps/api/src/routes/trips.ts:525` | Dispatch reaches 40% further than the team believes. The radius feature is inert at its default. | confirmed |
| F-06-16 | S3 | `city` is part of the cell key, so captains across a city boundary are in a different DO namespace and are mutually invisible | `apps/api/src/lib/pricing.ts:36-38`; `apps/api/src/routes/captain.ts:172`, `203`, `211` | A Giza-flagged captain 500 m from a Cairo pickup can never be matched. Cross-boundary demand in a contiguous metro is structurally unservable. | confirmed |
| F-06-17 | S3 | Candidate window (120 s) and eviction window (180 s) disagree | `apps/api/src/durable-objects/GeoCell.ts:49`, `73` | A 60 s band where a record exists, costs alarm wakeups and storage, and can never match. Harmless but confusing to operate. | confirmed |
| F-06-18 | S3 | `OfferScheduler` tears itself down the instant the final wave is pushed | `apps/api/src/durable-objects/OfferScheduler.ts:123-130`, `154-157` | No component is left holding the question "did anyone accept?". This is the mechanical cause of F-06-04. | confirmed |
| F-06-19 | S3 | A repeated `/schedule` call resets `waveIndex` to 0 and re-offers from the start | `apps/api/src/durable-objects/OfferScheduler.ts:69-81` | No idempotency key. A retried booking re-cards captains who already declined. Currently only reachable via retry, so low likelihood. | confirmed |
| F-06-20 | S3 | `migrations/0008_rejection_reason_and_online_guard.sql` contains no online guard — only `rejection_reason` | `migrations/0008_rejection_reason_and_online_guard.sql:1-6` | The filename claims a safety control the file does not implement. The guard exists in code; anyone auditing migrations will mis-read this. | confirmed |
| F-06-21 | S3 | Two disagreeing offer surfaces in the captain app; `available_trips_tab.dart` is dead code and `NearbyRequestsScreen` has no socket listener | `apps/captain/lib/screens/home/available_trips_tab.dart:29`; `apps/captain/lib/screens/home/main_shell.dart:443`; `apps/captain/lib/screens/home/nearby_requests_screen.dart:59-61` | A captain working from the mounted browse tab receives no pushed offers — that screen only updates on manual refresh. | confirmed |
| F-06-22 | S3 | `CaptainInbox.broadcast` second loop sends to every socket returned by `getWebSockets()` including unauthenticated pending-auth sockets after a hibernation eviction | `apps/api/src/durable-objects/CaptainInbox.ts:236-254`, `47-49` | Offer payloads (pickup coordinates, fare) could reach a socket that never completed the JWT handshake. Requires DO eviction with a pending-auth socket open. → **T07/T02** | likely |
| F-06-23 | S4 | The rider's nearby-cars probe sends a degenerate zero-length route to OSRM every 45 s per open app | `apps/rider/lib/screens/home/home_screen.dart:197-206`, `212-229`; `apps/api/src/routes/trips.ts:330-339` | Wasted OSRM calls and D1 pricing reads proportional to app-opens, not bookings. | confirmed |
| F-06-24 | S4 | The offer countdown stops when the counter-offer sheet opens and never resumes | `apps/captain/lib/widgets/offer_card.dart:189` | A card can stay alive indefinitely after the captain opens and abandons a counter-offer. | confirmed |

### The S1s, expanded

#### F-06-01 — Scheduled trips are dispatched at booking time

`POST /trips` inserts the `scheduled_trip_dispatch` row when `scheduledFor` is
present (`apps/api/src/routes/trips.ts:483-491`) and then **falls straight
through into the live dispatch block** at 518–586. There is no
`if (!body.scheduledFor)` guard anywhere between the insert and the
`findNearbyCaptains` call. I looked for one specifically; it does not exist.

So booking a 07:00 airport run at 22:00 the night before immediately runs
neighbourhood discovery against whoever is online at 22:00, flips the trip to
`'offered'`, schedules waves, and fires FCM to ten captains. The offer payload
built at 549–560 has no `scheduledFor` field, so nothing on the captain's card
indicates the trip is for tomorrow. A captain who accepts gets a trip that is
`assigned` nine hours early, with a rider who is asleep.

The cron is then unable to correct this. Its query requires `t.status =
'searching'` (`apps/api/src/index.ts:291`), but the trip was flipped to
`'offered'` at booking (trips.ts:537). The row will never be selected, so it
stays `'pending'` forever. And in the one case where the query *does* match — a
scheduled trip booked when nobody was online, which stayed `'searching'` — the
handler marks it `'dispatched'` (307–311) and then only pushes a notification to
admin users (316–327). It performs no dispatch of any kind. The comment at
312–315 asserts that "the actual /trips create already drives nearest-captain
matching through GeoCell" and that scheduled trips "flip their status to
`offered` automatically once a captain sees them in their inbox" — the first
clause is the bug, and the second describes a mechanism that does not exist.

Net: scheduled trips either fire nine hours early or never fire. There is no
path where a scheduled trip is dispatched at its scheduled time.

#### F-06-02 — The stationary captain vanishes

`GeoCell` treats a captain as a candidate only if `now - lastSeen <= 120_000`
(`GeoCell.ts:49,56`), and `lastSeen` is set server-side on each heartbeat
(`GeoCell.ts:27`). The only heartbeat writers are `POST /captain/online` and
`POST /captain/location` (`apps/api/src/routes/captain.ts:175`, `213`).

The captain app calls `/captain/location` exclusively from a `Geolocator`
position-stream listener whose `distanceFilter` is 50 m when idle
(`captain_state.dart:619-622`, pushed at 673–683). A position stream with a
distance filter emits **only on movement**. There is no `Timer.periodic`
anywhere that pushes location on a clock.

Therefore: a captain who goes online, parks at a taxi rank, and waits — the
canonical supply behaviour, and the captain with the fastest possible pickup —
sends one heartbeat at `/captain/online` and then nothing. 120 seconds later
they are no longer a candidate. 180 seconds later their record is deleted
(`GeoCell.ts:73`). Their app shows "online", D1 says `is_online = 1`, and
`GET /captain/offers` still serves them the browse list because that endpoint
reads D1, not the cell. They will simply never be dispatched to again until they
drive 50 metres.

The practical shape of this in production is that dispatch only ever sees
captains who happen to be in motion, which is both a small fraction of online
supply and a strictly worse fraction — a moving captain is further away by the
time they arrive.

#### F-06-03 — Backgrounding removes a captain silently

`handleAppLifecycleState` cancels the location stream and the offers timer on
`paused`/`inactive`/`hidden` (`captain_state.dart:1083-1090`), and
`_startLocationStream` early-returns while `_lifecyclePaused` is true (638–639).
Nothing calls `POST /captain/online {online:false}` on the way out, so
`is_online` stays `1` and no `/offline` message reaches the cell
(`apps/api/src/routes/captain.ts:179-184` is the only `/offline` caller, and it
runs only on an explicit toggle).

Combined with F-06-02's 120 s window: switching to Google Maps for directions,
taking a phone call, or answering a WhatsApp message for two minutes drops the
captain out of dispatch. On resume the stream restarts (1092–1100) but the
captain has no idea they were invisible, and the offers they missed are gone —
`CaptainInbox` does not replay (F-06-14).

A force-quit is worse: no cleanup runs at all, so `is_online = 1` persists
indefinitely. The captain shows as online supply in every admin view and count
until they next open the app.

#### F-06-04 — The unmatched trip, and the lockout it causes

Three mechanisms compose into the worst user-facing outcome in this track.

**The scheduler abandons the trip.** After the final wave, `pushWave` calls
`teardown()` (`OfferScheduler.ts:129`), which deletes the alarm and all state
(154–157). If the candidate list was empty from the start the DO is never even
created (`trips.ts:535` gates the whole block). Either way, once the last wave
is out, no component anywhere holds the question "did anybody take this?".
Nothing transitions the trip to a terminal or unfulfilled state. It stays
`'searching'` or `'offered'` in D1 forever.

**The rider is shown a spinner with no end.** The searching panel renders a
`CircularProgressIndicator` and the copy "جارٍ البحث عن كابتن…" with no
conditional branch for zero supply and no timeout
(`apps/rider/lib/screens/trip/trip_screen.dart:460-471`). The 10 s poll (170–190)
will keep returning `searching` indefinitely. There is no client-side timer that
fires after N seconds to offer a retry or a wider search. The only exit is the
cancel button.

**And then the rider is locked out.** `POST /trips` rejects any rider holding a
trip whose status is not `completed` or `cancelled`
(`apps/api/src/routes/trips.ts:362-376`). An abandoned `searching` trip
satisfies that condition permanently. The 409 carries the `tripId` (372) —
which is exactly what a recovery flow would need — but the rider app throws it
away: `fare_estimate_sheet.dart:217-223` catches the exception and shows the raw
error string in a `SnackBar`. There is no parse of the `code`, no navigation to
the orphaned trip, no "cancel it and rebook" affordance.

So the sequence is: rider requests a car in a low-supply area → spinner forever
→ rider backs out of the screen (`trip_screen.dart:282`, no confirmation, no
cancel) → rider tries to book again → a `SnackBar` that says `ACTIVE_TRIP` →
and there is no route in the UI back to the trip that is blocking them. The
rider is now unable to use the product at all.

This needs no unusual conditions. It is the *normal* outcome of requesting a
ride where no captain is online, which for a pre-production platform bootstrapping
supply in Cairo is going to be a large fraction of early requests.

#### F-06-05 — Captain cancellation is terminal

The cancel handler branches on `cancelledByRider` (`trips.ts:739`) and gates the
entire scheduler-teardown and inbox-fanout block on it (753). For a captain
cancellation, control reaches 727–731 — status becomes `'cancelled'` — and then
the only further action is a push to the rider saying the trip was cancelled
(812–820).

The trip is dead. It does not return to `searching`, the `OfferScheduler` is
never restarted, the remaining candidates are never contacted, and the rider's
place in the queue is not preserved. They must open the app and book from
scratch, re-entering pickup and destination, having already waited for a captain
who then dropped them.

In a market where captain-side cancellation is common — cash trips, short fares,
bad traffic toward the pickup — this converts every cancellation into a fully
lost booking. Uber and Careem both re-enter the trip into dispatch automatically
and preserve the rider's request; this is table stakes, not a refinement.

### The S2s, expanded

#### F-06-06 — The wave rollout is not actually staged

This is the finding I would put in front of whoever owns dispatch, because a
piece of correct engineering has been neutralised by the code around it.

`OfferScheduler` does exactly what its docstring claims: three captains at a
time, 15 s apart, driven by a DO alarm that survives the request, with a D1
status re-check before every wave. Read in isolation it is good.

But an offer reaches a captain by three routes, and the scheduler owns one:

1. **WebSocket inbox** — staged, 3 at a time. `OfferScheduler.ts:109-121`.
2. **FCM** — all 10 candidates, at t=0, no staging.
   `apps/api/src/routes/trips.ts:574-585`.
3. **`GET /captain/offers`** — every open trip in the city within the captain's
   radius, returned to *any* online captain who polls, whether or not they were
   ever a candidate. `apps/api/src/routes/captain.ts:462-491`. Polled every 8 s
   when the socket is down, every 60 s when it is up
   (`captain_state.dart:758,763`).

Channel 2 means candidates 4–10 get a phone notification about a trip 15–45
seconds before they are supposed to see it. Channel 3 is worse: it ignores the
candidate list entirely. A captain who was never in the neighbourhood query at
all — 20th closest, or in a cell the search never touched but within their own
15 km radius — will see the trip and can accept it.

So the audience for a new trip is not "3 captains, then 6, then 9". It is
"every online captain in the city whose radius covers the pickup, within one
poll interval, plus 10 phone notifications immediately". That is a strictly
larger race than the pre-PR-#14 behaviour the scheduler was written to fix, and
it explains why the losing-captain experience (F-06-07) has not improved.

The fix is not to remove the other channels — FCM genuinely is what wakes a
closed app, and the browse list is a legitimate inDrive-style surface. The fix
is to make all three agree on a single authority for "may this captain see this
trip right now", which is P0.2 below.

#### F-06-07 — Nobody tells the losers

When a captain wins, the handler logs the assignment, broadcasts to the trip
room, and pushes to the rider (`trips.ts:872-887`). It sends nothing to the
other captains holding a card.

Rider-cancel, by contrast, does this properly and the comment explains why
(741–752): it fans `trip.cancelled` out to a *wider* radius than dispatch used,
precisely so no card is stranded. That reasoning applies identically to accept
and was not carried over.

What the losing captain sees today: the card sits there. The 15 s countdown
(`offer_card.dart:69`) may expire it locally, or the next `refreshOffers` may
drop it — but if they tap accept first they get a red `SnackBar` containing the
raw server string, because the handler renders `e.toString()` with only the
`Exception:` prefix stripped (`offer_card.dart:148-161`). The captain sees the
literal text `TRIP_TAKEN`. Then `refreshOffers()` clears the card, and because
`_accepting` is reset to `false` before that refresh completes, there is a
window where they can tap a doomed card again and get a second identical error.

The mechanism to fix this already exists and is already wired: push a
`trip.taken` event to the same neighbourhood the cancel path uses.

#### F-06-08 — Ranking is a single straight line

Covered mechanically in §3.4. The impact worth stating plainly: with
straight-line ranking and no ETA, dispatch systematically prefers captains who
are geometrically near and practically far. In Cairo the Nile is the obvious
case — a captain in Zamalek is 900 m from a Dokki pickup and 15 minutes away
across the bridge at rush hour. Dispatch puts them in wave 1 and puts the
captain 2.5 km down the corniche, 6 minutes out, in wave 2 or later.

The platform already has a routing client (`apps/api/src/lib/routing.ts`) and
already calls OSRM on every booking for the fare estimate. Using it to rank a
handful of candidates is a small change with a large effect, and it is the
single highest-leverage improvement to time-to-pickup available here.

Separately, `vehicle_type_id` is written to the trip at
`apps/api/src/routes/trips.ts:471` and never read on any dispatch path. Whatever
vehicle-class product exists is not enforced by matching.

#### F-06-09 — Decline is a local variable

`decline(tripId)` adds the id to an in-memory set and removes the card
(`captain_state.dart:1041-1044`). No HTTP call. There is no
`POST /trips/:id/decline` endpoint in the API at all.

Three consequences. First, the rollout cannot accelerate: if all three captains
in wave 1 decline within two seconds, the rider still waits the full 15 s for
wave 2, because the alarm is the only thing that advances `waveIndex`. Across a
15-captain city this is 30–45 seconds of avoidable wait on trips that end up
matched anyway. Second, there is no rejection data — no acceptance rate can be
computed, so none of the fairness mechanisms in F-06-10 can be built until this
exists. Third, `_declinedTripIds` is memory-only and cleared on accept and
logout (993, 1161), so after a force-quit every previously declined trip
reappears in the queue.

#### F-06-10 — Nothing prevents starvation or cherry-picking

There is no cooldown after decline, no round-robin, no idle-time weighting, and
no acceptance-rate consequence anywhere in `GeoCell.ts`, `nearby.ts`,
`OfferScheduler.ts`, or the dispatch block of `trips.ts`. I checked for each
specifically.

The ordering function is stable and purely spatial, so the captain physically
closest to a demand hotspot is in wave 1 of every single trip generated there,
for as long as they sit there. Captains 300 m further out receive nothing until
that captain declines three times in a row — and since declining is free and
invisible (F-06-09), the closest captain can skim only the high-value trips
indefinitely at zero cost.

This is the classic supply-side failure mode of naive dispatch and it damages
both sides: the favoured captain burns out on volume, the neighbours earn
nothing and churn, and riders on cheap short trips wait longest because those
are the trips everyone skips.

#### F-06-11 — Filter after limit

`GET /captain/offers` runs `... WHERE status IN ('searching','offered') AND city
= ? ORDER BY created_at DESC LIMIT 20` (`captain.ts:462-467`) and only then
applies the haversine radius filter in JavaScript (483–491).

The `LIMIT 20` is applied by SQLite to the *city-wide, recency-ordered* set. If
25 trips are open in Cairo, the query returns the 20 newest, and the five oldest
are invisible to every captain regardless of proximity. A captain 800 m from an
older open request sees nothing while trips 12 km away fill their list. It also
means the oldest requests — the ones already struggling to match — are the first
to fall off the board, which is precisely backwards.

The fix is to filter by a bounding box in SQL before the limit, then refine by
haversine.

#### F-06-12 — Accept does not check candidacy

The accept handler validates approval, online state, trip status, and captain
busy-ness (`trips.ts:834-859`), then performs the conditional update. It never
asks whether this captain was a candidate, whether their wave has fired, how far
they are from the pickup, or whether they are in the same city.

Any approved, online captain who learns a trip id can take it. They will learn
it from `GET /captain/offers`, which as established (F-06-06) is city-scoped
rather than candidate-scoped. The 15 km default radius (F-06-15) means "city
-scoped" is close to "unscoped" in practice.

The consequence is that dispatch ranking is advisory. The system computes a
careful ordered candidate list and then accepts whoever calls first. It also
means a captain can accept a trip 14 km away, which no ETA model would ever have
offered them, and the rider waits 40 minutes for a pickup.

#### F-06-13 — Booking latency includes ten push notifications

`await Promise.all(nearby.captains.slice(0, 10).map((cap) => pushToUser({...})))`
sits directly in the request path (`trips.ts:574-585`). The rider's HTTP
response does not return until all ten external FCM calls settle.

Nothing about the rider's response depends on those pushes. This is the clearest
single latency win available: move it to `ctx.waitUntil` (or hand it to the
existing `NOTIFICATIONS` queue, which already exists with a DLQ per the stack
description) and the p95 booking response drops by roughly the FCM round-trip.
See the budget in §8.

#### F-06-14 — The inbox forgets

`CaptainInbox` handles `/push` by calling `broadcast` immediately
(`CaptainInbox.ts:35-39`), which iterates live sockets and writes to them
(236–254). There is no storage write, no queue, no replay on connect. When a
socket connects, the DO sends a `connected` frame (61–67) and nothing else.

A captain whose socket is re-establishing during wave 1 — the app backoff is
1/2/4/8/16 s with jitter — misses that wave permanently. Their recovery paths
are the FCM push, which is unreliable and which the app's foreground handler
does not route into offer state, and the poll, which is 8 s or 60 s away.

Persisting the last N offers per captain in DO storage and replaying unexpired
ones on connect is a small change that makes the socket authoritative.

## 5. Benchmark gap

### 5.1 Geospatial indexing

Uber runs H3, a hexagonal hierarchical index, using roughly resolution 9
(~174 m edge) for driver location and resolution 7 (~1.2 km edge) for
supply/demand aggregation, with `gridDisk(cell, k)` for neighbour lookup
(*confident* — [Uber Engineering, H3](https://www.uber.com/us/en/blog/h3/)).
Hexagons are used specifically because all six neighbours are equidistant,
whereas a square grid's diagonal neighbours sit √2 further away than its
cardinal ones, which distorts proximity queries.

Synaptic Go uses geohash-5 squares at ~4.89 × 4.24 km — **roughly 25× the area
of an Uber res-9 cell** — with a 3×3 neighbour fan-out. The square-grid
distortion Uber avoided is present, and the cell is so coarse that the
neighbourhood reaches 9.7 km when the useful dispatch radius in a dense city is
2–4 km.

The gap that actually costs money is not the hexagon-vs-square choice, it is the
granularity. A single Cairo cell can contain hundreds of captains during peak,
and every `/nearby` call does a full `storage.list` scan over that cell
(`GeoCell.ts:51`) and haversines every record (57). Going to geohash-6
(~1.2 × 0.6 km) with a 5×5 fan-out would give comparable reach with far smaller
scans — but see §10 Q3, because that is a real trade against DO count.

### 5.2 Matching model

Uber's DISCO does **batched** matching: requests accumulate over a short window
(commonly cited as 2–5 s), a full rider×driver cost matrix is built with ETA as
the edge weight, and a global minimum-weight bipartite matching is solved so all
assignments in the window are jointly optimal (*confident for the mechanism*;
*the 2–5 s figure is widely repeated in engineering design references citing
Uber's published work rather than in a primary Uber SLA document*). The
canonical illustration is three riders and three drivers where greedy yields 20
minutes of total ETA and optimal yields 10.

Synaptic Go is greedy first-come: the first captain to call accept wins,
regardless of whether they were the best global assignment. With current volumes
that is the correct engineering choice — batching only pays when several
requests are in flight in the same area within the same few seconds — but it
should be a *known* choice with a volume trigger, not an accident. It is listed
as P2.2 rather than P0 for exactly that reason.

The ranking signal is where the gap bites now. Uber ranks on DeepETA — a routing
engine ETA plus a learned residual for traffic and intersections, served in
single-digit milliseconds (*confident* —
[Uber Engineering, DeepETA](https://www.uber.com/ca/en/blog/deepeta-how-uber-predicts-arrival-times/)).
Synaptic Go ranks on crow-flies haversine (F-06-08). No ML is needed to close
most of this gap; an OSRM table call over ten candidates gets most of the way.

### 5.3 Offer rollout

Uber's primary model is exclusive sequential offers with a short response window
(~15 s) per driver, with Trip Radar as a parallel broadcast channel for
unfulfilled demand; declining a Trip Radar request carries no acceptance-rate
penalty, declining an exclusive one does (*confident* —
[Uber, acceptance and cancellation rates](https://www.uber.com/us/en/blog/understanding-acceptance-and-cancellation-rates/)).

inDrive is the opposite: broadcast to all nearby drivers simultaneously, drivers
counter-offer, and the rider picks from the offer list on price, rating, car and
ETA. Drivers are explicitly not penalised for ignoring requests (*confident* —
[TechCrunch, 2023](https://techcrunch.com/2023/07/20/indrive-brings-its-bid-based-ride-hail-app-to-the-us/);
[inDrive help](https://indrive.com/en-in/help/passengers/how-fares-are-calculated)).

**Synaptic Go is currently running both models at once without having chosen
either.** It has an Uber-style staged rollout in `OfferScheduler`, an
inDrive-style bidding flow (`POST /trips/:id/bid`, `POST /trips/:id/accept-bid`,
`trips.ts:1143-1370`), and an inDrive-style open broadcast board
(`GET /captain/offers`). The three do not agree on who may see a trip, which is
F-06-06. This is the central product question and it is §10 Q1 — the technical
fixes below are shaped differently depending on the answer, which is why P0.2 is
specified as "one authority" rather than "remove the broadcast".

Wave sizing itself is reasonable: 3 captains per wave sits inside the 3–5 range
that dispatch design literature recommends (*assumed* — industry convention,
not a sourced figure from any operator). The 15 s interval is defensible against
Uber's ~15 s exclusive-offer window. Neither number is the problem; the missing
decline signal (F-06-09) and the parallel channels (F-06-06) are.

### 5.4 Fairness and anti-starvation

Uber's main systemic lever against cherry-picking is a rolling 100-request
acceptance-rate window feeding Uber Pro tiers, with documented thresholds — ≥85%
acceptance and ≤4% cancellation to hold Gold and above, immediate reward loss
below 75% acceptance or above 10% cancellation (*confident* —
[Uber Pro](https://www.uber.com/bg/en/drive/uber-pro/)). Tier grants dispatch
priority and exclusive-request access. Post-regulatory-pushback the penalty is
loss of rewards and priority rather than deactivation.

Idle-time weighting and cooldown-after-decline are common in the industry as
anti-starvation floors (*assumed* — the pattern is documented in dispatch design
references; specific operator values are not public).

Synaptic Go has none of these, and cannot build them, because the decline signal
does not reach the server (F-06-09). That dependency ordering matters: P0.5
(record declines) is a prerequisite for P1.4 (fairness), not an independent item.

For an Egyptian market specifically, inDrive's "no penalty for declining" stance
is the more culturally realistic starting point, and Careem's approach —
demand heatmaps and peak-hour bonuses that *pull* captains toward demand rather
than punishing them for declining — is the better model to copy. Careem's
dispatch internals are not publicly documented; that supply-positioning and
predictive allocation are owned functions is confirmed only from their own
engineering job descriptions (*confident that the functions exist; mechanisms
not public*).

### 5.5 Location freshness

Design references citing Uber's published architecture put driver GPS ping
intervals at ~4 s with TTL-based eviction of stale records, commonly a 30 s TTL
in reference implementations (*confident for the ~4 s ping cadence; the 30 s TTL
is a design-reference value, not a confirmed Uber production number*).

Synaptic Go's candidate window is 120 s (`GeoCell.ts:49`) — already loose by 4×
against that reference — and, far more importantly, **nothing guarantees a ping
ever arrives**, because the client is movement-triggered with no periodic timer
(F-06-02). The threshold is not the problem; the absence of a heartbeat is.

### 5.6 Unfulfilled requests

The mature pattern is an escalation ladder: exhaust the candidate list, widen
the radius and re-query, broadcast to a wider pool, then either queue the
request with a notify-when-available or expire it explicitly after a bounded
window (typically 3–5 minutes) and tell the rider (*confident for the general
pattern*; *specific radii and timings vary by operator and are not public*).

Synaptic Go implements none of the ladder and, critically, does not implement
the final rung either: there is no expiry, no notification, and no terminal
state (F-06-04). Not widening the radius is a defensible early-stage choice.
Never telling the rider is not.

### 5.7 Where Synaptic Go actually sits

| Mechanism | Uber | inDrive | Synaptic Go | Gap |
|---|---|---|---|---|
| Spatial index | H3 res 9 (~174 m) | not public | geohash-5 (~4.9 km) | 25× coarser cells |
| Neighbour search | `gridDisk` | not public | 3×3 fan-out, correct | **at parity** |
| Ranking | routed ETA + learned residual | rider chooses on price/ETA/rating | straight-line haversine | no ETA at all |
| Rollout | exclusive, ~15 s, staged | broadcast to all | staged **and** broadcast **and** FCM blast | incoherent |
| Accept race | atomic | atomic | atomic conditional UPDATE | **at parity** |
| Decline signal | rolling 100-request window | none by design | none, and not recorded | blocks all fairness work |
| Fairness | acceptance-rate tiers | none by design | none | absent |
| Stale-location TTL | ~4 s ping, TTL eviction | not public | 120 s window, no ping guarantee | client never heartbeats |
| Unfulfilled | widen → broadcast → notify/expire | rider re-prices | nothing; trip orphaned | no terminal state |
| Reassign after driver cancel | automatic | automatic | none — trip dies | absent |
| Scheduled trips | dispatched near pickup time | n/a | dispatched at booking time | non-functional |

Two rows read "at parity", and they are the two the team should be told about:
the neighbourhood fan-out is correct, and the accept lock is correct. Everything
else on this axis needs work, but those two do not.

## 6. Improvement plan

Ordered. P0 items are the set I would block production traffic on.

### P0.1 — Make the captain heartbeat unconditional

- **Goal** — a captain who is online is dispatchable, whether or not they are
  moving and whether or not the app is in the foreground.
- **Design** — three changes, all on the client except the last:
  (a) add a `Timer.periodic` on a 45 s interval that pushes the last known
  position via `POST /captain/location` whenever `online == true`, independent
  of the position stream, so a stationary captain refreshes `lastSeen` well
  inside the 120 s window;
  (b) do not cancel that timer on `AppLifecycleState.paused` — only cancel the
  high-accuracy position *stream*, and keep the 45 s heartbeat running with the
  last cached fix;
  (c) on the server, add a `GET /captain/heartbeat`-equivalent cheap path or
  accept that `/location` is it, and raise its rate limit from 30/60 s
  (`captain.ts:192-197`) — 45 s heartbeats plus movement pushes will exceed 30/min
  during active driving.
  Longer term, a foreground service on Android is the correct answer for
  background presence; that is a T26 packaging concern and is noted there.
- **Files to change** — `apps/captain/lib/services/captain_state.dart`
  (619–626, 638–639, 673–683, 1083–1090), `apps/api/src/routes/captain.ts`
  (190–197).
- **DB** — none.
- **API contract** — none changed; rate limit raised to 90/60 s on
  `POST /captain/location`.
- **Effort** — S.
- **Risk** — battery drain and D1 write volume. Every heartbeat is a `captains`
  row `UPDATE` (`captain.ts:205-209`) plus a DO write; at 45 s that is ~1,900
  writes/captain/day. Mitigate by making the periodic heartbeat hit the DO only
  and letting D1 lag (see P1.6). Rollback is deleting the timer.
- **Acceptance criteria** — a captain parked with the app open is still returned
  by `findNearbyCaptains` after 10 minutes. A captain who backgrounds the app for
  5 minutes is still returned. A captain who force-quits is *not* returned after
  3 minutes.
- **Tests** — unit test on `GeoCell` expiry boundaries; a manual soak with one
  device parked for 15 minutes asserting continued candidacy.

### P0.2 — One authority for "may this captain see this trip"

- **Goal** — the three delivery channels stop disagreeing, so the staged rollout
  actually stages.
- **Design** — introduce a `trip_offers` table as the single source of truth.
  When `OfferScheduler` fires a wave it inserts one row per captain in that wave
  (`trip_id`, `captain_id`, `wave_index`, `offered_at`, `expires_at`,
  `state`). Then:
  (a) `GET /captain/offers` joins against `trip_offers` for this captain instead
  of scanning all open city trips;
  (b) the FCM fanout moves *inside* `OfferScheduler.pushWave` so it is emitted
  per wave, to that wave's captains only, instead of blasting 10 at t=0 from the
  request path;
  (c) `POST /trips/:id/accept` requires a live, unexpired `trip_offers` row for
  the calling captain — closing F-06-12 in the same change.
  If the product answer to §10 Q1 is "inDrive broadcast", this table still
  applies; the wave size simply becomes the whole candidate set and the browse
  board reads the same rows. The point is one authority, not a particular
  rollout shape.
- **Files to change** — `apps/api/src/durable-objects/OfferScheduler.ts`
  (109–130), `apps/api/src/routes/trips.ts` (561–585, 829–870),
  `apps/api/src/routes/captain.ts` (439–498).
- **DB** — migration `0020_trip_offers.sql`:
  ```sql
  CREATE TABLE trip_offers (
    id          TEXT PRIMARY KEY,
    trip_id     TEXT NOT NULL REFERENCES trips(id),
    captain_id  TEXT NOT NULL REFERENCES users(id),
    wave_index  INTEGER NOT NULL,
    distance_km REAL,
    offered_at  TEXT NOT NULL,
    expires_at  TEXT NOT NULL,
    state       TEXT NOT NULL DEFAULT 'offered',  -- offered|accepted|declined|expired|withdrawn
    UNIQUE (trip_id, captain_id)
  );
  CREATE INDEX idx_trip_offers_captain_state ON trip_offers(captain_id, state, expires_at);
  CREATE INDEX idx_trip_offers_trip ON trip_offers(trip_id);
  ```
- **API contract** — `GET /captain/offers` response shape unchanged (still
  `{trips, searchRadiusKm, captainLocation}`) but the set is now offer-scoped.
  `POST /trips/:id/accept` gains a new rejection:
  `403 {error, code: "NOT_OFFERED"}`.
- **Effort** — M.
- **Risk** — the highest-risk item here, because it narrows what captains can
  see. If wave sizing or expiry is wrong, supply appears to vanish. Ship behind a
  config flag that falls back to the current city-wide board, and watch
  offer→accept rate and unfulfilled rate for a week before removing the flag.
- **Acceptance criteria** — a captain not in a fired wave receives `NOT_OFFERED`
  on a direct accept call. `GET /captain/offers` for that captain does not
  include the trip. FCM count per trip equals wave size, not 10.
- **Tests** — integration test: create a trip with 6 candidates, assert captain 5
  cannot see or accept it at t=0 and can at t=15 s.

### P0.3 — Fix scheduled-trip dispatch

- **Goal** — a trip scheduled for 07:00 is dispatched at approximately 07:00 and
  not before.
- **Design** — guard the live dispatch block on `!body.scheduledFor` in
  `POST /trips`, and give scheduled trips their own status (`scheduled`) so they
  are excluded from every open-trip query. Move the real dispatch into the cron:
  select rows where `scheduled_for <= now + lead_time`, run
  `findNearbyCaptains` + `filterByCaptainRadius` + `OfferScheduler` exactly as
  the create path does, and only then mark the dispatch row `'dispatched'`. Use a
  lead time of 10 minutes so there is room for the rollout to run and for the
  captain to reach the pickup. Extract the dispatch block from `trips.ts` into a
  shared `dispatchTrip(env, trip)` in `apps/api/src/lib/` so the cron and the
  create path cannot drift again.
- **Files to change** — `apps/api/src/routes/trips.ts` (483–491, 518–586),
  `apps/api/src/index.ts` (283–331), new `apps/api/src/lib/dispatch.ts`.
- **DB** — migration `0021_scheduled_trip_status.sql`: add `'scheduled'` to the
  accepted status vocabulary (D1/SQLite has no enum here, so this is a
  documentation + `canTransition` change in `apps/api/src/lib/utils.ts` plus a
  backfill of any existing mis-dispatched rows), and add
  `CREATE INDEX idx_sched_dispatch_pending ON scheduled_trip_dispatch(status, scheduled_for);`
- **API contract** — `POST /trips` with `scheduledFor` now returns
  `status: "scheduled"` and `nearbyCaptains: []`. Client must render a
  "booked for <time>" state rather than a searching spinner.
- **Effort** — M.
- **Risk** — the rider app currently treats any non-terminal trip as "searching"
  and will show a spinner for a trip scheduled next week; the client change ships
  in the same release or the guard waits. Also interacts with the active-trip
  block (F-06-04) — a scheduled trip must not block a rider from booking a ride
  now, so the `ACTIVE_TRIP` query must exclude `'scheduled'`.
- **Acceptance criteria** — a trip created with `scheduledFor = now + 8h` sends
  zero offers at creation, and sends its first wave between T-10min and T-9min.
  A rider with a scheduled trip can still book an immediate trip.
- **Tests** — cron handler unit test with a frozen clock at T-11min, T-9min,
  T+1min.

### P0.4 — Terminate unmatched trips and unblock the rider

- **Goal** — no trip sits in `searching` forever, and no rider is ever locked out
  by one.
- **Design** — four parts:
  (a) `OfferScheduler` stops self-destructing after the final wave. Instead it
  arms one last alarm at `WAVE_DELAY_MS` past the final wave; when that fires and
  the trip is still open, it transitions the trip to `no_supply`, emits a
  `trip.unfulfilled` event to the rider's trip room, sends the rider a push, and
  only then tears down.
  (b) When zero candidates are found at creation, do the same immediately —
  set `no_supply`, tell the rider, and do not leave the trip searching.
  (c) `no_supply` is terminal for the purposes of the active-trip guard at
  `trips.ts:362-376`, so the rider can rebook instantly.
  (d) Rider app: render a real no-supply state with a "search again" button, and
  parse the `409 ACTIVE_TRIP` response — it already carries `tripId` (372) — to
  offer "go to your active trip" or "cancel it and rebook".
- **Files to change** — `apps/api/src/durable-objects/OfferScheduler.ts`
  (102–105, 123–130), `apps/api/src/routes/trips.ts` (362–376, 531–586),
  `apps/rider/lib/screens/trip/trip_screen.dart` (460–471),
  `apps/rider/lib/screens/home/fare_estimate_sheet.dart` (217–223).
- **DB** — none; `no_supply` is a new value in the existing `status` text column.
  `canTransition` in `apps/api/src/lib/utils.ts` must accept
  `searching|offered → no_supply` and `no_supply → cancelled`.
- **API contract** — new trip status `no_supply`. New trip-room event
  `{type: "trip.unfulfilled", tripId, at}`.
- **Effort** — M (backend S, rider Flutter M).
- **Risk** — declaring no-supply too early on a slow-but-matchable trip. The
  timer only starts *after* the whole candidate list is exhausted, so the floor
  is 45 s + one wave delay = 60 s; make it configurable and start at 90 s.
- **Acceptance criteria** — a trip created with no captains online reaches
  `no_supply` within 5 s and the rider can immediately create another. A trip
  whose candidates all decline reaches `no_supply` within 90 s. Zero trips older
  than 10 minutes in `searching` in a daily query.
- **Tests** — integration: empty neighbourhood → `no_supply` + rider can rebook.
  Backfill script for any already-orphaned rows.

### P0.5 — Record declines

- **Goal** — the server knows when a captain says no, which unblocks wave
  acceleration and every fairness mechanism.
- **Design** — add `POST /trips/:id/decline` writing `state='declined'` to the
  `trip_offers` row from P0.2. The captain app calls it from `decline()` instead
  of only mutating local state, and keeps the local suppression as an optimistic
  echo. `OfferScheduler` gains a `/declined` endpoint: when every captain in the
  current wave has declined, cancel the pending alarm and fire the next wave
  immediately.
- **Files to change** — `apps/api/src/routes/trips.ts` (new handler),
  `apps/api/src/durable-objects/OfferScheduler.ts` (91–131),
  `apps/captain/lib/services/captain_state.dart` (1041–1044),
  `apps/captain/lib/widgets/offer_card.dart` (117–126).
- **DB** — none beyond P0.2's `trip_offers`.
- **API contract** — `POST /trips/:id/decline` → `204`, body
  `{reason?: string}`.
- **Effort** — S (depends on P0.2).
- **Risk** — low. A decline that fails to reach the server degrades to today's
  behaviour.
- **Acceptance criteria** — three declines in wave 1 advance to wave 2 in under
  2 s rather than 15 s. `trip_offers` rows show declines.
- **Tests** — integration test asserting wave-2 timing under full wave-1 decline.

### P0.6 — Tell the losers, and re-dispatch on captain cancel

- **Goal** — nobody holds a dead card, and a captain cancellation does not
  destroy the booking.
- **Design** — two changes sharing one mechanism. On accept, mark sibling
  `trip_offers` rows `withdrawn` and fan a `trip.taken` event to those captains'
  inboxes, reusing the fanout the cancel path already implements
  (`trips.ts:775-793`). On captain cancel, instead of going to `cancelled`:
  clear `captain_id`, return the trip to `searching`, record the cancelling
  captain in a per-trip exclusion list, and re-run dispatch excluding them.
  Notify the rider that a new captain is being found rather than that the trip
  is dead. Cap re-dispatch attempts (3) before falling through to `no_supply`.
- **Files to change** — `apps/api/src/routes/trips.ts` (709–827, 861–889), new
  `apps/api/src/lib/dispatch.ts` from P0.3.
- **DB** — reuse `trip_offers.state='withdrawn'`; add
  `trips.reassign_count INTEGER DEFAULT 0` in migration `0022_trip_reassign.sql`.
- **API contract** — new inbox event `{type: "trip.taken", tripId, at}`. New
  rider trip-room event `{type: "trip.reassigning", tripId, at}`.
- **Effort** — M.
- **Risk** — a re-dispatch loop if the same captain keeps accepting and
  cancelling; the exclusion list and the attempt cap bound it.
- **Acceptance criteria** — losing captains' cards clear within 2 s of an accept
  without tapping. A captain cancelling an assigned trip results in a new
  captain being offered the same trip within 5 s, with the rider never returning
  to the booking form.
- **Tests** — integration: two captains race, assert loser receives
  `trip.taken`. Integration: accept then cancel, assert trip returns to
  `offered` with a different captain.

### P1.1 — Rank by routed ETA

- **Goal** — dispatch offers the captain who will actually arrive first.
- **Design** — after `filterByCaptainRadius` narrows the set, call OSRM's table
  service once for the surviving candidates (one request, N sources → 1
  destination) and sort by duration rather than haversine. Cache per
  cell-pair for 60 s in KV, as the ETA cache at `trips.ts:300-311` already does
  for a similar purpose. Fall back to haversine ordering on OSRM failure or
  timeout (250 ms budget) — never block dispatch on the routing service.
- **Files to change** — `apps/api/src/lib/nearby.ts` (102–104), new helper in
  `apps/api/src/lib/routing.ts`, call site `apps/api/src/routes/trips.ts:531`.
- **DB** — none.
- **API contract** — `nearbyCaptains[]` entries gain `etaMin` alongside
  `distanceKm`.
- **Effort** — M.
- **Risk** — an OSRM outage degrades ranking to today's behaviour, which is
  acceptable; the timeout must be strict or it becomes a booking-latency
  regression.
- **Acceptance criteria** — across-river candidates rank below same-side
  candidates in a Cairo fixture. Dispatch adds ≤250 ms p95.
- **Tests** — fixture with a known Nile-crossing pair asserting the ordering
  flips versus haversine.

### P1.2 — Vehicle-type matching

- **Goal** — a booking for a given vehicle class is only offered to captains who
  can serve it.
- **Design** — carry `vehicle_type_id` into the `GeoCell` presence record on
  heartbeat, and filter candidates on it in `findNearbyCaptains`. Requires the
  captain's vehicle class on the captain row, which `0015_captain_onboarding_fields.sql`
  may already supply — **needs-check**, I did not read that migration in full.
- **Files to change** — `apps/api/src/durable-objects/GeoCell.ts` (4–10, 20–37,
  45–63), `apps/api/src/lib/nearby.ts` (55–105),
  `apps/api/src/routes/captain.ts` (171–185, 211–221).
- **DB** — possibly none; confirm the captain-side column first.
- **API contract** — none.
- **Effort** — S.
- **Risk** — captains whose vehicle class is null must not be filtered out;
  treat null as "matches everything" until onboarding backfills.
- **Acceptance criteria** — a motorcycle captain is not offered a 4-seat booking.
- **Tests** — unit test on the candidate filter.

### P1.3 — Fix the offers query, and the boundary problem

- **Goal** — proximity, not recency, decides what a captain sees; and a captain
  across a city line is not invisible.
- **Design** — (a) rewrite `GET /captain/offers` to filter by a lat/lng bounding
  box derived from the captain's radius *in SQL*, before `LIMIT`, then refine
  with haversine — this closes F-06-11. (b) Drop `city` from the cell key so the
  grid is purely geographic, and keep city as a *filter* on the trip rather than
  a partition of the index. This closes F-06-16 and makes Cairo/Giza one
  contiguous supply pool.
- **Files to change** — `apps/api/src/routes/captain.ts` (462–491),
  `apps/api/src/lib/pricing.ts` (36–38), `apps/api/src/lib/nearby.ts` (40–53),
  `apps/api/src/routes/captain.ts` (172, 211).
- **DB** — `CREATE INDEX idx_trips_status_city_pickup ON trips(status, city, pickup_lat, pickup_lng);`
  in migration `0023_trips_pickup_index.sql`.
- **API contract** — none.
- **Effort** — M. Note (b) is a breaking change to cell identity: existing
  `GeoCell` instances become orphaned. Deploy during a low-traffic window and
  accept that every captain must re-heartbeat, which P0.1's 45 s timer makes
  self-healing within a minute.
- **Risk** — the cell-key change is the riskiest single line in this plan.
  Orphaned DOs retain state until their alarms drain them.
- **Acceptance criteria** — with 30 open Cairo trips, a captain 800 m from the
  oldest sees it. A Giza-flagged captain 500 m from a Cairo pickup is a
  candidate.
- **Tests** — seed 30 trips, assert proximity ordering. Cross-boundary fixture.

### P1.4 — Fairness floor

- **Goal** — the same captain does not receive every offer, and cherry-picking
  has a cost.
- **Design** — depends on P0.5. Two mechanisms, deliberately mild for this
  market: (a) a 60 s cooldown after a decline, implemented as a
  `trip_offers`-derived check that skips a captain for wave-1 placement if they
  declined within the window — they remain eligible for later waves, so supply is
  never reduced; (b) an idle-time bonus in the sort, subtracting a small
  distance-equivalent per minute since the captain's last completed trip, capped,
  so a captain who has been idle 20 minutes outranks one 400 m closer who just
  dropped off. Deliberately **not** proposing acceptance-rate penalties — see
  §10 Q4.
- **Files to change** — `apps/api/src/lib/nearby.ts` (102–104), new scoring
  helper, `apps/api/src/routes/trips.ts:531`.
- **DB** — none beyond `trip_offers`.
- **API contract** — none.
- **Effort** — M.
- **Risk** — over-tuning the idle bonus sends trips to distant captains and
  raises pickup ETAs. Cap the bonus at an equivalent of 1.5 km and monitor
  time-to-pickup.
- **Acceptance criteria** — in a simulation with 5 captains in one cell and 20
  sequential trips, no captain receives more than 40% of wave-1 placements.
- **Tests** — a deterministic dispatch simulation fixture.

### P1.5 — Persist and replay the inbox

- **Goal** — a reconnecting captain does not lose an offer.
- **Design** — `CaptainInbox` writes each pushed offer to DO storage with its
  `expires_at`, and on a new authenticated connection replays unexpired offers
  before the `connected` frame. Drop them on accept/decline/withdraw.
- **Files to change** — `apps/api/src/durable-objects/CaptainInbox.ts` (35–39,
  57–68, 236–254).
- **DB** — none (DO storage).
- **API contract** — none; the replayed frames are the existing `trip.offer`
  shape.
- **Effort** — S.
- **Risk** — replaying a stale offer that was already taken; the `expires_at`
  check plus the P0.2 `trip_offers` state check on accept make this safe.
- **Acceptance criteria** — kill the socket at t=1 s, reconnect at t=5 s, the
  wave-1 card is present.
- **Tests** — DO unit test with a forced disconnect.

### P1.6 — Get the FCM fanout and the D1 heartbeat write off the hot path

- **Goal** — booking latency reflects work the rider is waiting on, and heartbeat
  volume does not scale D1 writes linearly with captains.
- **Design** — (a) replace the awaited `Promise.all` FCM block with
  `ctx.waitUntil` or an enqueue onto the existing `NOTIFICATIONS` queue;
  (b) make `POST /captain/location` write the `GeoCell` DO synchronously but
  debounce the `captains` row `UPDATE` to at most once per 60 s per captain,
  since `last_lat/last_lng` on the row is only read for display and for the
  offers-list fallback.
- **Files to change** — `apps/api/src/routes/trips.ts` (574–585),
  `apps/api/src/routes/captain.ts` (205–221).
- **DB** — none.
- **API contract** — none.
- **Effort** — S.
- **Risk** — `captains.last_seen_at` becomes coarser; anything relying on it for
  freshness must read the DO instead. Grep confirms the offers endpoint uses
  `last_lat/lng` for distance only (`captain.ts:476-477`), which tolerates 60 s.
- **Acceptance criteria** — p95 `POST /trips` drops by ≥300 ms. D1 writes per
  online captain per hour ≤ 60.
- **Tests** — load test comparing p95 before and after.

### P2.1 — Widening ladder and notify-when-available

- **Goal** — a no-supply request has somewhere to go other than failure.
- **Design** — on reaching the P0.4 no-supply point, run one widened pass
  (5×5 cells) before declaring, then offer the rider a "notify me when a captain
  is free" option that registers interest against the pickup cell; when a captain
  next goes online in that cell, push the rider.
- **Files to change** — `apps/api/src/lib/nearby.ts`,
  `apps/api/src/durable-objects/GeoCell.ts`, new `trip_watchers` handling.
- **DB** — `0024_trip_watchers.sql` with `(id, rider_id, cell_key, created_at, expires_at, notified_at)`.
- **API contract** — `POST /trips/:id/watch`, and a push topic `supply.available`.
- **Effort** — L.
- **Risk** — notification spam in low-supply areas; cap one notification per
  rider per hour.
- **Acceptance criteria** — a watching rider is pushed within 30 s of a captain
  going online in their cell.
- **Tests** — integration on the watcher trigger.

### P2.2 — Batched matching, gated on volume

- **Goal** — globally better assignments once request density justifies it.
- **Design** — accumulate requests per cell over a 3 s window and solve a
  min-cost assignment over the ETA matrix from P1.1. Ship behind a per-city flag
  and only enable where the trigger metric (below) is met.
- **Files to change** — new `apps/api/src/lib/matching.ts`, called from
  `dispatchTrip`.
- **DB** — none.
- **API contract** — none.
- **Effort** — L.
- **Risk** — adds up to 3 s to time-to-match at low volume for no benefit. This
  is why it is gated.
- **Acceptance criteria** — do not build until a city sustains ≥3 concurrent
  open requests within one cell for ≥10% of peak-hour minutes. Below that,
  greedy is correct and this is premature.
- **Tests** — simulation comparing total ETA, greedy vs batched, on replayed
  production traffic.

### P2.3 — Supply positioning

- **Goal** — captains are near demand before the request arrives — the Careem
  model, and the right one for this market.
- **Design** — aggregate request counts per cell per 15-minute bucket, expose a
  heatmap in the captain app, and pair it with peak-hour bonuses. Pull, not
  punish.
- **Files to change** — new admin/captain endpoints, captain map overlay.
- **DB** — `0025_demand_buckets.sql` aggregate table.
- **API contract** — `GET /captain/demand-heatmap`.
- **Effort** — L.
- **Risk** — a heatmap built on thin data misleads captains into dead zones;
  suppress cells below a minimum sample count.
- **Acceptance criteria** — heatmap reflects the previous 7 days' demand;
  captains who follow it complete more trips per online hour.
- **Tests** — aggregation correctness against raw trip rows.

## 7. Phasing

**P0 — before any production traffic.** Everything that makes dispatch either
non-functional or actively trap a user. Six items, and P0.1 and P0.4 are the two
I would not negotiate on: without P0.1 there is effectively no supply, and
without P0.4 the product locks riders out of itself.

| Item | Phase | Effort | Owner type | Depends on |
|---|---|---|---|---|
| P0.1 Unconditional captain heartbeat | P0 | S | Flutter + backend | — |
| P0.2 One authority for offer visibility | P0 | M | backend | — |
| P0.3 Fix scheduled-trip dispatch | P0 | M | backend + Flutter (rider) | — |
| P0.4 Terminate unmatched trips, unblock rider | P0 | M | backend + Flutter (rider) | — |
| P0.5 Record declines | P0 | S | backend + Flutter (captain) | P0.2 |
| P0.6 Tell the losers; re-dispatch on captain cancel | P0 | M | backend | P0.2 |
| P1.1 Rank by routed ETA | P1 | M | backend | — |
| P1.2 Vehicle-type matching | P1 | S | backend | needs-check on `0015` |
| P1.3 Fix offers query; drop city from cell key | P1 | M | backend | P0.1 (for re-heartbeat) |
| P1.4 Fairness floor | P1 | M | backend | P0.5 |
| P1.5 Persist and replay the inbox | P1 | S | backend | — |
| P1.6 FCM + D1 writes off the hot path | P1 | S | backend | — |
| P2.1 Widening ladder, notify-when-available | P2 | L | backend + Flutter (rider) | P0.4 |
| P2.2 Batched matching (volume-gated) | P2 | L | backend | P1.1 |
| P2.3 Supply positioning heatmap | P2 | L | backend + Flutter (captain) + admin | — |

Rough shape: P0 is about two engineer-weeks of backend plus a few days of
Flutter on each app. P1 is another two to three weeks. P2 is quarter-scale work
and P2.2 should not start until its volume trigger fires.

Two sequencing notes worth flagging to whoever schedules this. P0.2 is the
keystone — P0.5 and P0.6 both build on `trip_offers`, so it should land first
even though P0.1 is the more urgent symptom. And P1.3's cell-key change forces
every captain to re-heartbeat, which is only safe *after* P0.1 ships; doing them
in the other order produces a supply blackout until captains happen to move.

## 8. Metrics

Nothing on this axis is currently instrumented. `trip_events` rows are written
for `created`, `offered`, `assigned` and `cancelled`
(`apps/api/src/routes/trips.ts:506-511`, `540-542`, `872`, `733`), and the
`offered` event usefully records the candidate list (541) — that is enough raw
material to compute most of the table below retroactively, but nothing is
aggregating it and no dashboard exists.

### 8.1 Latency budget: request created → first offer → accepted

Measured components are from reading the code path; the timings are estimates
grounded in the operation type, and every one of them is `needs-check` until
someone instruments it. I am giving them because a budget with honest estimates
is more useful than no budget, not because these are observed numbers.

**Stage A — `POST /trips` request handler** (rider is blocked on all of this):

| Component | Code | Est. p50 | Est. p95 | Target |
|---|---|---|---|---|
| Active-trip guard | `trips.ts:362-366` | 8 ms | 25 ms | ≤15 ms |
| Pricing lookup | `trips.ts:379` | 8 ms | 25 ms | ≤15 ms |
| **OSRM route** | `trips.ts:382-386` | **120 ms** | **500 ms** | ≤200 ms p95 |
| Promo + company lookups | `trips.ts:402-436` | 15 ms | 45 ms | ≤30 ms |
| Trip INSERT | `trips.ts:441-481` | 12 ms | 40 ms | ≤25 ms |
| **`findNearbyCaptains`** (9 parallel DOs) | `nearby.ts:71-88` | **35 ms** | **220 ms** | ≤100 ms p95 |
| `filterByCaptainRadius` | `trips.ts:531` | 10 ms | 30 ms | ≤20 ms |
| Status UPDATE + `offered` event | `trips.ts:537-542` | 18 ms | 55 ms | ≤35 ms |
| `OfferScheduler` schedule + wave 1 push | `trips.ts:564-571` | 25 ms | 120 ms | ≤80 ms |
| **FCM fanout ×10, awaited** | `trips.ts:574-585` | **180 ms** | **700 ms** | **0 ms — move off path (P1.6)** |
| Re-read trip + `broadcastTrip` | `trips.ts:588-592` | 20 ms | 70 ms | ≤40 ms |
| **Stage A total** | | **~450 ms** | **~1.8 s** | **≤600 ms p95** |

The two dominant controllable costs are the awaited FCM fanout and the OSRM
call. P1.6 removes the first outright — it is pure waste in the request path.
The second is harder: the route is genuinely needed for the fare, though it
could be computed in parallel with candidate discovery rather than before it
(they are independent, and `POST /estimate` at `trips.ts:330-339` already
demonstrates the pattern).

The 9-cell DO fan-out is the interesting one. Warm, it is a few milliseconds;
cold, each `GeoCell` costs an isolate start. p95 is dominated by whichever of the
9 cells is coldest, which in a low-density city is most of them. This improves
naturally with traffic and gets worse if P1.3 moves to a finer grid — a real
trade to watch.

**Stage B — first offer delivered to a captain's device:**

| Path | Est. latency | Note |
|---|---|---|
| WebSocket (socket already open) | +40–120 ms | `OfferScheduler.pushWave` → `CaptainInbox.broadcast`, `OfferScheduler.ts:109-121` |
| FCM (app backgrounded) | +1–5 s | Outside our control; Google's delivery |
| Poll (socket down) | +0–8 s | `captain_state.dart:758` |
| Poll (socket up) | +0–60 s | `captain_state.dart:763` |

**Target: first offer on a captain's screen within 800 ms p95 of the rider
tapping request**, achievable on the WebSocket path once Stage A is fixed.

**Stage C — offer → accept:** entirely captain-dependent, but the system imposes
a floor. Wave 1 covers captains 1–3; if all three decline instantly the rider
still waits 15 s for wave 2 (F-06-09), and the full candidate list takes 45 s to
exhaust. P0.5 removes the artificial floor. Target: **time-to-match p50 ≤ 12 s,
p95 ≤ 45 s** in a supplied cell.

**End-to-end target: request → assigned, p50 ≤ 15 s, p95 ≤ 50 s.** Today the p95
is unbounded, because an unmatched trip never terminates (F-06-04) — which is
also why "unfulfilled rate" below is the metric that matters most on day one.

### 8.2 Dispatch health metrics

| Metric | Definition | Current | Target |
|---|---|---|---|
| **Time-to-match p50 / p95** | `created` → `assigned` from `trip_events` | unknown, unmeasured | ≤12 s / ≤45 s |
| **Offer→accept rate** | accepted offers ÷ offers delivered, per wave | unmeasurable — offers aren't recorded | ≥25% wave 1; ≥60% within 3 waves |
| **Unfulfilled rate** | trips never assigned ÷ trips created, per cell per hour | unknown; currently invisible because they never terminate | ≤5% overall, ≤15% in any single cell |
| **Zero-candidate rate** | `POST /trips` returning `nearbyCaptains: []` | unknown | ≤10%, tracked per cell to target supply spend |
| **Time-to-pickup p50** | `assigned` → `arrived` | unknown | ≤6 min (Cairo) |
| **Wave depth to accept** | which wave produced the winner | unmeasurable today | ≥70% of matches from wave 1 |
| **Captain decline rate** | declines ÷ offers, per captain | not recorded at all (F-06-09) | monitor; no penalty threshold initially |
| **Post-accept cancellation rate** | captain cancels after `assigned` ÷ assigned | computable from `trip_events`, not aggregated | ≤6% |
| **Wave-1 concentration** | share of wave-1 placements going to the top captain in a cell | unmeasured | ≤40% (P1.4's acceptance criterion) |
| **Stale-candidate rate** | candidates whose `lastSeen` is 90–120 s old at query time | unmeasured | ≤5% after P0.1 |
| **Dispatch fan-out cost** | `GeoCell` DO requests per booking | ~9 by construction | keep ≤25 if the grid is refined |
| **Orphaned searching trips** | trips in `searching`/`offered` older than 10 min | unknown, and certainly non-zero | **0** |

The last row is the single best canary for this whole track. If it is anything
other than zero after P0.4, something in the termination path is broken.

Instrumentation is cheap here: the `trip_events` table already exists and
already carries the candidate list on the `offered` event. Adding
`offer.delivered`, `offer.declined`, `offer.withdrawn` and `trip.no_supply`
event types (the last three arrive naturally with P0.4/P0.5/P0.6) makes every
metric above computable with a daily aggregation job. That job, plus a
`GET /admin/dispatch-health` endpoint, is a day of work and should ship with P0.

### 8.3 Durable Object footprint and cost

Question 10 in the brief asks for the DO count at Cairo scale and what it costs.

Greater Cairo is roughly 3,000 km² of serviced area. At geohash-5
(4.89 × 4.24 km ≈ 20.7 km² per cell) that is **~145 `GeoCell` instances**, of
which perhaps 40–60 are active at any time given demand concentration. Each
occupied cell re-arms a 60 s alarm for as long as any captain is present
(`GeoCell.ts:77-80`), so an active cell wakes ~1,440 times/day. At 50 active
cells that is ~72,000 alarm invocations/day, plus one DO request per heartbeat
per captain and nine per booking.

`CaptainInbox` is one DO per online captain, and `OfferScheduler` is one per
dispatched trip — short-lived, self-destructing, and the count tracks bookings
directly.

Two things to note rather than a cost figure I would have to invent. First, all
four classes are declared as `new_sqlite_classes`
(`apps/api/wrangler.toml:31-41`), so they are on the SQLite-backed DO product and
priced on requests, duration and storage rather than the legacy model. Second,
**there is no explicit hibernation handling in `GeoCell` or `OfferScheduler`**,
and `CaptainInbox` uses `ctx.acceptWebSocket` (`CaptainInbox.ts:45`), which is
the hibernation API — so inbox sockets can hibernate but the in-memory
`sessions` map does not survive it, which is the root of F-06-22.

The alarm cadence is the one lever worth pulling early: `GeoCell`'s 60 s alarm
exists only to evict stale records, and eviction could be lazy (drop stale rows
during `/nearby` and `/heartbeat`, which already iterate them) with the alarm
falling back to a much longer sweep. That removes ~72,000 daily invocations for
no behavioural change. I have not costed this precisely — `needs-check` against
current Cloudflare pricing, and T24 owns the number.

## 9. Cross-cutting notes

**→ T07 (Realtime — Durable Objects & WebSockets).** `CaptainInbox.broadcast`
iterates `this.ctx.getWebSockets()` for any socket not in the in-memory
`sessions` map and writes to it unconditionally
(`apps/api/src/durable-objects/CaptainInbox.ts:246-253`). That second loop exists
to handle hibernation-restored sockets, but after a DO eviction the `sessions`
map is empty, so the `pendingAuth` guard at 239 no longer applies to anything —
including a socket that connected with `?pendingAuth=1` (47–49) and never
completed the JWT handshake. Offer payloads carry pickup coordinates and fare.
The `authTimers` map has the same problem: `setTimeout` handles do not survive
hibernation, so the 10 s auth timeout silently stops being enforced. Confidence:
likely — I did not test eviction behaviour. This is a realtime-lifecycle bug
rather than a dispatch bug, which is why it is here and not in §4 as an S1.

**→ T02 (Authorization, RBAC & Object-Level Access).** `POST /trips/:id/accept`
authorises on role, approval and online state but never on *candidacy*
(`apps/api/src/routes/trips.ts:829-870`). Any approved online captain can accept
any open trip anywhere in the country. I have proposed the fix as part of P0.2
because dispatch owns the `trip_offers` table that makes it checkable, but the
authorisation model itself is yours — you may want a broader "captain may act on
trip" predicate that this reuses.

**→ T08 (Data Model, Migrations & Integrity).** Three things.
`migrations/0008_rejection_reason_and_online_guard.sql` is named for an online
guard it does not contain (1–6) — the guard is code-only, and the filename will
mislead anyone auditing migrations for safety controls. The `trips.status`
vocabulary is a bare TEXT column with no constraint, which is how `no_supply`
and `scheduled` can be added cheaply in P0.3/P0.4 but also how an invalid status
could be written silently. And `0019`'s reasoning about D1 never running
`ANALYZE` (11–13) is correct and applies to every other index in the schema —
worth a systematic pass.

**→ T09 (Rider App).** The rider is trapped by an orphaned `searching` trip and
the app throws away the `tripId` the 409 hands it
(`apps/rider/lib/screens/home/fare_estimate_sheet.dart:217-223`,
`apps/api/src/routes/trips.ts:372`). Also `trip_screen.dart:282` pops the trip
screen with no confirmation and no cancel, which is how riders create orphans in
the first place. The backend half is P0.4; the client half is yours.

**→ T10 (Captain App).** `available_trips_tab.dart` is dead code — `main_shell.dart:443`
mounts `NearbyRequestsScreen` instead — and its doc comment advertises a 20 s
poll that does not exist (the real intervals are 8 s and 60 s,
`captain_state.dart:758,763`). More importantly the mounted browse screen has no
socket listener and its own separate skip set
(`nearby_requests_screen.dart:59-61`), so a captain working from that tab
receives no pushed offers at all. Also `offer_card.dart:148-161` renders raw
server error codes to captains — a captain literally reads the string
`TRIP_TAKEN` — and `offer_card.dart:189` stops the countdown when the
counter-offer sheet opens and never restarts it.

**→ T27 (Cross-App Parity).** Both apps ship their own `trip_ws.dart`
(`apps/rider/lib/services/trip_ws.dart`, `apps/captain/lib/services/trip_ws.dart`
— the captain copy's own comment says it "mirrors the rider app's
TripWebSocketService exactly"), their own `login_screen.dart` and their own
`splash_screen.dart`. The reconnect/backoff logic is duplicated in three places
counting `offers_ws.dart`. Relevant to dispatch specifically: the two apps have
*different* reconnect and poll behaviour, so an offer's delivery reliability
depends on which app you are, and any fix to socket resilience has to be made
twice. Whatever the parity plan is, the socket layer should be the first thing
pulled into `packages/flutter_shared`.

**→ T19 (Growth, Notifications & Lifecycle).** The FCM fanout is awaited inline
in the booking request (`trips.ts:574-585`) while a `NOTIFICATIONS` queue with a
DLQ already exists in the stack and is not used for it. Separately, the captain
app's foreground FCM handler shows a local notification but never routes the
payload into offer state (`apps/captain/lib/services/fcm_service.dart:79-93`),
so FCM cannot function as the offer-recovery channel it is being relied on to
be.

**→ T21 (Maps, Routing & Geospatial).** P1.1 depends on an OSRM table call being
fast and reliable enough to sit in the dispatch path with a 250 ms budget. If
that is not achievable with the current routing setup, P1.1 needs rescoping —
worth a conversation. Also `apps/api/src/lib/pricing.ts:30` applies a flat 1.35
road-distance factor to straight-line distance, which is the same
crow-flies-versus-road problem as F-06-08 showing up in fare estimation.

**→ T24 (Performance, Cost & Scale).** The `GeoCell` 60 s alarm cadence
(§8.3) is ~72,000 invocations/day at Cairo scale for eviction work that could be
done lazily. Also every booking fans out to 9 DOs and fetches up to 90 presence
records to return 10 (`nearby.ts:71-88`).

**→ T23 (Testing, CI/CD).** There is no test anywhere exercising dispatch. The
accept race, the wave scheduler's alarm, and the neighbourhood cell derivation
are all the kind of logic that is cheap to test and expensive to get wrong. The
cell-span maths in `neighbourhoodCellKeys` in particular is a pure function with
an obvious property test.

## 10. Open questions

**Q1 — Which matching model is the product actually committing to?**
This is the decision everything else hangs off, and today the codebase answers
it three different ways at once (§5.3).
*Options:* (a) **Uber-style staged assignment** — the system picks, captains
accept or decline, no bidding. (b) **inDrive-style open marketplace** — broadcast
to everyone nearby, captains bid, the rider chooses. (c) **Hybrid** — staged
assignment at the estimated fare, with bidding as an explicit fallback when
wave 1 goes unanswered.
*Recommendation:* **(c)**, and say so in writing. The bidding flow already exists
and works (`trips.ts:1143-1370`), price negotiation is the differentiator against
Careem and Uber in this market, and staged assignment is what keeps time-to-match
low for the ordinary case. But the hybrid only works if one component owns
visibility — which is P0.2 — otherwise it stays the incoherent state it is in
now. Whatever is chosen, P0.2's shape follows from it.

**Q2 — What is the maximum acceptable pickup distance?**
Dispatch currently reaches ~9.7 km with a 15 km default captain radius, so in
practice there is no cap (F-06-15).
*Options:* (a) hard cap at 5 km, refuse to offer beyond it; (b) soft cap —
offer beyond 5 km only after nearer waves are exhausted; (c) leave uncapped.
*Recommendation:* **(b)** with the cap at 5 km. A 9 km pickup is ~25 minutes in
Cairo traffic; riders cancel and captains resent the dead mileage. But refusing
outright in a thin market strands requests, so let distance degrade gracefully
across waves rather than being a hard filter.

**Q3 — Refine the cell grid, or keep geohash-5?**
Geohash-5 cells are ~25× the area of an Uber res-9 cell (§5.1), which makes
`/nearby` scans large at density but keeps the DO count and cold-start count
low at today's volume.
*Options:* (a) keep geohash-5; (b) move to geohash-6 (~1.2 × 0.6 km) with a 5×5
fan-out; (c) adopt H3 properly.
*Recommendation:* **(a) now, (b) when a single cell routinely holds >100 online
captains.** Geohash-5 is genuinely fine at pre-production density and the cost
of changing is real (P1.3 already forces one cell-key migration; don't force
two). Revisit on the metric, not on aesthetics. (c) is not worth the dependency
for a single-metro product.

**Q4 — Should declining have consequences for captains?**
P1.4 deliberately proposes only a cooldown and an idle bonus, no acceptance-rate
penalty.
*Options:* (a) no consequences ever (inDrive's stance); (b) soft — declines
affect wave placement only, never earnings or account standing; (c) Uber-style
acceptance-rate tiers gating bonuses.
*Recommendation:* **(b) now, revisit (c) after six months of data.** Captain
supply is the scarce side in a launching market and penalty systems drive churn
before they drive compliance. Note that (c) is *impossible* today regardless of
preference, because declines are never recorded (F-06-09) — so P0.5 should ship
even if the answer is (a), purely for the analytics.

**Q5 — How long should a rider wait before being told there is no supply?**
P0.4 proposes 90 s.
*Options:* (a) 60 s — fast honesty, may abandon matchable trips; (b) 90 s;
(c) 3 min — matches the industry's 3–5 min expiry convention but is a very long
spinner.
*Recommendation:* **(b) 90 s**, configurable per city, and revisit against the
observed time-to-match p95 once it is measured. The important thing is not the
number — it is that *some* number exists, because today it is infinite.

**Q6 — What should happen to a scheduled trip that finds no captain at T-10min?**
P0.3 dispatches with a 10-minute lead but does not specify the failure path.
*Options:* (a) retry every minute until the scheduled time, then declare
no-supply; (b) declare no-supply immediately at T-10min; (c) escalate to an
operator queue in the admin console.
*Recommendation:* **(a) with (c) as a follow-on.** A scheduled trip is a promise
the rider made plans around — an airport run at 05:00 — and failing it silently
ten minutes before is worse than failing an on-demand request. Retrying costs
little and an operator escalation path is genuinely valuable for the B2B
bookings this feature mostly serves.

**Q7 — Is Cairo/Giza one market or two?**
`city` currently partitions the spatial index itself (F-06-16), so the answer is
encoded as "two" by accident rather than by decision.
*Options:* (a) one contiguous metro pool, city used only for pricing and
reporting; (b) genuinely separate markets with separate supply.
*Recommendation:* **(a)** — this is one metro with one traffic system and
captains cross the line constantly. P1.3 implements it. If the answer is (b),
say so explicitly, because the current behaviour will still be wrong at the
boundary in ways nobody intended.
