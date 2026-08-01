# 19 — Growth, Notifications & Lifecycle Messaging

> Track: C — Feature parity & new capability · Reviewer: `chat-20260801-1350-caa1` · Date: 2026-08-01 (UTC)
> Base commit reviewed: `4fa12c4dd7f133f3eb335953a710875262383681` (`main`)

---

## 1. Scope

This document covers the machinery by which Synaptic Go talks to its users when they are
**not** looking at the screen, and the loops that are supposed to bring them back:

- the notification transport (Cloudflare Queue, FCM HTTP v1, WhatsApp, email) and its observability;
- the complete catalogue of messages the platform can send today, and the catalogue it needs;
- notification preferences, quiet hours, and the transactional/promotional split;
- deep links — whether tapping a notification lands anywhere useful;
- the referral loop (`referrals`, `user_credits`, `invite_screen.dart`) end to end;
- promo-code mechanics as a **growth** instrument (types, calendar, targeting);
- captain-supply growth: referrals, onboarding incentives, quests, guarantees;
- the activation/retention/resurrection lifecycle programme and the events needed to measure it;
- install attribution and store-review prompting.

**Explicitly out of scope**, owned elsewhere:

| Not covered here | Owner |
|---|---|
| Auth/OTP correctness, session handling (I only touch OTP as a *channel* consumer) | T01 |
| Wallet/ledger correctness of any credit I propose granting | T03 |
| PSP mechanics for paying out referral rewards | T04 |
| Promo effect on **fare maths** and commission split | T05 |
| Dispatch/offer fan-out semantics behind `trip.offer` | T06 |
| WebSocket/Durable-Object realtime path (push is the *fallback* for it) | T07 |
| Migration ordering and D1 integrity of the new tables I propose | T08 |
| Rider/captain screen-by-screen journey quality | T09 / T10 |
| Admin console IA beyond the promo/campaign surfaces | T11 |
| Design tokens and motion for the notification/inbox UI | T12 / T13 |
| Arabic copy *style guide* and RTL rendering (I supply strings; T14 owns the register) | T14 |
| Referral/promo **fraud engine** — I enumerate the abuse surface and hand it over | T18 |
| Telemetry pipeline and dashboards for the events I specify | T22 |
| Store listing, ASO and release mechanics | T26 |
| Systematic rider↔captain parity remediation | T27 |

One deliberate overlap: T18 owns fraud *detection*; I own the **reward-release rules** that make
fraud economically pointless in the first place. Both are needed.

---

## 2. What I actually read

Every file below was downloaded at commit `4fa12c4d` and read from disk with real line numbers.
Where I say "grepped", I searched the whole file but read only the matching regions.

**API — transport and producers**

| File | Note |
|---|---|
| `apps/api/src/lib/notifications.ts` | Read in full (409 lines). The entire notification transport: WhatsApp OTP, email OTP, FCM v1 with service-account JWT signing, `pushToUser` fan-out. |
| `apps/api/src/index.ts` | Read routing header + full queue/cron section (lines 232–372). This is where the queue consumer and both cron jobs live. |
| `apps/api/wrangler.toml` | Read in full (180 lines). Queue producer/consumer bindings, DLQ, batching, cron triggers, prod env overrides. |
| `apps/api/src/routes/devices.ts` | Read in full (41 lines). Token upsert and delete — the whole device-token lifecycle. |
| `apps/api/src/routes/promo.ts` | Read in full (108 lines). Validate / list / create / deactivate. |
| `apps/api/src/routes/user.ts` | Read the profile handler (72–90) closely; grepped the rest for `credits` / `referral`. |
| `apps/api/src/routes/trips.ts` | 1400+ lines — grepped and then read the promo-apply block (399–432), the `trip_promo` write (490–506), and all nine `pushToUser` call sites (576, 804, 813, 879, 931, 1063, 1074, 1199, 1361). |
| `apps/api/src/routes/safety.ts` | Read the two `pushToUser` sites (31, 202) — SOS fan-out to admins and trip chat. |
| `apps/api/src/routes/payments.ts` | Read the four `pushToUser` sites (189, 240, 279, 294) — top-up success/failure on both callback paths. |
| `apps/api/src/routes/intercity.ts` | Read the three `pushToUser` sites (175, 298, 454). |
| `apps/api/src/routes/captain.ts` | Read the earnings surface (700 lines, skimmed the document/onboarding half); confirmed there is no incentive, quest, streak or bonus concept anywhere in it. |
| `apps/api/src/routes/admin.ts` | Grepped only (36 KB). Confirmed zero occurrences of promo/referral/credit/campaign. |
| `apps/api/src/routes/auth.ts` | Grepped for the OTP send path to confirm WhatsApp/email are OTP-only consumers. |
| `apps/api/src/lib/schemas.ts` | Read `createPromoSchema` / `validatePromoSchema` / `deviceTokenSchema` regions. |
| `apps/api/src/lib/audit.ts`, `lib/cleanup.ts`, `lib/utils.ts`, `lib/types.ts` | Read; relevant for audit logging of promo actions and for `notification_log` retention. |
| `apps/api/src/middleware/rateLimit.ts` | Read to establish what actually rate-limits `/promos/validate`. |

**Migrations** — all 19 downloaded; read `0001`, `0002`, `0003`, `0016` closely, grepped the rest for
growth-relevant DDL.

| File | Note |
|---|---|
| `migrations/0002_enhancements.sql` | Read 54–122 in full: `promo_codes`, `trip_promo`, `referrals`, `user_credits`. |
| `migrations/0003_global_transport.sql` | Read 10–30 (`device_tokens`, `wallet_transactions`) and 187–229 (`trip_chat_messages`, `notification_log`). |
| `migrations/0016_system_config.sql` | Read — the config table that a campaign engine would extend. |

**Flutter — client side**

| File | Note |
|---|---|
| `packages/flutter_shared/lib/services/fcm_service.dart` | Read in full (116 lines). The whole client notification surface for **both** apps. |
| `apps/rider/lib/services/app_state.dart` | Read all four `FcmService.init` call sites (154, 396, 410, 440) and `registerDeviceToken` (522–530). |
| `apps/captain/lib/services/captain_state.dart` | Read the `FcmService.init` site (229) and `registerDeviceToken` (1109–1115). |
| `apps/rider/lib/main.dart`, `apps/captain/lib/main.dart` | Read; confirmed background-handler registration at line 21 in both. |
| `apps/rider/lib/screens/profile/invite_screen.dart` | Read in full (124 lines). |
| `apps/rider/lib/screens/notifications_screen.dart` | Read in full (165 lines). |
| `apps/rider/lib/screens/ride/promo_screen.dart` | Read in full (159 lines). |
| `apps/admin/src/pages/SettingsPage.tsx` | Read the promo CRUD region (~100–140, ~460–470) of 665 lines. |

**Read via subagent, spot-verified by me** — Android manifests and iOS `Info.plist` for both apps,
both `pubspec.yaml`, `apps/captain/lib/screens/**` listing, and `packages/flutter_shared/lib/widgets/main_bottom_nav.dart`.
I personally re-verified every claim from those reports that carries an S1 or S2 finding below;
where a subagent's reading and mine diverged, **my reading is what appears in this document** and I
note the correction in §9.

**Not read** — the Durable Objects (`TripRoom`, `CaptainInbox`, `OfferScheduler`) beyond their
bindings in `wrangler.toml`. Push is the fallback for the realtime path they own; T07 has them.
I also did not read the admin console's routing/layout beyond the promo page.

---

## 3. How it works today

### 3.1 The transport, in one paragraph

There is exactly one live delivery mechanism: **Firebase Cloud Messaging, called synchronously
from inside the HTTP request that triggered it.** A route handler calls `pushToUser(...)`, which
selects every row in `device_tokens` for that user and issues one FCM HTTP v1 request per token,
awaiting all of them (`notifications.ts:380-409`). WhatsApp and email exist but are wired to OTP
only. There is no SMS. The Cloudflare Queue that was designed to carry all of this is configured
at both ends and connected to nothing.

### 3.2 The queue that isn't

`wrangler.toml` declares a producer binding and a consumer with batching, retries and a DLQ, for
both the default and prod environments:

```
apps/api/wrangler.toml:46-55
[[queues.producers]]
queue = "synaptic-go-notifications"
binding = "NOTIFICATIONS"

[[queues.consumers]]
queue = "synaptic-go-notifications"
max_batch_size = 100
max_batch_timeout = 5
max_retries = 3
dead_letter_queue = "synaptic-go-notifications-dlq"
```

`index.ts:242-264` registers a `queue()` handler that unwraps `{ userId, topic, title, body, data }`
and calls `pushToUser`.

**No code ever sends to it.** A recursive grep for `NOTIFICATIONS` across the whole of
`apps/api/src/` returns nothing — not one `env.NOTIFICATIONS.send(...)`, not one `sendBatch`. The
binding is declared, the consumer is registered, and the producer side was never written. So:

- the queue is permanently empty;
- **the DLQ is empty**, which answers the brief's question "what is in the DLQ today" — nothing,
  and nothing ever will be until a producer exists;
- `max_retries = 3` and the DLQ are decorative;
- every notification is sent inline, in the request path, blocking the response.

That last point is the operationally interesting one. `trips.ts:576` pushes a `trip.offer` to each
nearby captain **during** `POST /trips`. The rider's request does not return until every one of
those FCM round-trips has resolved. FCM latency is now trip-creation latency.

### 3.3 The consumer would crash on its first message

```
apps/api/src/index.ts:244-245
  async queue(batch: Message[], env: Env): Promise<void> {
    for (const msg of batch) {
```

The Workers runtime invokes `queue()` with a **`MessageBatch`** — an object with a `.messages`
array plus `ackAll()` / `retryAll()`. It is not an array and it is not iterable. `for (const msg of batch)`
throws `TypeError: batch is not iterable` before the loop body runs even once, and the `try`/`catch`
that would have caught it (`index.ts:247-262`) is *inside* the loop. The exception escapes the
handler, Cloudflare fails the whole batch, retries it three times, and drops all 100 messages into
the DLQ.

It type-checks because the parameter is annotated `Message[]` rather than `MessageBatch`. This is
inert today precisely *because* nothing produces. It becomes a live S1 the instant anyone adds the
first `NOTIFICATIONS.send(...)` — which is step one of every lifecycle campaign in §6.

### 3.4 The channels

| Channel | State | Evidence |
|---|---|---|
| **FCM push** | Live. Service-account JWT signed in-worker with `crypto.subtle`, access token cached ~50 min in a module global. | `notifications.ts:219-304`, `sendFcm` 314–374 |
| **WhatsApp** | Live **but OTP-only.** `sendWhatsAppOtp` posts a fixed template `synaptic_go_otp` with one body param, and hardcodes `topic: "auth.otp"` at all four log sites. There is no generic "send a WhatsApp template" function. | `notifications.ts:71-150`, topic literal at 85, 127, 136, 143 |
| **Email** | Live but OTP-only, via Resend. Subject and HTML body are hardcoded Arabic OTP copy. | `notifications.ts:156-213`, copy at 184–185 |
| **SMS** | **Does not exist.** `notification_log.channel` permits `'sms'` (`0003:217`) but the TypeScript union does not (`notifications.ts:24`) and no code path sends one. | — |
| **In-app inbox** | `'in_app'` is in both the DB CHECK and the TS union, and is never written by any code path. The rider "notifications" screen is hardcoded dummy data (§3.8). | `notifications.ts:24`, `0003:217` |

All three live channels degrade to a logged `dropped` row when their secrets are absent
(`notifications.ts:83-91`, `164-172`, `368`), which is a genuinely good design choice for dev.

### 3.5 Everything the platform can send today

Fourteen distinct topics. Every one is transactional. Every one is FCM-only.

| # | Topic | Trigger | Recipient | `path:line` |
|---|---|---|---|---|
| 1 | `trip.offer` | Trip created, fanned to nearby captains | captain | `trips.ts:576` |
| 2 | `trip.cancelled` | Rider cancels | captain | `trips.ts:804` |
| 3 | `trip.cancelled` | Captain/system cancels | rider | `trips.ts:813` |
| 4 | `trip.accepted` | Captain accepts | rider | `trips.ts:879` |
| 5 | `trip.<status>` | Generic status transition (`arrived`, `started`, …) — topic built by interpolation | rider | `trips.ts:931-934` |
| 6 | `trip.completed` | Trip finished | rider | `trips.ts:1063` |
| 7 | `trip.completed` | Trip finished (earnings/commission copy) | captain | `trips.ts:1074` |
| 8 | `trip.bid_received` | Captain counter-offers a price | rider | `trips.ts:1199` |
| 9 | `trip.assigned` | Rider accepts a bid | captain | `trips.ts:1361` |
| 10 | `sos.new` | SOS raised | **all admins** | `safety.ts:31` |
| 11 | `trip.chat` | In-trip chat message | counterparty | `safety.ts:202` |
| 12 | `wallet.topup.success` | Paymob callback / webhook | rider | `payments.ts:189`, `279` |
| 13 | `wallet.topup.failed` | Paymob callback / webhook | rider | `payments.ts:240`, `294` |
| 14 | `intercity.booking.new` / `.cancelled` / `.assignment` | Intercity seat events | captain | `intercity.ts:175`, `298`, `454` |
| — | `scheduled.trip.dispatch` | Cron activates a scheduled trip | **all admins** | `index.ts:322` |

