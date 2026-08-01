# 07 — Realtime — Durable Objects & WebSockets

> Track: A — Foundation & safety-critical · Reviewer: chat-20260801-1235-66c2 · Date: 2026-08-01 (UTC)
> Base commit reviewed: `f906e0b06240ea84b20ef5c7b5633fd9abe02f8b`

## 1. Scope

Everything that moves without the user asking: the captain's car sliding across the
rider's map, the offer card landing in a captain's inbox, the in-trip chat bubble, and
the status flip from `assigned` to `arrived`. Concretely — the four Durable Objects
(`TripRoom`, `CaptainInbox`, `GeoCell`, `OfferScheduler`), the two WebSocket upgrade
routes in the Worker, the three Flutter socket clients, and the REST paths that feed or
back up any of them.

Judged on six axes: **correctness** (does the message arrive, once, in order),
**authentication** (can a stranger listen or speak), **reconnection** (what the user
sees when the network flaps), **state ownership** (D1 or the DO — and is the answer
consistent), **cost** (Cloudflare duration/requests, and the rider's mobile data), and
**blast radius** (what one failure takes down).

Explicitly **not** covered here, with the track that owns it:

| Out of scope | Owner |
|---|---|
| JWT minting, refresh rotation, session revocation | T01 |
| Whether the *REST* endpoints check object-level access (IDOR) | T02 |
| Which captain *should* win a trip — scoring, radius, fairness | T06 |
| D1 schema, indices, migration safety | T08 |
| Map rendering, marker art, camera behaviour | T21 |
| The duplicated-screen problem in general | T27 |
| Animation curves for the marker glide I recommend in P1.6 | T28 |

One boundary needs stating because it caused the worst finding in this document: I do
cover the **rate limit on `POST /captain/location`**, even though rate limiting is
nominally an infrastructure concern, because it is the mechanism that determines how
often the rider's car marker moves. It is a realtime bug wearing a middleware costume.

## 2. What I actually read

Every file below was downloaded at commit `f906e0b0` and read from disk, so line
numbers in this document are real. Where I skimmed, I say so.

**Durable Objects — read in full, line by line**

| File | Lines | Note |
|---|---|---|
| `apps/api/src/durable-objects/TripRoom.ts` | 290 | Per-trip fan-out. The centre of this review. |
| `apps/api/src/durable-objects/CaptainInbox.ts` | 255 | Per-captain offer inbox + the pending-auth proxy. |
| `apps/api/src/durable-objects/OfferScheduler.ts` | 158 | Wave rollout driven by alarms. The best-built object of the four. |
| `apps/api/src/durable-objects/GeoCell.ts` | 82 | Presence only; no sockets. |

**Worker — read in full**

| File | Lines | Note |
|---|---|---|
| `apps/api/src/index.ts` | 372 | DO exports, both `/ws/*` upgrade routes, CORS, queue + cron handlers. |
| `apps/api/wrangler.toml` | 180 | Bindings, migrations v1–v3, `compatibility_date = "2025-04-01"`. |
| `apps/api/src/middleware/rateLimit.ts` | 90 | Fixed-window KV limiter. Read closely — it matters more than it looks. |

**Worker — read the realtime-relevant sections closely, skimmed the rest**

| File | Lines | What I read |
|---|---|---|
| `apps/api/src/routes/trips.ts` | 1371 | `broadcastTrip` (160–174), trip creation + dispatch (515–600), cancel (720–800), accept (829–889), status advance (900–930), complete (960–1060), bids (1170–1200), accept-bid (1262–1371), `GET /trips/:id` (647–680). Skimmed pricing/promo blocks. |
| `apps/api/src/routes/captain.ts` | 700 | `POST /location` in full (190–271), `POST /online` (160–188), `GET /offers` (439–480). Skimmed earnings/documents. |
| `apps/api/src/routes/safety.ts` | 291 | Chat send + broadcast (150–200), typing (260–290). Skimmed SOS. |
| `apps/api/src/lib/schemas.ts` | — | `captainLocationSchema` only (181–187). |
| `apps/api/src/lib/nearby.ts` | 105 | Cell fan-out and per-cell error isolation. |
| `apps/api/src/lib/notifications.ts` | 408 | Skimmed — confirmed `pushToUser` is the FCM path used by the offer blast. |

**Flutter clients — read in full**

| File | Lines | Note |
|---|---|---|
| `apps/rider/lib/services/trip_ws.dart` | 117 | Rider socket. |
| `apps/captain/lib/services/trip_ws.dart` | 132 | Captain trip socket — a near-duplicate of the above. |
| `apps/captain/lib/services/offers_ws.dart` | 114 | Captain offer socket. |
| `apps/rider/lib/screens/trip/trip_chat_screen.dart` | 150 | Read in full because of what is *missing* from it. |

**Flutter — read the realtime paths, skimmed layout code**

| File | Lines | What I read |
|---|---|---|
| `apps/captain/lib/services/captain_state.dart` | 1189 | Location stream + accuracy profiles (610–700), socket wiring (760–900), `refreshOffers` (902–976), lifecycle (1081–1105), dispose/logout (1141–1188). |
| `apps/rider/lib/screens/trip/trip_screen.dart` | 835 | `_loadTrip`/`_connectWs`/`_startPolling`/`dispose` (50–190), marker build (318–394), status badge (412–426). Skimmed the sheet layouts. |
| `apps/rider/lib/services/app_state.dart` | 696 | Grepped for socket/chat wiring — there is none; confirmed by exhaustive grep. |
| `apps/captain/lib/screens/home/active_trip_panel.dart` | 708 | Event subscription + dispose (40–120). |
| `apps/captain/lib/screens/home/trip_chat_screen.dart` | 421 | Socket + poll + typing (50–100). |
| `apps/captain/lib/screens/home/available_trips_tab.dart` | 303 | Connection telltale (255–300). |
| `apps/rider/lib/services/location_service.dart` | 303 | Confirmed it holds no GPS publisher — geocoding and routing helpers only. |

**Docs read for context** (and deliberately written *on top of*, not restated):
`docs/ARCHITECTURE.md` (91), `docs/COST.md` (27), `docs/API.md` (155),
`docs/IMPROVEMENTS.md` (67).

**External, for the cost model and the benchmark section** — Cloudflare's published
Durable Objects [pricing](https://developers.cloudflare.com/durable-objects/platform/pricing/),
[WebSocket best practices](https://developers.cloudflare.com/durable-objects/best-practices/websockets/),
[lifecycle](https://developers.cloudflare.com/durable-objects/concepts/durable-object-lifecycle/),
[State API](https://developers.cloudflare.com/durable-objects/api/state/) and
[Alarms](https://developers.cloudflare.com/durable-objects/api/alarms/) pages.

**Not read, and it matters:** there are no tests anywhere near this surface. No unit
test for `TripRoom`, no integration test for the upgrade routes, nothing that would have
caught the rate-limit collision in §4 F-07-02. Flagged to **T23**.

## 3. How it works today

### 3.1 The shape of it

Four Durable Objects, two of which hold WebSockets:

```
                    POST /captain/location  (≤30/min enforced)
 Captain app ──────────────────┬─────────────────────────────────► GeoCell (presence)
      │                        └──────────► TripRoom ──► rider socket
      │  WS /ws/captain/offers
      └──────► CaptainInbox("pending-auth")  ──relay──►  CaptainInbox(captainId)
                                                              ▲
 Rider app ──── WS /ws/trips/:id ──► TripRoom(tripId)          │ /push
      │                                   ▲                    │
      └──── GET /trips/:id every 10s      │            OfferScheduler(tripId)
                                          │                 (alarm, 15s waves)
            POST /trips/... ──► broadcastTrip() ──┘
```

`GeoCell` and `OfferScheduler` are request/response objects with alarms; they hold no
sockets. All WebSocket traffic lives in `TripRoom` and `CaptainInbox`.

### 3.2 State ownership — D1 is the source of truth, mostly

**D1 owns trip state.** Every status transition is written to `trips` first, then
announced. The announcement helper is `broadcastTrip()`
(`apps/api/src/routes/trips.ts:160-174`): it enriches the row with captain facts, POSTs
`{type:"trip.updated", trip}` to the room, and then PUTs the same object to the room's
`/state`.

The DO is therefore a **fan-out bus with a cache**, not an authority — which is the
right choice, and it is applied consistently for status. There is one exception worth
naming: live captain position. `POST /captain/location` writes `trips.captain_lat/lng`
to D1 (`apps/api/src/routes/captain.ts:231-235`) and broadcasts `location.captain`
(`:255-265`), but it never PUTs `/state`. So `TripRoom`'s stored `trip` snapshot carries
the captain position *as of the last status change*, while D1 carries the latest ping.
A client that reconnects and reads `/state` gets a staler position than one that calls
`GET /trips/:id`. Nothing reads `/state` today (see §3.5), so this is latent rather than
live — but it is a split-brain seed.

`TripRoom` also stores `lastLocation` on every inbound socket location frame
(`apps/api/src/durable-objects/TripRoom.ts:176`) and never sends it to anyone. Dead
write.

### 3.3 Authentication — two paths, and the second one is load-bearing

Both upgrade routes accept a token in an `Authorization: Bearer` header or a deprecated
`?token=` query param, and fall back to a **first-message handshake** when neither is
present (`apps/api/src/index.ts:129-182` and `:187-230`).

*Trip room, token present* — the Worker verifies the JWT, rejects refresh tokens,
queries `trips` for membership, and forwards `?role=&userId=` to the DO
(`index.ts:151-167`). Clean.

*Trip room, no token* — the Worker forwards `?pendingAuth=1&tripId=<id>`
(`index.ts:175-176`). The DO accepts the socket, marks the session pending, arms a 10 s
`setTimeout`, and sends `{"type":"auth.required"}`
(`TripRoom.ts:109-119`). The client must reply `{"type":"auth","token":...}`; the DO
then re-verifies the JWT and re-checks trip membership itself
(`TripRoom.ts:199-242`) before flipping `pendingAuth` to false.

*Captain inbox, no token* — this is the load-bearing one, and it is strange. Because the
Worker cannot derive the per-captain DO id without a verified token, it routes the socket
to **one shared, well-known object**:

```ts
// apps/api/src/index.ts:226-229
const id = c.env.CAPTAIN_INBOX.idFromName("pending-auth");
const stub = c.env.CAPTAIN_INBOX.get(id);
url.searchParams.set("pendingAuth", "1");
return stub.fetch(url.toString(), c.req.raw);
```

After the handshake succeeds, that shared object opens a *second* WebSocket to the
captain's real inbox and proxies frames in both directions
(`CaptainInbox.ts:165-191`). All three Flutter clients use the first-message flow and
send no token in the URL (`offers_ws.dart:54-56`, `trip_ws.dart:73-74` in both apps), so
**this shared object is the front door for every captain socket in the fleet.**

### 3.4 The message catalogue

Every event that crosses a socket, exhaustively. "Freq" is per trip unless noted.

| # | `type` | Payload fields | Producer (`path:line`) | Transport | Consumers | Freq |
|---|---|---|---|---|---|---|
| 1 | `trip.updated` | `type`, `trip` (full row + captain name/phone/avatar/vehicle/rating) | `trips.ts:166-169` via `broadcastTrip` | TripRoom `/broadcast` | rider `trip_screen.dart:141`; captain `captain_state.dart:868-900` | ~6 |
| 2 | *(untyped state blob)* | the same enriched trip object, no `type` field | `trips.ts:170-173` | TripRoom `PUT /state` | **nobody** | ~6 |
| 3 | `location.captain` | `type`, `tripId`, `lat`, `lng`, `heading`, `at` | `captain.ts:255-265` | TripRoom `/broadcast` | rider `trip_screen.dart:143-150` | ≤450 (capped) |
| 4 | `location.captain` | `type`, `lat`, `lng`, `heading`, `userId`, `at` — **note: no `tripId`** | `TripRoom.ts:167-178` (inbound socket frame) | TripRoom self-broadcast | rider | 0 today |
| 5 | `chat.message` | `type`, `tripId`, `msgId`, `senderId`, `senderRole`, `body`, `at` | `safety.ts:180-191` | TripRoom `/broadcast` | captain only (`trip_chat_screen.dart:68`, `active_trip_panel.dart:60`) — **rider has no handler** | 0–20 |
| 6 | `chat.typing` | `type`, `tripId`, `senderId`, `senderRole`, `typing`, `at` | `safety.ts:274-284` | TripRoom `/broadcast` | captain only (`trip_chat_screen.dart:72`) | 0–40 |
| 7 | `trip.offer` | `type`, `tripId`, `city`, `pickupLat/Lng`, `dropoffLat/Lng`, `estimatedFare`, `currency`, `at`, `+distanceKm` | built `trips.ts:549-560`, pushed `OfferScheduler.ts:113-116` | CaptainInbox `/push` | captain `captain_state.dart:825-841` | 1 per captain per wave |
| 8 | `trip.cancelled` | `type`, `tripId`, `at` | `trips.ts:782-791` | CaptainInbox `/push` | captain `captain_state.dart:825-841` | 0–1 |
| 9 | `trip.assigned` | `type`, `reason:"bid.accepted"`, `tripId`, `bidId`, `acceptedPrice`, `at` | `trips.ts:1347-1354` | CaptainInbox `/push` | captain `captain_state.dart:825-841` | 0–1 |
| 10 | `connected` | `type`, `tripId`, `role` / `type`, `channel`, `userId` | `TripRoom.ts:125-131`, `:238`; `CaptainInbox.ts:61-67`, `:193-195` | direct | **nobody** | 1 per connect |
| 11 | `auth.required` | `type`, `tripId`\|`channel`, `timeoutMs` | `TripRoom.ts:117-119`; `CaptainInbox.ts:50-56` | direct | **nobody** | 1 per connect |
| 12 | `auth.failed` | `type` | `TripRoom.ts:202`; `CaptainInbox.ts:139` | direct | **nobody** | on failure |
| 13 | `pong` | `type`, `t` | `TripRoom.ts:163`; `CaptainInbox.ts:110` | direct | **nobody** | ~36 per socket |
| 14 | `error` | `type`, `message:"invalid message"` | `TripRoom.ts:180`; `CaptainInbox.ts:90,113` | direct | **nobody** | rare |
| 15 | `offer.withdrawn` / `bid.accepted` | — | **no producer found** | — | captain `captain_state.dart:825-841` handles both | never |

Two things fall out of this table immediately. **Six of the fifteen message types have
no consumer at all** (#2, #10, #11, #12, #13, #14) — the servers are politely announcing
things into a void. And **two message types have a consumer but no producer** (#15):
the captain handles `offer.withdrawn` and `bid.accepted`, which nothing in the API ever
sends. That is the signature of a contract nobody owns.

The catalogue is also the answer to brief question 4: there is **no envelope**. No
version field, no message id, no sequence number, no timestamp discipline (`at` is
present on some types and absent on others). Every payload is a bare ad-hoc object whose
shape is defined only by the line of code that builds it.

### 3.5 The reconnect and fallback story

| | Rider (`trip_screen`) | Captain (offers) | Captain (trip) |
|---|---|---|---|
| Auth | first-message (`trip_ws.dart:57`) | first-message (`offers_ws.dart:54`) | first-message (`trip_ws.dart:73`) |
| Backoff | `1<<min(n,4)` s + 0–999 ms jitter (`:93-94`) | identical (`:90-95`) | identical (`:110-114`) |
| Max attempts | unbounded | unbounded | unbounded |
| Ping | 25 s (`:76`) | 25 s (`:73-76`) | 25 s (`:92-95`) |
| Pong timeout | **none** | **none** | **none** |
| 4401 handling | **none** — reconnects forever | **none** | **none** |
| Backstop poll | `GET /trips/:id` every **10 s, always on** (`trip_screen.dart:56-57,172`) | `/captain/offers` every **8 s down / 60 s up** (`captain_state.dart:758-766`) | chat poll 6 s (`trip_chat_screen.dart:78`) |
| Resync on reconnect | **no** — relies on the poll | yes — `refreshOffers()` re-reads offers *and* active trip (`captain_state.dart:902-976`) | via `refreshOffers()` |
| Lifecycle aware | **no** observer at all | yes (`captain_state.dart:1081-1105`) | yes |
| Connection UI | **none** | yellow telltale (`available_trips_tab.dart:261-296`) | **none** |

The captain app is markedly more mature here: dual-cadence polling that *slows down*
when the socket is healthy, a real lifecycle observer that parks the GPS radio when
backgrounded, an honest connection indicator, and a genuine resync. The rider app polls
at a flat 10 s forever, has no lifecycle observer, no resync, and no indicator. The
comment above the rider's poll is candid about why it exists
(`trip_screen.dart:163-169`): *"`TripRoom` has failed closed before… this screen sat on
`searching` for the life of the trip."* The poll is scar tissue, and it is currently the
only thing holding the rider experience together.

### 3.6 Offer dispatch — three channels, one schedule

`OfferScheduler` is genuinely well built. It stores the captain list, releases three at a
time, arms a `storage.setAlarm` 15 s out, and — critically — **re-reads trip status from
D1 before every wave** and tears down if the trip left `searching`/`offered`
(`OfferScheduler.ts:134-151`). The docstring explaining why `ctx.waitUntil` was
insufficient (`:24-27`) is correct and shows real Workers fluency.

The problem is that it is one of three delivery channels and the only one that respects
the schedule:

1. **Socket card** — waves of 3, 15 s apart, via `CaptainInbox` (`OfferScheduler.ts:101-121`).
2. **FCM push** — *all ten captains, immediately*, in the same request that armed the
   scheduler (`trips.ts:574-585`). The comment concedes it: *"FCM fanout keeps the
   previous blast."*
3. **REST poll** — `GET /captain/offers` returns `status IN ('searching','offered')` for
   the whole city, radius-filtered, capped at 20 (`captain.ts:462-467`). No wave
   awareness, and **no restriction to the ten captains the scheduler knows about.**

So the wave mechanism throttles the one channel that was never the problem, while a
push notification hits all ten phones at t=0 and an 8-second poll shows the trip to
every online captain in Cairo inside the radius.

### 3.7 The location hot path

This is the busiest code path in the product. Per accepted ping
(`apps/api/src/routes/captain.ts:198-270`):

1. KV read + KV write for the rate limiter (`rateLimit.ts:29,50`)
2. `UPDATE captains SET last_lat, last_lng, last_seen_at, is_online, city, updated_at` (`:205-209`)
3. `GeoCell` `/heartbeat` — a DO round-trip, awaited (`:213-221`)
4. `SELECT * FROM trips WHERE id = ? AND captain_id = ?` (`:224-228`)
5. `UPDATE trips SET captain_lat, captain_lng, updated_at` (`:231-235`)
6. `SELECT recorded_at FROM trip_path_points … ORDER BY recorded_at DESC LIMIT 1` (`:238-242`)
7. conditionally `INSERT INTO trip_path_points` (~every 30 s) (`:246-251`)
8. `TripRoom` `/broadcast` — a second DO round-trip, awaited (`:254-265`)

**Five D1 statements and two sequential Durable Object round-trips, to move a dot four
metres.** Everything is awaited before the `{ok:true}` returns, so the captain's phone
waits for all of it.

## 4. Findings

Severity per `board/TEMPLATE.md`. Confidence: **confirmed** = I read the code and the
behaviour follows directly; **likely** = strong inference across files; **needs-check** =
could not verify without running it.

| ID | Sev | Finding | Evidence (`path:line`) | Impact | Confidence |
|---|---|---|---|---|---|
| F-07-01 | S1 | Captain publishes location 1.7–3.9× faster than the server's own rate limit accepts; excess is 429'd and silently discarded | `apps/captain/lib/services/captain_state.dart:625`, `:673-682`; `apps/api/src/routes/captain.ts:192-197`; `apps/api/src/middleware/rateLimit.ts:24` | Rider's car marker freezes for ~30–45 s of every minute, then teleports. The core live-tracking promise is broken at any real driving speed. | confirmed |
| F-07-02 | S1 | Per-connection session state lives only in an in-memory `Map` while sockets are accepted through the Hibernation API; eviction wipes identity and the auth gate | `apps/api/src/durable-objects/TripRoom.ts:30-31`, `:151-160`, `:268-288`; `CaptainInbox.ts:29-30`, `:79-105` | After any eviction, `sessions.get(ws)` is `undefined`, so `pendingAuth` reads falsy and the auth check at `TripRoom.ts:153` stops gating. Identity (`role`, `userId`) is lost on surviving sockets. | confirmed |
| F-07-03 | S1 | The `CaptainInbox` relay is an in-memory field; when the shared object is evicted the proxy dies while the client's socket stays open and healthy-looking | `apps/api/src/durable-objects/CaptainInbox.ts:9`, `:98-105`, `:176-191` | Captain's offer socket answers pings normally but receives no offers, forever, with no reconnect trigger. Only the 60 s REST poll saves them — by which time every wave has fired. | confirmed |
| F-07-04 | S1 | Every captain offer socket in the fleet enters through a single shared Durable Object named `"pending-auth"` | `apps/api/src/index.ts:226-229`; `apps/captain/lib/services/offers_ws.dart:54-56` | One single-threaded object is a fleet-wide SPOF and a hard concurrency ceiling for offer delivery; it also doubles the DO count and socket count per online captain. | confirmed |
| F-07-05 | S1 | The rider can never receive a chat message in real time — no `chat.message` handler exists anywhere in the rider app, and the rider chat screen fetches once and never again | `apps/rider/lib/screens/trip/trip_chat_screen.dart:19-23`, `:34-49`; `apps/rider/lib/screens/trip/trip_screen.dart:138-152`; exhaustive grep of `apps/rider/lib` returns zero hits for `chat.message` | A captain's message reaches D1 and the socket but never the rider's screen unless they close and reopen the chat. On a safety-adjacent surface shipped as a feature (`index.ts:94`). | confirmed |
| F-07-06 | S1 | No role check on the inbound `location` frame: any authenticated participant can inject the captain's position | `apps/api/src/durable-objects/TripRoom.ts:167-178` | A rider can broadcast a forged `location.captain` to their own trip room. Combined with F-07-02 the forged frame is also attributed `userId: null`. | confirmed |
| F-07-07 | S2 | The staged offer rollout is defeated by an immediate FCM blast to all ten captains and by an unscoped REST offers endpoint | `apps/api/src/routes/trips.ts:572-585`; `apps/api/src/routes/captain.ts:462-467` | `OfferScheduler`'s entire purpose — preventing a ten-captain acceptance race — is nullified. Two of three channels ignore the wave schedule. | confirmed |
| F-07-08 | S2 | `broadcastTrip()` has no error handling and makes two sequential DO round-trips inside the request | `apps/api/src/routes/trips.ts:160-174`, called at `:592`, `:737`, `:876`, `:923`, `:1060`, `:1196`, `:1330` | A TripRoom hiccup turns an already-committed D1 state change into a 500. The rider's app sees a failed cancel/complete on a trip that *is* cancelled/completed. | confirmed |
| F-07-09 | S2 | No message envelope: no version, no sequence number, no message id | catalogue in §3.4; `TripRoom.ts:117-131`, `:168-175`; `trips.ts:166-173` | No client can detect a gap, order two frames, or reject a message shape it does not understand. Six message types have no consumer; two consumed types have no producer. | confirmed |
| F-07-10 | S2 | The rider's backstop poll re-downloads the entire trip, every `trip_events` row, and the full route geometry every 10 s | `apps/api/src/routes/trips.ts:662-679`; `apps/rider/lib/screens/trip/trip_screen.dart:172` | The fallback costs roughly 7× the mobile data of the socket it backs up (§5.3). Runs unconditionally for the whole trip, including while the socket is perfectly healthy. | confirmed |
| F-07-11 | S2 | The rider socket never resyncs after reconnect | `apps/rider/lib/services/trip_ws.dart:49-84`; `apps/rider/lib/screens/trip/trip_screen.dart:132-154` | Any status transition missed during a reconnect is missed on the socket permanently; only the 10 s poll recovers it. Remove the poll and the rider hangs on a stale status forever. | confirmed |
| F-07-12 | S2 | Close code 4401 and `auth.failed` are unhandled on all three clients; both reconnect forever | `apps/rider/lib/services/trip_ws.dart:71`; `apps/captain/lib/services/offers_ws.dart:68-69`; `apps/captain/lib/services/trip_ws.dart:87-88` | An expired token produces an infinite 1→16 s reconnect loop against a server that will never accept it, draining battery and burning DO requests, with no user-visible error and no token refresh. | confirmed |
| F-07-13 | S2 | Application-level 25 s JSON pings wake the Durable Object and are billable; `setWebSocketAutoResponse` exists for exactly this | `apps/api/src/durable-objects/TripRoom.ts:162-165`; `CaptainInbox.ts:107-114`; clients at `trip_ws.dart:75-80` (rider), `:92-95` (captain), `offers_ws.dart:73-76` | Every idle room is woken ≥2×/25 s purely to say "pong", defeating hibernation on otherwise-quiet rooms. Cloudflare documents auto-response as free and non-waking. | confirmed |
| F-07-14 | S2 | No backpressure anywhere: `broadcast()` never inspects `bufferedAmount` | `apps/api/src/durable-objects/TripRoom.ts:268-288`; `CaptainInbox.ts:236-254` | A slow or stalled client causes unbounded buffering inside the DO, charged as memory and eventually killing the object for everyone else in the room. | confirmed |
| F-07-15 | S2 | The location hot path costs 5 D1 statements + 2 awaited DO round-trips per ping | `apps/api/src/routes/captain.ts:198-270` | ~2.25 M D1 statements per 1,000 trips (§5.2). Sustained write pressure on one SQLite DB, and the captain's phone waits for the whole chain. | confirmed |
| F-07-16 | S2 | The rider has no connection indicator of any kind; `onStatus` is emitted but never wired up | `apps/rider/lib/services/trip_ws.dart:51`, `:62`, `:88`, `:115`; `apps/rider/lib/screens/trip/trip_screen.dart:134-153` | The rider cannot distinguish "captain is stationary" from "we lost the connection". The captain app solves this for offers (`available_trips_tab.dart:261-296`) — the pattern exists and was not carried over. | confirmed |
| F-07-17 | S3 | `?tripId=` is forwarded only on the pending-auth branch, so a header-authenticated first connection resolves the trip id to the 64-hex `DurableObjectId` | `apps/api/src/index.ts:166-167` vs `:175-176`; `TripRoom.ts:49-74`, `:107` | The `connected` frame can carry a bogus `tripId`. Harmless today only because nobody reads it (§3.4 #10). PR #47's fix is real but incomplete — the fallback chain, not the caller, is doing the work. | confirmed |
| F-07-18 | S3 | `TripRoom` stores `lastLocation` and never replays it to a joining socket | `apps/api/src/durable-objects/TripRoom.ts:176`; `:125-131` | On reconnect the rider's map has no car until the next location broadcast — up to 2 s at best, 40 s given F-07-01. The data needed to fix it is already stored. | confirmed |
| F-07-19 | S3 | `heading` is dead end-to-end: the schema accepts it, the client never sends it, the rider never reads it | `apps/api/src/lib/schemas.ts:184`; `apps/captain/lib/services/captain_state.dart:676-681`; `apps/api/src/routes/captain.ts:262`; grep for `heading` in `trip_screen.dart` returns nothing | The car marker can never rotate to face its direction of travel. Every `location.captain` frame carries a `null` field. | confirmed |
| F-07-20 | S3 | No pong timeout on any client — a half-open TCP connection is never detected | `apps/rider/lib/services/trip_ws.dart:75-80`; `apps/captain/lib/services/trip_ws.dart:92-95`; `offers_ws.dart:73-76` | Pings are sent into a dead socket forever. On Android a backgrounded-then-foregrounded app commonly holds exactly this kind of zombie connection; nothing triggers a reconnect. | confirmed |
| F-07-21 | S3 | The rider marker jumps between fixes — no interpolation or animation | `apps/rider/lib/screens/trip/trip_screen.dart:149`, `:318-394` | Even with the cadence fixed, the car teleports every update instead of gliding. This is the single cheapest perceived-quality win in the document. | confirmed |
| F-07-22 | S3 | The offers socket stays open for the whole active trip alongside the trip socket | `apps/captain/lib/services/captain_state.dart:771-772`, `:1147`, `:1183` | Two sockets, two DOs, two 25 s ping timers per captain during every trip, for offers they cannot accept. | confirmed |
| F-07-23 | S3 | `GeoCell` re-arms a 60 s alarm indefinitely while any captain record remains | `apps/api/src/durable-objects/GeoCell.ts:32-35`, `:68-81` | Every populated cell wakes 1,440×/day whether or not anything changed. Correct, but a standing cost proportional to city coverage rather than to demand. | confirmed |
| F-07-24 | S3 | The global 120 req/min limiter keys on client IP, and location pings consume up to a quarter of it | `apps/api/src/index.ts:59-66`; `apps/api/src/middleware/rateLimit.ts:18-22` | On Egyptian mobile CGNAT, several captains share one public IP. Four active captains at 30 pings/min exhaust the shared budget and 429 each other out of the entire API, not just location. | likely |
| F-07-25 | S3 | `OfferScheduler` `/cancel` is never called on either accept path | `apps/api/src/routes/trips.ts:829-889`, `:1262-1371`; `OfferScheduler.ts:134-151` | One redundant alarm wake and up to 15 s of stale DO storage per accepted trip. **Bounded, not a leak** — see §4.1 for why the brief's "orphaned alarm billing forever" premise does not hold. | confirmed |
| F-07-26 | S4 | The two `trip_ws.dart` implementations have diverged into different architectures | `apps/rider/lib/services/trip_ws.dart` (callback-based, 4 status transitions) vs `apps/captain/lib/services/trip_ws.dart` (broadcast-stream, silent) | Identical reconnect maths maintained in two places; one exposes connection state and the other cannot. Handed to **T27**. | confirmed |
| F-07-27 | S4 | The KV fixed-window limiter is eventually consistent and writes via `waitUntil` | `apps/api/src/middleware/rateLimit.ts:24`, `:49-53` | The counter under-counts under concurrency, so the effective location cap is fuzzy and varies by PoP — which makes F-07-01's symptom intermittent and hard to reproduce. | likely |
| F-07-28 | S4 | Malformed frames get an `error` reply no client handles; `type:"trip.chat"` is accepted by the captain but never produced | `TripRoom.ts:180`; `apps/captain/lib/screens/home/trip_chat_screen.dart:68` | Dead contract surface accumulating in both directions. | confirmed |

### 4.1 What the S1s actually mean

**F-07-01 — the rate limit and the GPS filter were designed by different people on
different days.**

Two reasonable-looking decisions, made independently, that cannot both hold:

```dart
// apps/captain/lib/services/captain_state.dart:623-626
static LocationSettings get _tripLocationSettings => const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10, // precise tracking while on a trip
    );
```

```ts
// apps/api/src/routes/captain.ts:190-197
captainRoutes.post(
  "/location",
  rateLimit({ prefix: "captain-loc", limit: 30, windowSec: 60,
              keyFn: (c) => c.get("user")?.id ?? "anon" }),
```

A 10-metre distance filter is a *speed-dependent* publish rate. The 30/min cap is a
*time-based* one. Work out where they meet:

| Speed | Metres/s | 10 m interval | Publishes/min | Server accepts | **Dropped** |
|---|---|---|---|---|---|
| 20 km/h (congested Cairo) | 5.6 | 1.80 s | 33 | 30 | 9 % |
| 30 km/h (typical city) | 8.3 | 1.20 s | 50 | 30 | **40 %** |
| 50 km/h (clear arterial) | 13.9 | 0.72 s | 83 | 30 | **64 %** |
| 80 km/h (Ring Road) | 22.2 | 0.45 s | 133 | 30 | **77 %** |

The percentage understates the damage, because `rateLimit` is a **fixed window**, not a
sliding one or a token bucket:

```ts
// apps/api/src/middleware/rateLimit.ts:24
const bucket = Math.floor(Date.now() / 1000 / opts.windowSec);
```

The captain therefore spends their 30 allowed pings in the first **22 seconds** of each
minute at 30 km/h — or the first **13 seconds** at 80 km/h — and every subsequent ping
until the bucket rolls is rejected. The rider does not see a degraded 30-updates-per-minute
stream. They see the car move smoothly for a quarter of a minute, **freeze for the
remaining 38–47 seconds, then teleport** to where it now is. Once a minute. For the
entire trip.

The client cannot tell, because the failure is swallowed whole:

```dart
// apps/captain/lib/services/captain_state.dart:673-682
Future<void> pushLocationCoordinates(double lat, double lng) async {
  if (!online && activeTrip == null) return;
  try {
    await _post('/captain/location', { ... });
  } catch (_) {}          // ← the 429 dies here
}
```

No backoff, no queue, no coalescing of the dropped fix into the next accepted one, no
telemetry. `_post` does throw on a 4xx (`captain_state.dart:287-289`), so the information
exists at the call site and is discarded one line later. Nobody will ever see this in a
dashboard; they will see it in a support ticket that says *"الكابتن واقف على الخريطة"*
and be unable to reproduce it in the office, because at walking pace the filter produces
fewer than 30 pings/min and everything works.

This is the finding I would fix first. It is also the cheapest: the two numbers simply
have to be derived from one another (P0.1).

**F-07-02 and F-07-03 — hibernation is enabled, and the code is written as if it is not.**

`TripRoom` and `CaptainInbox` both accept sockets through the Hibernation API:

```ts
// apps/api/src/durable-objects/TripRoom.ts:105
this.ctx.acceptWebSocket(server);
```

That is the correct, cost-aware choice, and the handler names (`webSocketMessage`,
`webSocketClose`, `webSocketError`) are the right hibernation-style handlers. But
Cloudflare is explicit about the contract that comes with it: *"When a Durable Object
receives no events (such as alarms or messages) for a short period, it is evicted from
memory. During hibernation: WebSocket clients remain connected to the Cloudflare network;
**in-memory state is reset**; when an event arrives, the Durable Object is re-initialized
and its `constructor` runs."*
([best practices](https://developers.cloudflare.com/durable-objects/best-practices/websockets/))

Both objects keep every scrap of per-connection state in exactly the place that gets
reset:

```ts
// apps/api/src/durable-objects/TripRoom.ts:30-31
sessions: Map<WebSocket, Session> = new Map();
authTimers: Map<WebSocket, number> = new Map();
```

Neither calls `serializeAttachment()`, the documented mechanism for exactly this problem
(16 KB per socket, survives hibernation). So after an eviction:

*The auth gate stops being a gate.* `webSocketMessage` looks the session up and gets
`undefined`:

```ts
// apps/api/src/durable-objects/TripRoom.ts:151-160
const session = this.sessions.get(ws);          // undefined after eviction
if (session?.pendingAuth) {                     // undefined?.x → undefined → falsy
  if (data.type === "auth") { ... }
  return;                                       // ← never reached
}
```

Execution falls straight through to the `ping` and `location` handlers. A socket that was
still `pendingAuth` when the object was evicted is, on wake, indistinguishable from an
authenticated one — and `broadcast()` will now send it everything, because the
`pendingAuth` skip only guards sockets still present in the Map, while the second loop
sends to every socket that is *absent* from it:

```ts
// apps/api/src/durable-objects/TripRoom.ts:270-288
for (const [socket, session] of this.sessions) {
  if (session.pendingAuth) continue;            // empty Map → loop does nothing
  ...
}
for (const ws of this.ctx.getWebSockets()) {
  if (this.sessions.has(ws)) continue;          // false for everyone → send to all
  ws.send(raw);                                 // ← no pendingAuth check here
}
```

Reaching that state requires an eviction *while a socket is still pending*, and there is
a genuine mitigation: Cloudflare lists *"no `setTimeout`/`setInterval` scheduled callbacks
are set"* among the conditions required for hibernation
([lifecycle](https://developers.cloudflare.com/durable-objects/concepts/durable-object-lifecycle/)),
so the 10 s `armAuthTimeout` timer (`TripRoom.ts:244-258`) does block hibernation for its
own duration. **The timeout works.** But hibernation is not the only eviction: a
deployment evicts every object, and this API deploys from CI. A deploy landing inside
somebody's 10-second auth window leaves an ungated socket attached to a live trip room.
I mark the *mechanism* confirmed and the *frequency* likely.

The consequence that needs no eviction race at all is the loss of identity on
**authenticated** sockets. After a routine idle hibernation, every surviving socket has
lost its `role` and `userId`. Broadcasts still reach clients (via `getWebSockets()`), so
nothing looks broken — but the DO can no longer tell a rider from a captain, which is
precisely what F-07-06 needs it to do.

And in `CaptainInbox` the same reset is unambiguously fatal, because the relay itself is
an in-memory field:

```ts
// apps/api/src/durable-objects/CaptainInbox.ts:9, 176
relay?: WebSocket;
...
session.relay = upstream;
```

After eviction, `session` is `undefined`, so the forwarding branch at `:98-105` is skipped
and the frame falls through to `:107-114` — where a `ping` is answered locally with a
cheerful `pong`. **The captain's app has a socket that responds to heartbeats and delivers
no offers.** Every client-side health signal says green. There is no close, so no
reconnect fires. The captain is invisible to dispatch until the 60 s poll happens to
notice a trip — by which time all four waves (t=0, 15, 30, 45 s) are long gone. This is the
single most likely explanation for any "I stopped getting requests but the app looked
fine" report from the field, and it will not reproduce on a busy test account, because a
busy object never hibernates.

**F-07-04 — one object, whole fleet.**

Every captain socket without a URL token lands here:

```ts
// apps/api/src/index.ts:226-229
const id = c.env.CAPTAIN_INBOX.idFromName("pending-auth");
```

and all three Flutter clients deliberately send no URL token
(`offers_ws.dart:36-39`, `:54-56`). So this is not an edge case for legacy builds — it is
the production path for 100 % of captains.

A Durable Object is single-threaded and pinned to one location. Cloudflare documents a
soft limit of ~1,000 requests/second per object and a 32,768-socket ceiling. With 1,000
online captains pinging every 25 s, this one object handles ~40 inbound frames/second
before a single offer is delivered — and because the relay forwards client frames upstream
(`CaptainInbox.ts:98-105`), each ping is *two* DO requests, not one. It also means every
online captain costs two Durable Objects and two WebSockets instead of one, and that the
shared object is permanently resident: it can never hibernate, because the fleet's
heartbeats never stop arriving.

The failure mode is the real problem. If this object throws, is overloaded, or is
rescheduled, **no captain in the country receives an offer over a socket**, and the only
thing standing between that and a total dispatch outage is the 60-second REST poll. That
is the answer to brief question 12: error isolation between captains does not exist,
because there is nothing to isolate — they all share one object. There is also no alerting
on it (see §9, T22).

The fix is not to shard the pending object; it is to stop needing it. A WebSocket
subprotocol header, or a short-lived single-use ticket minted by an authenticated REST
call and passed as `?ticket=`, lets the Worker derive the real per-captain DO id before
the upgrade — no proxy, no shared object, no relay to lose (P0.3).

**F-07-05 — the chat is one-way and the comment says otherwise.**

The server broadcasts chat correctly:

```ts
// apps/api/src/routes/safety.ts:173-177
// Live fan-out: push the message into the trip's WebSocket room so the
// other party's app renders it immediately. Both apps subscribe to the
// room for the active trip; without this the message existed only in D1
// and the captain (whose app previously had no chat surface at all) saw
// nothing until a manual refresh — the "رسايل الراكب مش بتظهر" bug.
```

The captain side is fully wired — `chat.message` at `trip_chat_screen.dart:68`,
`captain_state.dart:894`, and an unread badge at `active_trip_panel.dart:60`, plus a 6 s
poll at `trip_chat_screen.dart:78` and typing indicators at `:72`.

The rider side has none of it. `grep -rn "chat.message" apps/rider/lib` returns **zero
hits**. The rider's only socket handler knows two message types
(`trip_screen.dart:138-152`): `trip.updated` and `location.captain`. And the rider's chat
screen has no socket, no stream subscription, and no timer — it calls `_fetchMessages()`
once from `initState` (`trip_chat_screen.dart:22`) and never again:

```dart
// apps/rider/lib/screens/trip/trip_chat_screen.dart:19-23
@override
void initState() {
  super.initState();
  _fetchMessages();
}
```

So a captain typing *"أنا واقف عند البوابة"* reaches D1, reaches the room, reaches the
socket the rider's trip screen is holding — and is dropped on the floor, because that
handler has no branch for it. The rider sees the message only if they leave the chat
screen and re-enter it.

The comment is the interesting part. Someone fixed this bug in the captain→rider
direction, wrote *"both apps subscribe"*, and never checked the mirror. That is the
cross-app parity problem in miniature, and it is why **T27** exists.

**F-07-06 — the room takes anyone's word for where the captain is.**

```ts
// apps/api/src/durable-objects/TripRoom.ts:167-178
if (data.type === "location" && typeof data.lat === "number" && ...) {
  const payload = { type: "location.captain", lat: data.lat, lng: data.lng, ... };
  await this.ctx.storage.put("lastLocation", payload);
  this.broadcast(payload, ws);
}
```

There is no `session.role === "captain"` check. Membership was verified at connect
(`index.ts:162` or `TripRoom.ts:229`), so the sender is a legitimate participant — but on
a two-party trip, "a legitimate participant who is not the captain" means **the rider**.
A modified rider client can drive the car marker on its own trip: fake an arrival, fake a
route, fake proximity. Whether that is worth money depends on things T05 and T18 own
(arrival-triggered waiting fees, fraud signals), so I am not scoring the exploit — I am
scoring the missing check, which is one line.

No client sends `type:"location"` today (the captain uses REST, F-07-15), so this path is
currently unreachable in the shipped apps and entirely reachable with `wscat`.

### 4.2 The S2s, briefly

**F-07-07 — three channels, one schedule.** `OfferScheduler` releases the socket card to
3 captains every 15 s. In the very same request, all 10 get an FCM push
(`trips.ts:574-585`), and `GET /captain/offers` shows the trip to *every* online captain
in the city inside their radius, capped at 20 and with no wave filter
(`captain.ts:462-467`) — polled every 8 s when the socket is down. The scheduler's own
docstring frames the problem it solves as *"Acceptance turned into a race between ~10
captains"* (`OfferScheduler.ts:11-13`). That race is still on; the DO just made one of the
three starting pistols quieter. Fixing this is not a DO change — it is a `captain_offers`
projection table so all three channels read the same release state (P2.1).

**F-07-08 — a fan-out failure becomes a user-facing 500.** `broadcastTrip` is bare:

```ts
// apps/api/src/routes/trips.ts:160-174
const payload = await withCaptain(env, trip);
const room = env.TRIP_ROOM.get(env.TRIP_ROOM.idFromName(trip.id));
await room.fetch("https://room/broadcast", { ... });   // no try/catch
await room.fetch("https://room/state",     { ... });   // sequential, also bare
```

Called on seven paths including cancel (`:737`), accept (`:876`) and complete (`:1060`).
The D1 write has already committed when this runs, so a transient DO error returns 500 for
an operation that *succeeded*. On complete, wallet movements have already landed (T03's
territory) and the captain's app shows a failure. Note the contrast: the `CaptainInbox`
fan-outs on the same paths *are* wrapped and swallowed (`:776-793`, `:1340-1358`), and
`nearby.ts:73-86` isolates per-cell failures properly. The pattern is understood in this
codebase; `broadcastTrip` just missed it. It should also be `Promise.all` — two sequential
round-trips on every status change is pure added latency.

**F-07-09 — no envelope.** Brief question 4 asks what happens when an old build receives a
new message type. The answer: the `if/else if` chain ends without an `else`
(`trip_screen.dart:138-152`), so it is silently ignored — which is the *good* failure mode,
arrived at by accident rather than design. What is missing is the other half: no `v` field,
so the server can never learn which builds are still out there; no `seq`, so no client can
detect that it missed frame 41; no message id, so nothing is idempotent if a resend is ever
added. §3.4 shows the drift this permits — six unconsumed types, two unproduced ones.

**F-07-10 — the backstop is heavier than the thing it backs up.** `GET /trips/:id` returns
the enriched trip, *every* `trip_events` row, and the parsed `route_geometry`
(`trips.ts:662-679`), and the rider fetches it every 10 s unconditionally
(`trip_screen.dart:56-57`, `:172`). See §5.3 for the numbers: ~540 KB per trip against
~72 KB for the socket. It also never stops when the socket is healthy, and never pauses
when the app is backgrounded, because the rider screen has no lifecycle observer at all.

**F-07-13 — paying to say "pong".** `setWebSocketAutoResponse` is documented to answer a
fixed ping *"without waking WebSockets in hibernation and incurring billable duration
charges"* ([State API](https://developers.cloudflare.com/durable-objects/api/state/)), and
the pricing page confirms auto-responses *"will not incur additional wall-clock time"*.
Today both objects handle ping in JS (`TripRoom.ts:162-165`, `CaptainInbox.ts:107-114`),
so every heartbeat from every client wakes the object. Two sockets × 25 s means an
otherwise-silent trip room is woken at least 5 times a minute for nothing. One line in the
constructor removes it entirely.

**F-07-14 — no backpressure.** `broadcast()` calls `socket.send(raw)` in a loop and only
catches a throw. A client on a stalled connection accumulates an unbounded send buffer
inside the DO, billed as that object's memory, until the runtime kills it — taking down the
other participant's live tracking with it. `bufferedAmount` is the standard guard and is
not consulted anywhere in either object.

### 4.3 Two premises in the brief that the code does not support

The brief asked me to verify specific claims. Two of them are wrong, and recording that is
as useful as the findings.

**"Can an orphaned `OfferScheduler` alarm keep firing and billing forever?" — No.** The
chain is bounded on two independent axes. `pushWave` only re-arms while captains remain,
and tears down otherwise:

```ts
// apps/api/src/durable-objects/OfferScheduler.ts:123-130
const nextIndex = waveIndex + WAVE_SIZE;
await this.ctx.storage.put("waveIndex", nextIndex);
if (nextIndex < captains.length) {
  await this.ctx.storage.setAlarm(Date.now() + WAVE_DELAY_MS);
} else {
  await this.teardown();
}
```

With the hard cap of 10 captains (`trips.ts:568`) that is at most 4 alarms, ~45 s. And
`alarm()` re-reads trip status from D1 before every wave and tears down the moment the trip
leaves `searching`/`offered` (`:134-151`), so acceptance stops it even though `/cancel` is
never called on the accept paths (F-07-25). `teardown()` does `deleteAlarm()` +
`deleteAll()` (`:154-157`). This object is the best-engineered thing in the review and I
want that on the record — the residual issue is 15 s of stale storage and one wasted wake
per accepted trip, which is S3 housekeeping, not a billing leak.

**"PR #47 fixed the wrong-`TripRoom`-id bug — verify the fix is complete." — Half.** The
DO-side fix is real and well reasoned; the comment at `TripRoom.ts:35-48` correctly
explains that `ctx.id.toString()` returns the hex `DurableObjectId`, never the
`idFromName` input. But the caller only holds up its end on one of two branches:

```ts
// apps/api/src/index.ts:166-167  (authenticated branch)
url.searchParams.set("role", user.role);
url.searchParams.set("userId", user.id);
// ...no tripId

// apps/api/src/index.ts:175-176  (pending-auth branch)
url.searchParams.set("pendingAuth", "1");
url.searchParams.set("tripId", tripId);
```

A header-authenticated socket arriving at a cold room with no stored `tripId` therefore
falls all the way down `resolveTripId`'s chain to `ctx.id.toString()` (`TripRoom.ts:73`).
It does not break auth — that branch was verified in the Worker — but it does put a
64-hex string in the `connected` frame's `tripId`, and it means the storage seed depends
on whichever client happens to connect first. Both apps use the pending-auth path today,
so the good branch is the one in production. Adding `tripId` to line 166 makes the fix
actually complete instead of accidentally sufficient (P0.2).

## 5. Benchmark gap

### 5.1 Location cadence and marker motion

**Uber.** The mechanism is well established: driver location is published at an adaptive
frequency — higher while approaching pickup and at speed, lower when idle or stationary —
and the rider's client **interpolates between fixes** so the marker glides continuously at
a much lower update rate than 60 fps. Marker rotation follows the bearing between
successive points. I could not retrieve a citable Uber engineering post with exact interval
figures during this review, so I mark the *specific numbers* as **assumed** (commonly
quoted as ~4–8 s while driving to pickup, ~2–4 s with a passenger aboard, 30–60 s idle) and
the *mechanisms* — adaptive cadence and client-side interpolation — as **confident**, since
both are directly observable in the product.

**Synaptic Go.** Cadence is speed-derived rather than phase-derived (`distanceFilter: 10`
during any active trip, `50` when idle — `captain_state.dart:619-626`), which is a
reasonable instinct and is the *only* adaptive behaviour in the system. But it is then
truncated by a fixed 30/min server cap (F-07-01), and there is no interpolation at all:
`setState(() => _captainLoc = LatLng(lat, lng))` (`trip_screen.dart:149`) snaps the marker.
Net result at 30 km/h: the rider sees roughly 22 seconds of stuttering movement followed by
38 seconds of a frozen car, then a jump. Uber at a *slower* nominal update rate looks
smooth because the interpolation and the honest cadence do the work.

**The gap is not "update more often" — it is "update honestly and interpolate."** Publishing
at a deliberate 4 s with a 250–300 ms glide would use **7× less** bandwidth than the current
attempted rate, sit comfortably inside the existing rate limit, and look dramatically better.

**inDrive / Careem on low-end Android.** Both are notably conservative with the driver
radio: coarse fixes when idle, tighter only with a passenger aboard, and aggressive
back-off when backgrounded. Synaptic Go's captain app is actually *good* here — it parks
the GPS stream entirely on `paused`/`inactive`/`hidden` (`captain_state.dart:1088`,
`:637-639`) and re-arms on resume (`:1098`). That is better discipline than the rider app,
which has no lifecycle awareness whatsoever and keeps a 10 s poll running in the background
for the life of the trip. Marked **confident** on the mechanism, **assumed** on the specific
thresholds.

### 5.2 Cost model — Durable Objects per 1,000 trips

Rates from Cloudflare's [pricing page](https://developers.cloudflare.com/durable-objects/platform/pricing/)
(Workers Paid): duration **$12.50 / million GB-s** with 400,000 GB-s included; requests
**$0.15 / million** with 1 M included; a DO is billed at a **fixed 128 MB** regardless of
usage, so one active wall-clock second = **0.125 GB-s**. Incoming WebSocket messages bill at
**20:1**; outgoing are free. Alarm invocations count as requests. SQLite rows written are
**$1.00 / million** after 50 M.

Assumptions, stated so they can be argued with: average trip 15 min (900 s) from assignment
to completion; average city speed 30 km/h; both parties connected throughout; server-side
location accepted at the 30/min cap.

**Duration — the dominant line.** The room is woken by a `location.captain` broadcast every
~2 s (the cap) plus a ping every ~12 s (two clients at 25 s). Cloudflare only stops the
duration meter once an object is idle *and* eligible to hibernate; at sub-2-second event
spacing it never gets there. Duration is therefore effectively wall-clock:

```
per trip      : 900 s × 0.125 GB-s/s              =    112.5 GB-s
per 1,000     : 112,500 GB-s → × $12.50/1e6       =    $1.41
1,000 concurrent, sustained 1 h : 450,000 GB-s    =    $5.63 / hour
                                  sustained 24/7  ≈  $4,050 / month
```

**The same workload with hibernation actually working.** Batch location to one broadcast
per 4 s and move pings to `setWebSocketAutoResponse` (free and non-waking, per the pricing
page): 225 wakes per trip at a generous 20 ms of handler time each = 4.5 s active.

```
per trip      : 4.5 s × 0.125                     =      0.56 GB-s
per 1,000     : 563 GB-s → × $12.50/1e6           =    $0.007
1,000 concurrent, 1 h                             ≈    $0.03 / hour
```

**That is the answer to brief question 3: roughly a 200× swing on the duration line — about
$5.63/hour versus $0.03/hour at 1,000 concurrent trips, or ~$4,000/month against
essentially free.** The Hibernation API is already enabled; the code simply never lets it
engage. Note that the *correctness* work in P0.2 (`serializeAttachment`) is a prerequisite,
because the moment hibernation does start engaging reliably, F-07-02 and F-07-03 stop being
rare-eviction bugs and become routine.

**Requests.** Per trip: 450 accepted location POSTs × 2 DO round-trips (GeoCell +
TripRoom) = 900; ~6 status changes × 2 = 12; 72 inbound pings ÷ 20 = 3.6. ≈ 916 DO requests
per trip → **916,000 per 1,000 trips ≈ $0.14**. Immaterial next to duration, and it stays
immaterial — this is not where the money is.

**The permanently-resident shared inbox.** At 1,000 online captains, the `"pending-auth"`
object sees ~40 frames/s and never hibernates: 0.125 GB-s/s × 86,400 = **10,800 GB-s/day
≈ $4/month**. Trivial in money, alarming in shape — one single-threaded object absorbing
~4 % of its documented ~1,000 req/s soft ceiling before delivering a single offer, and a
hard dependency for the entire fleet.

**GeoCell alarms.** Each populated cell re-arms every 60 s (`GeoCell.ts:79`): 1,440
wakes/cell/day, each an alarm request plus a `setAlarm` row write. 200 active cells ≈ 288 k
requests + 288 k row-writes/day ≈ 8.6 M rows/month — inside the 50 M free tier, but growing
linearly with coverage rather than with demand.

**D1 — the line nobody has costed.** Five statements per accepted ping (§3.7) × 450 =
**2,250 D1 statements per trip → 2.25 million per 1,000 trips.** At 100 k trips/month that
is ~225 M statements, of which ~90 M are writes — past the 50 M free tier and, far more
importantly, sustained write pressure on a single SQLite database that also serves every
other feature. Collapsing this path (P1.4) is as much a T08/T24 concern as a realtime one.

### 5.3 Cost model — the rider's and captain's mobile data

Assume EGP 8–12/GB on a typical Egyptian prepaid bundle.

**Rider, per 15-minute trip:**

| Stream | Size | Count | Total |
|---|---|---|---|
| `location.captain` frames (~150 B JSON + framing) | 160 B | 450 | **72 KB** |
| `trip.updated` frames (full enriched trip, ~1.2 KB) | 1.2 KB | 6 | 7 KB |
| `GET /trips/:id` poll — trip + all events + full geometry | ~6 KB | 90 | **540 KB** |
| Pings/pongs | ~40 B | 72 | 3 KB |
| | | | **~0.62 MB** |

**The 10-second backstop poll is 87 % of the rider's realtime data budget** — roughly 7×
the socket it exists to protect. A 10 km Cairo route geometry is commonly 3–8 KB of JSON
and it is re-sent every ten seconds despite never changing after dispatch. Two trips a day
is ~37 MB/month, most of it re-downloading the same polyline 180 times.

**Captain, per trip:** the app *attempts* 750 POSTs at 30 km/h and gets 450 through. Each
request+response with headers is ~700 B, so ~0.5 MB/trip of which **40 % is 429 responses**.
Idle mode (50 m filter, ~13 pings/min while cruising) adds ~0.5 MB/hour. Across a 12-trip,
8-hour shift: **~14 MB/day, ~420 MB/month** — a real line item on a prepaid bundle, and
close to half of it is traffic the server has already decided to reject.

P0.1 and P1.2 together cut the rider to ~0.15 MB/trip and the captain to ~0.2 MB/trip
without losing a single meaningful update.

## 6. Improvement plan

Ordered. P0 items are the gate for production traffic.

### P0.1 — Make the publish cadence and the rate limit one decision

- **Goal** — the car on the rider's map moves continuously for the whole trip instead of
  freezing for ~40 seconds of every minute.
- **Design** — replace the distance-filtered fire-and-forget publisher with a **time-based
  coalescing publisher**. Keep the GPS stream at `distanceFilter: 5` for accuracy, but
  write each fix to a `_pendingFix` field instead of POSTing it. A single `Timer.periodic`
  flushes the newest pending fix on a phase-derived interval: **3 s** while `assigned`/
  `arrived` (rider is watching the approach), **5 s** while `in_progress`, **20 s** idle-online.
  Skip the flush entirely when the fix has moved <5 m. Worst case 20 publishes/min against
  a limit of 60 — comfortable headroom at any speed. Raise the server cap to **60/min** so
  the client is the throttle and the limiter is a genuine abuse guard, and switch it from a
  fixed window to a token bucket so a burst after a tunnel does not eat the whole minute.
  On a 429, back the flush interval off to 10 s for 60 s and **increment a counter**, so
  this can never again be invisible.
- **Files to change** — `apps/captain/lib/services/captain_state.dart` (619–626, 637–657,
  673–683), `apps/api/src/routes/captain.ts` (190–197),
  `apps/api/src/middleware/rateLimit.ts` (token-bucket variant).
- **DB** — none.
- **API contract** — unchanged. `POST /captain/location` gains an optional
  `at` (ISO string, the fix timestamp) so the server can reject out-of-order fixes.
- **Effort** — S (client ~half a day, server ~2 h).
- **Risk** — a longer interval looks *worse* without P1.6's interpolation; ship them
  together or ship P1.6 first. Rollback is two constants.
- **Acceptance criteria** — at a simulated 80 km/h for 10 minutes, zero 429s on
  `/captain/location`; the rider marker's longest gap between updates is <6 s; captain
  location bytes/trip drop >60 %.
- **Tests** — a unit test over the coalescer driven by a synthetic `Position` stream at
  5/13/22 m per second asserting publishes/min ≤ 20; an integration test asserting 429 count
  is 0 across a 10-minute drive trace.

### P0.2 — Make per-connection state survive hibernation

- **Goal** — a Durable Object that is evicted and revived behaves identically to one that
  never slept: identity intact, auth gate intact, offers still flowing.
- **Design** — three changes to both socket-holding objects. **(a)** Replace the
  `sessions` Map as the source of truth with `ws.serializeAttachment({role, userId, tripId,
  pendingAuth})` at connect and after `completeAuth`; read it with
  `ws.deserializeAttachment()` at the top of every handler (16 KB limit, far more than
  needed). Keep the Map only as a warm cache populated lazily from the attachment.
  **(b)** Replace the `setTimeout` auth timeout with `ctx.storage.setAlarm()` — durable,
  and it stops blocking hibernation for 10 s on every connect. **(c)** Fix `broadcast()` to
  iterate `ctx.getWebSockets()` **only**, reading `pendingAuth` from each attachment, so
  there is exactly one code path and it cannot be bypassed by an empty Map. Also add
  `tripId` to the authenticated branch at `index.ts:166` so `resolveTripId` never falls
  through to the hex id.
- **Files to change** — `apps/api/src/durable-objects/TripRoom.ts` (30–31, 105–135,
  140–182, 199–266, 268–288), `apps/api/src/durable-objects/CaptainInbox.ts` (29–30,
  41–74, 76–115, 136–199, 236–254), `apps/api/src/index.ts` (166).
- **DB** — none (DO storage only).
- **API contract** — none.
- **Effort** — M (2–3 days including a hibernation test harness).
- **Risk** — the attachment is lost if the socket closes, which is correct semantics but
  changes reconnect timing; verify against a forced-eviction test. Rollback is the current
  file.
- **Acceptance criteria** — with an eviction forced between two messages, an authenticated
  socket retains `role`/`userId`; a still-pending socket is closed with 4401 by the alarm
  and never receives a broadcast; a `CaptainInbox` client receives an offer pushed *after*
  an eviction.
- **Tests** — Miniflare/`workerd` tests that explicitly evict between assertions. This is
  the single most valuable test file the repo could gain.

### P0.3 — Delete the shared `"pending-auth"` inbox

- **Goal** — remove the fleet-wide single point of failure from the offer path, and halve
  the DO and socket count per online captain.
- **Design** — authenticate *before* the upgrade so the Worker can derive the real
  per-captain DO id. Preferred: a **single-use ticket**. `POST /auth/ws-ticket` (normal
  bearer auth) returns an opaque 60-second ticket stored in KV against `{userId, role}`;
  the client connects to `wss://…/ws/captain/offers?ticket=…`; the Worker redeems it,
  deletes the key, and routes straight to `CAPTAIN_INBOX.idFromName(userId)`. Tickets are
  single-use and short-lived, so they carry none of the `?token=` log-leakage problem the
  code rightly calls out (`index.ts:142-143`). The `Sec-WebSocket-Protocol` header is a
  reasonable alternative but `web_socket_channel` support for it is uneven across
  platforms — a decision for §10 Q1. Once tickets land, delete the pending-auth branch, the
  relay, and `detachRelay` entirely; keep the first-message handshake for one release as a
  deprecated fallback for old builds, then remove it.
- **Files to change** — `apps/api/src/index.ts` (187–230), `apps/api/src/routes/auth.ts`
  (new endpoint), `apps/api/src/durable-objects/CaptainInbox.ts` (delete 95–105, 131–210),
  `apps/captain/lib/services/offers_ws.dart` (36–60), and the same for both
  `trip_ws.dart` clients.
- **DB** — none. KV: `wst:<ticket>` with a 60 s TTL.
- **API contract** — new: `POST /auth/ws-ticket` → `{ticket: string, expiresIn: 60}`.
  Changed: `GET /ws/captain/offers?ticket=…` and `GET /ws/trips/:id?ticket=…`.
- **Effort** — M (2–3 days across three clients).
- **Risk** — a botched rollout locks captains out of offers; gate behind the deprecated
  first-message path staying live for one full release. Rollback is a client-side flag.
- **Acceptance criteria** — `CAPTAIN_INBOX.idFromName("pending-auth")` appears nowhere in
  the codebase; one online captain = exactly one DO and one socket; a ticket cannot be
  redeemed twice.
- **Tests** — ticket single-use and expiry tests; a load test asserting 500 concurrent
  captain connections create 500 distinct DO ids.

### P0.4 — Give the rider the realtime surface the server already sends

- **Goal** — a captain's chat message appears on the rider's screen the moment it is sent,
  and the rider can tell when the connection is down.
- **Design** — three additions to the rider app, all mirroring code that already exists in
  the captain app. **(a)** Handle `chat.message` and `chat.typing` in the rider's socket
  handler, lift the message list into `AppState` so it survives screen transitions, and
  subscribe the chat screen to it — the captain's `trip_chat_screen.dart:60-80` is the
  reference implementation. **(b)** Wire the already-emitted `onStatus` callback
  (`trip_ws.dart:51,62,88,115`) into a connection banner, mirroring
  `available_trips_tab.dart:261-296`. **(c)** Add a `WidgetsBindingObserver` to the trip
  screen so the socket is re-opened and state re-fetched on resume.
- **Files to change** — `apps/rider/lib/screens/trip/trip_screen.dart` (132–154, add
  observer), `apps/rider/lib/screens/trip/trip_chat_screen.dart` (19–49),
  `apps/rider/lib/services/app_state.dart` (add chat state + WS ownership).
- **DB** — none. **API contract** — none; the server is already correct.
- **Effort** — M (2 days).
- **Risk** — low. Moving socket ownership out of the screen touches `dispose` ordering;
  cover with a widget test.
- **Acceptance criteria** — a captain message renders on the rider's open chat screen in
  <1 s with no manual refresh; killing the network shows a banner within 30 s;
  backgrounding for 2 minutes and returning resyncs without a manual pull.
- **Tests** — widget test driving a fake socket through `chat.message`; a manual airplane-
  mode script in the release checklist.

### P0.5 — Reject location frames from non-captains

- **Goal** — only the captain can say where the captain is.
- **Design** — one guard in `webSocketMessage`, reading the role from the P0.2 attachment:
  `if (data.type === "location" && session.role !== "captain") return;`. Stamp the
  broadcast with the authenticated `userId` and the server's own timestamp rather than
  echoing client-supplied fields, and add the missing `tripId` (§3.4 #4 omits it while the
  REST-sourced #3 includes it).
- **Files to change** — `apps/api/src/durable-objects/TripRoom.ts` (167–178).
- **DB / API contract** — none.
- **Effort** — S (under an hour, but sequenced after P0.2 so `role` is trustworthy).
- **Risk** — none; the path is unused by shipped clients.
- **Acceptance criteria** — a socket authenticated as `rider` sending `type:"location"`
  produces no broadcast.
- **Tests** — a DO unit test per role.

### P0.6 — Stop a fan-out failure from failing the request

- **Goal** — a committed state change is never reported to the user as an error.
- **Design** — wrap `broadcastTrip`'s two fetches in `try/catch`, log with the trip id, and
  run them with `Promise.all`. Do the same for the two bare `GEO_CELL` calls
  (`captain.ts:174-184`, `:212-221`) and the bare `OFFER_SCHEDULER` call (`trips.ts:564`).
  Emit a `realtime.broadcast.failed` counter so silence is measurable (T22).
- **Files to change** — `apps/api/src/routes/trips.ts` (160–174, 564),
  `apps/api/src/routes/captain.ts` (174–184, 212–221).
- **DB / API contract** — none.
- **Effort** — S (2 h).
- **Risk** — swallowing a real outage silently; mitigated by the counter, which is the
  point.
- **Acceptance criteria** — with `TRIP_ROOM` forced to throw, `POST /trips/:id/complete`
  returns 200 and increments the failure counter.
- **Tests** — a route test with a throwing DO stub.

### P1.1 — A versioned envelope with sequence numbers

- **Goal** — clients can detect a gap, ignore what they do not understand, and resync
  deterministically.
- **Design** — every socket frame becomes
  `{v: 1, seq: <monotonic per room>, id: <ulid>, type, at, data: {...}}`. `seq` comes from a
  counter in DO storage, incremented per broadcast. Clients track the last `seq`; on a gap
  or reconnect they call `GET /trips/:id/since?seq=N`, which replays from `trip_events` or
  returns a full snapshot when the gap is too large. Unknown `type` is ignored; unknown `v`
  triggers an "update your app" prompt. Ship the envelope additively — emit both shapes for
  one release so old builds keep working.
- **Files to change** — `TripRoom.ts` (broadcast path), `trips.ts:160-174`,
  `safety.ts:180-191`, `captain.ts:255-265`, all three Dart clients, plus a new shared
  `packages/flutter_shared/lib/services/ws_envelope.dart`.
- **DB** — none (`trip_events` already exists).
- **API contract** — new `GET /trips/:id/since?seq=<n>` →
  `{seq, events: [...]} | {seq, snapshot: {...}}`.
- **Effort** — L. **Risk** — a dual-emit release is the safe path; single-shot is not.
- **Acceptance criteria** — dropping 5 frames in a proxy causes the client to resync within
  2 s and reach identical state.
- **Tests** — a lossy-socket harness asserting eventual consistency.

### P1.2 — Make the backstop poll cheap and conditional

- **Goal** — keep the safety net, stop paying for it continuously.
- **Design** — adopt the captain app's dual-cadence pattern (`captain_state.dart:758-766`):
  poll every 8 s while the socket is not `connected`, every 60 s while it is. Add
  `GET /trips/:id?fields=light` returning the trip row and nothing else — no events array,
  no geometry (the geometry is immutable after dispatch; fetch it once). Stop the poll on
  `paused` via the P0.4 lifecycle observer.
- **Files to change** — `apps/rider/lib/screens/trip/trip_screen.dart` (163–190),
  `apps/api/src/routes/trips.ts` (647–680).
- **DB** — none. **API contract** — additive `fields` query param.
- **Effort** — S. **Risk** — low; the fallback still exists, it just idles.
- **Acceptance criteria** — rider poll bytes per trip drop >85 %; with the socket
  blackholed, worst-case status latency stays ≤8 s.

### P1.3 — Let the objects actually hibernate

- **Goal** — collect the ~200× duration saving the Hibernation API is already meant to be
  providing.
- **Design** — `ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair(
  JSON.stringify({type:"ping"}), JSON.stringify({type:"pong"})))` in both constructors, and
  delete the JS ping handlers. Server-side, coalesce location broadcasts to at most one per
  2 s per room. Depends on P0.2 — do not ship this before identity survives eviction.
- **Files to change** — `TripRoom.ts` (constructor, 162–165), `CaptainInbox.ts`
  (constructor, 107–114).
- **Effort** — S. **Risk** — the auto-response string must match the client's ping frame
  **byte for byte**; a mismatch silently disables it. Assert with a test.
- **Acceptance criteria** — a room with two idle sockets shows no duration accrual over
  5 minutes; measured GB-s per 1,000 trips falls >90 %.

### P1.4 — Collapse the location hot path

- **Goal** — one D1 write and one DO call per fix instead of five and two.
- **Design** — drop the `SELECT * FROM trips` (the trip id and captain id are already
  known from the request and the JWT — validate with a single conditional `UPDATE …
  WHERE id = ? AND captain_id = ?` and check `changes`). Move path sampling into `TripRoom`
  storage and flush to `trip_path_points` in batches on an alarm or at trip completion,
  removing both the `SELECT recorded_at` and the per-30 s `INSERT` from the request path.
  Fire the `GeoCell` heartbeat with `ctx.waitUntil` rather than awaiting it — presence is
  not worth latency on the response.
- **Files to change** — `apps/api/src/routes/captain.ts` (198–270),
  `apps/api/src/durable-objects/TripRoom.ts` (storage + flush alarm).
- **DB** — none; write pattern only. **API contract** — none.
- **Effort** — M. **Risk** — batched path points are lost if the room dies before flush;
  acceptable for a breadcrumb trail, and flushing at each status change bounds it.
- **Acceptance criteria** — D1 statements per accepted ping ≤2; p95 latency of
  `POST /captain/location` under 120 ms.

### P1.5 — Handle 4401 like an auth failure instead of a network blip

- **Goal** — an expired token produces a refresh, not an infinite reconnect loop.
- **Design** — inspect the close code in all three clients. On **4401** (or an
  `auth.failed` frame): attempt one token refresh through the existing interceptor
  (`captain_state.dart:249-275`), reconnect once with the new token, and on a second
  failure surface a real error and stop. Cap total reconnect attempts at ~30 and expose
  `onStatus('failed')` so the UI can offer a retry button.
- **Files to change** — all three `*_ws.dart`, plus the rider's missing 401 interceptor.
- **Effort** — S. **Risk** — a refresh storm if the refresh endpoint itself is failing;
  single-flight the refresh (T01 flagged the same requirement).
- **Acceptance criteria** — connecting with an expired token triggers exactly one refresh
  and one retry, then a visible error — not an endless loop.

### P1.6 — Interpolate the marker and be honest when it is stale

- **Goal** — the car glides; when the data stops, the rider is told rather than deceived.
- **Design** — animate between the previous and newest `LatLng` over the expected update
  interval with a `Tween` on an `AnimationController` (250–400 ms, ease-out), rotating the
  marker to the computed bearing — which also finally gives `heading` (F-07-19) something to
  do; send it from the captain and use it when present, falling back to the computed
  bearing. If no fix has arrived in >15 s, fade the marker to 60 % opacity and show
  "آخر تحديث منذ …". Detailed motion spec belongs to **T28**.
- **Files to change** — `apps/rider/lib/screens/trip/trip_screen.dart` (143–150, 318–394),
  `packages/flutter_shared/lib/widgets/vehicle_map_marker.dart`,
  `apps/captain/lib/services/captain_state.dart` (676–681, send `heading`).
- **Effort** — S–M. **Risk** — animation cost on low-end Android; cap to one controller and
  test on a 2 GB device.
- **Acceptance criteria** — with fixes arriving every 3 s the marker never visibly jumps;
  with the socket cut, staleness is visible within 15 s.

### P2.1 — One offer release schedule across all three channels

- **Goal** — the wave rollout means something.
- **Design** — a `captain_offers` projection table (`trip_id`, `captain_id`, `wave`,
  `released_at`, `expires_at`, `state`). `OfferScheduler` inserts a row when it releases a
  captain; `GET /captain/offers` joins against it instead of scanning open city trips; the
  FCM blast moves inside the wave loop so pushes are staged too. Adds a natural home for a
  per-offer TTL, which does not exist today.
- **Files to change** — `OfferScheduler.ts` (92–131), `captain.ts` (439–480),
  `trips.ts` (572–585).
- **DB** — migration `0020_captain_offers.sql`.
- **Effort** — L. **Risk** — a projection that drifts is worse than none; make the
  scheduler the only writer.
- **Acceptance criteria** — a captain in wave 3 cannot see the trip through *any* channel
  before wave 3 releases; 409-on-accept rate falls >70 %.

### P2.2 — Backpressure, isolation and alerting

- **Goal** — one slow client cannot degrade a room; one broken object is visible.
- **Design** — check `ws.bufferedAmount` before each send and close sockets over ~1 MB with
  a 1013; wrap each `send` individually; add a per-room socket cap (~50) as an abuse guard;
  emit `realtime.socket.closed_slow`, `realtime.broadcast.failed`, `realtime.auth.failed`
  and per-object error counters. Alerting design belongs to **T22**.
- **Files to change** — `TripRoom.ts` (268–288), `CaptainInbox.ts` (236–254).
- **Effort** — M. **Acceptance criteria** — a deliberately stalled client is closed within
  30 s without affecting the other participant.

### P2.3 — One WebSocket client, shared

- **Goal** — stop maintaining the same reconnect maths in three files.
- **Design** — move a single `GoSocket` into `packages/flutter_shared/lib/services/`,
  parameterised by path and message handler, exposing a status stream and the P1.1 envelope
  handling. Delete all three bespoke clients. Coordinate with **T27**, which owns the
  duplication problem systematically.
- **Effort** — M. **Acceptance criteria** — `web_socket_channel` is imported in exactly one
  file across the monorepo.

### P2.4 — Trim the standing DO costs

- **Goal** — cost that tracks demand, not coverage.
- **Design** — close the offers socket while a trip is active (F-07-22) and reopen on
  completion; back `GeoCell`'s alarm off to 180 s and skip re-arming when the cell has been
  static for two cycles; call `OFFER_SCHEDULER` `/cancel` from both accept paths
  (F-07-25).
- **Effort** — S. **Acceptance criteria** — one socket per captain during a trip; GeoCell
  alarm wakes fall >60 %.

## 7. Phasing

| Item | Phase | Effort | Owner type | Gated by |
|---|---|---|---|---|
| P0.1 Cadence ↔ rate limit reconciliation | **P0** | S | Flutter + backend | — |
| P0.2 `serializeAttachment` + alarm auth timeout | **P0** | M | backend | — |
| P0.3 Delete the shared pending-auth inbox | **P0** | M | backend + Flutter | P0.2 |
| P0.4 Rider chat + connection state + lifecycle | **P0** | M | Flutter | — |
| P0.5 Role check on inbound location frames | **P0** | S | backend | P0.2 |
| P0.6 Non-fatal, parallel `broadcastTrip` | **P0** | S | backend | — |
| P1.1 Versioned envelope + `seq` + `/since` | P1 | L | backend + Flutter | P0.2 |
| P1.2 Cheap, conditional backstop poll | P1 | S | Flutter + backend | P0.4 |
| P1.3 Auto-response pings + broadcast coalescing | P1 | S | backend | **P0.2** |
| P1.4 Collapse the location hot path | P1 | M | backend | P0.1 |
| P1.5 4401 handling + single-flight refresh | P1 | S | Flutter | T01's refresh work |
| P1.6 Marker interpolation + staleness | P1 | S–M | Flutter | P0.1 |
| P2.1 Unified offer release schedule | P2 | L | backend | P0.3 |
| P2.2 Backpressure, isolation, counters | P2 | M | backend + ops | P0.2 |
| P2.3 Shared `GoSocket` in `flutter_shared` | P2 | M | Flutter | P1.1, T27 |
| P2.4 Standing DO cost trims | P2 | S | backend | — |

**P0 total ≈ 8–10 engineer-days.** Two sequencing rules matter more than the estimates:

1. **P0.2 before P1.3.** Enabling effective hibernation before per-connection state
   survives it converts two rare eviction bugs into routine ones. The cost saving is worth
   ~$4,000/month; shipping it first would be the most expensive way to collect it.
2. **P1.6 with or before P0.1.** Lengthening the publish interval without interpolation
   makes the marker look *worse* than today's stutter-then-freeze, even though it is
   strictly better data.

## 8. Metrics

Nothing on this axis is currently measured — `[observability]` is enabled in
`wrangler.toml:93` and no realtime counter exists anywhere in the code. Instrument these
before P0 lands so the fixes are provable rather than asserted.

| Metric | How | Today | Target |
|---|---|---|---|
| `location.rate_limited` (429s on `/captain/location`) | counter at `captain.ts:192` | unmeasured; **estimated 40–77 % of attempts** while driving | **<0.1 %** |
| Rider marker gap p95 (seconds between consecutive `location.captain` renders) | client timing, reported with trip telemetry | est. 38–47 s once per minute | **<6 s** |
| `realtime.broadcast.failed` | counter in P0.6's catch | unmeasured (currently surfaces as a user-facing 500) | <0.01 % of broadcasts, alerted |
| `ws.auth.failed` / `ws.close.4401` | counter in `completeAuth` | unmeasured | tracked; a spike means a token bug |
| `ws.reconnect.attempts` p95 per trip | client → telemetry | unmeasured | <2 |
| DO duration GB-s per 1,000 trips | Cloudflare analytics | **≈112,500** (est., §5.2) | **<1,000** after P1.3 |
| D1 statements per accepted location ping | query analytics | **5** | **≤2** after P1.4 |
| Rider realtime bytes per trip | client accounting | **≈0.62 MB** (est., §5.3) | **<0.15 MB** |
| Captain location bytes per shift | client accounting | **≈14 MB/day** (est.) | **<5 MB/day** |
| Distinct `CaptainInbox` DO ids per 100 online captains | Cloudflare analytics | **101** (100 + the shared one) | **100**, and no shared id |
| Chat delivery latency p95, captain→rider | client timestamp diff | **∞** (never delivered live) | **<1 s** |
| 409 `TRIP_TAKEN` rate on accept | counter at `trips.ts:869` | unmeasured; wave rollout currently bypassed | **<5 %** after P2.1 |

## 9. Cross-cutting notes

Findings outside this axis, addressed to their owners. Not fixed here.

- **T27 — Cross-app parity.** This track produced the clearest parity evidence in the
  review. (1) `apps/rider/lib/services/trip_ws.dart` and
  `apps/captain/lib/services/trip_ws.dart` are the same 120-line service forked into two
  architectures — callback-based with four status transitions vs. broadcast-stream with
  none — while sharing byte-identical reconnect maths (`1<<min(n,4)` + jitter, 25 s ping)
  that must now be maintained twice. (2) The captain app has a lifecycle observer
  (`captain_state.dart:1081-1105`), a dual-cadence poll (`:758-766`), a connection telltale
  (`available_trips_tab.dart:261-296`) and a real resync (`:902-976`); the rider app has
  none of the four. Every one of those is a solved problem in this repo that was not
  carried across. (3) The chat asymmetry in F-07-05 — with `safety.ts:173-177` asserting
  *"Both apps subscribe"* — is the same failure in narrative form: a bug fixed in one
  direction, declared fixed in both. My P2.3 proposes the shared `GoSocket`; the ownership
  is yours.
- **T22 — Observability.** There is no realtime instrumentation at all. The specific
  blind spot that let F-07-01 survive to production: `POST /captain/location` returns 429
  for the majority of a driving captain's pings and **nothing counts it** — not the server,
  not the client (`captain_state.dart:682` swallows it). Please treat "a rate limiter with
  no rejection counter" as a class of defect. Also needed: alerting on the shared
  `CaptainInbox` object while it still exists (F-07-04), since its failure is a silent
  fleet-wide dispatch outage.
- **T23 — Testing.** Zero tests touch this surface. Two harnesses would have caught most
  of §4: a `workerd`/Miniflare test that **forces eviction** between assertions (catches
  F-07-02, F-07-03), and a synthetic drive-trace test that replays GPS at 20/50/80 km/h
  against the real rate limiter (catches F-07-01). Both are more valuable than broad
  coverage elsewhere.
- **T24 — Performance & cost.** The D1 line from §5.2 is yours: ~2.25 M statements per
  1,000 trips, ~90 M writes/month at 100 k trips, all from one endpoint. Also the
  duration model — ~$4,000/month at 1,000 sustained concurrent trips versus near-zero,
  turning on P0.2 + P1.3.
- **T06 — Dispatch.** F-07-07: your wave rollout is architecturally sound and functionally
  bypassed. `GET /captain/offers` (`captain.ts:462-467`) hands every open city trip to
  every in-radius captain regardless of wave, and the FCM blast (`trips.ts:574-585`)
  notifies all ten at t=0. Any fairness or matching logic built on the assumption that
  waves gate visibility is not currently true.
- **T02 — Authorization.** F-07-06 is an object-level access gap in a non-REST surface:
  `TripRoom` verifies *membership* but never *role*, so a rider can act as the captain over
  the socket. Worth including in your IDOR sweep — WebSocket frames are an authorization
  surface too.
- **T01 — Auth & sessions.** Two hand-offs. (1) All three socket clients reconnect forever
  against a 4401 with no refresh attempt (F-07-12); my P1.5 depends on your single-flight
  refresh landing first. (2) My P0.3 proposes `POST /auth/ws-ticket` (60 s single-use KV
  ticket) to replace the URL-token/pending-auth mess — that endpoint lives in your file and
  should follow your token conventions.
- **T08 — Data model.** `trip_path_points` is written from the request path with a
  `SELECT … ORDER BY recorded_at DESC LIMIT 1` before every insert
  (`captain.ts:238-251`). P1.4 moves it to batched writes; the table may want a
  `(trip_id, recorded_at)` index either way.
- **T28 — Motion.** The marker interpolation in P1.6 is a signature moment — the car
  gliding along the road is the single most-watched animation in the product, and today it
  teleports. Curve, duration and the stale-fade treatment are yours; I have specified only
  the mechanism.
- **T09 / T10 — App journeys.** The rider trip screen owns its socket inside the widget
  (`trip_screen.dart:132-154`) with no lifecycle observer, so backgrounding the app during
  a trip leaves a 10 s poll running and no reconnect on resume. Both are structural to the
  screen, not the socket layer.
- **T25 — Privacy.** `?token=` is still accepted on both upgrade routes
  (`index.ts:144`, `:199`) and JWTs in query strings land in access logs. The code
  acknowledges it as deprecated; P0.3 removes the need for it entirely. Also note
  `location.captain` frames are broadcast to *all* room members including any `admin`
  socket — worth confirming that admin trip-watching is intentional and logged.

## 10. Open questions

Decisions for the product owner. Each with options and my recommendation.

**Q1 — How should a WebSocket authenticate?** Options: (a) `?ticket=` — a 60 s single-use
KV ticket from an authenticated REST call; (b) `Sec-WebSocket-Protocol` header carrying the
JWT; (c) keep the first-message handshake and shard the pending object. **Recommend (a).**
It is the only one that lets the Worker derive the per-captain DO id *before* the upgrade,
which is what deletes F-07-04 outright rather than mitigating it. (b) is cleaner in theory
but `web_socket_channel`'s subprotocol support is uneven across Android/iOS/web and would
need validating on all three first. (c) preserves the proxy, the doubled DO count, and the
relay that F-07-03 shows we cannot keep alive.

**Q2 — What is the target location cadence?** Options: (a) fixed 3 s throughout; (b)
phase-adaptive — 3 s approaching pickup, 5 s in transit, 20 s idle; (c) speed-adaptive.
**Recommend (b)**, which is P0.1 as written. It matches the observable Uber behaviour, it
is trivially reasonable about a rate limit, and it cuts captain data ~70 %. (c) is what the
code attempts today via `distanceFilter` and is exactly how we got here: a speed-derived
rate cannot be reconciled with a time-derived cap without one of them adapting.

**Q3 — Keep the always-on rider poll?** Options: (a) keep 10 s flat; (b) dual-cadence
8 s down / 60 s up (P1.2); (c) drop it once P1.1's `seq`-gap resync lands. **Recommend (b)
now, revisit (c) after P1.1 has run in production for a month.** The poll is scar tissue
from a real outage (`trip_screen.dart:163-169`) and the team's instinct to keep a backstop
is right; the fix is to make it cheap, not to remove it. (c) only becomes safe once gap
detection is proven.

**Q4 — Should the socket be authoritative for anything?** Today D1 owns everything and the
DO is a bus with a stale cache (§3.2). Options: (a) formalise that — delete `PUT /state`
and `lastLocation`, since nothing reads them; (b) make `TripRoom` authoritative for live
position only (the one field D1 does not need durably) and have it serve a snapshot on
connect. **Recommend (b)** — it fixes F-07-18 (a reconnecting rider currently sees no car
at all until the next broadcast), keeps the ownership rule crisp ("D1 owns the trip, the
room owns the dot"), and costs one storage read on connect. It does mean writing down the
rule somewhere durable so the next person does not re-introduce a third owner.

**Q5 — How long should an offer live?** There is no TTL anywhere: no `expires_at` on the
payload (`trips.ts:549-560`), no server-side expiry, and the countdown implied by
`available_trips_tab.dart:112` is client-local only. Options: (a) 20 s per wave, expiring
with the wave; (b) 60 s per offer regardless of wave; (c) no expiry, first-come until the
trip is taken. **Recommend (a)** alongside P2.1's `captain_offers` table, which is the
natural home for `expires_at`. Without it, a captain can accept a card their app has been
holding for ten minutes, and the rider — who gave up and re-booked — gets a captain they no
longer want.

**Q6 — Do we support the currently-shipped app builds through P0.3?** Removing the
first-message handshake breaks any build that has not updated. Options: (a) keep both paths
for one release and remove the old one after adoption crosses ~95 %; (b) hard cut with a
forced-update gate. **Recommend (a).** `APP_VERSION` is 0.4.0 and pre-production, so the
installed base is small — but the shared pending-auth object is a fleet-wide SPOF, and the
one thing worse than keeping it for another release is deleting it while captains are still
routed through it.
