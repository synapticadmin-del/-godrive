# 17 — Safety, Trust & Two-Sided Accountability

> Track: C — Feature parity & new capability · Reviewer: chat-20260801-1340-1f20 · Date: 2026-08-01
> Base commit reviewed: `4330518f5e3031cd9de124773a6e3c4783c6b138`

## 1. Scope

This document covers the trust-and-safety axis of Synaptic Go: the SOS path, trip
sharing, in-trip chat and contact privacy, captain identity assurance, rider
identity, the two-sided rating system, blocking, trip-anomaly detection, incident
response, and women's safety. It audits what exists on `main` today and specifies
what must be built before the platform carries a paying passenger.

**In scope:** `apps/api/src/routes/safety.ts` in full · `sos_alerts`,
`trip_share_tokens`, `trip_chat_messages`, `ratings`, `driver_documents`,
`document_types` · the verification workflow across `apps/api/src/routes/captain.ts`,
`apps/api/src/routes/admin.ts` and `apps/admin/src/pages/CaptainVerificationPage.tsx`
· the rating write path in `apps/api/src/routes/trips.ts` · the dispatch gate as it
relates to safety (documents, blocks) · both apps' safety and chat surfaces.

**Explicitly out of scope** (named owner):

| Not covered here | Owner |
|---|---|
| Session/JWT design, OTP, Turnstile, refresh rotation | T01 |
| RBAC and object-level access as a system (I only report the safety-relevant instances) | T02 |
| Wallet/ledger correctness, refunds after a disputed trip | T03 |
| Fraud scoring, multi-accounting economics, promo abuse | T18 |
| Dispatch/matching architecture and wave tuning (I specify only where a block filter must hook in) | T06 |
| WebSocket/Durable Object transport correctness | T07 |
| Migration hygiene and D1 constraint-rebuild mechanics | T08 |
| The systematic rider↔captain parity programme | T27 |
| Notification delivery infrastructure and lifecycle messaging | T19 |
| Data-protection/PDPL legal posture (I flag the leaks; the legal framing is theirs) | T25 |

A structural note that shapes everything below: **the entire safety feature set is
one 291-line file** (`apps/api/src/routes/safety.ts`) plus two Flutter screens per
app. There is no safety service, no incident model, and no ops surface. Safety here
is a set of gestures, not a system.

## 2. What I actually read

Read in full, line by line, at the pinned commit:

| File | Note |
|---|---|
| `apps/api/src/routes/safety.ts` (291 lines) | The whole safety surface: SOS, share, track, chat, typing. |
| `apps/api/src/index.ts` (372 lines) | Route mounts (`:108-122`), WS upgrades, `scheduled()` cron (`:267-371`). |
| `apps/api/src/middleware/auth.ts` (75 lines) | `authMiddleware`, query-token allowlist, `requireRole`. Never consults the DB. |
| `apps/api/src/lib/schemas.ts` (331 lines) | `sosSchema` (`:90-95`), `tripShareSchema` (`:97-100`), `captainLocationSchema` (`:181-187`), `documentRegisterSchema` (`:200-220`). |
| `apps/api/src/lib/utils.ts` | `id()` (`:9-12`) — token entropy. |
| `apps/api/src/lib/jwt.ts` (96 lines) | `ACCESS_TTL = "15m"` (`:8`), `REFRESH_TTL = "30d"` (`:9`). |
| `apps/api/src/lib/cleanup.ts` (76 lines) | Only `otp_codes` (`:36`) and `refresh_tokens` (`:49`) are ever purged. |
| `apps/api/src/lib/nearby.ts` | `findNearbyCaptains(env, city, lat, lng, limit)` (`:62-68`) — no rider identity in the signature. |
| `apps/api/src/lib/audit.ts` (37 lines) | `logAudit` — the only durable trace an SOS leaves outside its own row. |
| `migrations/0001_init.sql`, `0002_enhancements.sql`, `0003_global_transport.sql`, `0012`, `0014`, `0015`, `0017` | All safety-relevant DDL. |
| `apps/rider/lib/screens/safety/sos_screen.dart` (163 lines) | Rider SOS + the only share-link trigger in the product. |
| `apps/captain/lib/screens/safety/sos_screen.dart` (322 lines) | Captain SOS — a different, more polished implementation of the same call. |
| `apps/rider/lib/screens/trip/trip_chat_screen.dart` (150 lines) | Rider chat. |
| `apps/captain/lib/screens/home/trip_chat_screen.dart` (421 lines) | Captain chat — same endpoints, 2.8× the code. |
| `apps/rider/lib/screens/ride/rating_sheet.dart` (170 lines) | The only rating UI that exists in either app. |
| `apps/admin/src/components/RejectionReasonModal.tsx` (226 lines) | Six rejection presets including "expired". |

Read closely in the regions that matter (I navigated by symbol and read the
surrounding blocks, not the whole file):

| File | Regions read |
|---|---|
| `apps/api/src/routes/trips.ts` (1371 lines) | `withCaptain` (`:100-158`), `broadcastTrip` (`:160-174`), `/path` (`:682-706`), cancel (`:709-737`), complete (`:951-984`), rate (`:1090-1137`), bids (`:1236-1248`), bid-accept gates (`:1291-1297`). |
| `apps/api/src/routes/captain.ts` (700 lines) | profile upsert (`:26-78`), `/profile` read (`:120`), online gate (`:131-188`), location + path insert (`:190-260`), nearby-requests (`:328-412`), documents (`:504-594`), upload (`:625-670`). |
| `apps/api/src/routes/admin.ts` (937 lines) | audit-log (`:219-227`), captain approve (`:261-270`), suspend (`:289-310`), users list (`:326`), documents list (`:620-680`), document review (`:821-864`), online-captains (`:925-937`). |
| `apps/api/src/lib/notifications.ts` (408 lines) | `pushToUser` (`:380-409`), `sendFcm`, `logNotification`. |
| `apps/admin/src/pages/CaptainVerificationPage.tsx` (1050 lines) | `daysUntilExpiry` (`:60-67`), `expiryChip` (`:68-91`), preview modal identity strip (`:254-369`), review actions (`:861-863`). |
| `apps/admin/src/pages/UsersPage.tsx` (75 lines) | Read-only table; zero action controls. |
| `apps/captain/lib/screens/home/active_trip_panel.dart` | `_callRider` (`:125-131`), phone read (`:307`), call button (`:374-385`). |
| `apps/api/wrangler.toml` | DO bindings (`:24-28`), queues + DLQ (`:43-55`), crons (`:62`). |

Skimmed / structural only: the four Durable Objects (`TripRoom`, `GeoCell`,
`CaptainInbox`, `OfferScheduler`) — I read their HTTP contracts and alarm handlers
to establish what identity they carry and what they do not, not their internals;
`apps/captain/lib/screens/onboarding/onboarding_screen.dart` (1416 lines) — I read
the document-capture steps only.

Searched exhaustively (absence is a finding, so the searches are evidence):
`sos_alerts` across `apps/api/src` → 2 hits, both in `safety.ts`. `sos|emergency|
incident` across `apps/admin/src` → zero. `block|mute|avoid|blacklist` across
routes, both apps and all migrations → only the prose word "block" in comments and
the `go.muted` colour token. `gender|sex|trusted_contact|emergency_contact` across
schemas, both apps and migrations → zero. `selfie|liveness|face_match|biometric`
repo-wide → zero. `tel:|url_launcher` across `apps/rider/lib` → zero.

## 3. How it works today

### 3.1 SOS

Both apps take a GPS fix and POST it. The rider first passes a confirmation dialog
whose text promises the authorities (`apps/rider/lib/screens/safety/sos_screen.dart:33`
— "سيتم إرسال موقعك للسلطات وإدارة التطبيق"), then calls `/safety/sos`
(`:78`). The captain screen fires on a single tap with haptics and a sent-state
screen (`apps/captain/lib/screens/safety/sos_screen.dart:61-93`), and carries a
deeper location fallback chain (live fix → last known → the server's cached
`captain.last_lat/last_lng`) where the rider has only two levels.

Server side (`apps/api/src/routes/safety.ts:15-51`) the handler does exactly three
things: inserts one `sos_alerts` row with `status='open'` (`:21-26`), selects every
`users` row with `role='admin'` and pushes each one an FCM notification (`:29-39`),
and writes one `audit_log` row (`:41-48`). It returns `{ok:true, alertId}`.

`pushToUser` (`apps/api/src/lib/notifications.ts:380-409`) reads `device_tokens` for
the target user and **returns silently if there are none** (`:393`). Its return type
is `void`; the SOS handler does not and cannot check whether anything was delivered.
`device_tokens` is populated by the two mobile apps; the admin console is a React SPA
and registers nothing. So the realistic delivery path for an emergency is: *whichever
internal admin happens to have a mobile app installed with a live FCM token.*

After the INSERT, the row is inert. `sos_alerts.status`, `resolved_at` and
`shared_with` are never written again anywhere in the codebase — `sos_alerts` appears
in exactly two places in `apps/api/src`, both inside `safety.ts`. There is no admin
endpoint and no admin screen: `sos|emergency|incident` returns zero matches across
all of `apps/admin/src`, and the two apparent `sos` hits in `admin.ts` are the
substring inside `toISOString()` at `:24` and `:65`. **Nobody can see an SOS alert in
a UI, and no alert can ever be closed.**

### 3.2 Trip sharing

`POST /safety/share` (`safety.ts:56-86`) authorises the caller as the trip's rider,
captain or an admin (`:67-69`), mints `token = id("sh")` — `crypto.randomUUID()`
without dashes, 122 bits of entropy (`apps/api/src/lib/utils.ts:9-12`), which is the
one thing in this feature that is properly built — stores it with an expiry from
`ttlMinutes` (5 min to 7 days, default 24 h; `apps/api/src/lib/schemas.ts:97-100`),
and returns `url: https://api.synapticstudio.tech/track/${token}` (`:83`).