Zero promotional messages. Zero lifecycle messages. No welcome, no activation nudge, no lapsed-user
win-back, no rating request, no promo announcement, no captain-earnings summary, no document-expiry
warning. The catalogue is "things that happen during a trip", and nothing else.

Two of them fan out to **every admin** with no batching (`safety.ts:28-38`, `index.ts:316-327`).
`scheduled.trip.dispatch` fires inside a cron that runs **every minute** (`wrangler.toml:63`).

### 3.6 Device tokens

`POST /user/device` upserts on a unique `token` index, reassigning `user_id` on conflict — correct,
and it handles the "same phone, new account" case (`devices.ts:18-28`, unique index at `0003:13`).
`DELETE /user/device` removes one token by `(token, user_id)` (`devices.ts:34-41`).

Three problems:

1. **`platform` is a lie.** Both apps hardcode `'platform': 'android'` when registering
   (`app_state.dart:526`, `captain_state.dart:1113`). Every iOS device in `device_tokens` is
   recorded as Android. Any future platform-targeted send, and any "opt-in rate by OS" metric, is
   built on a column that is constant.
2. **`app_role` is stored and ignored.** The column exists (`0003:17`) and is populated
   (`devices.ts:27`), but `pushToUser` selects on `user_id` alone:
   ```
   apps/api/src/lib/notifications.ts:388-392
   SELECT token FROM device_tokens WHERE user_id = ? ORDER BY last_seen_at DESC
   ```
   No `LIMIT`, no `app_role` filter, no `platform` filter. A user who has both apps installed under
   one account receives captain trip-offers on the rider app.
3. **Stale tokens are never pruned.** `sendFcm` logs the failure and returns
   (`notifications.ts:349-357`); it never inspects the error for FCM's `UNREGISTERED` /
   `NOT_FOUND` and never deletes the row. `device_tokens` only grows. Delivery rate decays
   silently and the `notification_log` fills with permanent failures that look like transient ones.

### 3.7 Observability

```
migrations/0003_global_transport.sql:214-226
CREATE TABLE IF NOT EXISTS notification_log (
  id, user_id, channel, topic, payload, status, provider_ref, attempts, last_error, created_at, sent_at
);
status ... CHECK (status IN ('queued','sent','failed','dropped'))
```

Indexed on `user_id`, `status`, `created_at` (`0003:227-229`) — **not** on `topic`, which is the
column any campaign report would group by.

The ceiling here is structural: `sent` means *FCM's HTTP endpoint returned 200*. It does not mean
delivered to the handset, and it certainly does not mean seen. There is no `delivered`, no `opened`,
no `clicked` state, and no client-side event that could produce one. So:

- **Delivery is observable to the edge of Google's infrastructure and no further.**
- Open rate is unmeasurable. Click-through is unmeasurable.
- Nobody is alerted on anything. There is no consumer for the DLQ, no threshold on the `failed`
  count, no alert on `dropped` (which is what a missing secret produces in prod).
- `attempts` is written as a literal `1` on every row (`notifications.ts:40`, the default parameter)
  because there is no retry loop to count.

### 3.8 The client

`FcmService.init` (`fcm_service.dart:23-75`) does the right things in the right order: initialises
Firebase and `flutter_local_notifications`, creates the Android channel `synaptic_go_default` at
`Importance.high` (15–20, created at 35–38), subscribes to `onMessage`, subscribes to
`onMessageOpenedApp`, checks `getInitialMessage()`, requests permission, gets the token, and
subscribes to `onTokenRefresh`. The Android manifest declares `POST_NOTIFICATIONS` and sets the
default channel metadata in both apps. Both `main.dart` files register a background handler at
line 21. That is a competent baseline.

It is undone by four things:

1. **`onTap` is never supplied.** The parameter exists (`fcm_service.dart:25`) and is wired to both
   `onMessageOpenedApp` (43) and `getInitialMessage` (49). Every caller omits it —
   `app_state.dart:154`, `:396`, `:410`, `:440`, and `captain_state.dart:229`. `_pendingTapHandler`
   (100) is therefore always `null`. **Every notification tap in both apps is silently discarded**
   and lands the user on whatever `MaterialApp.home` resolves to.
2. **Two incompatible tap contracts.** Background taps deliver `m.data` — a `Map`. Foreground taps
   go through `_onLocalTap` and deliver `{'rawPayload': response.payload}` where the payload was
   built as `message.data.toString()` (96) — Dart's `{tripId: abc, status: assigned}` map-toString,
   which is not JSON and will not `jsonDecode`. Even after wiring `onTap`, the two paths need
   different parsers.
3. **iOS is half-initialised.** `InitializationSettings` passes `android:` only
   (`fcm_service.dart:30-32`); there is no `DarwinInitializationSettings`, so foreground local
   notifications do nothing on iOS. There is no `getAPNSToken()` call anywhere.
4. **The rider re-initialises FCM on every login path** with no callbacks at all
   (`app_state.dart:396`, `:410`, `:440`). Each call re-subscribes `onMessage` and
   `onMessageOpenedApp` without cancelling the previous subscription — duplicate foreground
   notifications after any re-login — and re-assigns `_pendingTapHandler = onTap` where `onTap` is
   `null` (`fcm_service.dart:44`). The captain app calls `init` exactly once (`:229`). This
   asymmetry is unexplained and is a T27 item.

Neither app reads any of the `data` keys the API sends — `tripId`, `bookingId`, `alertId`, `msgId`,
`status`, `channel`, `finalFare`, `counterPrice`. All of it is discarded on arrival.

### 3.9 Deep links

There are none, in any form:

- no `intent-filter` with `android.intent.action.VIEW` in either manifest — only `MAIN`/`LAUNCHER`;
- no `CFBundleURLTypes` / `CFBundleURLSchemes` in either `Info.plist`;
- no `go_router`, `uni_links` or `app_links` in any `pubspec.yaml`;
- no `routes:` table and no `onGenerateRoute` in either `MaterialApp`; navigation is imperative
  `Navigator.push(MaterialPageRoute(...))` throughout, and tab switching is an `IndexedStack` index.

There is no route name in this codebase to link *to*. Deep linking is not a configuration change
here; it is a navigation refactor. `invite_screen.dart:37` already shares
`https://godrive.app` in its invite text — a URL that resolves to nothing and is registered nowhere.

### 3.10 The referral loop

The schema was designed and then abandoned.

```
migrations/0002_enhancements.sql:107-115   referrals(id, referrer_id, referred_id,
                                            reward_type DEFAULT 'credit', reward_value DEFAULT 0,
                                            status DEFAULT 'pending', created_at)
migrations/0002_enhancements.sql:118-122   user_credits(user_id PK, balance DEFAULT 0, updated_at)
```

Searching the entire repository: **`referrals` is never inserted into, updated, or selected from by
any API code.** `user_credits` is read in exactly one place —

```
apps/api/src/routes/user.ts:80-88
SELECT balance FROM user_credits WHERE user_id = ?
...
return c.json({ user: dbUser, credits: credits?.balance ?? 0 });
```

— and is **never written** by anything. `wallet_transactions` even reserves a `'promo_credit'` type
(`0003:21`) that no code path ever inserts.

There is no `referral_code` column on `users` or anywhere else across all 19 migrations. So on the
client:

```
apps/rider/lib/screens/profile/invite_screen.dart:34
    final code = _referral?['referral_code'] ?? 'GODRIVE';
apps/rider/lib/screens/profile/invite_screen.dart:49
    final code = _referral?['referral_code'] as String? ?? 'GODRIVE';
```

`_referral` is the `/user/profile` response (`invite_screen.dart:24-31`), which contains
`{ user, credits }` and no `referral_code`. **Every user in the system shares the identical
hardcoded string `GODRIVE`.** `invited_count` (`:51`) reads a key that does not exist and always
renders `0`. `credits` (`:50`) reads a key that *does* exist and always renders `0`, because
nothing can ever write to `user_credits`.

The invite screen is a facade over four missing links: code generation, signup attribution,
qualifying-event detection, and reward issuance. **The growth loop does not exist.**

### 3.11 Promo codes

`promo_codes` supports a percent or fixed discount, a global `max_uses`, an `expires_at` and an
`active` flag (`0002:54-63`). That is the entire feature set. There is **no** per-user cap, no
minimum fare, no first-ride-only flag, no city or corridor scope, no product/vertical scope, no
budget ceiling, and no campaign grouping.

Apply path — `POST /trips` (`trips.ts:401-425`): read the code, check `expires_at`, check
`uses_count < max_uses`, compute the discount, floor the fare at zero (`:428`), compute commission
on the discounted fare (`:429`). Then write two independent statements:

```
apps/api/src/routes/trips.ts:493-503
INSERT INTO trip_promo (trip_id, promo_code, discount) VALUES (?, ?, ?)
UPDATE promo_codes SET uses_count = uses_count + 1 WHERE code = ?
```

Consequences I can demonstrate from the code:

- **No per-user cap exists.** The validity check at `:415-419` never looks at who the rider is.
  One rider can redeem the same code on every trip until the *global* counter is exhausted. For a
  first-ride acquisition code this is the whole budget, spent by one person.
- **TOCTOU on the counter.** The read at `:418` and the increment at `:499-503` are separate
  awaits with no `D1.batch()` and no transaction. Concurrent redemptions overshoot `max_uses`.
- **A fixed-value code can produce a free ride.** `Math.min(promo.value, est.fare.total)` (`:424`)
  clamps the discount *to the fare*, so a code with a large value zeroes any trip; `:428` floors at
  0 and `:429` then computes 0 commission.
- **Code enumeration is cheap.** `POST /promos/validate` is open to any authenticated user
  (`promo.ts:10`) and returns three distinguishable states — `PROMO_INVALID` (404),
  `PROMO_EXPIRED`, `PROMO_EXHAUSTED` (`promo.ts:28-35`). The only limiter is the global soft
  rate limit of 120 requests/minute/IP (`index.ts:59-66`), i.e. ~172,800 guesses per day per IP.
- Admin can create, list and deactivate; there is **no edit and no reactivate** (`promo.ts:53`,
  `:60`, `:94`). A typo in a code is permanent. Create and deactivate are audit-logged
  (`promo.ts:82-89`, `:100-106`); list is not.
- The rider's promo screen calls `GET /promos` (`promo_screen.dart:29`), which is
  `requireRole("admin")` (`promo.ts:53`). Riders get 403, the error is swallowed by
  `catch (_) {}` (`promo_screen.dart:31`), and the "available offers" list is permanently empty.
  The rider can only blind-type a code they learned elsewhere.

### 3.12 Captain-side growth

There is none. `captain.ts` (700 lines) contains earnings queries and document/onboarding handling,
and no concept of a bonus, quest, streak, guarantee, referral or incentive anywhere in it. No table
in any of the 19 migrations models a captain incentive. Supply growth is currently: recruit a
captain, and hope.

### 3.13 Attribution and store presence

No attribution SDK of any kind is present in either `pubspec.yaml`. There is no install source, no
campaign parameter, no deferred deep link, no `SKStoreReviewController` / Play In-App Review call.
The platform cannot answer "where did this rider come from?" for any rider.

### 3.14 The in-app inbox

`apps/rider/lib/screens/notifications_screen.dart` renders a list seeded from hardcoded
`AppStrings` constants (`:22-26`). It fetches nothing, subscribes to nothing, and its unread state
is in-memory and resets on cold start. It is also not reachable — it is not in the rider's
`IndexedStack` or bottom nav. The captain app has no notifications screen at all. So the `in_app`
channel that both the DB CHECK and the TS union declare has no surface to render into.

---

## 4. Findings

| ID | Sev | Finding | Evidence (`path:line`) | Impact | Confidence |
|---|---|---|---|---|---|
| F-19-01 | S1 | The `NOTIFICATIONS` queue has **no producer**. Nothing anywhere calls `env.NOTIFICATIONS.send`. Every notification is sent inline, inside the triggering HTTP request. | `wrangler.toml:46-55`; recursive grep of `apps/api/src/` for `NOTIFICATIONS` → 0 hits; `trips.ts:576` | FCM latency is trip-creation latency. No retry, no backpressure, no isolation. A slow or degraded FCM makes `POST /trips` slow. | confirmed |
| F-19-02 | S1 | The queue **consumer would crash on its first message**: it types the batch as `Message[]` and iterates it directly, but Workers passes a non-iterable `MessageBatch`. The throw escapes the per-message `try`. | `index.ts:244-245`, `try` at `:247` | Latent today (no producer). The instant anyone adds a producer, 100% of messages fail 3× and land in a DLQ with no consumer. This is the first step of every plan in §6. | confirmed |
| F-19-03 | S1 | **The referral loop does not exist.** `referrals` and `user_credits` are dead schema; there is no `referral_code` column anywhere; every user shares the hardcoded code `GODRIVE`. | `0002:107-122`; `user.ts:80-88` (only read); `invite_screen.dart:34`, `:49` | The single highest-leverage growth mechanism for a launch-stage Egyptian product is a non-functional UI shell. Zero attributable acquisition. | confirmed |
| F-19-04 | S1 | **No deep linking, and every notification tap is discarded.** `onTap` is never passed to `FcmService.init`; no URL scheme, no `VIEW` intent-filter, no route table in either app. | `fcm_service.dart:25,43,49,100`; `app_state.dart:154,396,410,440`; `captain_state.dart:229`; manifests/`Info.plist` (no scheme) | All 14 notifications carry `tripId`/`bookingId`/`alertId` payloads that are thrown away. Tapping "your captain arrived" opens the home screen. Kills push CTR and makes referral install-attribution impossible. | confirmed |
| F-19-05 | S1 | **No notification preferences, no transactional/promotional split, no quiet hours.** `pushToUser` sends to every token unconditionally; no preferences table exists in any of the 19 migrations. | `notifications.ts:380-409`; migrations grep | Blocks any promotional programme from launching safely. A 2 a.m. promo is uninstall-bait, and there is no mechanism to prevent one or to let a user opt out of marketing while keeping trip alerts. | confirmed |
| F-19-06 | S2 | Promo codes have **no per-user redemption cap**. Validity is checked without reference to the rider. | `trips.ts:415-419` | One rider can drain an entire acquisition budget. A "first ride free" code is a permanent free-rides code. | confirmed |
| F-19-07 | S2 | **TOCTOU on `uses_count`** — the cap check and the increment are separate, untransacted statements. | read `trips.ts:418`; write `trips.ts:499-503` | Concurrent redemptions exceed `max_uses`. Budget overrun is unbounded under a burst. | confirmed |
| F-19-08 | S2 | A fixed-value promo can produce a **zero-fare trip with zero commission**; the discount is clamped to the fare rather than capped independently. | `trips.ts:424`, `:428`, `:429` | Free rides at platform cost, with no floor and no per-code budget ceiling. | confirmed |
| F-19-09 | S2 | **Stale FCM tokens are never pruned.** `sendFcm` never inspects the error for `UNREGISTERED`/`NOT_FOUND` and never deletes the row. | `notifications.ts:349-357`; `devices.ts` has delete-by-request only | `device_tokens` grows monotonically. Measured delivery rate decays and the failure log fills with permanent errors indistinguishable from transient ones. | confirmed |
| F-19-10 | S2 | `app_role` is stored but **ignored on fan-out**; `platform` is hardcoded `'android'` by both clients. | `notifications.ts:388-392`; `0003:17`; `app_state.dart:526`; `captain_state.dart:1113` | Cross-app misdelivery for dual-app users. Every iOS device is recorded as Android, so platform-segmented sends and per-OS metrics are built on a constant. | confirmed |
| F-19-11 | S2 | **Delivery is unobservable past FCM's front door.** `status` allows only `queued/sent/failed/dropped`; there is no `delivered`, `opened` or `clicked`, and no client event that could produce one. No alerting on `failed`/`dropped`, no DLQ consumer. | `0003:214-229`; `notifications.ts:35-65` | Nobody can answer "did the captain get the offer?" or "did anyone open the promo?". Every campaign in §6 would be unmeasurable. | confirmed |
| F-19-12 | S2 | **WhatsApp is OTP-only** despite being the dominant channel in Egypt; the topic is hardcoded `auth.otp` and there is no generic template-send function. | `notifications.ts:71-150`, topic literal at `:85,127,136,143` | The cheapest, highest-reach channel in the market carries exactly one message type. See §5 for the cost case. | confirmed |
| F-19-13 | S2 | The two notification **tap payload contracts are incompatible**: background delivers a `Map`, foreground delivers `{'rawPayload': <Dart map toString>}` which is not JSON. | `fcm_service.dart:43` vs `:96,101-104` | Even after wiring `onTap`, foreground taps need a separate bespoke parser. Guaranteed to be missed and to fail only in the foreground case. | confirmed |
| F-19-14 | S2 | **iOS notification setup is incomplete**: no `DarwinInitializationSettings`, no APNS token handling. | `fcm_service.dart:30-32` | Foreground local notifications silently do nothing on iOS. Combined with F-19-10, the iOS notification path is untested and unmeasured. | confirmed |
| F-19-15 | S2 | The rider **re-initialises `FcmService` on every login path with no callbacks**, stacking duplicate `onMessage`/`onMessageOpenedApp` subscriptions and nulling the tap handler. The captain app initialises once. | `app_state.dart:396,410,440` vs `captain_state.dart:229`; `fcm_service.dart:44` | Duplicate foreground notifications after re-login. Unexplained rider/captain asymmetry → T27. | confirmed |
| F-19-16 | S2 | The rider's **promo screen calls an admin-only endpoint**; the 403 is swallowed and the offers list is permanently empty. | `promo_screen.dart:29,31`; `promo.ts:53` | Riders can never discover a promo in-app. Every campaign must be distributed out-of-band, which there is no channel for (F-19-12). | confirmed |
| F-19-17 | S2 | **No captain growth programme of any kind** — no referral, onboarding incentive, quest, streak or earnings guarantee in code or schema. | `captain.ts` (full read); all 19 migrations | Supply is the binding constraint in a launch market and there is no instrument to grow or steer it. | confirmed |
| F-19-18 | S2 | **No install attribution and no activation instrumentation.** No SDK in either `pubspec.yaml`; no funnel events emitted anywhere. | both `pubspec.yaml`; grep for analytics/attribution | Channel spend is unattributable and the install→first-trip funnel is invisible. Nothing in §6 can be proven to work. | confirmed |
| F-19-19 | S3 | Promo model lacks first-ride-only, minimum-fare, city/corridor scope, vertical scope, per-campaign budget and campaign grouping. | `0002:54-63` | Cannot run a real growth calendar; every code is a blunt global instrument. | confirmed |
| F-19-20 | S3 | Promo codes **cannot be edited or reactivated**; only create / list / deactivate exist. | `promo.ts:53,60,94` | A typo is permanent; a paused campaign cannot be resumed. Ops works around it by minting new codes, fragmenting reporting. | confirmed |
| F-19-21 | S3 | Two notification types fan out to **all admins individually**, one of them from a cron that runs every minute. | `safety.ts:28-38`; `index.ts:316-327`; `wrangler.toml:63` | Admin push volume scales with admin count × event rate. Will be muted by the humans who most need SOS alerts. | confirmed |
| F-19-22 | S3 | The in-app inbox is **hardcoded dummy data and unreachable from navigation**; the captain app has no equivalent. | `notifications_screen.dart:22-26`; not present in rider `IndexedStack`; `apps/captain/lib/screens` listing | The `in_app` channel declared in schema and TS has no surface. No message history after a push is dismissed. | confirmed |
| F-19-23 | S3 | `notification_log` has no index on `topic`, the natural GROUP BY for any campaign report. | `0003:227-229` | Reporting queries table-scan as volume grows. | confirmed |
| F-19-24 | S3 | `attempts` is always written as `1`; there is no retry loop to count. | `notifications.ts:40` | The column is misleading in any operational query. | confirmed |
| F-19-25 | S3 | No store-review prompt anywhere; no `SKStoreReviewController` / Play In-App Review integration. | both apps, grep | Free, high-intent rating opportunities after a good trip go unused. → T26 | confirmed |
| F-19-26 | S3 | `referrals` has no constraint preventing `referrer_id = referred_id`. | `0002:107-115` | When the loop is built, self-referral is not blocked at the schema level. → T18 | confirmed |
| F-19-27 | S4 | `SettingsPage.tsx` declares a `min_fare?` field on its `Promo` interface that does not exist in the DB. | `SettingsPage.tsx:18` vs `0002:54-63` | Dead interface field; reads `undefined` forever. | confirmed |
| F-19-28 | S4 | The invite share text hardcodes `https://godrive.app`, a URL registered nowhere and handled by nothing. | `invite_screen.dart:37` | Broken promise in user-visible copy. | confirmed |

### The S1 set, in prose

**F-19-01 / F-19-02 — the queue is a decoration with a landmine under it.**
These are one problem seen from both ends. The design intent was clearly right: a durable queue
with batching, three retries and a DLQ, so that a route handler could fire a notification and
return. What shipped is the configuration and the consumer, with the producer never written. The
result is that every notification is sent inline — `POST /trips` awaits an FCM round-trip per
nearby captain (`trips.ts:576`) before the rider gets a response — and that the retry/DLQ machinery
protects nothing.

The landmine is that fixing the obvious half (adding producers) detonates the other half. The
consumer iterates its `MessageBatch` as if it were an array (`index.ts:244-245`). Because Workers
hands it an object with a `.messages` property and no `Symbol.iterator`, the `for...of` throws
immediately — and it throws *outside* the `try` that was meant to catch per-message failures,
because that `try` is inside the loop body that never executes. Cloudflare sees the handler reject,
fails the entire batch of up to 100, retries three times, and DLQs everything. Since no DLQ
consumer is configured and nothing alerts on DLQ depth, the first symptom would be users reporting
that notifications stopped, with a clean-looking log.

Fix order matters: **repair the consumer before writing the first producer.** This is P0.1 and P0.2
in §6 and they must ship in that order, in the same release.

**F-19-03 — the referral loop is a screen with no machine behind it.**
`referrals` and `user_credits` were created in migration `0002` and never touched again. There is
no `referral_code` column in any of the 19 migrations, so `invite_screen.dart:34` and `:49` fall
through to their fallback and hand *every user in the system the same code, `GODRIVE`*. A user who
shares it is sharing a string that no endpoint validates, that attributes to nobody, and that
grants nothing. `credits` renders `0` forever because `user_credits` has no writer; `invited_count`
renders `0` because the key does not exist in the profile response (`user.ts:86-89`).

For a pre-launch Egyptian ride-hailing product this is the most expensive gap in the document.
Referral is the primary growth engine in this market (§5.6) and the platform currently cannot
attribute a single install to a single existing user.

**F-19-04 — the payload arrives and is thrown on the floor.**
The API is disciplined about `data`: every push carries `tripId`, or `bookingId`, or `alertId` and
`msgId`, or `finalFare` and `counterPrice`. `FcmService` even exposes an `onTap` parameter and
wires it to both `onMessageOpenedApp` and `getInitialMessage` (`fcm_service.dart:43,49`). No caller
ever passes it — four sites in the rider, one in the captain. `_pendingTapHandler` is permanently
`null`. So a captain tapping "رحلة جديدة متاحة" lands on the home screen and has to find the offer
himself, during the seconds when the offer is still live.

Underneath that, there is nowhere to navigate *to*: no named routes, no `go_router`, no
`onGenerateRoute`, navigation is imperative `Navigator.push` and tabs are an `IndexedStack` index.
And there is no way in from outside: no `VIEW` intent-filter, no `CFBundleURLTypes`. This is why
P0.4 is scoped as a navigation refactor rather than a config change, and why it is a shared
prerequisite for referral attribution (you cannot land an invited user on a pre-filled invite
screen without it).

**F-19-05 — nothing separates a receipt from an advert.**
`pushToUser` takes a `topic` string and sends to every token, unconditionally
(`notifications.ts:380-409`). There is no preferences table, no category on the topic, no quiet-hours
window, no per-user mute. Today that is survivable because all 14 message types are transactional
and expected. It becomes a blocker the moment §6 adds a single promotional message, because there
is no mechanism to (a) let a user keep trip alerts while refusing marketing, or (b) prevent a
campaign from firing at 03:00. Both are table stakes, and the second one is how you lose the
install rather than the click.

### The S2 set, in prose