That URL is wrong. `safetyRoutes` is mounted at `/safety`
(`apps/api/src/index.ts:120`), so the handler declared at `safety.ts:90` actually
lives at `/safety/track/:token`. A contact who taps the shared link hits a path with
no registered handler and gets the app's 404. If they hand-correct the path, they
hit `safetyRoutes.use("*", authMiddleware)` at `safety.ts:11` — which covers every
route in the file including this one — and get a 401. **The public tracking page is
unreachable by two independent bugs at once.** Only the rider app calls the create
endpoint at all (`apps/rider/lib/screens/safety/sos_screen.dart:97`), handing the URL
straight to the OS share sheet (`:104`).

Were it reachable, it would return `pickup_address` and `dropoff_address`
(`safety.ts:104`, returned at `:119-120`) plus the latest `trip_path_points` row —
directly under a comment at `safety.ts:89` that reads "no PII". A rider's 2 a.m.
pickup address is their home.

Nothing revokes the token when the trip ends. I checked both terminal paths
(`apps/api/src/routes/trips.ts:709-737` cancel, `:951-984` complete) and all four
Durable Objects: no write to `trip_share_tokens` exists outside `safety.ts` itself.
The daily cleanup cron (`apps/api/src/index.ts:275` → `apps/api/src/lib/cleanup.ts`)
purges only `otp_codes` (`:36`) and `refresh_tokens` (`:49`). A revoke endpoint
exists (`safety.ts:126-136`) and no UI in either app calls it.

### 3.3 In-trip chat and contact privacy

`POST /safety/chat/:tripId` (`safety.ts:140-212`) validates the body for length only
— a string of 1 to 1000 characters (`:144-153`) — persists it, broadcasts into the
`TripRoom` DO, and pushes FCM to the other party. The file header at `safety.ts:138`
describes the feature as "In-call anonymous chat … no phone numbers exchanged". There
is no filter of any kind, so a phone number is one paste away.

Sender attribution is a two-way ternary: `user.id === trip.rider_id ? "rider" :
"captain"` (`:163`, repeated at `:272` for typing). The `sender_role` CHECK
constraint allows a third value, `'support'`
(`migrations/0003_global_transport.sql:191`), which no code path ever writes. An
admin intervening in a dispute is therefore **recorded and rendered as the captain**.

Messages are never deleted (no `trip_chat_messages` DELETE anywhere, and the cleanup
cron does not know the table). Support access exists only as the inline
`user.role === "admin"` bypass at `safety.ts:224`; there is no admin screen to read a
thread, so a dispute is arbitrated by an engineer curling an endpoint.

Voice is worse than chat. `withCaptain()` joins `u.phone AS captain_phone`
(`apps/api/src/routes/trips.ts:136`) and `broadcastTrip()` (`:160-174`) ships that
enriched payload into the trip's WebSocket room on every status change, so the
rider's client holds the captain's real mobile number continuously. In the other
direction `GET /captain/nearby-requests` returns `rider_phone` (`captain.ts:372`,
`:412`) — **before the captain has accepted anything** — and the captain app has a
working dial button (`apps/captain/lib/screens/home/active_trip_panel.dart:125-131`,
`:307`, `:374-385`). There is no masking layer anywhere in the repo. The rider app
has no call affordance at all (`tel:`/`url_launcher` return zero matches across
`apps/rider/lib`), so the asymmetry is: the captain can call the rider, the rider
cannot call the captain, and both real numbers are on the wire regardless.

### 3.4 Identity assurance

A captain uploads photos to R2 (`captain.ts:625-670`, with real byte-signature
sniffing and a 10 MB cap — this part is well built) and registers them against a
type from the `document_types` catalogue (`captain.ts:529-594`). The catalogue seeds
eight types (`migrations/0014_document_types.sql:29-37`): driving licence, national
ID, criminal record (+ back), vehicle registration (+ back), vehicle photo, personal
photo. **There is no insurance type and no periodic-inspection type.**

Identity metadata — `holder_full_name`, `national_id_number`, `expires_at` — is
attached to the document row by migration 0012 (`:10-12`) and is entirely
self-reported; `nationalIdNumber` is validated as free text up to 30 characters
(`apps/api/src/lib/schemas.ts:210-211`), with no check against the 14-digit Egyptian
format. Verification is an admin looking at the photo beside the typed fields in
`apps/admin/src/pages/CaptainVerificationPage.tsx:254-369` and clicking approve.
There is no selfie, no liveness, no face match: `selfie|liveness|face_match|biometric`
has zero matches repo-wide. Approving the last outstanding document flips the captain
to `approved` automatically (`admin.ts:838-852`) with no expiry check at that moment.

Expiry is decorative. The admin page computes a colour-coded countdown chip
(`CaptainVerificationPage.tsx:60-91`, used at `:861-863`) that changes nothing
downstream. `driver_documents.status` has no `expired` value in its CHECK constraint
(`migrations/0002_enhancements.sql:31-32`). The online gate tests one thing —
`captain.approval_status !== "approved"` (`captain.ts:146`) — and the trip-accept and
bid gates in `trips.ts` test the same field. No cron scans `expires_at`: the
`scheduled()` handler runs exactly three jobs (cleanup, scheduled-trip dispatch,
monthly invoices) at `apps/api/src/index.ts:267-371`. **An approved captain with an
expired licence drives forever.**

Vehicle identity is looser still. `captains.vehicle_make/model/plate/color` are
free-text columns (`migrations/0001_init.sql:29-33`) with no link to any approved
`vehicle_reg` document, and `POST /captain/profile` (`captain.ts:26-78`) updates them
by COALESCE with no re-review and no status change. A captain approved on one car can
be driving another by the next request.

Suspension (`admin.ts:289-310`) sets `approval_status='suspended'`, `is_online=0` and
`users.status='suspended'`, and writes an audit row. It does not touch
`refresh_tokens` or KV. `authMiddleware` verifies the JWT signature and nothing else
— it never reads `users` (`apps/api/src/middleware/auth.ts:29-65`) — so a suspended
captain's access token keeps working for the remainder of its 15 minutes
(`apps/api/src/lib/jwt.ts:8`).

A rider, meanwhile, is a phone number and an OTP. There is no rider document flow,
no rider verification screen, and — critically — **no way to ban a rider**:
`/admin/users` is a GET (`admin.ts:326`) and `apps/admin/src/pages/UsersPage.tsx` is a
read-only table with no action controls at all. `users.phone` carries no UNIQUE
constraint in any of the 19 migrations, so the same number can back many accounts.

### 3.5 Ratings, blocking, anomalies

`POST /trips/:id/rate` (`trips.ts:1090-1137`) requires a completed trip (`:1099`),
resolves the target by direction — rider→captain, captain→rider, admin→captain
(`:1104-1106`) — inserts into `ratings`, and relies on the
`UNIQUE(trip_id, from_user_id)` constraint (`migrations/0001_init.sql:113`) caught as
a 409 (`:1117-1118`) to prevent double-rating. Then comes the line that defines this
axis:

```ts
if (toUserId === trip.captain_id && toUserId) {   // trips.ts:1121
```

Only a captain gets an aggregate. `users` has no `rating_avg`/`rating_count` column,
so a captain's rating of a rider is written to a table nobody reads. There is no
captain-side rating UI to write it in the first place: `apps/captain/lib/screens/`
contains `home`, `onboarding`, `profile`, `safety` — no rating file anywhere — while
the captain's `.arb` files ship a `riderRating` string with no call site. The rating
is two-way in the schema and one-way in reality.

And the captain aggregate does nothing. `rating_avg` is read for display in
`withCaptain()` (`trips.ts:143`) and the bids list (`:1239`, ordered by
`created_at`, not rating). `apps/api/src/lib/nearby.ts` and the `GeoCell` DO never
reference it. No cron and no admin route checks it against a threshold. A captain can
sit at 1.0 indefinitely and receive offers at parity with a 5.0 captain.

Blocking does not exist in any form — no table, no endpoint, no UI, no filter. The
structural reason it will not be a one-line fix is in the dispatch signature:
`findNearbyCaptains(env, city, lat, lng, limit)` (`nearby.ts:62-68`) never receives
the rider's identity, and the `GeoCell` DO's `/nearby` contract carries only
coordinates. The rider is not knowable at the point where candidates are chosen.

Anomaly detection also does not exist. `trip_path_points` has a `speed` column
(`migrations/0002_enhancements.sql:20`) that is never populated, because the INSERT
lists only `id, trip_id, lat, lng, heading, recorded_at` (`captain.ts:247`) and
`captainLocationSchema` does not accept a speed field
(`apps/api/src/lib/schemas.ts:181-187`). Points are written at most once per 30
seconds (`captain.ts:239-247`) and only while the trip is assigned/arrived/in-progress.
`GET /trips/:id/path` (`trips.ts:682-706`) is a raw dump with no analytics.

### 3.6 Women's safety

Nothing exists. No gender field on `users` (`migrations/0001_init.sql:3-13`), no
field in any profile schema, no female-captain preference in trip creation, no
trusted-contacts table, and no discreet trigger — both SOS screens are deliberately
loud, full-screen and unmissable. `sos_alerts.shared_with`
(`migrations/0003_global_transport.sql:169`) is a stub column that no code reads or
writes.

## 4. Findings