**Promo integrity (F-19-06, F-19-07, F-19-08).** These three compound. There is no per-user cap, so
one rider may reuse a code indefinitely; the global cap that is supposed to bound the damage can be
overshot by concurrent redemptions because the check and the increment are separate untransacted
statements; and a fixed-value code clamps to the fare, so a sufficiently large one makes every ride
free at zero commission. A single leaked code with a generous fixed value and a loose `max_uses` is
an unbounded liability, and the only rate limiter in front of the enumeration endpoint is a global
120 req/min/IP (`index.ts:59-66`). T05 owns the fare arithmetic and T18 owns detection; the
*mechanism* fixes — per-user cap, atomic conditional update, independent discount ceiling, per-code
budget — are P0.6 here.

**Deliverability decay (F-19-09, F-19-10, F-19-14).** Tokens are never pruned on `UNREGISTERED`,
so `device_tokens` accumulates dead rows and the real delivery rate falls month over month while
the logs show only "failed". `app_role` is captured and then ignored at fan-out, so a dual-app user
gets the other app's notifications. `platform` is hardcoded `'android'` on both clients, so the
column is a constant and iOS is invisible — which matters because iOS is also the platform whose
foreground local-notification path is not initialised at all. Together these mean the notification
system's actual reach is unknown and drifting downward.

**Measurement (F-19-11).** `sent` means Google accepted the HTTP request. There is no delivery
receipt, no open, no click, and no client event that could supply one. Combined with F-19-04
(taps discarded) there is literally no signal that any human has ever seen a notification. Every
target in §8 is unmeasurable until P0.3 lands.

**Channel strategy (F-19-12, F-19-16).** WhatsApp — the channel with ~90% reach among Egyptian
internet users — carries OTP and nothing else, because `sendWhatsAppOtp` hardcodes its topic and
there is no generic template sender. Meanwhile the only in-app promo surface calls an admin-only
endpoint and shows an empty list forever. So there is currently no way to tell a rider that a promo
exists: not in-app, not on WhatsApp, not by push.

**Supply and measurement of growth (F-19-17, F-19-18).** No captain incentive exists in code or
schema, and no attribution or funnel instrumentation exists in either app. The platform can neither
steer supply nor tell where demand came from.

---

## 5. Benchmark gap

*Competitor mechanics below are marked **confident** where sourced to primary documentation, and
**assumed** where inferred. Pricing figures move quarterly — treat the rate card as
`needs-check` at implementation time.*

### 5.1 Channel economics in Egypt — the decisive number

WhatsApp Business moved to **per-delivered-template pricing on 1 July 2025** (previously
conversation-based). Approximate Egypt rate card at time of review:

| Category | Per delivered message (USD) |
|---|---|
| Authentication | ~$0.0036 |
| Utility | ~$0.0036 |
| Marketing | ~$0.0644 |

Egyptian A2P SMS, for comparison: ~$0.014 (regional bulk providers) to ~$0.048 (Twilio) per message,
and Arabic Unicode halves the per-segment character budget (70 vs 160), so real Arabic SMS cost is
often ~2× the headline. *Confidence: sourced but `needs-check` — Meta revises rates up to four
times a year.*

Three consequences that should drive the architecture:

1. **WhatsApp authentication is 4–13× cheaper than SMS for OTP.** The platform already made this
   choice (`notifications.ts:71-150`) — correctly — and simply never extended it.
2. **Utility templates are ~18× cheaper than marketing templates.** The category you declare is
   the cost lever. Trip receipts, captain-arrival notices and document-expiry warnings are
   *utility*. Discounts are *marketing*. Getting this classification right is worth more than any
   volume discount.
3. **Messages inside an open 24-hour customer-service window are free**, and utility templates
   within that window are free. A rider who messages the business — or who arrives via a WhatsApp
   entry point — opens a free window in which the entire trip's messaging costs nothing.

A worked figure for the transactional programme in §6: at ~$0.0036 per out-of-window utility
template, one paid template per booking plus free in-window follow-ups costs roughly **$72/week at
10,000 weekly active riders taking two rides each**. That is not a budget line worth optimising.
The marketing category is, at ~18× the price.

### 5.2 Push benchmarks

Cross-vertical benchmark data puts opt-in in the 33–70% band depending on OS and vertical, with
travel at the top and food/on-demand in the 33–40% range. Triggered/contextual messages run
~16% average open versus ~4.7% for untargeted broadcast; behaviour-triggered CTR lands in the
7.5–16% band against ~1.3–1.8% for promotional broadcast. *Confidence: sourced for the
cross-vertical figures; **assumed** that ride-hailing transactional sits at the high end (10–15%
open) — no ride-hailing-specific study found.*

The operative lesson is not the absolute numbers, which vary. It is that **triggered beats
broadcast by 3–10×**, which is an argument for the event-driven catalogue in §6.3 over a
campaign-blast tool.

### 5.3 Uber

- Rider referral rewards are gated on the referee **completing a first trip**, not on signup.
  *Confident — Uber Help documentation.*
- Driver referrals pay after the referred driver completes a **specified number of trips within a
  window**, paid the following week. *Confident.*
- Quests moved from trip-count to **earnings-based** goals in June 2024, with the driver opting
  into a tier before the period starts. *Confident.*
- "Trips in a row" streaks pay ~5% extra per consecutive trip up to ~20%, with declines dropping
  the driver a level. *Confident.*

**Gap:** Synaptic Go has none of these. It has no referral at all (F-19-03) and no captain
incentive primitive whatsoever (F-19-17).

### 5.4 Careem

- Runs a paid subscription (Careem Plus) with credit-back and delivery benefits, priced so a single
  month's usage clears the fee. *Confident on existence and structure; Egypt pricing **assumed**.*
- Uses WhatsApp Business for service/support interactions in MENA. Whether it uses marketing-category
  WhatsApp for promotions in Egypt is **assumed**, not confirmed.
- Launched price-negotiation ("Go 3ala Kefak") in Cairo in Feb 2024 — i.e. the bidding model
  Synaptic Go is building is already contested by an incumbent. *Confident.*

**Gap:** Synaptic Go has no loyalty or subscription concept. That is fine for launch — §10 argues
against building one before ride-frequency data exists — but it is the eventual retention endgame.

### 5.5 inDrive

- Positions on price transparency and negotiation, and self-describes as the leading ride-hailing
  app in Egypt. *Confident on positioning; market-leadership claim is their own.*
- Market-entry playbook is a **supply shock**: a "Super Launch" at ~1% commission (against a
  15–25% norm) in Cairo and then Alexandria, to build captain density first. *Confident.*
- Growth is referral- and word-of-mouth-led rather than paid-acquisition-led. *Confident directionally.*
- Invested heavily in device-fingerprint fraud intelligence specifically because incentive and
  referral fraud scaled with them. *Confident — vendor case study, so treat the ROI figure as
  marketing, but the direction is credible.*

**Gap and lesson:** the competitor Synaptic Go most resembles won its position with a referral loop
plus a supply subsidy, and had to build fraud controls to survive its own referral programme. Synaptic
Go has the fraud exposure (F-19-06/07/08, F-19-26) without the programme. That is the worst ordering.

### 5.6 Where Synaptic Go actually sits

| Capability | Uber | Careem | inDrive | Synaptic Go |
|---|---|---|---|---|
| Transactional push | ✅ | ✅ | ✅ | ✅ (14 topics, FCM-only, unmeasured) |
| WhatsApp beyond OTP | ✅ (MENA) | ✅ (service) | ✅ | ❌ OTP only |
| Deep-linked notifications | ✅ | ✅ | ✅ | ❌ taps discarded |
| Notification preferences / quiet hours | ✅ | ✅ | ✅ | ❌ none |
| Delivery + open analytics | ✅ | ✅ | ✅ | ❌ `sent` only |
| Rider referral, attributed | ✅ | ✅ | ✅ core | ❌ dead schema, one shared code |
| Captain referral | ✅ | ✅ (some markets) | ✅ | ❌ |
| Captain quests / streaks / guarantees | ✅ | ✅ | ✅ | ❌ |
| Promo targeting (first-ride, city, per-user cap) | ✅ | ✅ | ✅ | ❌ global codes only |
| In-app offer discovery | ✅ | ✅ | ✅ | ❌ 403 → empty list |
| Install attribution | ✅ | ✅ | ✅ | ❌ |
| Lifecycle campaigns | ✅ | ✅ | ✅ | ❌ zero |
| Loyalty / subscription | ✅ Uber One | ✅ Careem Plus | ➖ | ❌ (correctly deferred) |

The honest summary: **the transactional layer is roughly one bug-fix away from competitive; the
growth layer does not exist.** Every row marked ❌ except the last is a §6 item.

### 5.7 Attribution tooling

Firebase Dynamic Links **shut down on 25 August 2025** — links now fail. Any plan that reaches for
it is dead on arrival. *Confident.* Practical options for a launch-stage team: AppsFlyer's free
tier (~12,000 non-organic installs in year one) or Branch's free tier (~10,000 clicks/month), both
of which also solve **deferred deep linking** — the "install the app, then land on the invite screen
with the code pre-filled" flow that the referral programme in §6.5 requires. Native Android App
Links + iOS Universal Links cover post-install routing for free but cannot do deferred attribution.
*Pricing tiers: sourced but `needs-check`.*

### 5.8 Store review prompts

iOS `SKStoreReviewController` is capped at **3 prompts per user per 365 days**, silently ignored
beyond that, with no success signal returned. Google's In-App Review API applies an undisclosed
quota, practically observed at roughly one prompt per 1–2 weeks. *Confident on the iOS cap;
Android figure is community-observed, mark **assumed**.* The standard pattern is an internal
sentiment gate: ask a cheap in-app question first, and only invoke the OS prompt for users who
answer positively. Synaptic Go invokes neither (F-19-25). → T26.

---

## 6. Improvement plan

Ordered. P0.1 and P0.2 must ship in that order and in the same release — see F-19-02.

### P0.1 — Fix the queue consumer before anything is queued

- **Goal** — the notification queue can be used at all without silently dead-lettering every message.
- **Design** — correct the handler signature to `MessageBatch<NotificationJob>` and iterate
  `batch.messages`. Move the `try` to wrap the whole batch as well as each message, so a malformed
  payload retries one message instead of failing 100. Ack explicitly on success, `retry()` with
  backoff on transient failure, and ack-with-log on permanent failure (a malformed body will never
  succeed; retrying it three times then DLQing it is noise). Add a second consumer for
  `synaptic-go-notifications-dlq` whose only job is to write the failed job to `notification_log`
  with `status='failed'` and increment a counter metric.
- **Files to change** — `apps/api/src/index.ts` (242–264), `apps/api/wrangler.toml` (add the DLQ
  consumer block in both the default and `env.prod` sections).
- **DB** — none.
- **API contract** — none.
- **Effort** — S.
- **Risk** — very low; the code path is currently unreachable. Rollback is a revert.
- **Acceptance criteria** — a unit test invokes the handler with a mock `MessageBatch` of 3
  messages, one of which throws, and asserts 2 acks + 1 retry and no thrown exception. A message
  published to the DLQ produces a `notification_log` row.
- **Tests** — Vitest with `unstable_dev` or a hand-rolled `MessageBatch` stub; assert `ack`/`retry`
  call counts.

### P0.2 — Route every notification through the queue

- **Goal** — take FCM latency out of the request path and give notifications retry and isolation.
- **Design** — introduce `enqueueNotification(env, job)` in `lib/notifications.ts` that calls
  `env.NOTIFICATIONS.send(job)`, and replace all 17 inline `pushToUser` call sites with it. Keep
  `pushToUser` as the consumer-side primitive. Add `NOTIFICATIONS: Queue<NotificationJob>` to the
  `Env` interface. Two call sites should **not** move: `trip.offer` (`trips.ts:576`) and
  `sos.new` (`safety.ts:31`) are latency-critical — for those, send inline *and* enqueue a
  delayed re-send that is cancelled on acknowledgement, or simply keep them inline behind
  `ctx.waitUntil` so they no longer block the response. Prefer `waitUntil` for both: it is one line
  and removes the blocking without changing semantics.
- **Files to change** — `apps/api/src/lib/notifications.ts`, `apps/api/src/lib/types.ts` (Env),
  `routes/trips.ts` (9 sites), `routes/safety.ts` (2), `routes/payments.ts` (4),
  `routes/intercity.ts` (3), `index.ts` (1 cron site).
- **DB** — none.
- **API contract** — none.
- **Effort** — M.
- **Risk** — a queue outage becomes a notification outage rather than a request failure; acceptable
  and preferable. Roll back by reverting the call sites; the consumer is harmless if unused.
- **Acceptance criteria** — `POST /trips` p95 no longer varies with captain count. No route handler
  awaits an FCM call. Every `notification_log` row for a queued topic has `attempts >= 1` reflecting
  real attempts.
- **Tests** — integration test asserting `POST /trips` returns before any FCM mock resolves.

### P0.3 — Make delivery observable