| ID | Sev | Finding | Evidence (`path:line`) | Impact | Confidence |
|---|---|---|---|---|---|
| F-17-01 | S1 | The public trip-tracking link is unreachable twice over: the URL handed to the sharer omits the `/safety` mount prefix, and the "public" route sits behind `authMiddleware` applied to `*`. | `safety.ts:83`, `index.ts:120`, `safety.ts:11,90` | The only "someone knows where I am" feature in the product returns 404, or 401 if the path is corrected. It has never worked. | confirmed |
| F-17-02 | S1 | The tracking response returns `pickup_address` and `dropoff_address` to an unauthenticated bearer, under a comment claiming "no PII". | `safety.ts:89,104,119-120` | Once F-17-01 is fixed, every forwarded link discloses the rider's home address plus a live position. | confirmed |
| F-17-03 | S1 | Share tokens are never revoked when the trip ends, live up to 7 days, and no cron ever purges them. | `trips.ts:709-737,951-984`; `cleanup.ts:36,49`; `schemas.ts:99` | A link shared for a 20-minute ride keeps tracking the rider for a week. | confirmed |
| F-17-04 | S1 | `sos_alerts` is INSERT-only: no admin endpoint, no admin screen, no nav entry, and `status`/`resolved_at`/`shared_with` are never written again. | `sos_alerts` appears only at `safety.ts:14,22-26`; zero `sos` matches in `apps/admin/src`; `admin.ts` hits at `:24,:65` are `toISOString` | An emergency alert cannot be seen, triaged, assigned or closed by anyone. Every alert is "open" forever. | confirmed |
| F-17-05 | S1 | SOS delivery is a best-effort FCM fan-out to every `role='admin'` user; `pushToUser` returns silently when the admin has no device token, and the handler cannot detect that. | `safety.ts:29-39`; `notifications.ts:388-393` | The alert can reach nobody, with no error, no retry, no fallback channel and no record that it failed. | confirmed |
| F-17-06 | S1 | Neither app can dial 122/123/180, while the rider's confirm dialog states the location will be sent to the authorities. | `apps/rider/lib/screens/safety/sos_screen.dart:33`; zero `tel:`/`url_launcher` in `apps/rider/lib`; captain screen has no dial-out | The product makes an explicit safety promise it does not keep. This is the finding most likely to end up in a news story. | confirmed |
| F-17-07 | S1 | No blocking exists — no table, endpoint, UI or filter — and the dispatch signature cannot express one: `findNearbyCaptains` never receives rider identity. | `nearby.ts:62-68`; `GeoCell.ts` `/nearby` contract; zero block-concept matches repo-wide | A rider who was assaulted will be re-matched with the same captain by chance. Table stakes, entirely absent. | confirmed |
| F-17-08 | S1 | Ratings are one-way in practice: only a captain gets an aggregate, `users` has no rating columns, and no captain-side rating UI exists. | `trips.ts:1121`; `migrations/0001_init.sql:3-13`; `apps/captain/lib/screens/` has no rating file; `riderRating` string unused | Captains have no way to flag a dangerous rider. Half of "two-sided accountability" is missing. | confirmed |
| F-17-09 | S1 | `rating_avg` has no consequence anywhere — not in dispatch, not in bid ordering, not in any threshold or review trigger. | `nearby.ts` and `GeoCell.ts` never read it; `trips.ts:1239` orders by `created_at`; no cron reads ratings | A 1.0-rated captain keeps driving at full dispatch parity. Rating is theatre. | confirmed |
| F-17-10 | S1 | Document expiry is never enforced: no `expired` status exists, the online gate checks only `approval_status`, and no job scans `expires_at`. | `migrations/0002_enhancements.sql:31-32`; `captain.ts:146`; `index.ts:267-371` | Captains drive on expired licences and registrations indefinitely. Uninsurable and, after an incident, indefensible. | confirmed |
| F-17-11 | S1 | No liveness, selfie or face-match check exists; identity is an admin eyeballing an uploaded photo against self-typed text. | zero matches for `selfie\|liveness\|face_match\|biometric` repo-wide; `CaptainVerificationPage.tsx:254-369` | Anyone can onboard using someone else's documents. Nothing binds the account to the human. | confirmed |
| F-17-12 | S1 | A captain can change plate/make/model after approval with no re-review, and no insurance or inspection document type exists at all. | `captain.ts:26-78`; `captains` DDL `migrations/0001_init.sql:29-33`; `migrations/0014_document_types.sql:29-37` | The approved vehicle and the driven vehicle are unrelated records. No insurance is ever verified. | confirmed |
| F-17-13 | S1 | Suspension does not revoke live sessions; `authMiddleware` never re-checks `users.status`. | `admin.ts:289-310`; `middleware/auth.ts:29-65`; `jwt.ts:8` | A captain suspended mid-incident keeps full API access for up to 15 minutes. | confirmed |
| F-17-14 | S1 | Riders cannot be banned at all — no suspend endpoint and a read-only admin users page. | `admin.ts:326`; `apps/admin/src/pages/UsersPage.tsx` (no action controls) | The subject of a harassment report cannot be removed from the platform by any product action. | confirmed |
| F-17-15 | S1 | There is no incident/report concept: no table, no report endpoint, no category taxonomy, no ops queue, no SLA, no law-enforcement record. | no incident/report table in any of the 19 migrations; no report route in `safety.ts` or `admin.ts` | "A rider reports harassment" has no path through this system whatsoever. | confirmed |
| F-17-16 | S2 | Chat body validation is length-only, so the "no phone numbers exchanged" design intent is unenforced. | `safety.ts:138` (intent), `:144-153` (validator) | Off-platform contact, off-platform payment, and unmasked number exchange are trivially available. | confirmed |
| F-17-17 | S2 | `sender_role` is a two-way ternary; an admin's message is stored and rendered as `captain`, though the schema reserves `'support'`. | `safety.ts:163,272`; `migrations/0003_global_transport.sql:191` | Support messages impersonate the captain in exactly the disputes the log exists to arbitrate. | confirmed |
| F-17-18 | S2 | Both parties' real mobile numbers are exposed with no masking; `rider_phone` is disclosed to captains before acceptance. | `trips.ts:136,160-174`; `captain.ts:372,412`; `active_trip_panel.dart:125-131,374-385` | Post-trip harassment by phone is fully enabled, and the rider's number leaks to captains who never took the trip. | confirmed |
| F-17-19 | S2 | No trip-anomaly detection exists, and `trip_path_points.speed` is structurally unfillable — the client schema has no speed field. | `migrations/0002_enhancements.sql:20`; `captain.ts:247`; `schemas.ts:181-187`; `trips.ts:682-706` | Long stops, detours and off-destination endings are invisible. No RideCheck equivalent is even possible on current data. | confirmed |
| F-17-20 | S2 | Chat is retained forever with no purge and no admin viewer. | no `trip_chat_messages` DELETE anywhere; `cleanup.ts` covers two tables; no admin chat surface | Unbounded PII retention plus a dispute process that requires an engineer with DB access. | confirmed |
| F-17-21 | S2 | No women's-safety surface at all: no gender field, no female-captain preference, no trusted contacts, no discreet SOS. `shared_with` is a stub column. | `migrations/0001_init.sql:3-13`; zero `gender\|trusted_contact` matches; both SOS screens are full-screen and loud | The single largest addressable-market safety concern in Egypt has no product answer. | confirmed |
| F-17-22 | S2 | `/safety/sos` has no per-user rate limit; only the global 120 req/min-per-IP limiter applies, and no trip is required. | `safety.ts:1-9` (never imports `rateLimit`); `index.ts:59-66`; `schemas.ts:91` | An abusive client can flood `sos_alerts` and every admin's notifications, drowning a real alert. | confirmed |
| F-17-23 | S2 | `users.phone` has no UNIQUE constraint in any migration, so one person can hold unlimited accounts. | `migrations/0001_init.sql:8`; `migrations/0011_payment_intentions.sql:28` (plain index) | Even once rider bans exist, a banned rider returns in 60 seconds. Coordinate with T18. | confirmed |
| F-17-24 | S2 | The share-link revoke endpoint exists but no UI in either app calls it, and no rider can list their active links. | `safety.ts:126-136`; no call site in either app | A rider who shared a link with the wrong person has no way to cut it off. | confirmed |
| F-17-25 | S3 | `notification_log` is written on every push attempt and read by nothing. | `notifications.ts:35-65`; no reader in `apps/api/src` | A failed SOS push is technically recorded and operationally invisible. | confirmed |
| F-17-26 | S3 | No anti-retaliation window and no blind rating; an admin can also rate a captain via the same endpoint. | `trips.ts:1104-1106`; no delay logic in `:1090-1137` | Becomes a live retaliation vector the moment rider aggregates ship (F-17-08). | confirmed |
| F-17-27 | S3 | National ID accepted as free text up to 30 chars with no 14-digit Egyptian format or checksum validation. | `schemas.ts:210-211` | Placeholder and garbage IDs pass, compounding F-17-11. | confirmed |
| F-17-28 | S3 | The two chat screens have drifted badly: the captain's has WebSocket delivery, typing indicators, i18n and a send guard; the rider's has none of these. | `apps/rider/.../trip_chat_screen.dart` (150 lines) vs `apps/captain/.../trip_chat_screen.dart:65-126,161-185` (421 lines) | The rider — the more vulnerable party — gets the worse safety-relevant channel. → T27. | confirmed |
| F-17-29 | S3 | `read_at` is tracked and returned by the API and rendered by neither app. | `safety.ts:229-243`; no `read_at` use in either screen | "Did the captain see my message" is answerable by the server and not shown. | confirmed |
| F-17-30 | S3 | The `NOTIFICATIONS` queue and its DLQ are fully configured and never produced to; the SOS push runs inline in the request. | `wrangler.toml:43-55`; no `NOTIFICATIONS.send` in `apps/api/src`; `safety.ts:31-38` | FCM latency is added to the emergency response, and the configured retry/DLQ safety net is unused. | confirmed |
| F-17-31 | S4 | The admin verification page renders an expiry countdown chip that has no backend effect. | `CaptainVerificationPage.tsx:60-91,861-863` | Gives reviewers a false impression that expiry is enforced. | confirmed |
| F-17-32 | S4 | `ttlMinutes` permits a 7-day share token by default policy. | `schemas.ts:99` | Widens the F-17-02/03 exposure window unnecessarily. | confirmed |
| F-17-33 | S4 | The rider SOS screen hardcodes Arabic strings; the captain's routes everything through `AppStrings`. | `apps/rider/.../sos_screen.dart:32-39,54,63,75,84,88,102,115,144,152` | Safety copy cannot be corrected consistently across apps. → T14/T27. | confirmed |

### S1 expanded

**F-17-01 / F-17-02 / F-17-03 — trip sharing is simultaneously broken and unsafe.**
These three belong together because fixing one without the others makes things worse.
Today the feature is dead: the rider taps share, the OS share sheet opens, the contact
taps the link and gets a 404 (`safety.ts:83` vs `index.ts:120`). The natural fix is a
one-character path change — and the moment someone makes it, the second bug bites,
because `authMiddleware` at `safety.ts:11` covers `*` and the anonymous contact gets a
401. Fix that too, and the third bug is now live in production: the endpoint discloses
`pickup_address` and `dropoff_address` (`safety.ts:104,119-120`) to anyone holding a
URL that was designed to be forwarded through WhatsApp, that is never revoked when the
trip ends, and that can live for seven days (`schemas.ts:99`). The comment at
`safety.ts:89` asserting "no PII" is how this ships without anyone noticing. The order
of operations matters: **redact the payload first, then fix the routing.**

**F-17-04 / F-17-05 / F-17-06 — the SOS button is a notification, not a response.**
Pressing it writes a row and fires a push. That is the whole feature. There is no
queue to land in (`sos_alerts` is referenced only inside `safety.ts`), no screen to see
it on (zero `sos` matches across `apps/admin/src`), no state machine to move it
through (`status` is written once, at INSERT), and no guarantee anyone was reached —
`pushToUser` returns silently when the recipient has no device token
(`notifications.ts:393`), and the admin console is a web SPA that registers no tokens
at all. Meanwhile the rider has been told, in Arabic, on screen, that their location is
going to the authorities (`sos_screen.dart:33`). No code path contacts any authority,
and neither app can even dial 122. A safety feature that overstates itself is worse
than an absent one: it changes what a frightened person does next.

**F-17-07 — blocking is absent and the architecture currently forbids it.** This is the
one gap where the fix is not "add a table". Candidate captains are selected inside
`findNearbyCaptains(env, city, lat, lng, limit)` (`nearby.ts:62-68`), which is called
from the trip-creation handler but never told who the rider is; the `GeoCell` DO it
queries is a pure geospatial index that stores presence and nothing else. The rider's
identity has to be threaded down into that call before any block filter can be applied,
which is a change to a hot path in the dispatch flow that T06 owns. Until then, a rider
who reports a captain for assault and a captain who is reported both remain in each
other's matching pool.

**F-17-08 / F-17-09 — reputation exists as a number and not as a mechanism.** The
aggregate update is gated to captains at `trips.ts:1121`; `users` has no rating columns
to hold the other direction; and there is no captain-facing UI to submit one, which is
why the `riderRating` string in the captain's `.arb` files has no call site. So the
system cannot answer "is this rider dangerous". For captains it can answer the question
and then does nothing with the answer: `rating_avg` is displayed in bid cards
(`trips.ts:1239`) and never consulted by `nearby.ts`, the `GeoCell` DO, bid ordering, or
any threshold job. Ratings that carry no consequence also train users not to leave them.

**F-17-10 / F-17-11 / F-17-12 — verification is a one-time photo review that never
expires and never re-checks.** Documents carry `expires_at` (`0012:12`), the admin UI
renders a countdown chip for it (`CaptainVerificationPage.tsx:60-91`), and no gate
anywhere reads it: the online toggle tests `approval_status` alone (`captain.ts:146`),
the CHECK constraint has no `expired` value to move into
(`0002_enhancements.sql:31-32`), and no cron looks (`index.ts:267-371`). Nothing binds
the account to a human — no selfie, no liveness, zero matches repo-wide — so a
verified account is transferable by handing over a phone. And nothing binds the account
to a vehicle: plate and model are free-text columns a captain can PATCH at will
(`captain.ts:26-78`) with no link to the approved `vehicle_reg` document, while
insurance and periodic inspection are not collected at all
(`0014_document_types.sql:29-37`). After a serious accident, the platform cannot
demonstrate that the driver was licensed, the car was insured, or the person driving
was the person approved.

**F-17-13 / F-17-14 / F-17-15 — enforcement has no teeth and reporting has no door.**
Suspension writes three columns and revokes nothing (`admin.ts:289-310`;
`middleware/auth.ts:29-65`), so a suspended captain has up to 15 minutes of full API
access (`jwt.ts:8`) — the exact window in which someone is being suspended mid-incident.
For riders there is no suspension at all: `/admin/users` is a GET (`admin.ts:326`) and
the page has no controls. And upstream of both, there is no way to report anything: no
incident table in 19 migrations, no report endpoint, no category taxonomy, no queue, no
SLA, no record suitable for handing to police. The end-to-end harassment path today is
that the rider tells nobody, because there is nowhere to tell.

### S2 expanded

**F-17-16 / F-17-18 — the anonymity model is stated but not implemented.** The chat
header comments describe an anonymous channel where no phone numbers are exchanged
(`safety.ts:138`) while the validator checks only that the string is 1–1000 characters
(`:144-153`). It does not matter much, because the numbers are already exposed
elsewhere: `withCaptain()` puts `captain_phone` into every broadcast payload
(`trips.ts:136,160-174`) and `/captain/nearby-requests` hands out `rider_phone`
(`captain.ts:372,412`) to captains browsing offers they have not accepted. The captain
app dials it directly (`active_trip_panel.dart:125-131`). Post-trip phone harassment —
the single most common complaint category in ride-hailing — is fully enabled, and the
pre-acceptance leak means a rider's number reaches captains who never carried them.

**F-17-17 / F-17-20 — the dispute record is both wrong and unreachable.** Support
messages are attributed to the captain (`safety.ts:163`) despite the schema reserving
`'support'` (`0003:191`), so the evidence log misrepresents who said what. And there is
no way to read it: no admin screen renders a thread, so arbitration means an engineer
calling the API by hand, against a table that is never purged.

**F-17-19 — anomaly detection is not merely missing, it is currently impossible.**
`trip_path_points.speed` exists in DDL (`0002:20`), is absent from the INSERT
(`captain.ts:247`), and cannot be supplied because the client schema has no speed field
(`schemas.ts:181-187`). With 30-second sampling, some detections are still viable
(long stop, ending far from the destination, gross detours); citation-grade speeding is
not. The honest position is that Uber-style RideCheck requires a data change first.

**F-17-21 — women's safety has no surface area.** No gender field, no preference, no
trusted contacts, no discreet trigger; `sos_alerts.shared_with` is a column that no code
touches. Both SOS screens are maximally visible, which is precisely wrong for the case
where the threat is the other person in the car.

**F-17-22 / F-17-23 / F-17-24 — the surrounding controls are missing too.** SOS is
protected only by a global per-IP limiter shared with all other traffic
(`index.ts:59-66`); `users.phone` is not unique, so ban evasion is a new SIM or even
just a new email; and the revoke endpoint that would let a rider undo a bad share has
no caller.

## 5. Benchmark gap

| Mechanism | Uber | inDrive | Careem | Synaptic Go today |
|---|---|---|---|---|
| Emergency button → live human response | Confident: in-app 911/emergency dial with location read-out to the operator, plus a 24/7 incident team. | Confident: in-app safety button with live location sharing to a dedicated response team. | Confident: regional safety centre with local emergency dial-out. | Row inserted, push to any admin with a phone. No queue, no owner, no dial-out. F-17-04/05/06 |
| Trip sharing | Confident: link shows vehicle, ETA and live position; auto-expires at trip end. | Confident: share-ride link. | Confident: "Ride Sharing" to chosen contacts. | Non-functional (404/401); would expose home address; never expires at trip end. F-17-01/02/03 |
| Number masking | Confident: PSTN masking on all rider↔driver calls. | Assumed: masking or in-app calling on most markets. | Confident: masked calling. | None. Real numbers both ways, rider's number exposed pre-acceptance. F-17-18 |
| Anomaly detection | Confident: RideCheck — long stop, unexpected route deviation, crash detection, with a proactive in-app check-in. | Assumed: limited. | Assumed: limited. | None; `speed` unfillable, 30 s sampling. F-17-19 |
| Two-way ratings with consequences | Confident: both sides rated; drivers below a market threshold are deactivated; riders with low ratings are warned and eventually lose access. | Confident: two-way. | Confident: two-way. | Captain-only aggregate, zero consequence, no captain-side UI. F-17-08/09 |
| Block / never match again | Confident: post-trip "don't match me again" via support and in-app. | Assumed: present. | Assumed: present. | Absent, and unbuildable without threading rider identity into dispatch. F-17-07 |
| Driver re-screening | Confident: periodic background-check re-runs and document-expiry enforcement that blocks dispatch. | Assumed: document expiry enforced. | Confident: periodic re-screening. | One-time photo review; expiry decorative; no re-verification ever. F-17-10 |
| Identity binding (selfie / liveness) | Confident: periodic Real-Time ID Check selfie matched against the file photo. | Assumed: selfie check at onboarding. | Confident: selfie verification. | None at all. F-17-11 |
| Incident reporting & case management | Confident: in-app report flow with taxonomy, ticketing, SLA and law-enforcement liaison. | Assumed: in-app reporting. | Confident: in-app reporting. | No report path of any kind. F-17-15 |
| Women's safety | Assumed regionally varied. | Assumed: some markets. | Confident: female-captain programme in several markets. | Nothing. F-17-21 |