- **Goal** — be able to answer "was it delivered, and did anyone open it?"
- **Design** — three parts. (a) Extend `notification_log.status` to
  `queued|sent|delivered|failed|dropped|suppressed` and add `opened_at`, `category`,
  `campaign_id`, `dedupe_key`. (b) On the client, when a notification is tapped, POST the
  notification id back — the id already exists (`id("ntf")`, `notifications.ts:49`); include it in
  the FCM `data` map as `nid` so the client can echo it. (c) On `sendFcm` failure, parse the FCM
  error: on `UNREGISTERED` / `NOT_FOUND`, delete the `device_tokens` row (this closes F-19-09).
  Add an index on `topic` and on `(campaign_id, status)`.
- **Files to change** — `apps/api/src/lib/notifications.ts` (log writer, `sendFcm` error branch,
  add `nid` to data), new `apps/api/src/routes/notifications.ts` (POST `/notifications/:id/opened`),
  `packages/flutter_shared/lib/services/fcm_service.dart` (echo on tap),
  `apps/api/src/index.ts` (mount route).
- **DB** — migration `0020_notification_observability.sql`:
  ```sql
  ALTER TABLE notification_log ADD COLUMN opened_at TEXT;
  ALTER TABLE notification_log ADD COLUMN category TEXT NOT NULL DEFAULT 'transactional';
  ALTER TABLE notification_log ADD COLUMN campaign_id TEXT;
  ALTER TABLE notification_log ADD COLUMN dedupe_key TEXT;
  CREATE INDEX IF NOT EXISTS idx_notif_topic     ON notification_log(topic);
  CREATE INDEX IF NOT EXISTS idx_notif_campaign  ON notification_log(campaign_id, status);
  CREATE UNIQUE INDEX IF NOT EXISTS idx_notif_dedupe ON notification_log(dedupe_key)
    WHERE dedupe_key IS NOT NULL;
  -- SQLite cannot extend a CHECK in place; recreate the table or drop the CHECK.
  ```
  *Note for T08: the `status` CHECK constraint cannot be widened by `ALTER`. Either rebuild the
  table (create-copy-drop-rename) or drop the constraint and enforce in application code. I
  recommend the rebuild; the table is append-only and small at this stage.*
- **API contract** — `POST /notifications/:id/opened` → `204`. Auth required; the row's `user_id`
  must match the caller.
- **Effort** — M.
- **Risk** — the table rebuild is the only real risk; do it while volume is negligible, i.e. now.
- **Acceptance criteria** — a delivered-and-tapped notification has non-null `opened_at`. An
  `UNREGISTERED` FCM response removes exactly one `device_tokens` row. `SELECT topic, COUNT(*)`
  uses the index.
- **Tests** — unit test for the FCM error branch with a mocked `UNREGISTERED` body; integration
  test for the open callback authorisation check.

### P0.4 — Deep links and a real tap handler

- **Goal** — tapping any notification lands on the right screen with the right state; external
  links open the app.
- **Design** — adopt a single navigation entry point in each app: a `GlobalKey<NavigatorState>` and
  a `handleNotificationTap(Map<String,dynamic> data)` dispatcher, rather than a full `go_router`
  migration (which T27 may want to own more broadly). Define the URL scheme
  **`synapticgo://`** plus HTTPS App Links on `go.synapticstudio.tech`:

  | Route | Deep link | Source topics |
  |---|---|---|
  | Trip detail / live trip | `synapticgo://trip/{tripId}` | `trip.accepted`, `trip.<status>`, `trip.cancelled`, `trip.completed` |
  | Captain offer inbox | `synapticgo://offer/{tripId}` | `trip.offer`, `trip.assigned` |
  | Bid review sheet | `synapticgo://trip/{tripId}/bids` | `trip.bid_received` |
  | Trip chat | `synapticgo://trip/{tripId}/chat` | `trip.chat` |
  | Wallet | `synapticgo://wallet` | `wallet.topup.*` |
  | Promo detail | `synapticgo://promo/{code}` | promo campaigns |
  | Invite | `synapticgo://invite?ref={code}` | referral install |
  | Admin SOS | `synapticgo://sos/{alertId}` | `sos.new` |
  | Intercity booking | `synapticgo://intercity/{scheduleId}` | `intercity.*` |

  Fix the two contract bugs while in here: serialise the local-notification payload as
  `jsonEncode(message.data)` instead of `.toString()` (`fcm_service.dart:96`), and make
  `_onLocalTap` decode it into the same `Map` shape the background path delivers
  (`:101-104`). Pass `onTap` at all five init sites. Make the rider's repeated `init` calls
  idempotent — guard with a static `_initialised` flag so `:396/:410/:440` stop stacking listeners.
  Add `DarwinInitializationSettings` (`:30-32`).
- **Files to change** — `packages/flutter_shared/lib/services/fcm_service.dart`;
  new `packages/flutter_shared/lib/services/deep_link_router.dart`;
  `apps/rider/lib/services/app_state.dart` (154, 396, 410, 440);
  `apps/captain/lib/services/captain_state.dart` (229);
  `apps/rider/lib/main.dart`, `apps/captain/lib/main.dart` (navigator key);
  both `android/app/src/main/AndroidManifest.xml` (VIEW intent-filter);
  both `ios/Runner/Info.plist` (`CFBundleURLTypes`, associated domains);
  both `pubspec.yaml` (`app_links`).
- **DB** — none.
- **API contract** — none. Add `nid` and keep existing `data` keys unchanged.
- **Effort** — L.
- **Risk** — navigation regressions; mitigate by routing through one dispatcher that falls back to
  the home screen on any unknown link. Rollback is a flag that disables the dispatcher.
- **Acceptance criteria** — `adb shell am start -a android.intent.action.VIEW -d "synapticgo://trip/abc"`
  opens the trip screen from cold start, warm start and foreground. Each of the 9 route rows above
  is verified on both platforms. An unknown link opens home and logs, never crashes.
- **Tests** — widget test per route asserting the dispatcher resolves the right screen; a manual
  matrix for cold/warm/foreground × Android/iOS.

### P0.5 — Notification preferences, categories and quiet hours

- **Goal** — a user can refuse marketing without losing trip alerts, and no promotional message
  ever fires at night.
- **Design** — every notification gets a **category**: `transactional` (never suppressible),
  `service` (suppressible, e.g. document expiry), `promotional` (suppressible, quiet-hours
  enforced). Add a `notification_prefs` row per user, defaulting promotional to **opt-in at
  first launch via a soft prompt**, not silently on. Enforce in one place — a
  `resolveRecipients(env, userId, category)` gate inside `pushToUser` — so no call site can bypass
  it. Quiet hours default 22:00–08:00 Africa/Cairo; promotional messages scheduled inside the
  window are deferred to 09:00 local, not dropped. Add a per-user daily promotional cap (default 1)
  and a global `dedupe_key` so a retry cannot double-send.
- **Files to change** — `apps/api/src/lib/notifications.ts` (the gate), new
  `apps/api/src/routes/notifications.ts` (prefs CRUD), `apps/rider/lib/screens/profile/**` and the
  captain equivalent (a preferences screen — coordinate with T09/T10/T27 on placement).
- **DB** — migration `0021_notification_prefs.sql`:
  ```sql
  CREATE TABLE IF NOT EXISTS notification_prefs (
    user_id       TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    push_txn      INTEGER NOT NULL DEFAULT 1,   -- always 1; kept for audit symmetry
    push_service  INTEGER NOT NULL DEFAULT 1,
    push_promo    INTEGER NOT NULL DEFAULT 0,
    wa_txn        INTEGER NOT NULL DEFAULT 1,
    wa_promo      INTEGER NOT NULL DEFAULT 0,
    email_promo   INTEGER NOT NULL DEFAULT 0,
    quiet_start   TEXT NOT NULL DEFAULT '22:00',
    quiet_end     TEXT NOT NULL DEFAULT '08:00',
    timezone      TEXT NOT NULL DEFAULT 'Africa/Cairo',
    updated_at    TEXT NOT NULL DEFAULT (datetime('now'))
  );
  ```
- **API contract** — `GET /notifications/prefs` → the row; `PATCH /notifications/prefs` with any
  subset of the boolean/quiet fields → the updated row.
- **Effort** — M.
- **Risk** — a bug in the gate silences transactional messages. Mitigate: `transactional` short-circuits
  the gate before any lookup, and there is a test asserting that a user with every flag off still
  receives `trip.offer`.
- **Acceptance criteria** — promotional send to a user with `push_promo = 0` writes
  `status='suppressed'` and no FCM call. A promotional send at 02:00 Cairo is deferred, not dropped.
  A user with all flags off still receives all 14 existing topics.
- **Tests** — table-driven unit tests over (category × prefs × local time) → send/suppress/defer.

### P0.6 — Promo integrity

- **Goal** — a promo code cannot cost more than its budget, and cannot be farmed by one account.
- **Design** — add per-user caps and a real budget to `promo_codes`; enforce the global cap with a
  single conditional UPDATE rather than read-then-write; cap the discount independently of the fare
  so a fixed code cannot zero a trip; record redemptions per user.
  Replace `trips.ts:499-503` with:
  ```sql
  UPDATE promo_codes SET uses_count = uses_count + 1
   WHERE code = ? AND (max_uses IS NULL OR uses_count < max_uses)
  ```
  and treat `meta.changes === 0` as "cap reached" → apply no discount. Add a
  `promo_redemptions(promo_code, user_id, trip_id)` table with a unique index on
  `(promo_code, user_id)` when `per_user_limit = 1`, so the database refuses a second redemption.
- **Files to change** — `apps/api/src/routes/trips.ts` (401–425, 493–503),
  `apps/api/src/routes/promo.ts` (validate + create + new update/reactivate),
  `apps/api/src/lib/schemas.ts`, `apps/admin/src/pages/SettingsPage.tsx`.
- **DB** — migration `0022_promo_targeting.sql`:
  ```sql
  ALTER TABLE promo_codes ADD COLUMN per_user_limit  INTEGER NOT NULL DEFAULT 1;
  ALTER TABLE promo_codes ADD COLUMN first_ride_only INTEGER NOT NULL DEFAULT 0;
  ALTER TABLE promo_codes ADD COLUMN min_fare        REAL;
  ALTER TABLE promo_codes ADD COLUMN max_discount    REAL;      -- caps percent AND fixed
  ALTER TABLE promo_codes ADD COLUMN city            TEXT;      -- NULL = all cities
  ALTER TABLE promo_codes ADD COLUMN budget_total    REAL;      -- currency ceiling
  ALTER TABLE promo_codes ADD COLUMN budget_spent    REAL NOT NULL DEFAULT 0;
  ALTER TABLE promo_codes ADD COLUMN campaign_id     TEXT;
  ALTER TABLE promo_codes ADD COLUMN starts_at       TEXT;
  CREATE TABLE IF NOT EXISTS promo_redemptions (
    id          TEXT PRIMARY KEY,
    promo_code  TEXT NOT NULL REFERENCES promo_codes(code),
    user_id     TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    trip_id     TEXT NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
    discount    REAL NOT NULL,
    created_at  TEXT NOT NULL DEFAULT (datetime('now'))
  );
  CREATE INDEX IF NOT EXISTS idx_promo_redeem_user ON promo_redemptions(promo_code, user_id);
  ```
  *`max_discount` closes F-19-08: the discount becomes `min(computed, max_discount ?? computed)`
  and is then still floored at the fare, so a fixed code can no longer be a free ride unless
  someone deliberately sets `max_discount` above the fare.*
- **API contract** — `POST /promos/:code` (update), `POST /promos/:code/activate`;
  `POST /promos/validate` gains `{ eligible: boolean, reason?: string }` and stops distinguishing
  `PROMO_INVALID` from `PROMO_EXPIRED`/`PROMO_EXHAUSTED` for non-admin callers — return a single
  opaque `PROMO_NOT_APPLICABLE` to blunt enumeration (F-19-16 abuse surface). Add a per-user rate
  limit of 10/min on validate.
- **Effort** — M.
- **Risk** — the conditional UPDATE changes behaviour at the cap boundary; previously a race
  overshot, now it under-applies by design. Acceptable and correct.
- **Acceptance criteria** — 50 concurrent redemptions of a `max_uses=10` code yield exactly 10
  `trip_promo` rows. A second redemption by the same user of a `per_user_limit=1` code is refused.
  A fixed code of 9999 on a 60 EGP fare with `max_discount=30` discounts 30, not 60.
- **Tests** — a concurrency test firing N parallel `POST /trips`; unit tests over the eligibility
  matrix.

### P0.7 — Close the referral loop

- **Goal** — a real, attributed, fraud-resistant two-sided referral programme.
- **Design** — the mechanic, concretely:

  1. **Code generation.** On user creation, generate a short, unambiguous code: 6 characters from
     `ABCDEFGHJKMNPQRSTUVWXYZ23456789` (no `I/L/O/0/1`), unique-indexed, stored on `users`.
     Backfill existing users in the migration.
  2. **Distribution.** `invite_screen.dart` reads the real code from `/user/profile` and shares a
     link `https://go.synapticstudio.tech/i/{CODE}` which App-Links into
     `synapticgo://invite?ref={CODE}` when installed, and falls through to the store with the code
     preserved for deferred deep linking when not.
  3. **Attribution.** The signup request accepts `referralCode`. On success, insert `referrals`
     with `status='pending'`. Reject if the code is the user's own, if the referee already has a
     row, or if the device fingerprint already appears against the referrer.
  4. **Qualification.** On the referee's **first completed trip with a settled payment** — not on
     signup — flip to `status='qualified'` and grant both sides. This single rule removes most of
     the fraud incentive, matching Uber's published mechanic (§5.3).
  5. **Reward.** Credit both parties via a `wallet_transactions` row of type `promo_credit`
     (the type already exists, `0003:21`) rather than the orphan `user_credits` table — T03 owns
     the ledger and there should be exactly one balance of record. Deprecate `user_credits`:
     keep the read in `user.ts:80-88` but source it from the ledger.
  6. **Guards.** Referrer cap of 20 qualified referrals/month; reward expiry 30 days;
     48-hour hold before the credit is spendable; block when referrer and referee share a device
     fingerprint or payment instrument. Detection heuristics belong to **T18** — the *rules* above
     are what make detection cheap.

  **Unit economics** (recommended launch values; the model, not the gospel):

  | Item | Value | Basis |
  |---|---|---|
  | Referee reward | 30 EGP off first ride | ≈ half a typical Cairo fare — enough to trigger the trip |
  | Referrer reward | 30 EGP credit, on referee's first completed trip | symmetric, paid only on proven value |
  | Gross cost per activated rider | 60 EGP ≈ **$1.25** | both legs |
  | Marginal cost of the invite itself | ~$0 (organic share) or ~$0.0036 if nudged by WhatsApp utility template | §5.1 |
  | Platform revenue per trip @ 15% take on a 60 EGP fare | 9 EGP | §5.1 fare assumption — **assumed** |
  | Trips to repay the 60 EGP subsidy | ~7 completed trips | 60 ÷ 9 |
  | Referrer cap | 20/month | bounds worst-case exposure to 600 EGP/referrer/month |

  At 7 trips to payback, this is only sound if referred riders retain — which is exactly why P1.2
  (activation instrumentation) must land alongside it, and why the reward is gated on a completed
  trip rather than an install. If cohort retention shows referred riders reaching 7 trips at under
  50%, cut the referrer leg to 20 EGP before cutting the referee leg; the referee leg is what
  produces the trip.

- **Files to change** — `apps/api/src/routes/auth.ts` (accept `referralCode` at signup),
  `apps/api/src/routes/user.ts` (return `referral_code`, `invited_count`, ledger-sourced `credits`),
  `apps/api/src/routes/trips.ts` (qualification hook at completion, near `:1063`),
  new `apps/api/src/lib/referrals.ts`,
  `apps/rider/lib/screens/profile/invite_screen.dart` (34, 49, 51 — real values; 37 — real link).
- **DB** — migration `0023_referrals.sql`: add `users.referral_code TEXT UNIQUE` (backfilled);
  add to `referrals` — `qualified_at`, `rewarded_at`, `referrer_reward`, `referee_reward`,
  `device_fingerprint`, `CHECK (referrer_id <> referred_id)` (closes F-19-26), unique index on
  `referred_id` (one referrer per referee).
- **API contract** — `POST /auth/verify-otp` and the email register endpoints accept optional
  `referralCode`. `GET /user/profile` gains `referral_code`, `invited_count`, `pending_rewards`.
  `GET /user/referrals` → the list with statuses.
- **Effort** — L.
- **Risk** — fraud. Mitigated by the completed-trip gate, the caps and the hold; T18 owns detection.
  Rollback: feature-flag reward issuance while leaving attribution recording on, so no data is lost.
- **Acceptance criteria** — two fresh devices, one invited by the other, produce a `qualified` row
  and two ledger credits only after the referee's first trip completes and payment settles.
  Self-referral is refused at the DB level. A 21st referral in a month is recorded but not rewarded.
- **Tests** — end-to-end referral test; a fraud test asserting same-fingerprint pairs are not
  rewarded; a concurrency test on the referrer cap.

### P0.8 — WhatsApp as a first-class channel

- **Goal** — use the channel that actually reaches Egyptians for more than OTP.
- **Design** — generalise `sendWhatsAppOtp` into `sendWhatsAppTemplate({ env, userId, to, template,
  category, params, topic })` with the category (`authentication` | `utility` | `marketing`)
  explicit at the call site, because category is the cost lever (§5.1). Keep `sendWhatsAppOtp` as a
  thin wrapper so the auth path is untouched. Register the utility templates needed by the
  catalogue in §6.3 and store their names in `system_config` (`0016`) rather than hardcoding them.
  Route selection lives in the queue consumer: try push; if the user has no live token or the push
  fails permanently, fall back to WhatsApp utility for a defined subset of topics.
- **Files to change** — `apps/api/src/lib/notifications.ts` (71–150 generalised),
  `apps/api/src/index.ts` (consumer fallback logic), `migrations/0016` follow-up config rows.
- **DB** — config rows only.
- **API contract** — none.
- **Effort** — M.
- **Risk** — template rejection by Meta; mitigate by submitting templates for approval before the
  code ships and failing closed to push-only.
- **Acceptance criteria** — a trip receipt is delivered on WhatsApp when push fails, with
  `notification_log.channel='whatsapp'` and the correct `category`. Marketing templates are
  refused for users with `wa_promo = 0`.
- **Tests** — mocked Graph API responses for success, template-not-approved, and rate-limit.

### P1.1 — The notification catalogue

- **Goal** — one authoritative, versioned catalogue covering the whole product surface, replacing
  fourteen ad-hoc call sites.
- **Design** — a single `catalog.ts` mapping `topic → { category, channels, timing, template,
  deepLink, dedupe }`. Copy lives in the catalogue, not inline in route handlers, so T14 can own the
  Arabic register without touching business logic. `T` = transactional, `S` = service,
  `P` = promotional. Channel order is the fallback chain.

**Rider — trip lifecycle** (all exist today except where marked **NEW**)

| Topic | Trigger | Cat | Channels | Timing | Arabic copy | Deep link |
|---|---|---|---|---|---|---|
| `trip.searching` **NEW** | Trip created | T | push | immediate | جاري البحث عن كابتن قريب منك… | `trip/{id}` |
| `trip.bid_received` | Captain counter-offers | T | push | immediate | عرض جديد بمبلغ {price} ج.م — اضغط للمراجعة | `trip/{id}/bids` |
| `trip.accepted` | Captain accepts | T | push, WA-utility | immediate | تم قبول رحلتك — {captain} في الطريق إليك | `trip/{id}` |
| `trip.arriving` **NEW** | Captain <300 m | T | push | immediate | كابتنك على وصول — {plate} | `trip/{id}` |
| `trip.arrived` | Captain at pickup | T | push, WA-utility | immediate | كابتنك في انتظارك الآن — {plate} | `trip/{id}` |
| `trip.started` | Trip begins | T | push | immediate | بدأت رحلتك — رحلة سعيدة | `trip/{id}` |
| `trip.completed` | Trip ends | T | push, WA-utility | immediate | وصلت بسلامة — الأجرة {fare} ج.م. قيّم رحلتك | `trip/{id}` |
| `trip.cancelled` | Either side cancels | T | push, WA-utility | immediate | تم إلغاء الرحلة — يمكنك طلب رحلة جديدة فورًا | `trip/{id}` |
| `trip.no_captain` **NEW** | Search times out | T | push | on timeout | لم نجد كابتنًا متاحًا الآن — جرّب تعديل السعر | `trip/{id}` |
| `trip.chat` | Chat message | T | push | immediate, coalesced 30 s | رسالة جديدة من كابتنك | `trip/{id}/chat` |
| `trip.receipt` **NEW** | 2 min after completion | S | WA-utility, email | +2 min | إيصال رحلتك — {fare} ج.م | `trip/{id}` |
| `trip.rate_reminder` **NEW** | Unrated after 2 h | S | push | +2 h, once | قيّم رحلتك مع {captain} — رأيك يهمنا | `trip/{id}` |

**Rider — money**

| Topic | Trigger | Cat | Channels | Timing | Arabic copy | Deep link |
|---|---|---|---|---|---|---|
| `wallet.topup.success` | PSP confirms | T | push, WA-utility | immediate | تم شحن محفظتك بمبلغ {amount} ج.م | `wallet` |
| `wallet.topup.failed` | PSP declines | T | push | immediate | تعذّر إتمام الشحن — جرّب مرة أخرى | `wallet` |
| `wallet.low_balance` **NEW** | Balance < 20 EGP | S | push | max 1/week | رصيد محفظتك منخفض — اشحن الآن لتجنّب تعطّل رحلتك | `wallet` |
| `promo.credit_granted` **NEW** | Referral qualifies | T | push, WA-utility | immediate | حصلت على {amount} ج.م رصيد من دعوة {name} | `wallet` |
| `promo.credit_expiring` **NEW** | 3 days before expiry | S | push | 10:00 local | رصيدك {amount} ج.م ينتهي خلال 3 أيام | `wallet` |

**Rider — lifecycle** (all **NEW**)

| Topic | Trigger | Cat | Channels | Timing | Arabic copy | Deep link |
|---|---|---|---|---|---|---|
| `life.welcome` | Signup complete | T | push, WA-utility | +5 min | أهلًا بك في Synaptic Go — أول رحلة عليها خصم {amount} ج.م | `promo/{code}` |
| `life.d1_unactivated` | No trip after 24 h | P | WA-marketing | day 1, 18:00 | لسه ما جربتش أول رحلة؟ خصمك {amount} ج.م لسه مستنيك | `promo/{code}` |
| `life.d3_unactivated` | No trip after 72 h | P | push | day 3, 18:00 | خصم أول رحلة ينتهي بكرة — احجز دلوقتي | `promo/{code}` |
| `life.post_first_trip` | 1 h after first trip | T | push | +1 h | إزاي كانت أول رحلة؟ ادعُ صديقك واكسبوا {amount} ج.م | `invite` |
| `life.d7_lapsed` | 7 days since last trip | P | push | 18:00 | وحشتنا — رحلتك الجاية عليها خصم {amount} ج.م | `promo/{code}` |
| `life.d30_winback` | 30 days since last trip | P | WA-marketing | 18:00 | رجعنالك بعرض خاص — {amount} ج.م خصم على رحلتك الجاية | `promo/{code}` |
| `life.weekly_habit` | 3+ trips/week, Sunday | P | push | Sun 09:00 | {n} رحلات الأسبوع ده — شكرًا لثقتك | `home` |
| `life.commute_nudge` | Recurring corridor detected | P | push | 15 min before usual | رحلتك المعتادة للشغل؟ احجز في ثانية | `home` |

**Captain** (all **NEW** except the three that exist)

| Topic | Trigger | Cat | Channels | Timing | Arabic copy | Deep link |
|---|---|---|---|---|---|---|
| `trip.offer` | Nearby trip | T | push (high) | immediate, TTL 30 s | رحلة جديدة — {fare} ج.م على بعد {km} كم | `offer/{id}` |
| `trip.assigned` | Rider accepts bid | T | push | immediate | تم قبول عرضك — {price} ج.م. توجه للانطلاق | `offer/{id}` |
| `trip.cancelled` | Rider cancels | T | push | immediate | ألغى الراكب الرحلة — لا إجراء مطلوب | `home` |
| `cap.doc_expiring` **NEW** | 14/7/1 days before | S | push, WA-utility | 10:00 | {document} ينتهي خلال {n} يوم — جدّده لتفادي إيقاف الحساب | `documents` |
| `cap.doc_rejected` **NEW** | Admin rejects | T | push, WA-utility | immediate | تم رفض {document} — {reason} | `documents` |
| `cap.approved` **NEW** | Onboarding approved | T | push, WA-utility | immediate | تمت الموافقة على حسابك — ابدأ استقبال الرحلات | `home` |
| `cap.daily_summary` **NEW** | End of active day | S | push | 23:00 | حصيلة اليوم: {n} رحلة و{amount} ج.م | `earnings` |
| `cap.weekly_summary` **NEW** | Monday | S | push, WA-utility | Mon 09:00 | أرباح الأسبوع: {amount} ج.م من {n} رحلة | `earnings` |
| `cap.commission_low` **NEW** | Wallet below threshold | T | push, WA-utility | immediate | رصيدك لا يكفي لعمولة الرحلات — اشحن للاستمرار | `wallet` |
| `cap.quest_progress` **NEW** | 80% of a quest | P | push | immediate | باقي {n} رحلات على مكافأة {amount} ج.م | `earnings` |
| `cap.quest_completed` **NEW** | Quest done | T | push, WA-utility | immediate | مبروك — أضفنا {amount} ج.م مكافأة لمحفظتك | `wallet` |
| `cap.surge_zone` **NEW** | Demand spike nearby | P | push | max 3/day | طلب مرتفع في {area} — اتجه هناك الآن | `home` |
| `cap.idle_nudge` **NEW** | Offline 3+ days | P | push | 08:00 | الطلب مرتفع الصباح ده — افتح التطبيق واستقبل رحلات | `home` |