**Where Synaptic Go actually sits.** On this axis the product is not "behind on
features" — it is pre-foundational. Every competitor mechanism in the table depends on
two primitives this codebase does not have: an **incident record** with a lifecycle, and
an **actor relationship** (block / ban / reputation with consequence). Everything else
is downstream. The two genuinely good pieces of existing work are the share-token
entropy (`utils.ts:9-12`) and the R2 upload hardening with byte-signature sniffing
(`captain.ts:625-670`); both are the kind of detail teams usually get wrong, which makes
the systemic absences above look like scope that was never opened rather than
carelessness.

## 6. Improvement plan

Ordered by "what stops someone getting hurt, or stops us being unable to answer for it".
Next free migration number is **0020**; I allocate 0020–0024 below.

### P0.1 — Stop the trip-share leak, then make sharing work

- **Goal** — a contact can watch the ride's progress; nobody learns where the rider
  lives.
- **Design** — three changes in one PR, in this order. (1) Redact the payload: drop
  `pickup_address`/`dropoff_address` entirely and coarsen `lastPoint` to ~3 decimal
  places (≈100 m), returning `{tripId, status, coarsePoint, vehicleLabel, updatedAt}`.
  (2) Split the router: create `publicSafetyRoutes` holding only `GET /track/:token`
  and mount it on `app` *before* `safetyRoutes`, leaving `use("*", authMiddleware)`
  covering everything else. (3) Fix the URL at the mint site to match the real mount.
  Then add revoke-on-terminal-state in both the cancel and complete handlers
  (`UPDATE trip_share_tokens SET revoked_at=? WHERE trip_id=? AND revoked_at IS NULL`),
  drop `ttlMinutes` max from 10080 to 240, and add the rider-facing revoke control.
- **Files to change** — `apps/api/src/routes/safety.ts` (`:11`, `:83`, `:88-123`),
  `apps/api/src/index.ts` (`:120`), `apps/api/src/routes/trips.ts` (`:709-737`,
  `:951-984`), `apps/api/src/lib/schemas.ts` (`:99`),
  `apps/rider/lib/screens/safety/sos_screen.dart`.
- **DB** — none for the fix itself. Add `CREATE INDEX idx_share_expires ON
  trip_share_tokens(expires_at);` in 0020 to support the purge in P0.6.
- **API contract** — `GET /safety/track/:token` → `200 {tripId, status, coarsePoint:
  {lat,lng}|null, vehicleLabel, updatedAt}`, `404 NOT_FOUND`, `410 EXPIRED|REVOKED`.
  New `GET /safety/share?tripId=` → `{tokens:[{token, expiresAt, createdAt}]}` so the
  rider can list and revoke.
- **Effort** — M.
- **Risk** — the router split is the risky part; a mistake exposes authenticated safety
  routes anonymously. Mitigate with a test asserting that every path except
  `/safety/track/:token` returns 401 without a bearer token. Rollback is a revert.
- **Acceptance criteria** — an anonymous `curl` of the minted URL returns 200; the
  response body contains no address string and no coordinate finer than 3 dp;
  completing the trip makes the same URL return 410 within one request; a rider can
  revoke from the app and see 410 immediately.
- **Tests** — route-table test for the auth boundary; integration test create → track →
  complete → track; snapshot test on the exact response key set.

### P0.2 — Make SOS reach a human who is accountable for it

- **Goal** — every SOS is seen, owned and closed by a named person, with an auditable
  clock.
- **Design** — keep the INSERT, add the missing system around it. Route the fan-out
  through the already-configured `NOTIFICATIONS` queue instead of an inline loop, so FCM
  latency is off the emergency request path and the DLQ finally does something. Page an
  on-call rotation rather than every admin. Add an ops queue in the admin console
  (poll ~5 s while any alert is open) showing time-since-raise with a colour-coded SLA
  badge, the raiser's name and phone, the linked trip and last known position, with
  Acknowledge / Resolve / False-alarm / Escalate actions. Add a per-minute escalation
  sweep to the existing cron: unacknowledged at T+2 min → tier 2, at T+5 min → tier 3
  plus an optional external webhook. Record every transition as an immutable row rather
  than mutating one status in place.
- **Files to change** — `apps/api/src/routes/safety.ts` (`:15-51`),
  `apps/api/src/routes/admin.ts` (new endpoints), `apps/api/src/index.ts` (`:267-371`
  cron, wrapped in its own try/catch so a failure cannot block scheduled dispatch),
  `apps/admin/src/pages/SosQueuePage.tsx` (new), `apps/admin/src/App.tsx`,
  `apps/admin/src/components/layout/Sidebar.tsx`.
- **DB** — `migrations/0020_incident_response.sql`:

```sql
ALTER TABLE sos_alerts ADD COLUMN acknowledged_by   TEXT REFERENCES users(id);
ALTER TABLE sos_alerts ADD COLUMN acknowledged_at   TEXT;
ALTER TABLE sos_alerts ADD COLUMN escalation_level  INTEGER NOT NULL DEFAULT 0;
ALTER TABLE sos_alerts ADD COLUMN last_escalated_at TEXT;
ALTER TABLE sos_alerts ADD COLUMN resolved_by       TEXT REFERENCES users(id);
ALTER TABLE sos_alerts ADD COLUMN resolution_note   TEXT;
ALTER TABLE sos_alerts ADD COLUMN category          TEXT
  CHECK (category IN ('medical','harassment','accident','vehicle','other') OR category IS NULL);

CREATE TABLE IF NOT EXISTS sos_events (
  id         TEXT PRIMARY KEY,
  alert_id   TEXT NOT NULL REFERENCES sos_alerts(id) ON DELETE CASCADE,
  event      TEXT NOT NULL CHECK (event IN
               ('created','pushed','acknowledged','escalated','resolved','false_alarm','reopened')),
  actor_id   TEXT REFERENCES users(id),          -- NULL for cron/system
  level      INTEGER,
  note       TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_sos_events_alert ON sos_events(alert_id, created_at);

CREATE TABLE IF NOT EXISTS on_call_roster (
  id         TEXT PRIMARY KEY,
  user_id    TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  tier       INTEGER NOT NULL CHECK (tier IN (1,2,3)),
  active     INTEGER NOT NULL DEFAULT 1,
  starts_at  TEXT NOT NULL DEFAULT (datetime('now')),
  ends_at    TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_oncall_active ON on_call_roster(tier, active);
CREATE INDEX IF NOT EXISTS idx_share_expires ON trip_share_tokens(expires_at);
```

- **API contract** — `GET /admin/sos-alerts?status=&limit=` → list joined with
  `users`/`trips`/latest path point · `POST /admin/sos-alerts/:id/acknowledge` ·
  `POST /admin/sos-alerts/:id/resolve {note}` · `.../false-alarm {note}` ·
  `.../escalate {level?}` · `GET /admin/sos-alerts/:id/timeline` ·
  `GET|PUT /admin/on-call-roster`.
- **Effort** — L (M for API + DB, the queue UI is the rest).
- **Risk** — the escalation sweep shares the per-minute cron with scheduled dispatch;
  isolate it. Over-paging is the second risk — tune tiers before enabling tier 3.
- **Acceptance criteria** — an SOS raised with zero admin device tokens still appears in
  the queue within one poll interval; an unacknowledged alert produces `escalated` rows
  at T+2 and T+5; resolving requires a note and writes both the projection and an event
  row; the sidebar badge equals `COUNT(*) WHERE status='open'`.
- **Tests** — integration test for the full lifecycle; a cron unit test with a frozen
  clock asserting exactly one escalation per threshold crossing.

**Ops runbook (the human half — this is the deliverable, not the code).**
1. Page fires with alert id, raiser name + phone, category, coarse address, trip id.
2. **Call the raiser first.** Voice beats any dashboard for ground truth.
3. Acknowledge in the console immediately — it stops the escalation clock and tells
   tier 2 that someone owns it.
4. If it is real, **the ops person dials 122 / 123 / 180 themselves.** The platform must
   never auto-dial a national emergency line; a human places that call, knowing the
   jurisdiction, and writes what happened in the note.
5. Pull `GET /trips/:id/path` for the last ten minutes to distinguish "stationary,
   possible incident" from "still moving, probable false trigger".
6. Resolve or mark false alarm **with a note**. Next week's false-positive rate is built
   from these notes.
7. Handover is an explicit reassign, never a second acknowledge.

### P0.3 — Tell the truth on the SOS screen, and add real dial-out

- **Goal** — the copy matches what the system does, and a user in danger can reach
  emergency services from inside the app.
- **Design** — add three dial buttons (122 police, 123 ambulance, 180 fire) using
  `url_launcher`, which is already a dependency in both apps and already used for
  `tel:` in `active_trip_panel.dart:125-131`. Rewrite the rider's confirm text so it
  stops claiming the authorities are notified. Route both screens' strings through
  `AppStrings` while the file is open (closes F-17-33).
- **Files to change** — `apps/rider/lib/screens/safety/sos_screen.dart` (`:33`),
  `apps/captain/lib/screens/safety/sos_screen.dart`, the shared `.arb` files.
- **DB** — none. **API contract** — none.
- **Effort** — S. **Risk** — none material; `tel:` on Android 11+ needs the documented
  `LaunchMode.externalApplication` already used in the captain app.
- **Acceptance criteria** — both SOS screens show three working dial buttons; no screen
  or code comment claims authority notification that the system does not perform.
- **Tests** — widget test that each button launches the correct `tel:` URI.

### P0.4 — Suspension that actually suspends, and a rider ban