**Admin**

| Topic | Trigger | Cat | Channels | Timing | Arabic copy | Deep link |
|---|---|---|---|---|---|---|
| `sos.new` | SOS raised | T | push (critical) | immediate | إنذار طوارئ — تحقق فورًا | `sos/{id}` |
| `ops.dlq_depth` **NEW** | DLQ > 0 | S | push, email | max 1/15 min | فشل تسليم إشعارات — راجع قائمة الانتظار | — |
| `ops.promo_budget` **NEW** | Code at 80% budget | S | push | once per code | كود {code} استهلك 80% من ميزانيته | — |

Replace the per-admin fan-out (`safety.ts:28-38`, `index.ts:316-327`) with one send to an admin
topic subscription, and drop `scheduled.trip.dispatch` as a push entirely — it is a log line, not a
notification, and it currently fires from a once-per-minute cron.

- **Files to change** — new `apps/api/src/lib/notifications/catalog.ts`; all producer call sites
  refer to catalogue entries; `packages/flutter_shared/lib/l10n/app_strings.dart` for client-side
  strings.
- **DB** — none beyond P0.3/P0.5.
- **API contract** — none.
- **Effort** — L. **Risk** — copy regressions; mitigate with a snapshot test over the catalogue.
- **Acceptance criteria** — every topic sent in production exists in the catalogue; a lint rule
  fails the build on a `pushToUser` call with a topic not in the catalogue.
- **Tests** — snapshot test of the rendered catalogue; a test asserting every `P` entry is
  quiet-hours gated.

### P1.2 — Activation instrumentation

- **Goal** — see the install→first-trip funnel for both apps, so nothing else in this document is
  guesswork.
- **Design** — a minimal event spine written to a new `analytics_events` table via one batched
  endpoint, plus the attribution SDK from P1.5. Events, in order, per app:

  **Rider:** `app_open` · `permission_prompt_shown` · `permission_granted` ·
  `signup_started` · `otp_sent` · `otp_verified` · `signup_completed` (with `referral_code`) ·
  `home_viewed` · `destination_entered` · `fare_estimated` · `promo_applied` ·
  `trip_requested` · `bid_received` · `bid_accepted` · `trip_assigned` · `trip_started` ·
  `trip_completed` · `trip_rated` · `payment_settled` · `invite_opened` · `invite_shared`

  **Captain:** `app_open` · `signup_completed` · `doc_uploaded` (per type) · `doc_approved` ·
  `onboarding_completed` · `first_online` · `offer_received` · `offer_viewed` · `offer_accepted` ·
  `offer_expired` · `trip_completed` · `payout_requested`

  **Drop-off points to watch:** permission prompt → granted (sets the ceiling on every push metric);
  `otp_sent` → `otp_verified` (channel deliverability); `destination_entered` → `trip_requested`
  (price rejection); `trip_requested` → `trip_assigned` (supply); `doc_uploaded` → `doc_approved`
  (the captain funnel's real bottleneck); `onboarding_completed` → `first_online`.
- **Files to change** — new `apps/api/src/routes/analytics.ts`; new
  `packages/flutter_shared/lib/services/analytics.dart`; call sites across both apps.
- **DB** — migration `0024_analytics_events.sql` with
  `(id, user_id, anon_id, app, event, props JSON, session_id, app_version, created_at)`,
  indexed on `(event, created_at)` and `(user_id, created_at)`.
- **API contract** — `POST /analytics/events` accepting a batch of up to 50; fire-and-forget, 202.
- **Effort** — M. **Risk** — event volume on D1; mitigate with client-side batching, a 30-day
  retention job in `lib/cleanup.ts`, and a hard cap per session. **T22 owns the pipeline** — if
  T22 lands a real sink, this table is the interim shim and should be retired into it.
- **Acceptance criteria** — the rider funnel from `app_open` to `trip_completed` is queryable for a
  single `anon_id` across the signup boundary.
- **Tests** — an end-to-end test asserting anon→user id stitching at `signup_completed`.

### P1.3 — Captain growth programme

- **Goal** — a lever to grow and steer supply, which is the binding constraint at launch.
- **Design** — three instruments on one table.
  1. **Captain referral** — same machinery as P0.7, different reward: 150 EGP to the referrer after
     the referred captain completes **20 trips within 30 days**. Paying on trips rather than signup
     is what stops referral farming (§5.3).
  2. **Onboarding guarantee** — for the first 14 days: complete 40 trips with ≥80% acceptance and
     ≥90% completion → guaranteed 1,500 EGP total earnings, topped up if actual earnings fall short.
     Bounds the platform's exposure to the gap, not the whole amount.
  3. **Quests and streaks** — a weekly earnings-based quest the captain opts into (Uber's post-2024
     model, §5.3), plus a same-session streak paying +5% per consecutive accepted trip to a +20%
     ceiling, reset on a captain-initiated cancel.

  **Anti-gaming, from §5.7:** exclude trips whose GPS trace shows under 0.5 km of movement; exclude
  trips priced under 70% of the system estimate (collusion signal); require distinct riders for at
  least 70% of quest trips; hold all bonuses 48 h. Detection → **T18**.

  **Cost model** — at 150 EGP per referred captain reaching 20 trips, and 9 EGP platform revenue per
  trip (§6 P0.7 assumptions), the referral repays in ~17 trips and the captain has already done 20
  to qualify. The onboarding guarantee is the expensive one and must be capped by cohort: budget it
  as (target captains × expected shortfall), not (target captains × 1,500), and shut it off per city
  once captain-to-rider ratio clears target.
- **Files to change** — new `apps/api/src/routes/incentives.ts`; `routes/trips.ts` (completion hook);
  `routes/captain.ts` (progress surface); captain app earnings screens.
- **DB** — migration `0025_captain_incentives.sql`: `incentive_programs`,
  `incentive_enrollments(captain_id, program_id, progress, status, awarded_at)`,
  `incentive_events(enrollment_id, trip_id, counted, reason)` — the last one exists so a disputed
  bonus can be audited trip by trip.
- **API contract** — `GET /captain/incentives`, `POST /captain/incentives/:id/enroll`,
  `GET /captain/incentives/:id/progress`.
- **Effort** — L. **Risk** — direct financial exposure; every program row carries a hard
  `budget_total` and the enrollment endpoint refuses once spent.
- **Acceptance criteria** — a captain completing 40 qualifying trips in 14 days receives exactly the
  shortfall to 1,500 EGP. Excluded trips appear in `incentive_events` with a reason.
- **Tests** — scenario tests per program type, including the exclusion rules.

### P1.4 — Lifecycle campaign engine

- **Goal** — run the eight rider and three captain lifecycle campaigns in §6 P1.1 without
  hand-written cron code per campaign.
- **Design** — a `campaigns` table describing (audience SQL predicate, topic, channel, schedule,
  budget, holdout %), evaluated by a new daily cron branch that enqueues jobs. Every campaign runs
  with a **10% holdout** by default so lift is measurable rather than assumed — without a holdout,
  a win-back campaign takes credit for people who were coming back anyway. Cap: one promotional
  message per user per day, enforced by P0.5's gate, not by the campaign.
- **Files to change** — `apps/api/src/index.ts` (cron branch), new
  `apps/api/src/lib/campaigns.ts`, `apps/admin/src/pages/` (a campaigns page).
- **DB** — migration `0026_campaigns.sql`: `campaigns`, `campaign_sends(campaign_id, user_id,
  variant, sent_at, converted_at)`.
- **API contract** — admin CRUD under `/admin/campaigns`.
- **Effort** — L. **Risk** — a bad audience predicate messaging everyone; mitigate with a mandatory
  dry-run returning the audience count and a hard ceiling requiring explicit override above 5,000
  recipients.
- **Acceptance criteria** — a campaign with a 10% holdout reports send, open and conversion counts
  for both arms.
- **Tests** — audience-predicate tests; a dry-run test asserting nothing is enqueued.

### P1.5 — Install attribution and deferred deep links

- **Goal** — know which channel produced a rider, and land invited users on a pre-filled invite screen.
- **Design** — adopt one attribution SDK (AppsFlyer or Branch free tier, §5.7) purely for install
  attribution + deferred deep linking. Do **not** route product analytics through it; P1.2 owns
  those. Minimum viable: capture `media_source`, `campaign`, and the deferred `ref` parameter, and
  stamp them on the user row at signup. **Firebase Dynamic Links is shut down (Aug 2025) and must
  not be used.**
- **Files to change** — both `pubspec.yaml`, both `main.dart`, `routes/auth.ts` (persist source).
- **DB** — `ALTER TABLE users ADD COLUMN acquisition_source TEXT, acquisition_campaign TEXT`.
- **API contract** — signup accepts an optional `attribution` object.
- **Effort** — M. **Risk** — SDK size and privacy review → **T25**. **Acceptance criteria** — a
  fresh install from a referral link lands on the invite screen with the code pre-filled and the
  resulting user row carries the source.
- **Tests** — manual install-matrix; unit test on the signup persistence.

### P1.6 — In-app inbox

- **Goal** — a message survives being swiped away.
- **Design** — make the `in_app` channel real: persist every notification and render it from
  `notification_log` in a shared screen used by **both** apps, replacing the rider's dummy screen and
  filling the captain's gap. Wire it into both bottom navs. Unread count from `opened_at IS NULL`.
- **Files to change** — new `packages/flutter_shared/lib/screens/notifications_screen.dart`;
  delete `apps/rider/lib/screens/notifications_screen.dart`; both nav hosts; new
  `GET /notifications?cursor=` endpoint.
- **DB** — none beyond P0.3. **Effort** — M. **Risk** — low.
- **Acceptance criteria** — both apps show identical inbox behaviour; unread badge clears on read.
- **Tests** — widget tests; pagination test.

### P2.1 — Store-review prompting

Gate the OS prompt behind an in-app sentiment question after the 3rd completed trip, ≥7 days since
install, no open support ticket, and a 120-day internal cooldown; only invoke
`SKStoreReviewController` / Play In-App Review for positive responses, and route negatives to
support. Respects the 3-per-year iOS cap (§5.8). **Effort S. → T26.**

### P2.2 — Promo discovery surface

Add `GET /promos/available` returning codes the caller is actually eligible for (using P0.6's
targeting), and point `promo_screen.dart:29` at it instead of the admin endpoint. **Effort S.**

### P2.3 — Loyalty / subscription

Deferred deliberately. Do not build before ride-frequency data exists (§10, Q4). Revisit at 90 days
with the P1.2 cohort data in hand.

---

## 7. Phasing

**P0 — before any production traffic.** The S1 set plus the promo-integrity fix. Nothing here is
optional: without P0.1–P0.2 the notification system has no retry and puts FCM in the request path;
without P0.3 nothing that follows is measurable; without P0.5 no promotional message can legally or
sensibly be sent; without P0.6 a single leaked code is an unbounded liability.

| Item | Phase | Effort | Owner type |
|---|---|---|---|
| P0.1 Fix queue consumer (+ DLQ consumer) | P0 | S | backend |
| P0.2 Route notifications through the queue | P0 | M | backend |
| P0.3 Delivery observability + stale-token pruning | P0 | M | backend + Flutter |
| P0.4 Deep links + tap handler + iOS init | P0 | L | Flutter |
| P0.5 Preferences, categories, quiet hours | P0 | M | backend + Flutter |
| P0.6 Promo integrity (per-user cap, atomic cap, discount ceiling) | P0 | M | backend + admin |
| P0.7 Close the referral loop | P0 | L | backend + Flutter |
| P0.8 WhatsApp as a first-class channel | P0 | M | backend + ops |
| P1.1 Notification catalogue | P1 | L | backend + content |
| P1.2 Activation instrumentation | P1 | M | backend + Flutter |
| P1.3 Captain growth programme | P1 | L | backend + Flutter |
| P1.4 Lifecycle campaign engine | P1 | L | backend + admin |
| P1.5 Install attribution + deferred deep links | P1 | M | Flutter + ops |
| P1.6 In-app inbox | P1 | M | Flutter + backend |
| P2.1 Store-review prompting | P2 | S | Flutter |
| P2.2 Promo discovery surface | P2 | S | backend + Flutter |
| P2.3 Loyalty / subscription | P2 | L | product |

Sequencing notes that matter:

- **P0.1 strictly before P0.2.** Adding a producer to a broken consumer dead-letters everything.
- **P0.4 before P0.7's distribution step.** Referral links need deep-link handling to land anywhere.
- **P0.3 before P1.4.** A campaign engine with no open-rate signal cannot be tuned or defended.
- **P1.2 alongside P0.7.** The referral payback assumption (7 trips) is unverified; the
  instrumentation is what turns it from a guess into a decision.
- **P0.8 can run in parallel** with everything, but template approval by Meta has external lead
  time — start it first, ship it whenever it clears.

---

## 8. Metrics

Current values are almost all *unmeasurable today*, which is itself the finding.

| Metric | Current | Target | Source once instrumented |
|---|---|---|---|
| Notification delivery rate (sent → delivered) | unmeasurable — `sent` means FCM accepted | ≥ 92% | `notification_log.status` after P0.3 |
| Notification open rate, transactional | unmeasurable | ≥ 25% | `opened_at` |
| Notification open rate, promotional | n/a — none sent | ≥ 6% | `opened_at` + `campaign_id` |
| Push opt-in rate, rider / captain | unmeasurable (`platform` hardcoded) | ≥ 60% Android, ≥ 45% iOS | `permission_granted` event |
| Stale-token share of `device_tokens` | unknown, grows monotonically | < 5% | pruning job counters |
| DLQ depth | 0 (nothing produced) | 0, alerted at > 0 | DLQ consumer |
| Notification-driven session share | 0 (taps discarded) | ≥ 15% of sessions | deep-link attribution |
| Install → signup | unmeasurable | ≥ 55% | P1.2 funnel |
| Signup → first completed trip (rider) | unmeasurable | ≥ 45% within 7 days | P1.2 funnel |
| Captain signup → first online | unmeasurable | ≥ 60% within 7 days | P1.2 funnel |
| Captain doc upload → approval | unmeasurable | ≥ 80%, median < 24 h | P1.2 funnel |
| Referral share rate (invite screen opens → shares) | 0 (facade) | ≥ 25% | `invite_shared` |
| Referral conversion (shares → qualified) | 0 | ≥ 8% | `referrals.status` |
| Share of new riders from referral | 0 | ≥ 30% by day 90 | `acquisition_source` |
| Cost per activated rider (referral) | n/a | ≤ 60 EGP | ledger `promo_credit` sum ÷ qualified |
| D7 / D30 rider retention | unmeasurable | ≥ 35% / ≥ 20% | trip cohorts |
| Promo budget overrun incidents | possible today (TOCTOU) | 0 | `budget_spent` vs `budget_total` |
| WhatsApp spend per active rider per week | ~0 (OTP only) | ≤ $0.02 | `notification_log` × rate card |
| Campaign lift vs 10% holdout | n/a | > 0 and significant, per campaign | `campaign_sends` |

The single most important one to stand up first is **notification open rate**, because it is the
only number that proves the P0.3 + P0.4 pair worked, and every campaign decision downstream depends
on it.

---

## 9. Cross-cutting notes

Findings outside my axis, addressed to their owners. I have not fixed any of these.

**→ T27 (Cross-App Parity)** — the biggest pile.
- `FcmService.init` is called **four times** in the rider (`app_state.dart:154, 396, 410, 440`) and
  **once** in the captain (`captain_state.dart:229`). The rider's extra three pass no callbacks at
  all, stacking duplicate `onMessage` listeners and nulling `_pendingTapHandler`
  (`fcm_service.dart:44`). Same shared service, two different integration disciplines.
- Neither app passes `onTap`, so the shared service's tap contract is dead in both — but it is dead
  *differently*, because only the rider re-registers.
- `apps/rider/lib/screens/notifications_screen.dart` exists with hardcoded dummy data (`:22-26`) and
  is **not reachable** from the rider's `IndexedStack`/bottom nav. The captain app has **no**
  notifications screen at all. My P1.6 proposes one shared screen in `flutter_shared` and deletion
  of the rider's copy — that is a parity decision T27 should ratify.
- `registerDeviceToken` is duplicated with identical logic and the identical
  `'platform': 'android'` bug in both apps (`app_state.dart:522-530`, `captain_state.dart:1109-1115`).
  It belongs in `flutter_shared`.
- The shared `fcmBackgroundHandler` (`fcm_service.dart:108-116`) is dead code: both apps define
  their own local `_firebaseMessagingBackgroundHandler` and register it at `main.dart:21`. Three
  implementations of the same concept, one of them unused.

**→ T18 (Fraud, Abuse & Risk)** — the abuse surface I found, all confirmed against code:
- No per-user promo cap (`trips.ts:415-419`) — one account can drain a whole code.
- TOCTOU on `uses_count` (`trips.ts:418` vs `:499-503`) — concurrent redemptions exceed `max_uses`.
- A fixed-value code clamps to the fare (`trips.ts:424`) → zero-fare, zero-commission trips.
- `POST /promos/validate` returns distinguishable `PROMO_INVALID` / `PROMO_EXPIRED` /
  `PROMO_EXHAUSTED` (`promo.ts:28-35`) to any authenticated user, behind only a global
  120 req/min/IP limit (`index.ts:59-66`) — roughly 172,800 guesses/day/IP. My P0.6 proposes
  collapsing these to one opaque code and adding a per-user limit; detection is yours.
- `referrals` has no `CHECK (referrer_id <> referred_id)` (`0002:107-115`). My P0.7 adds it, but
  device/payment-instrument collusion detection is yours. The reward-release rules in P0.7
  (qualify on completed trip, 48 h hold, monthly cap) are designed to make your job cheaper.

**→ T03 (Money Integrity)** — `user_credits` (`0002:118-122`) is a second, orphan balance store
that is read by `user.ts:80-88` and written by nothing, while `wallet_transactions` already
reserves a `'promo_credit'` type (`0003:21`) that nothing inserts. My P0.7 routes all referral
rewards through the ledger and reduces `user_credits` to a derived read. **Two balances of record
is a T03 decision** — please confirm the ledger is the single source of truth before I am
implemented.

**→ T05 (Pricing)** — the promo discount is applied to `est.fare.total` and commission is then
computed on the *discounted* fare (`trips.ts:428-429`), so the platform absorbs the discount via a
reduced commission base rather than as an explicit marketing cost. That may be intended, but it
means promo spend never appears as promo spend in any report. My P0.6 adds `budget_spent` so it
becomes visible; the accounting treatment is yours.

**→ T08 (Data Model)** — `notification_log.status` has a CHECK constraint that SQLite cannot widen
with `ALTER`. P0.3 needs `delivered`/`suppressed` added, which means a create-copy-drop-rename
rebuild. Doing it now while the table is empty is free; doing it later is not. Also:
`notification_log` has no index on `topic` (`0003:227-229`) and `attempts` is always literal `1`
(`notifications.ts:40`).

**→ T22 (Observability)** — there is **no consumer for `synaptic-go-notifications-dlq`** and no
alert on anything: not DLQ depth, not `failed` rate, not `dropped` (which is what a missing secret
produces in prod, silently — `notifications.ts:83-91`). My P1.2 `analytics_events` table is an
interim shim; if you land a real sink it should be retired into it rather than maintained.

**→ T07 (Realtime)** — push is the fallback when the WebSocket is not connected, and today it is a
fallback with no delivery confirmation (§3.7). Whatever guarantees `TripRoom` offers, `trip.offer`
currently also blocks `POST /trips` on FCM round-trips per captain (`trips.ts:576`); P0.2 removes
that coupling.

**→ T14 (Localisation & Content)** — I supply ~40 Arabic strings in §6 P1.1 as *specifications*,
not as finished copy. They are Egyptian-colloquial where the moment is emotional and MSA where it
is procedural, but the register needs your ruling. Note that the existing OTP email subject and
body are hardcoded Arabic inside `notifications.ts:184-185` rather than living in any string
catalogue.

**→ T09 / T10 (App Journeys)** — the notification-preferences screen (P0.5) and the in-app inbox
(P1.6) need a home in both apps' IA. The rider's promo screen shows a permanently empty offers list
because it calls an admin-only endpoint (`promo_screen.dart:29` → `promo.ts:53`), and the invite
screen displays a code that is the same for every user (`invite_screen.dart:34`) — both are journey
defects as much as growth defects.

**→ T25 (Privacy)** — P1.5 introduces an attribution SDK; consent and data-residency review is
yours. Also, `notification_log.payload` stores the raw FCM token for every push
(`notifications.ts:351, 359, 367`), which is a device identifier retained indefinitely with no
cleanup rule in `lib/cleanup.ts`.

**→ T26 (Store Readiness)** — store-review prompting (P2.1) and the App Links / Universal Links
associated-domain configuration that P0.4 requires both land in your territory.

**→ T11 (Admin Console)** — promo codes cannot be edited or reactivated (`promo.ts` has create,
list, deactivate only), and `SettingsPage.tsx:18` declares a `min_fare?` field that does not exist
in the schema. P0.6 and P1.4 add substantial admin surface (promo targeting, campaigns) that needs
IA placement.

**Correction to a claim I could not reproduce.** An earlier pass suggested the apps never register
a background message handler. That is wrong: both `apps/rider/lib/main.dart:21` and
`apps/captain/lib/main.dart:21` call `FirebaseMessaging.onBackgroundMessage(...)` with a locally
defined handler. What is true is narrower — the *shared* `fcmBackgroundHandler` in
`fcm_service.dart:108` is unused, and none of the three handlers do anything with the payload.

---

## 10. Open questions

**Q1 — Does the referral reward come out of marketing budget or the ledger as a liability?**
P0.7 issues rewards as `wallet_transactions` rows of type `promo_credit`, which makes them a real
liability on the balance sheet, redeemable against future fares.
*Options:* (a) ledger credit — honest, redeemable, needs T03 sign-off;
(b) a single-use promo code per referral — cheaper to build, easier to expire, but fragments
reporting and reuses the promo machinery that P0.6 is busy hardening.
**Recommendation: (a).** One balance of record, and it makes the cost of growth visible.

**Q2 — Should promotional push be opt-in or opt-out at first launch?**
P0.5 defaults `push_promo = 0` (opt-in).
*Options:* (a) opt-in — lower reach, higher trust, cleaner under any future regulation;
(b) opt-out — higher reach, and the standard practice of most competitors.
**Recommendation: (a) for push, with a well-timed soft prompt after the first completed trip.**
The single OS permission prompt is the scarce resource; spending it on a promo is how you lose
trip alerts too.

**Q3 — What is the actual referral reward value, and who approves changing it?**
I modelled 30 + 30 EGP with a ~7-trip payback on assumed unit economics (60 EGP fare, 15% take).
Both inputs need confirmation from real pricing (**T05**).
*Options:* symmetric 30/30; asymmetric 50 referee / 20 referrer (buys more first trips per pound);
or tiered by city.
**Recommendation: launch symmetric 30/30 in one city, with the values in `system_config`
(`0016`) so they can be changed without a deploy, and revisit after 30 days of P1.2 cohort data.**

**Q4 — Loyalty programme now or later?**
**Recommendation: later, and explicitly.** P2.3. There is no ride-frequency data to price a
subscription against, and a mispriced one is worse than none. Revisit at 90 days.

**Q5 — Which attribution vendor, and is a paid tier acceptable at launch?**
Free tiers cover roughly 10–12k installs. Beyond that it is a real line item.
**Recommendation: start on a free tier for deferred deep linking and install source only; do not
route product analytics through it (P1.2 owns those), so switching vendors later is cheap.**

**Q6 — How aggressive should the captain onboarding guarantee be, and who owns the budget?**
The guarantee (P1.3) is the only item in this document with unbounded downside if it is not capped
per cohort and per city.
**Recommendation: run it in one city, cap the cohort explicitly, and make the shut-off condition a
captain-to-rider ratio rather than a date.**

**Q7 — Is WhatsApp marketing category acceptable at ~18× the utility rate?**
**Recommendation: yes, but only for 30-day win-back and only against a holdout.** Every other
lifecycle message in §6 P1.1 should be push-first with WhatsApp *utility* as fallback. If the
holdout shows no lift, stop paying for it.

**Q8 — Do we send anything to users who have never granted push permission?**
Today they are simply unreachable, and we cannot even count them (F-19-10).
**Recommendation: after P0.3, treat "no live token" as a segment and route its transactional
messages to WhatsApp utility. That is the cheapest reach available (§5.1) and it is the segment
most likely to churn silently.**