- **Goal** — an admin action removes access now, for both roles.
- **Design** — on suspend, delete the user's `refresh_tokens` and write a
  `revoked:<userId>` marker into KV `SESSIONS` with a TTL equal to `ACCESS_TTL`;
  `authMiddleware` checks that marker on each request. A 15-minute-TTL key is a cheap
  bounded blocklist — no per-request DB read. Add the symmetric rider endpoint and wire
  buttons into the admin users page.
- **Files to change** — `apps/api/src/middleware/auth.ts` (`:29-65`),
  `apps/api/src/routes/admin.ts` (`:289-310` and new `/users/:id/suspend|reinstate`),
  `apps/admin/src/pages/UsersPage.tsx`.
- **DB** — none (`users.status` already has the value).
- **API contract** — `POST /admin/users/:id/suspend {reason}` ·
  `POST /admin/users/:id/reinstate`.
- **Effort** — M. **Risk** — a KV read on every authenticated request adds latency;
  keep it to a single `get` and fail open on KV error so an outage cannot lock out the
  platform (documented trade-off: a suspended user survives a KV outage).
- **Acceptance criteria** — a suspended user's existing access token is rejected on the
  next request, not in 15 minutes; a suspended rider cannot create a trip; reinstate
  restores access immediately.
- **Tests** — integration test issuing a token, suspending, then asserting 401.

### P0.5 — Incidents and blocking: the two missing primitives

- **Goal** — a rider or captain can report what happened and never see that person
  again.
- **Design** — one migration introduces both. A report is filed against a trip with a
  category, free text and optional attachments, and lands in the same ops queue as SOS
  (a report is an incident that is not urgent). Blocking is a symmetric edge between two
  users who share a completed trip; creating a report offers "also block this person" in
  the same sheet. The dispatch hook is the hard part: change
  `findNearbyCaptains(env, city, lat, lng, limit)` to take a `riderId`, load the rider's
  block edges in **one** query (`WHERE blocker_id = ?1 OR blocked_id = ?1`), and filter
  the merged candidate list before `.slice(0, limit)`. Keep `GeoCell` identity-agnostic
  — filter after the DO returns, not inside it. Apply the same filter to the offer
  fan-out so a blocked captain never receives the request.
- **Files to change** — `apps/api/src/lib/nearby.ts` (`:62-68` signature and the merge
  step), `apps/api/src/routes/trips.ts` (both `findNearbyCaptains` call sites),
  `apps/api/src/routes/safety.ts` (new report + block endpoints),
  `apps/api/src/lib/schemas.ts`, `apps/admin/src/pages/SosQueuePage.tsx` (render reports
  alongside alerts), rider and captain post-trip sheets.
- **DB** — `migrations/0021_incidents_and_blocks.sql`:

```sql
CREATE TABLE IF NOT EXISTS incidents (
  id            TEXT PRIMARY KEY,
  trip_id       TEXT REFERENCES trips(id) ON DELETE SET NULL,
  reporter_id   TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  subject_id    TEXT REFERENCES users(id) ON DELETE SET NULL,
  category      TEXT NOT NULL CHECK (category IN
                  ('harassment','assault','unsafe_driving','fraud','discrimination',
                   'property','vehicle_condition','other')),
  description   TEXT,
  severity      TEXT NOT NULL DEFAULT 'normal' CHECK (severity IN ('low','normal','high','critical')),
  status        TEXT NOT NULL DEFAULT 'open'   CHECK (status IN ('open','triaged','actioned','closed')),
  assigned_to   TEXT REFERENCES users(id),
  resolution    TEXT,
  created_at    TEXT NOT NULL DEFAULT (datetime('now')),
  closed_at     TEXT
);
CREATE INDEX IF NOT EXISTS idx_incidents_status  ON incidents(status, created_at);
CREATE INDEX IF NOT EXISTS idx_incidents_subject ON incidents(subject_id);

CREATE TABLE IF NOT EXISTS blocks (
  id         TEXT PRIMARY KEY,
  blocker_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  blocked_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  incident_id TEXT REFERENCES incidents(id) ON DELETE SET NULL,
  reason     TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(blocker_id, blocked_id)
);
CREATE INDEX IF NOT EXISTS idx_blocks_blocker ON blocks(blocker_id);
CREATE INDEX IF NOT EXISTS idx_blocks_blocked ON blocks(blocked_id);
```

- **API contract** — `POST /safety/report {tripId, category, description, alsoBlock?}` →
  `{ok, incidentId, blockId?}` · `POST /safety/block {blockedUserId, reason?}` → 409 if
  already blocked, 403 unless a shared completed trip exists ·
  `DELETE /safety/block/:userId` · `GET /admin/incidents?status=` ·
  `POST /admin/incidents/:id/{assign,action,close}`.
- **Effort** — L.
- **Risk** — the dispatch change is on the critical path; one extra indexed query per
  trip creation is acceptable, N queries per cell is not. Guard against a rider blocking
  their way to zero supply by alerting ops when a user's block count crosses ~10.
- **Acceptance criteria** — after A blocks B, a new request from A never reaches B's
  inbox and still reaches C; the reverse holds when B blocks A; in-flight trips are
  unaffected; a filed report appears in the ops queue with its category.
- **Tests** — dispatch unit test with a seeded block; end-to-end report → queue →
  close; a latency assertion on trip creation.

### P0.6 — Enforce document expiry at the dispatch gate

- **Goal** — an expired licence, registration or (once collected) insurance takes the
  captain offline.
- **Design** — add a `hasValidDocuments(db, captainId)` helper asserting that every
  `document_types.required = 1` type has an approved row with
  `expires_at IS NULL OR expires_at > datetime('now')`. Call it in the online toggle and
  again at trip-accept as defence in depth. Add a daily cron that flips lapsed rows to
  `expired`, forces `is_online = 0`, and notifies the captain 14/7/1 days ahead. Treat
  `expires_at IS NULL` as valid so legacy rows do not brick the fleet, and give admins a
  logged one-click waiver.
- **Files to change** — new `apps/api/src/lib/verification.ts`,
  `apps/api/src/routes/captain.ts` (`:146`), `apps/api/src/routes/trips.ts` (accept and
  bid gates), `apps/api/src/index.ts` (cron),
  `apps/admin/src/pages/CaptainVerificationPage.tsx` (make the existing chip meaningful).
- **DB** — `migrations/0022_document_expiry.sql`: rebuild `driver_documents` to add
  `'expired'` to the status CHECK (SQLite/D1 cannot alter a constraint in place — create
  `driver_documents_new`, copy, drop, rename, recreate `idx_docs_captain`; coordinate
  with **T08**), plus `ALTER TABLE captains ADD COLUMN requires_reverification INTEGER
  NOT NULL DEFAULT 0;` and `ALTER TABLE captains ADD COLUMN last_reverified_at TEXT;`.
  Seed two new required types: `vehicle_insurance`, `vehicle_inspection`.
- **API contract** — `POST /captain/online` gains
  `403 {code:"DOCS_EXPIRED", expiredTypes:[...]}`.
- **Effort** — M (the table rebuild is most of the risk).
- **Risk** — a bad `expires_at` typed by a captain can lock out a legitimate driver;
  soft-launch with warnings for 14 days before enforcing, and keep the waiver.
- **Acceptance criteria** — a captain with an expired required document gets
  `DOCS_EXPIRED` on going online; the cron force-offlines within 24 h of expiry; row
  counts match before and after the rebuild.
- **Tests** — migration round-trip count check; gate unit tests at each boundary date.

### P1.1 — Two-sided ratings with consequences

- **Goal** — both parties are rated, low scores route to human review, and retaliation
  is structurally discouraged.
- **Design** — add `rating_avg`/`rating_count` to `users` and extend the handler at
  `trips.ts:1121` with the rider branch. Ship the captain-side rating sheet (mirror
  `apps/rider/lib/screens/ride/rating_sheet.dart`). Hide each side's score from the
  other until both have rated or 48 h have passed — compute at read time, do not store.
  When an aggregate crosses a threshold (≤ 2.5 over ≥ 5 ratings, tuned later), open a
  `review_queue` row rather than auto-suspending: automated suspension on small samples
  is its own abuse vector. Feed `rating_avg` into offer ordering as a tiebreaker only,
  never as a hard filter.
- **Files to change** — `apps/api/src/routes/trips.ts` (`:1090-1137`, `:1239`),
  `apps/api/src/routes/admin.ts`, new captain rating sheet,
  `apps/captain/lib/l10n/*.arb` (wire the orphaned `riderRating`).
- **DB** — `migrations/0023_two_sided_ratings.sql`: `ALTER TABLE users ADD COLUMN
  rating_avg REAL NOT NULL DEFAULT 5.0;` · `ALTER TABLE users ADD COLUMN rating_count
  INTEGER NOT NULL DEFAULT 0;` · a `review_queue` table keyed by subject user, role,
  reason, trigger values and `status IN ('open','resolved','dismissed')`.
- **API contract** — `POST /trips/:id/rate` unchanged in shape; counterpart rating
  becomes conditionally visible. New `GET /admin/review-queue`,
  `POST /admin/review-queue/:id/resolve`.
- **Effort** — M. **Risk** — riders discovering a low score with no appeal path; ship
  an appeal route to support at the same time.
- **Acceptance criteria** — a captain rating a rider updates `users.rating_avg`; five
  low ratings open exactly one queue row, not five; neither party sees the other's score
  before the window closes; duplicate rating still 409s.
- **Tests** — aggregate recompute test; visibility-window test at T+0 and T+49 h.

### P1.2 — Number masking

- **Goal** — coordination without either party learning a real number.
- **Design** — stop selecting `u.phone` into trip payloads and offer lists; introduce
  `getOrCreateMaskedNumber(env, tripId, forRole)` backed by a PSTN masking provider with
  Egyptian MSISDN support, cached per trip and released on terminal state (reuse the
  same hook as P0.1's revoke). Because both apps already dial a string, this is a
  server-side swap with no client change beyond adding the rider's missing call button.
  If no vendor is viable at launch economics, the interim mitigation is to stop
  returning `rider_phone` in `/captain/nearby-requests` before acceptance
  (`captain.ts:372,412`) — that leak has no justification at all.
- **Files to change** — new `apps/api/src/lib/telephony.ts`,
  `apps/api/src/routes/trips.ts` (`:136`, `:1238`), `apps/api/src/routes/captain.ts`
  (`:372`, `:412`), rider trip screen (add call button).
- **DB** — `migrations/0024_call_proxies.sql`: `trip_call_proxies (id, trip_id,
  rider_proxy_number, captain_proxy_number, vendor_session_ref, expires_at,
  released_at, created_at)` + index on `trip_id`.
- **API contract** — payload fields become masked numbers; no shape change.
- **Effort** — L. **Risk** — vendor cost per minute and Egyptian regulatory approval for
  masked-number services; validate before committing. **Acceptance criteria** — no API
  response contains a value equal to `users.phone`; proxies stop routing within minutes
  of trip end.
- **Tests** — contract test asserting no payload field matches the stored phone.

### P1.3 — Chat hygiene: attribution, PII filter, retention, support view

- **Goal** — the chat log is accurate, does not carry contact details, and is readable
  by support.
- **Design** — make `senderRole` three-way (`admin → 'support'`, already permitted by
  the CHECK) and render it distinctly in both apps. Add an Egyptian mobile-pattern
  filter (`01[0125]\d{8}` plus spaced/dashed/Arabic-numeral variants) that **redacts and
  flags** rather than hard-rejecting in v1 — a hard reject on a false positive in an
  active pickup is worse than a redaction. Add a 90-day purge to `cleanup.ts` alongside
  a `trip_share_tokens` purge. Add a read-only thread viewer to the admin trip row.
- **Files to change** — `apps/api/src/routes/safety.ts` (`:144-153`, `:163`, `:272`),
  `apps/api/src/lib/cleanup.ts`, `apps/admin/src/pages/TripsPage.tsx`, both chat screens.
- **DB** — none. **API contract** — unchanged.
- **Effort** — M. **Risk** — filter false positives on fare amounts; tune against a real
  Arabic sample before enabling. **Acceptance criteria** — an admin message stores as
  `support`; a pasted Egyptian number is redacted and flagged; messages older than 90
  days are purged; support can read a thread from the trip row.

### P1.4 — Identity binding: selfie at onboarding, then face match

- **Goal** — the account belongs to the person in the documents, and keeps belonging to
  them.
- **Design** — rung 1 (now): capture a camera-only selfie (no gallery) at onboarding and
  show it beside the national ID in the review modal — reuses the existing upload and
  review pipeline entirely, no new infrastructure. Rung 2 (next): an automated face-match
  score surfaced to the admin as a decision aid, never an auto-reject, with accuracy
  validated against real Egyptian ID photo quality before it influences decisions. Rung 3:
  re-selfie at each 12-month re-verification plus low-frequency random prompts at
  go-online (never mid-trip) to catch account handover. Rung 4 (roadmap): national ID
  registry cross-check, gated on a partner being available.
- **Files to change** — `apps/captain/lib/screens/onboarding/onboarding_screen.dart`,
  `apps/api/src/routes/captain.ts` (`:529-594`),
  `apps/admin/src/pages/CaptainVerificationPage.tsx`, `document_types` seed.
- **DB** — covered by 0022 (`requires_reverification`, `last_reverified_at`); add
  `face_match_score REAL` to `driver_documents` at rung 2.
- **Effort** — S for rung 1, M for rung 2, M for rung 3.
- **Risk** — face-match bias across skin tone and lighting; keeping it advisory is the
  mitigation. **Acceptance criteria** — every new captain has a selfie on file; changing
  the plate sets `requires_reverification` and blocks the next go-online until a fresh
  `vehicle_reg` is approved.

### P1.5 — Anomaly detection on the data we can actually get

- **Goal** — detect the three anomalies the current sampling supports, and fix the data
  gap blocking the fourth.
- **Design** — first make speed obtainable: add `speed` to `captainLocationSchema` and to
  the INSERT column list, and derive it server-side as a fallback from consecutive point
  deltas. Then ship, in order of false-positive safety: (a) **ending far from the
  destination** — a one-time comparison at completion against `trips.dropoff_lat/lng`,
  needs no new data at all; (b) **long stop** — a `TripRoom` alarm refreshed on each
  path write, firing if consecutive points stay within ~50 m for >3 min while
  `in_progress`; (c) **sustained speeding** — two consecutive derived samples above a
  per-vehicle threshold, never a single sample. Each detection writes a `trip_events`
  row and, above a severity bar, opens an incident and triggers an in-app check-in
  ("are you OK?" with SOS one tap away). Be explicit with stakeholders: **true route
  deviation needs `trips.route_geometry` to be populated at trip start**, which I did not
  verify — see Open questions.
- **Files to change** — `apps/api/src/lib/schemas.ts` (`:181-187`),
  `apps/api/src/routes/captain.ts` (`:239-252`),
  `apps/api/src/durable-objects/TripRoom.ts`, `apps/api/src/routes/trips.ts` (completion).
- **DB** — none if `trip_events` is a generic event table (verify shape first).
- **Effort** — L. **Risk** — GPS noise in urban canyons; ship (a) and (b) only in the
  first release. **Acceptance criteria** — a simulated 3-minute stationary segment
  produces exactly one `long_stop` event; a completion >300 m from the dropoff produces
  exactly one event; a normal trip produces none.

### P2.1 — Women's safety

- **Goal** — a female rider has protections that match the market's actual concern.
- **Design** — (1) optional self-reported gender on the profile, never inferred from a
  name, with a plain-Arabic explanation of use and an opt-out. (2) Trusted contacts (1–3)
  that are automatically notified with a tracking link when SOS fires — this is what
  `sos_alerts.shared_with` was always for, and it finally makes P0.1's share link
  load-bearing. (3) A **discreet SOS**: a long-press on an ordinary-looking element of
  the in-trip screen that fires the same endpoint with `category='harassment'` and a
  `discreet` flag, producing no visible UI change beyond a faint haptic, and routing to a
  quiet call-back protocol rather than a visible response. (4) Female-captain preference
  as a **soft, opt-in, best-effort** two-phase dispatch: prefer matching captains for the
  first wave, then fall back to the full pool with clear disclosure.
- **Caveats that must be stated to the product owner** — there is currently no
  female-captain supply funnel in the codebase at all, so a hard filter would mostly
  produce "no captains available"; a hard filter also risks being an employment-
  discrimination problem for male captains, whereas a rider-initiated preference with
  graceful fallback is defensible; and collecting gender creates a data-protection
  obligation that T25 must sign off.
- **Files to change** — `apps/api/src/routes/safety.ts`, `apps/api/src/lib/nearby.ts`
  (two-phase), `apps/api/src/lib/schemas.ts`, rider profile and trip screens.
- **DB** — `ALTER TABLE users ADD COLUMN gender TEXT CHECK (gender IN
  ('female','male','prefer_not_to_say'));` · `trusted_contacts(id, user_id, name, phone,
  created_at)` · `ALTER TABLE trips ADD COLUMN prefer_female_captain INTEGER NOT NULL
  DEFAULT 0;`
- **Effort** — L. **Risk** — availability collapse if the preference is ever hardened;
  contact-spam on repeated false alarms (rate-limit the fan-out).
- **Acceptance criteria** — SOS with contacts configured populates `shared_with` and
  sends exactly one notification per contact; the discreet trigger produces no visible
  change; a preference request with no matching supply still receives normal offers
  within the existing wave timing.

### P2.2 — Rider identity hardening

- **Goal** — a ban means something.
- **Design** — a unique partial index on `users.phone` (after de-duplicating existing
  rows), plus device-signal collection at signup for T18 to score. Validate the national
  ID format for captains (14 digits with the embedded date sanity-checked).
- **Files to change** — `apps/api/src/routes/auth.ts`, `apps/api/src/lib/schemas.ts`
  (`:210-211`).
- **DB** — de-dup migration then `CREATE UNIQUE INDEX idx_users_phone ON users(phone)
  WHERE phone IS NOT NULL;`
- **Effort** — M. **Risk** — the de-dup must be run and reviewed before the index; it
  can fail loudly on real data. **Acceptance criteria** — a second signup with an
  existing phone is rejected; a malformed national ID is rejected at document
  registration.

## 7. Phasing

**P0 — before any production traffic.** Everything here is an S1. The gate for carrying
a paying passenger is: an emergency reaches an accountable human, the sharing feature
does not leak a home address, an admin can remove a dangerous actor, and a captain
cannot drive on expired papers.

| Item | Phase | Effort | Owner type |
|---|---|---|---|
| P0.1 Share redaction + routing + revoke-on-end | P0 | M | backend + Flutter |
| P0.2 SOS ops queue, SLA, escalation, ack trail | P0 | L | backend + admin + ops |
| P0.3 Truthful SOS copy + 122/123/180 dial-out | P0 | S | Flutter |
| P0.4 Session-revoking suspension + rider ban | P0 | M | backend + admin |
| P0.5 Incidents + blocks + dispatch filter | P0 | L | backend + admin + Flutter |
| P0.6 Document-expiry enforcement | P0 | M | backend + admin |
| P1.1 Two-sided ratings with consequences | P1 | M | backend + Flutter + admin |
| P1.2 Number masking | P1 | L | backend + vendor + Flutter |
| P1.3 Chat attribution, PII filter, retention, support view | P1 | M | backend + admin + Flutter |
| P1.4 Selfie capture, then face match | P1 | S→M | Flutter + backend |
| P1.5 Anomaly detection (speed data, then detections) | P1 | L | backend |
| P2.1 Women's safety (contacts, discreet SOS, preference) | P2 | L | backend + Flutter + legal |
| P2.2 Rider identity hardening | P2 | M | backend |
| F-17-25/29/30/31/32 cleanups | P2 | S | backend + admin |

**Sequencing note.** P0.1 must land before or with P0.2, because the trusted-contact
notification in P2.1 and the ops queue's location view both lean on the share link. P0.5
must land before P1.1, because a rating threshold with nowhere to route is another dead
number. P1.5's schema change (speed) should ride along with any earlier migration to
avoid a separate deploy.

## 8. Metrics

Nothing on this axis is instrumented today — `notification_log` is written and never
read (F-17-25), and no SOS or safety metric exists anywhere. Baselines below are "0" in
the literal sense that the system cannot currently produce the number.

| Metric | Definition | Current | Target |
|---|---|---|---|
| SOS acknowledgement time (p50 / p95) | `acknowledged_at − created_at` | unmeasurable | < 60 s / < 180 s |
| SOS alerts never acknowledged | share of alerts with no ack in 15 min | unknown; structurally 100% today | 0% |
| SOS push delivery rate | `notification_log` sent ÷ attempted for `topic='sos.new'` | logged, never read | > 99%, alerting below 95% |
| False-alarm rate | `false_alarm ÷ all alerts` | unmeasurable | track only; used to tune, never to suppress |
| Incident time-to-first-response | first `triaged` − `created_at` | no incidents exist | < 4 h; < 30 min for `critical` |
| Incident closure rate within SLA | closed within category SLA | n/a | > 90% |
| Blocks created per 1,000 completed trips | volume signal for matching quality | n/a | track; a spike is a supply-quality alarm |
| Repeat-pairing after a block | matches between blocked pairs | unbounded today | exactly 0 |
| Two-sided rating coverage | share of completed trips rated by each side | rider→captain only, unmeasured | > 60% rider, > 40% captain |
| Captains below the review threshold | `rating_avg ≤ 2.5` with ≥ 5 ratings | computable, unused | 100% reviewed within 7 days |
| Expired-document driving | online captains with a lapsed required document | unknown, likely non-zero | 0, enforced at the gate |
| Verification coverage | approved captains with a selfie on file | 0% | 100% of new, 100% backfilled in 90 days |
| Share links live after trip end | non-revoked tokens on terminal trips | 100% | 0% |
| PII exposure in the public track payload | address fields returned | 2 | 0 |
| Unmasked phone exposure | API responses containing a real `users.phone` | multiple paths | 0 after P1.2 |
| Anomaly check-ins | check-ins sent ÷ trips, and the share answered "not OK" | n/a | establish a baseline, then tune |

## 9. Cross-cutting notes

- **T27 (cross-app parity) — the largest single hand-off.** The two chat screens are the
  clearest drift in the product: the captain's (`apps/captain/lib/screens/home/trip_chat_screen.dart`,
  421 lines) has WebSocket delivery (`:65-75`), a typing indicator (`:46-126`, `:375-421`),
  `AppStrings` throughout and a send guard (`:161-185`); the rider's
  (`apps/rider/lib/screens/trip/trip_chat_screen.dart`, 150 lines) has none of them and
  hardcodes Arabic. Same for SOS: the captain's screen is a polished rebuild with
  haptics, a sent state and full i18n, while the rider's is a dialog plus a snackbar with
  inline strings (`:32-39` onward). The rider — the party more likely to be at risk —
  has the weaker safety surface in both cases. Recommend extracting a shared
  `TripChatController` into `packages/flutter_shared` rather than porting screen code, so
  the drift cannot recur. Also for T27: the rider app has a share-trip action and the
  captain app has none; the captain app can call the rider and the rider cannot call the
  captain.
- **T06 (dispatch) — I need a signature change you own.** Blocking cannot exist until
  `findNearbyCaptains(env, city, lat, lng, limit)` (`apps/api/src/lib/nearby.ts:62-68`)
  accepts the rider's id and the merged candidate list is filtered before truncation.
  I have specified the filter (P0.5) but the hot-path change and its latency budget are
  yours. Please keep `GeoCell` identity-agnostic.
- **T08 (data model) — one constraint rebuild.** P0.6 needs `'expired'` added to the
  `driver_documents.status` CHECK (`migrations/0002_enhancements.sql:31-32`), which on
  D1/SQLite means a create-copy-drop-rename. Please fold this into your migration
  strategy rather than letting me do it inline. Also: `users.phone` has no UNIQUE index
  in any of the 19 migrations (`0001_init.sql:8`; `0011:28` is a plain index).
- **T18 (fraud) — shared root cause.** Ban evasion and multi-accounting are the same
  problem: no unique phone, no device fingerprint, no rider ban. My P0.4 adds the ban;
  the identity primitive that makes it stick is yours. `turnstile_verifications` exists
  and is used at auth; consider whether it can carry a device signal.
- **T22 (observability) — two ready-made wins.** `notification_log`
  (`apps/api/src/lib/notifications.ts:35-65`) is written on every push and read by
  nothing; and the `NOTIFICATIONS` queue plus DLQ are fully configured in
  `apps/api/wrangler.toml:43-55` with **no producer anywhere in the codebase** — every
  push, including SOS, runs inline in the request. Both belong to your axis; my P0.2
  assumes the queue becomes real.
- **T25 (privacy/legal) — three items need a legal position.** The public track payload
  discloses addresses (F-17-02); chat is retained indefinitely with no purge (F-17-20);
  and P2.1 proposes collecting gender, which is special-category-adjacent under Egypt's
  PDPL. I have proposed a 90-day chat retention window as an engineering default — it
  needs your sign-off, not mine.
- **T19 (notifications) — the SOS fan-out targets `role='admin'` users
  (`safety.ts:29`), which is not an on-call concept.** P0.2 introduces `on_call_roster`;
  if you are building a notification-preferences system, that roster should live inside
  it rather than beside it.
- **T14 (i18n) — safety copy is the highest-stakes copy in the product** and the rider
  SOS screen hardcodes it (`apps/rider/lib/screens/safety/sos_screen.dart:32-39` etc.).
  The line at `:33` is not just untranslated, it is factually wrong (F-17-06).
- **T23 (testing) — the auth-boundary test in P0.1 is the one test I would not ship
  without**: a route-table assertion that every `/safety/*` path except the public
  tracker rejects an unauthenticated request. The bug class it guards against
  (`use("*")` versus a deliberately public route) is exactly what produced F-17-01.

## 10. Open questions

1. **Who is on call at 03:00, and are they employees?** P0.2 assumes a human answers
   within two minutes. *Options:* (a) a founder rotation for launch; (b) a small
   in-house ops shift covering peak hours with an escalation phone overnight; (c) an
   outsourced first-line service. **Recommendation:** (a) for a limited launch with a
   hard cap on concurrent trips, moving to (b) before any marketing spend. The technical
   work is worthless without this answer, and it is the answer that costs money.
2. **Do we auto-notify emergency services, ever?** **Recommendation: no.** A human ops
   agent dials, having spoken to the user. Auto-dialling 122 from a backend is
   jurisdictionally fraught and will produce false calls that damage the relationship
   with the responders we most need. Revisit only with a formal integration and a
   partner on the other side.
3. **Number masking: buy, build, or defer?** *Options:* (a) PSTN masking vendor with
   Egyptian MSISDNs — per-minute cost, no client change; (b) in-app VoIP — no PSTN cost,
   but fails in the data dead zones where pickup coordination matters most; (c) defer,
   and merely stop leaking `rider_phone` pre-acceptance. **Recommendation:** (c)
   immediately as a free mitigation, then (a) before scale. (b) is the wrong trade for
   Egyptian network conditions.
4. **Chat retention window.** *Options:* 30 / 90 / 365 days. **Recommendation:** 90 days
   — long enough for a dispute and a chargeback cycle, short enough to limit exposure.
   Needs T25's sign-off.
5. **Female-captain preference: ship it at all, given there is no female-captain supply
   funnel today?** *Options:* (a) build the preference now and let it no-op; (b) build
   the recruitment funnel first and the preference second; (c) ship trusted contacts and
   discreet SOS now and defer the preference. **Recommendation:** (c) then (b). A
   preference toggle that never matches is worse than no toggle — it advertises a
   protection that does not arrive.
6. **Rating threshold and what happens at it.** *Options:* auto-suspend; auto-review;
   review plus dispatch de-prioritisation. **Recommendation:** review only for the first
   90 days (≤ 2.5 over ≥ 5 ratings), gathering data before anything automatic touches a
   captain's income. Small samples plus automated suspension is how you deactivate a good
   captain over one bad night.
7. **Is `trips.route_geometry` (`migrations/0002_enhancements.sql:129`) actually
   populated at trip start?** I did not verify the write path — `apps/api/src/lib/routing.ts`
   was not read in this pass. **`needs-check`.** True route-deviation detection in P1.5
   depends entirely on the answer; if it is null in practice, we ship only the
   destination-deviation and long-stop detections and say so plainly.
8. **What is the exact shape of `trip_events`?** P1.5 writes anomaly events to it; I
   read it as existing (`migrations/0001_init.sql:94`) but did not read its columns.
   **`needs-check`** before implementation — it may need a severity column.
9. **Do we backfill selfies for already-approved captains, or grandfather them?**
   **Recommendation:** backfill with a 90-day deadline enforced at the online gate. A
   grandfathered cohort with no identity binding is precisely the population an attacker
   buys an account from.
