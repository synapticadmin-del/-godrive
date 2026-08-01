# 09 — Rider App — End-to-End Journey

> Track: B — Product surface & experience · Reviewer: chat-20260801-1247-15a1 · Date: 2026-08-01 (UTC)
> Base commit reviewed: `f3e0419ed76487c687d11ed76153857bc8ec2199` (`main`)

## 1. Scope

This document walks the rider's journey through `apps/rider` screen by screen: first run and
permissions, the booking loop (pickup → destination → estimate → price offer → bids → captain →
ride → pay → rate), the live trip surface, and every ancillary screen the rider can reach
(wallet, places, history, promo, invite, help, notifications, SOS, settings). It covers the
rider's own state management, its error/offline behaviour, and the places where the app's model
of a trip disagrees with the server's.

It does **not** own, and only refers to:

- Auth/session mechanics → **T01**. Object-level access on `/trips/:id` → **T02**.
- Wallet/ledger correctness and commission maths → **T03**. PSP/Paymob internals → **T04**.
- Pricing formula and surge → **T05**. Dispatch/matching and `OfferScheduler` waves → **T06**.
- `TripRoom`/WebSocket server implementation → **T07**. Schema and migrations → **T08**.
- The captain app's own journey → **T10**. Admin console → **T11**.
- Design tokens and theme system → **T12**. Motion → **T13**/**T28**.
- i18n strategy → **T14**. Accessibility → **T15**. Systematic cross-app parity → **T27**.

Where the rider surface exposes a defect owned by one of those tracks, it appears in
§9 Cross-cutting notes rather than in the improvement plan here.

**A note on method.** Every finding below was read on the pinned commit. Where a parallel
analysis produced a claim I could not reproduce in the source, I dropped or corrected it; three
such corrections are called out explicitly in §4 so the reader can see the evidence bar.

## 2. What I actually read

Read in full (line-by-line):

| File | Note |
|---|---|
| `apps/rider/lib/main.dart` | 173 lines. App shell, theme/locale wiring, root gate. No route table. |
| `apps/rider/lib/services/app_state.dart` | 696 lines. The god-object: auth, HTTP, trips, wallet, avatar, theme, locale. |
| `apps/rider/lib/services/trip_ws.dart` | 117 lines. Trip socket: backoff, heartbeat, first-frame auth. |
| `apps/rider/lib/services/location_service.dart` | 303 lines. Routing/geocoding only — contains no device-GPS code. |
| `apps/rider/lib/screens/trip/trip_screen.dart` | 835 lines. The live trip surface and its status machine. |
| `apps/rider/lib/screens/ride/captain_bids_sheet.dart` | 789 lines. The bid list; the negotiation moment. |
| `apps/rider/lib/screens/home/fare_estimate_sheet.dart` | 831 lines. Price entry and trip creation. |
| `apps/api/src/routes/trips.ts` | 1371 lines. Read for the authoritative trip lifecycle and contract. |
| `apps/api/src/durable-objects/TripRoom.ts` | 290 lines. Read for the WS event and auth contract. |
| `board/PROTOCOL.md`, `board/TEMPLATE.md`, `board/tasks/T09.md` | The rules for this document. |

Read closely, targeted at specific questions (structure, the handlers named in §4, and every
line I cite):

`apps/rider/lib/screens/home/home_screen.dart` (1509) · `login_screen.dart` (1044) ·
`profile/profile_screen.dart` (913) · `places/saved_places_screen.dart` (631) ·
`home/location_search_sheet.dart` (623) · `splash_screen.dart` (531) ·
`wallet/wallet_screen.dart` (497) · `home/vehicle_selector.dart` (419) ·
`places/saved_destinations_sheet.dart` (379) · `ride/trip_detail_screen.dart` (212) ·
`home/travel_mode_bottom_bar.dart` (209) · `wallet/topup_screen.dart` (196) ·
`history/history_screen.dart` (189) · `ride/rating_sheet.dart` (170) ·
`notifications_screen.dart` (165) · `safety/sos_screen.dart` (163) · `ride/promo_screen.dart` (159) ·
`trip/trip_chat_screen.dart` (150) · `ride/schedule_screen.dart` (148) ·
`ride/payment_methods_screen.dart` (145) · `profile/invite_screen.dart` (124) ·
`profile/settings_screen.dart` (117) · `profile/help_screen.dart` (75).

Shared package: `packages/flutter_shared/lib/l10n/app_strings.dart` (5664, sampled + key-counted) ·
`theme/app_theme.dart` (1055, sampled) · `services/fcm_service.dart` (115, full) ·
`services/api_client.dart` (36, full) · `models/trip.dart` (53, full) · and all 15 widgets under
`widgets/` (usage-counted across both apps; `offline_gate.dart`, `offline_guard_banner.dart`,
`error_state.dart`, `empty_state.dart`, `skeleton_loader.dart` read in full).

Server, read for contract only: `routes/user.ts` (328) · `routes/promo.ts` (108) ·
`routes/payments.ts` (313) · `routes/safety.ts` (291) · `routes/wallet.ts` (142) ·
`lib/notifications.ts` (408) · `lib/pricing.ts` (38) · `index.ts` (372, route mounting + cron) ·
`migrations/0001_init.sql`, `0004_bidding_system.sql`, `0005_integer_currency_and_idempotency.sql`.

Cross-app comparison (read for parity, not reviewed on their own merits):
`apps/captain/lib/screens/home/trip_chat_screen.dart` · `services/trip_ws.dart` ·
`services/captain_state.dart` · `screens/safety/sos_screen.dart` · `main.dart`.

Config: `apps/rider/pubspec.yaml`, `android/app/build.gradle`,
`android/app/src/main/AndroidManifest.xml`, `ios/Runner/Info.plist`, `l10n.yaml`,
`lib/l10n/app_ar.arb`, `lib/l10n/app_en.arb`. Asset byte sizes were taken from the git tree at the
pinned commit, not from a checkout.

Skimmed, not read: the generated `l10n/generated/app_localizations*.dart` (confirmed unreachable —
see F-09-14, then not read further), and the iOS/Android platform scaffolding beyond the manifest,
plist and gradle file.

## 3. How it works today

### 3.1 Launch and routing

`main()` awaits `Firebase.initializeApp()` before `runApp` (`apps/rider/lib/main.dart:19-30`).
`RiderApp` creates `AppState(role: 'rider')..bootstrap()` and renders a `MaterialApp` whose `home:`
is resolved by `_resolveRoot` (`main.dart:101-119`): splash while `state.loading || !_introFinished`,
then `LoginScreen` when `state.token == null`, else `HomeScreen`.

There is **no route table** — no `routes:`, no `onGenerateRoute`, no `navigatorKey`. Every
navigation in the app is an imperative `Navigator.push(MaterialPageRoute(...))`. This one fact
drives several findings below: it makes deep links, notification-taps-into-a-screen and
"restore me to the live trip" structurally impossible without new plumbing.

`bootstrap()` (`services/app_state.dart:133-175`) reads the persisted theme, reads the access token
from `FlutterSecureStorage`, restores the cached user blob from `SharedPreferences`, initialises
FCM, refreshes the token if the JWT `exp` has passed, and best-effort re-fetches the profile. It
never asks the server whether the rider is currently on a trip.

The splash holds for a fixed 2400 ms (`screens/splash_screen.dart:97`) and the app leaves it only
when that timer *and* `state.loading == false` have both completed (`main.dart:102`).

### 3.2 The booking loop

| Step | Where | Taps |
|---|---|---|
| Land on map | `home_screen.dart:489` — map tab is the default (`_mapTab = 4`, line 41) | 0 |
| Pickup defaults to GPS | `_determinePosition` → `_applyPosition` (`home_screen.dart:131`, `:177`) | 0 |
| Set destination | tap the "Where to?" field → `_openSearch(false)` (`home_screen.dart:406`) | 1 |
| Choose a place | search result tap, or "pick on map" → centre-pin → confirm | 1–3 |
| Route is fetched | `_refreshRoute` → `POST /trips/estimate` (`home_screen.dart:254`) | 0 |
| Continue | `_showBookingFlow` opens `FareEstimateSheet` (`home_screen.dart:455`) | 1 |
| Pick car class | `VehicleSelector` inside the sheet | 1 |
| Set the offer price | stepper `−/+` or keyboard (`fare_estimate_sheet.dart:687-717`) | 1–n |
| Book | `_bookTrip` → `POST /trips` → push `TripScreen` (`fare_estimate_sheet.dart:170-216`) | 1 |
| Watch bids arrive | `CaptainBidsSheet` polls `GET /trips/:id/bids` every 5 s (`captain_bids_sheet.dart:75-78`) | 0 |
| Accept a captain | `POST /trips/:id/accept-bid` (`captain_bids_sheet.dart:129`) | 1 |
| Ride | `TripScreen` panels by status (`trip_screen.dart:448-458`) | 0 |
| Pay | nothing happens — every trip is created `paymentMethod: 'cash'` (`app_state.dart:504`) | 0 |
| Rate | button on the completed panel → `RatingSheet` (`trip_screen.dart:561`, `:203`) | 2 |

Best case from cold start to a booked trip is **6 taps**; realistically 7–9 with a map pin
correction. inDrive's equivalent is 4–5 because the destination field and the price field are on
the same first surface. See §5.

### 3.3 The trip state machine

The server's authoritative status set, taken from every write to `trips.status`:

| Status | Written at |
|---|---|
| `searching` | `apps/api/src/routes/trips.ts:450` (INSERT) |
| `offered` | `trips.ts:537` (captain nearby at creation), `trips.ts:1177` (a captain bid) |
| `assigned` | `trips.ts:862` (captain accepts directly), `trips.ts:1306` (rider accepts a bid) |
| `arrived` | `trips.ts:914` via `advanceStatus` |
| `in_progress` | `trips.ts:914` via `advanceStatus` |
| `completed` | `trips.ts:974` |
| `cancelled` | `trips.ts:728` |

The column has no `CHECK` constraint — `migrations/0001_init.sql:62` is
`status TEXT NOT NULL DEFAULT 'searching'`, so the set is defined only by what the API writes.

The rider models exactly the same seven names (`trip_screen.dart:448-458`), which is the good news:
**there is no status the server emits that the rider fails to name.** The divergence is in the
fallbacks — `_buildPanelContent`'s `default:` renders the *searching spinner* (`trip_screen.dart:456`)
while the status badge's `default:` renders the raw status string (`trip_screen.dart:750`). An
unexpected value therefore produces a screen that says "searching for a captain" under a badge
showing the literal unknown status.

The screen is fed by three concurrent mechanisms: the WebSocket (`trip_screen.dart:132-154`), a
10-second REST poll (`trip_screen.dart:170-190`), and — while bids are open — a second 5-second
REST poll inside `CaptainBidsSheet` (`captain_bids_sheet.dart:75-78`).

### 3.4 The WebSocket contract

`TripRoom` emits `auth.required`, `connected`, `trip.updated`, `location.captain`, `pong`, `error`
and `auth.failed` (`apps/api/src/durable-objects/TripRoom.ts:118`, `:126`, `:97`, `:169`, `:163`,
`:180`, `:202`). The rider handles exactly two of them — `trip.updated` and `location.captain`
(`trip_screen.dart:140-151`). The rest fall off the end of the `if/else if` chain. The
`onStatus` callback the service exposes (`trip_ws.dart:22`) is never passed by the trip screen, so
connection state is invisible to the UI.

### 3.5 Money on screen

On bid acceptance the server writes **both** `accepted_price` and `final_fare` to the agreed number
(`trips.ts:1306-1309`), and `GET /trips/:id` returns the whole row (`trips.ts:675`). The rider app
contains **zero references to `accepted_price`** — the live trip panels read `estimated_fare`
(`trip_screen.dart:503`, `:531`). See F-09-02; this is the most damaging finding in the document.

### 3.6 Screen by screen

| Screen | Purpose | What works | What is broken or missing | Sev |
|---|---|---|---|---|
| `splash_screen.dart` | Brand moment while the session restores | Precache + graceful fallback lockup; reduce-motion respected | Fixed 2400 ms floor holds even when bootstrap finished in 200 ms | S2 |
| `login_screen.dart` | OTP / email sign-in | Hero carousel with auto-advance; every controller disposed; theme-aware | Largest screen in the app at 1044 lines; 57% duplicated with the captain's | S3 |
| `home/home_screen.dart` | Map, pickup/destination, entry to booking | Two-phase GPS warm start; real OSRM geometry; centre-pin with race-guarded reverse geocode | Silent dead-end on denied location; whole screen rebuilds on any `AppState` notify; route failure vanishes with no retry | S2 |
| `home/location_search_sheet.dart` | Find a destination | Debounced, proximity-sorted, skeleton + empty + error states | No retry affordance on error; unmirrored trailing chevron | S3 |
| `home/vehicle_selector.dart` | Choose car class | Selection is threaded into `POST /trips` | Prices rendered ad-hoc with `$price ج.م` | S4 |
| `home/fare_estimate_sheet.dart` | Set the offered price, book | Best error handling in the app: keeps the sheet open, explains, retries; suggested-price coaching copy | Booking failure prints the server's raw English string; 409 `ACTIVE_TRIP` not handled | S1 |
| `home/travel_mode_bottom_bar.dart` | Intercity mode switch | Clean tab semantics | Unmirrored back arrow | S3 |
| `ride/captain_bids_sheet.dart` | See and accept captain offers — the product's signature screen | Rich cards: price, rating, trip count, server-routed ETA; double-accept guard; 409 handled by refetch | Bypasses the auth interceptor with raw `http` and no timeout; hardcoded RTL; decline is local-only; polls instead of using the socket | S2 |
| `trip/trip_screen.dart` | The live trip | Handles all seven server statuses; WS plus a 10 s poll backstop; captain card with plate and colour swatch | Shows `estimated_fare`, not the negotiated `accepted_price`; socket token never refreshed; unknown status silently renders "searching" | S1 |
| `trip/trip_chat_screen.dart` | Talk to the captain | Sends reliably; controller disposed | No timer, no socket — the captain's replies never arrive on their own; load error renders as an empty chat | S1 |
| `ride/rating_sheet.dart` | Rate the captain | Skippable, non-blocking, retries on failure | Comment text and tag chips are collected and then dropped by `rateTrip` | S2 |
| `ride/trip_detail_screen.dart` | Trip receipt | Proper loading/error/empty triad with retry | Total and discount only — no fare breakdown, no dispute path, no re-book | S2 |
| `history/history_screen.dart` | Past trips | Clean list with empty state | Network error renders as "no trips"; no row actions; `DateFormat` without locale | S2 |
| `ride/schedule_screen.dart` | Book for later | The UI itself is complete and correct | Orphaned — nothing in the app imports or pushes it | S2 |
| `ride/promo_screen.dart` | Promo codes | Manual code entry validates against a real endpoint | The list calls an admin-only route, gets 403, swallows it, and shows empty forever | S2 |
| `ride/payment_methods_screen.dart` | Choose how to pay | Renders wallet balance | Cannot affect anything: `createTrip` hardcodes cash. Card is a "soon" snackbar. Wallet load error shows a false 0 balance | S2 |
| `wallet/wallet_screen.dart` | Balance and transactions | The best-behaved screen: skeleton, error with retry, empty state, pull-to-refresh | Money formatted differently here than on the trip screen | S3 |
| `wallet/topup_screen.dart` | Add funds via Paymob | Real intention + webhook flow; error surfaced | Hardcoded `ج.م` suffix; WebView costs ~3–4 MB for this one screen | S3 |
| `places/saved_places_screen.dart` | Manage saved places | Full CRUD against a real endpoint; skeleton and empty states | Fetch error renders as "no saved places"; location denial silently continues with a null position | S2 |
| `places/saved_destinations_sheet.dart` | Quick re-pick of a destination | Correct loading/error/empty with retry — the pattern the other screens should copy | — | — |
| `profile/profile_screen.dart` | Identity and avatar | Avatar upload with correct MIME handling; server-authoritative avatar key | No `dispose` in the file: three controllers leak per edit-sheet open; unawaited fetches swallow errors | S2 |
| `profile/settings_screen.dart` | Theme, language, sign out | Theme choice persists correctly | Language choice does not persist; logout is one unguarded tap | S2 |
| `profile/invite_screen.dart` | Referrals | Share sheet wired | Reads fields the API never returns; every rider shares the literal code `GODRIVE` | S2 |
| `profile/help_screen.dart` | Support | — | Static FAQ; the contact button is a snackbar placeholder; no support endpoint exists | S4 |
| `safety/sos_screen.dart` | Emergency | Confirmation dialog before firing; posts to a real endpoint | Hardcoded light palette; throws a raw string on permanently-denied location; unlabelled `SOS` glyph | S2 |
| `notifications_screen.dart` | Notification centre | Empty state exists | Entirely static mock data — zero network calls; taps do nothing | S2 |

## 4. Findings

Severity: **S1** blocker · **S2** major · **S3** moderate · **S4** polish.
Confidence: **confirmed** = I read the code and reproduced the claim on the pinned commit.

| ID | Sev | Finding | Evidence (`path:line`) | Impact | Confidence |
|---|---|---|---|---|---|
| F-09-01 | S1 | No active-trip recovery. Force-quit mid-trip and the rider can never get back to the live trip; the 409 that carries the `tripId` is discarded | `app_state.dart:133-175`, `main.dart:116-118`, `fare_estimate_sheet.dart:214`, `trips.ts:362-375`, `app_state.dart:318` | Rider is orphaned from a live trip and is also blocked from booking a new one. Support-ticket generator | confirmed |
| F-09-02 | S1 | The live trip shows the **system estimate**, not the price the rider negotiated. `accepted_price` is never read anywhere in the app | `trip_screen.dart:503`, `:531`, `:737`, vs `trips.ts:1306-1309` | In a price-negotiation product, the fare on screen for the whole ride is a number the rider never agreed to | confirmed |
| F-09-03 | S1 | Rider chat only fetches on open and after the rider sends. A captain's reply is invisible until the rider happens to send another message | `trip_chat_screen.dart:22`, `:64` (no `Timer`, no WS) vs captain's `trip_chat_screen.dart:65-80` | In-trip communication is one-directional in practice. "Where are you?" goes unanswered | confirmed |
| F-09-04 | S2 | The WS token is captured once at construction and never refreshed. After a mid-trip token rotation the socket retries forever with the stale token; `auth.failed` is not handled | `trip_screen.dart:137`, `trip_ws.dart:57`, `:70-71`, `:86-98` vs `TripRoom.ts:199-209` | Silent permanent downgrade to 10 s polling: no live captain marker, no instant status, battery and data burned on a loop that cannot succeed | confirmed |
| F-09-05 | S2 | Permanently-denied location dead-ends. Three call sites bare-`return`; `openAppSettings` appears nowhere in the app | `home_screen.dart:141`, `saved_places_screen.dart:399-401`, `sos_screen.dart:62-63` | Rider who tapped "don't ask again" gets a map stuck on default Cairo with no explanation and no way back | confirmed |
| F-09-06 | S2 | `CaptainBidsSheet` bypasses the auth interceptor with raw `http` calls and sets no timeout | `captain_bids_sheet.dart:96-99`, `:129-133` vs `app_state.dart:294-306` | A 401 during the negotiation shows "(401)" and re-polls every 5 s forever — no refresh, no logout, no recovery | confirmed |
| F-09-07 | S2 | Payment method is hardcoded `'cash'` on every trip. `PaymentMethodsScreen` cannot affect what is sent | `app_state.dart:504`, `payment_methods_screen.dart:84-89` | A whole payment surface is decorative; wallet balance can never be spent on a ride | confirmed |
| F-09-08 | S2 | The notifications screen is static mock data — zero network calls in the file | `notifications_screen.dart:20-26` (no `initState` fetch, no `apiGet`) | The notification centre is a prop. Riders cannot see real trip/wallet/promo events | confirmed |
| F-09-09 | S2 | Notification taps do nothing. `FcmService.init` is called four times and `onTap` is never supplied | `app_state.dart:154`, `:396`, `:410`, `:440` vs `fcm_service.dart:43-49` | No deep link into a live trip. Push is a buzz with no destination — the single biggest re-engagement loss | confirmed |
| F-09-10 | S2 | Six screens convert a network error into an *empty* state, so an outage reads as "you have nothing" | `history_screen.dart:35-37`, `promo_screen.dart:31`, `invite_screen.dart:29`, `saved_places_screen.dart:63-65`, `payment_methods_screen.dart:32-34`, `trip_chat_screen.dart:45-48` | Riders believe their data is gone. The wrong mental model is the expensive part | confirmed |
| F-09-11 | S2 | The rider app has no offline awareness at all. `OfflineGate` and `OfflineGuardBanner` are used by zero rider screens | `packages/flutter_shared/lib/widgets/offline_gate.dart`, `offline_guard_banner.dart` — 0 imports under `apps/rider` | On the metro, in a lift, in a tunnel, every screen fails silently and separately | confirmed |
| F-09-12 | S2 | `GET /promos` is admin-only; the rider's promo list is always empty and the 403 is swallowed | `promo.ts:53` (`requireRole("admin")`) vs `promo_screen.dart:29-31` | The promo screen can never list a promo. Only blind code entry works | confirmed |
| F-09-13 | S2 | `InviteScreen` reads `referral_code` and `invited_count`, which `GET /user/profile` does not return; it shows the literal `'GODRIVE'` to everyone | `invite_screen.dart:34`, `:93` vs `user.ts:72-91` | Every rider is told their referral code is "GODRIVE". Referral attribution is impossible | confirmed |
| F-09-14 | S2 | The ARB/gen-l10n pipeline is unreachable: `AppLocalizations.delegate` is not registered, and `AppLocalizations` is referenced 0 times | `main.dart:59-63`, 0 hits for `AppLocalizations` under `apps/rider/lib` outside `l10n/generated` | 56 translated keys are dead weight; the real strings are 337 Arabic literals inline in the widgets | confirmed |
| F-09-15 | S2 | The language choice is not persisted; theme is. Every cold start reverts to Arabic | `app_state.dart:532-544` (no `prefs.setString`) vs `:580-587` (theme persists) | An English-preferring rider re-picks their language every single launch | confirmed |
| F-09-16 | S2 | `ScheduleScreen` is orphaned — it is never imported or pushed from anywhere, though the API field and the dispatch cron both exist | `schedule_screen.dart:5` is the only reference in `apps/rider`; `trips.ts:487`, `index.ts` cron | A shipped, built capability is unreachable. Scheduled rides are Careem/Uber table stakes | confirmed |
| F-09-17 | S2 | No receipt. `TripDetailScreen` shows a total and a discount; base/distance/time/surge are never displayed and the components are not persisted on the row | `trip_detail_screen.dart:128-146`, `trips.ts:675` | A rider who believes they were overcharged has nothing to look at, and support has nothing to point to | confirmed |
| F-09-18 | S2 | Rating drops the rider's words. The comment field and the tag chips are rendered but `rateTrip` posts only `{score}` | `rating_sheet.dart:26`, `:109-115`, `:34` vs `app_state.dart:516-518` | The only qualitative signal about captains is collected on screen and thrown away in the client | confirmed |
| F-09-19 | S2 | `AppState` is a 16-notify god-object with 5 whole-object listeners and no selectors; a wallet fetch rebuilds the 1509-line map screen | 16 `notifyListeners()` in `app_state.dart`; `main.dart:52`, `home_screen.dart:490`, `profile_screen.dart:313`, `settings_screen.dart:17`, `wallet_screen.dart:91`; 0 `Selector` in the app | Avoidable jank on exactly the screen that must stay at 60 fps | confirmed |
| F-09-20 | S2 | Three `TextEditingController`s are leaked on every profile-edit open; `profile_screen.dart` has no `dispose` at all | `profile_screen.dart:191-193`; 0 hits for `dispose` in the file | Repeatable, unbounded leak on a screen riders revisit | confirmed |
| F-09-21 | S2 | 5.47 MB of rider assets, including a 876 KB `splash.mp4` that nothing plays and a 627 KB iOS app icon shipped as a Flutter asset | git tree at `f3e0419`: `assets/videos/splash.mp4` 875,855 B, `splash_brand.png` 999,730 B, `godrive_logo.png` 668,684 B, `icons/ios/godrive_1024.png` 627,808 B; no `video_player` in `pubspec.yaml` | Download size on the exact devices and networks this product targets | confirmed |
| F-09-22 | S2 | Cold start is a 2400 ms fixed hold plus up to three sequential network calls, each with a 15 s timeout | `splash_screen.dart:97`, `main.dart:102`, `app_state.dart:154`, `:159`, `:170` | On Cairo 3G the brand screen can hold for well over ten seconds before the map appears | confirmed |
| F-09-23 | S2 | `google_fonts` with no bundled font files — the Arabic typeface is fetched from the network at runtime | `pubspec.yaml` dependency; `GoogleFonts.ibmPlexSansArabic` used directly, e.g. `home_screen.dart:1252` | First launch and every offline launch render Arabic in a fallback face, then reflow | confirmed |
| F-09-24 | S2 | No ABI splits in the release build | `apps/rider/android/app/build.gradle` has no `splits` block (`minifyEnabled`/`shrinkResources` are on) | Roughly a third of the APK is native code for architectures Egypt does not use | confirmed |
| F-09-25 | S3 | A failed route lookup is silent: the summary row simply disappears, with no error and no retry | `location_service.dart:215-217` returns `null`; `home_screen.dart:270-273`; `:1159` gate | Rider sees the distance/ETA vanish and is given no reason and no retry | confirmed |
| F-09-26 | S3 | `CaptainBidsSheet` hardcodes `TextDirection.rtl` around the whole sheet | `captain_bids_sheet.dart:222-223` | In English the negotiation surface — the product's signature screen — mirrors incorrectly | confirmed |
| F-09-27 | S3 | Chat bubbles use physical `Alignment.centerLeft/Right` instead of directional alignment | `trip_chat_screen.dart:97` vs captain's `AlignmentDirectional` | Correct in Arabic, inverted in English: the rider's own messages sit on the wrong side | confirmed |
| F-09-28 | S3 | Declining a bid is client-only; the bid stays `pending` server-side and returns on re-entry | `captain_bids_sheet.dart:172` (in-memory `Set`); no decline endpoint in `trips.ts` | Dismissed captains reappear; the captain is never told | confirmed |
| F-09-29 | S3 | Bids are polled every 5 s even though the server already pushes `trip.updated` on every bid | `captain_bids_sheet.dart:75-78` vs `trips.ts:1196` | Up to 5 s of dead air at the highest-intent moment in the product | confirmed |
| F-09-30 | S3 | No trip timeout. A trip can sit in `searching` indefinitely; the only exit is the rider cancelling | no timeout in `trips.ts`; `cleanup.ts` does not touch trips; `trip_screen.dart:460-470` | The spinner is the product's answer to "nobody wants your price" | confirmed |
| F-09-31 | S3 | Nearby cars are drawn by firing a zero-length `POST /trips/estimate` every 45 s | `home_screen.dart:197-205`, `:212-229` | A pricing endpoint used as an ambient presence probe: wrong cost centre, wrong rate limit, wrong semantics | confirmed |
| F-09-32 | S3 | `registerDeviceToken` hardcodes `'platform': 'android'` | `app_state.dart:526` | Every iOS install is recorded as Android; platform-targeted push and analytics are wrong from day one | confirmed |
| F-09-33 | S3 | Logging out takes one tap with no confirmation, from a screen reachable mid-trip | `settings_screen.dart:101-104` | An accidental tap ends the session while a captain is en route | confirmed |
| F-09-34 | S3 | `shareTripUrl` builds `/trips/:id/track`, an endpoint that does not exist — and nothing calls it | `app_state.dart:695`; no `/track` route in `trips.ts`; 0 call sites | "Share my trip" — a core safety expectation — is absent, with a broken stub standing in for it | confirmed |
| F-09-35 | S3 | Five distinct "it failed, try again" patterns coexist | `ErrorState` (`trip_detail_screen.dart:56`, `wallet_screen.dart:143`, `trip_screen.dart:229`, `saved_destinations_sheet.dart:251`); bespoke `_ErrorBody` (`fare_estimate_sheet.dart:243`); snackbar-only; silent; none | Recovery is a lottery that depends on which screen the rider is standing on | confirmed |
| F-09-36 | S3 | Navigation chevrons and back arrows do not mirror in RTL | `travel_mode_bottom_bar.dart:115`, `trip_screen.dart:282`, `schedule_screen.dart:98`, `:118`, `location_search_sheet.dart:544` | Arrows point the wrong way throughout an Arabic-first app | confirmed |
| F-09-37 | S3 | Money is formatted three different ways and never through `intl` | `.toStringAsFixed(0)` (`trip_screen.dart:559`), `.toStringAsFixed(2)` (`profile_screen.dart:703`), `.round()` (`captain_bids_sheet.dart:459`); no `NumberFormat` anywhere | The same balance renders differently on two screens; no thousands separators | confirmed |
| F-09-38 | S3 | `DateFormat` is constructed without a locale | `history_screen.dart:64`, `wallet_screen.dart:50` | Dates ignore the rider's language | confirmed |
| F-09-39 | S3 | A 401 that survives refresh clears the session but leaves pushed routes on screen | `app_state.dart:302-303`; `main.dart:90` swaps only the `home:` subtree | The rider keeps interacting with a screen that is no longer backed by a session | confirmed |
| F-09-40 | S3 | `_connectWs` force-unwraps the token (`state.token!`) | `trip_screen.dart:137` | A null token at that instant crashes into a raw Dart null-check error shown in a snackbar | confirmed |
| F-09-41 | S4 | Post-trip features absent: tipping, re-book, favourite driver, lost item, dispute, report captain | 0 hits under `apps/rider` for each; only `POST /trips/:id/rate` exists post-trip in `trips.ts` | The entire post-ride surface is one rating star row | confirmed |
| F-09-42 | S4 | Help centre is static and its contact button is a snackbar placeholder | `help_screen.dart:47-50`; no `/support` route on the API | There is no way to reach a human from inside the app | confirmed |
| F-09-43 | S4 | `assets/videos/` is declared in `pubspec.yaml` for an asset nothing reads | `apps/rider/pubspec.yaml:63` | Ships the dead MP4 of F-09-21 | confirmed |
| F-09-44 | S4 | The notification permission prompt fires during `bootstrap`, before the rider has seen the product | `fcm_service.dart:52` via `app_state.dart:154` | Predictably high denial rate on the permission that drives retention | confirmed |

**Three corrections to claims I could not reproduce**, recorded so the evidence bar is visible:
(1) a reported infinite spinner on route-fetch failure is not real — `fetchRoute` catches internally
and returns `null` (`location_service.dart:215-217`), so `_loadingRoute` always clears; the real
defect is the silent disappearance in F-09-25. (2) A reported crash from `route!`
(`home_screen.dart:1263`) is guarded by `if (loadingRoute || route != null)` at `home_screen.dart:1159`.
(3) A report that the splash video had been deleted was wrong: `assets/videos/splash.mp4` is present
in the tree at 875,855 bytes and is shipped — it is simply never played (F-09-21).

### Expanding the S1s and the S2s that matter most

**F-09-01 — the orphaned trip.** This is the worst defect in the rider app because the server
already solved it and the client throws the solution away. `POST /trips` refuses a second trip and
returns `409 {error, code: "ACTIVE_TRIP", tripId}` (`trips.ts:362-375`). `AppState._post` extracts
only `data['error']` and raises it as a string (`app_state.dart:318`); `_bookTrip` prints that string
in a snackbar (`fare_estimate_sheet.dart:217-221`). So the rider who force-quits during a ride —
or whose app is killed by a low-memory Android — reopens to `HomeScreen` with no trace of the trip
(the only construction site for `TripScreen` is `fare_estimate_sheet.dart:214`), and when they try to
rebook they are told, in **English**, in an Arabic-first app: "You already have an active trip."
They cannot see it, cannot cancel it, cannot rejoin it. They wait for the captain to complete or
cancel it for them. Note the compounding factor: with no notification deep link (F-09-09) there is
no other way back in either.

**F-09-02 — the wrong number on screen.** Synaptic Go's entire differentiation is that the rider
names a price and the captain agrees to it. When a bid is accepted the server records
`accepted_price = final_fare = the agreed number` (`trips.ts:1306-1309`) and returns the whole row.
The rider's assigned and in-progress panels read `estimated_fare` (`trip_screen.dart:503`, `:531`)
and render it under the label `'الأجرة'` — *the fare* (`trip_screen.dart:737`). The word
`accepted_price` does not appear anywhere in `apps/rider`. So a rider who offers 45, receives a
counter of 60, and accepts it, watches "الأجرة ٥٢ ج.م" — the system estimate — for the entire ride,
and then sees 60 on the completion panel, which reads `final_fare` first (`trip_screen.dart:551`).
Every negotiated trip where the agreed price differs from the estimate ends in a surprise. For a
negotiation product this is a credibility failure, and it will be read as a bait-and-switch.

**F-09-03 — half a chat.** `TripChatScreen` calls `_fetchMessages()` in `initState`
(`trip_chat_screen.dart:22`) and again after a successful send (`:64`). There is no timer, no
WebSocket subscription, no `didChangeAppLifecycleState`. The captain's app has both a live WS path
and a 6-second backstop poll (`apps/captain/lib/screens/home/trip_chat_screen.dart:65-80`). The
asymmetry is total: the captain sees the rider immediately, the rider sees the captain only if they
speak again first. The messages are stored correctly — this is purely a client refresh failure — which
makes it cheap to fix and embarrassing to ship.

**F-09-04 — the socket that can never come back.** `TripScreen` builds the service once with
`token: state.token!` (`trip_screen.dart:137`). If `TripRoom` rejects the token it sends
`auth.failed` and closes with 4401 (`TripRoom.ts:199-209`). The client sees only `onDone` and
schedules a reconnect (`trip_ws.dart:71`), which reopens with the *same captured token* and is
rejected again, forever, on a 1-2-4-8-16 s cycle. Meanwhile the REST poller refreshes the token
successfully through the interceptor, so the rider keeps getting status updates every 10 seconds
and never learns that the live layer is gone: the captain's car stops moving on the map, and
nothing says why.

**F-09-05 — the silent permission dead-end.** `_determinePosition` returns bare on service-disabled
(`home_screen.dart:134`), on `denied` (`:139`) and on `deniedForever` (`:141`). Nothing is shown.
The map keeps its default Cairo centre and the rider is left to wonder why the pickup pin is in the
wrong district. `openAppSettings` does not appear anywhere in `apps/rider`. The SOS screen is worse:
it throws a string (`sos_screen.dart:62-63`) at the one moment the rider is in trouble.

**F-09-07 — a payment surface with no wiring.** `createTrip` hardcodes
`'paymentMethod': 'cash'` (`app_state.dart:504`). `PaymentMethodsScreen` lets the rider add a card
(a snackbar saying "soon", `payment_methods_screen.dart:84-89`) and shows a wallet balance, but no
selection it offers can reach `POST /trips`. The wallet can be topped up through Paymob
(`payments.ts:23`) and then cannot be spent on a ride.

**F-09-10 and F-09-11 — failure looks like emptiness.** Six screens catch, clear the loading flag,
and fall through to their empty state. The rider with saved places sees "no saved places"; the rider
with history sees "no trips"; the rider with promos sees "no promos". Because there is also no
connectivity awareness anywhere in the app (F-09-11 — both offline widgets exist in the shared
package and are imported by zero rider screens), the rider is never told the one fact that explains
all of it at once: the phone is offline.

## 5. Benchmark gap

**inDrive (rider) — the model this product is copying.** *Confident:* inDrive's home screen collects
destination and the rider's price offer on the same surface, then shows a list of driver responses
with rating, ETA and price, and the rider picks one. Synaptic Go has the same conceptual flow but
splits it across a map screen, a modal sheet and then an inline panel, costing 6–9 taps against
inDrive's 4–5. Two mechanics inDrive has that Synaptic Go lacks entirely: an **offer expiry**, so a
price that nobody takes visibly dies and invites a new one (Synaptic Go spins forever — F-09-30),
and a **real decline** that removes a driver from the pool (Synaptic Go's decline is a local `Set` —
F-09-28). The bid list itself is the strongest part of this app: `captain_bids_sheet.dart` shows
price, rating, trip count and a server-routed ETA — that is genuinely at parity.

**Uber (rider).** *Confident:* upfront price, one-tap rebooking of a recent trip, predictively
surfaced saved places, an itemised receipt after every trip, and lock-screen live activity for trip
progress. Synaptic Go has saved places (`saved_places_screen.dart`, real CRUD) but no rebooking
(F-09-41), no itemised receipt (F-09-17), and no live activity or even a working notification tap
(F-09-09). The gap that matters most commercially is the receipt: Uber's receipt is the artefact
that ends fare arguments before they start.

**Careem (region).** *Confident:* Arabic-first typography with proper mirroring, and payment
flexibility — cash, card, and Careem Pay — chosen per trip. Synaptic Go is Arabic-first in tone but
mechanically monolingual: 337 Arabic literals sit inline in the widgets, the translation pipeline is
unreachable (F-09-14), and the language toggle forgets itself on restart (F-09-15). On payment it is
strictly cash (F-09-07). *Assumed:* Careem's scheduled-ride and in-app support surfaces are standard
in this market; Synaptic Go has scheduling built but unreachable (F-09-16) and no support path at
all (F-09-42).

**Where Synaptic Go is genuinely ahead:** the real OSRM route geometry drawn on the map
(`location_service.dart:80-108`), the two-phase location acquisition that paints a warm map before
the GPS lock (`home_screen.dart:143-163`), the server-routed per-captain ETA in the bid list, and a
trip screen that keeps a REST poll behind the socket instead of trusting the socket alone. These are
better than a first version usually gets.

## 6. Improvement plan

### P0.1 — Restore the rider to their live trip
- **Goal** — a rider who reopens the app during a trip lands back on that trip.
- **Design** — add `GET /trips/active` returning the rider's single non-terminal trip or `204`. Call
  it at the end of `bootstrap()` and store `activeTripId` on `AppState`. `_resolveRoot` routes to
  `TripScreen` when it is set. Separately, parse the `409 ACTIVE_TRIP` body in `_post` so
  `createTrip` can surface a typed `ActiveTripException(tripId)` and `_bookTrip` can navigate to the
  trip instead of printing an English string.
- **Files to change** — `apps/api/src/routes/trips.ts` (new route, reusing the query at `:363`),
  `apps/rider/lib/services/app_state.dart` (`bootstrap`, `_post` error typing, `createTrip`),
  `apps/rider/lib/main.dart` (`_resolveRoot`), `apps/rider/lib/screens/home/fare_estimate_sheet.dart`.
- **DB** — none.
- **API contract** — `GET /trips/active` → `200 {trip, geometry}` | `204`. `POST /trips` 409 body is
  unchanged; the client starts honouring `code` and `tripId`.
- **Effort** — S.
- **Risk** — an extra call on the launch path; mitigate by firing it in parallel with `fetchProfile`
  and never letting it block `loading = false`. Rollback is a client-side flag.
- **Acceptance criteria** — force-quit during `assigned`, reopen: `TripScreen` for the same trip
  within one launch. Attempting to book while a trip is live navigates to it rather than erroring.
- **Tests** — widget test for `_resolveRoot` with `activeTripId` set; API test for the new route
  across all seven statuses; integration test for the 409 path.

### P0.2 — Show the price the rider agreed to
- **Goal** — the fare on screen during the trip is the fare that will be charged.
- **Design** — one resolver, `num? get agreedFare => accepted_price ?? final_fare ?? estimated_fare`,
  used by every panel. Where the value is still an estimate, label it "تقديري" rather than "الأجرة".
- **Files to change** — `apps/rider/lib/screens/trip/trip_screen.dart:503`, `:531`, `:551`, `:737`;
  `apps/rider/lib/screens/ride/trip_detail_screen.dart:81`, `:128`;
  `apps/rider/lib/screens/history/history_screen.dart:128`.
- **DB** — none. **API contract** — none; the fields are already returned.
- **Effort** — S. **Risk** — none beyond display; rollback is a one-line revert.
- **Acceptance criteria** — negotiate a price different from the estimate; the assigned,
  in-progress and completed panels all show the negotiated number; history and detail agree.
- **Tests** — golden/widget tests over a trip fixture where `accepted_price != estimated_fare`.

### P0.3 — Make the chat two-way
- **Goal** — the rider sees the captain's message when it is sent.
- **Design** — subscribe `TripChatScreen` to the existing trip socket for a `chat.message` event and
  add a 6-second backstop poll, mirroring the captain implementation. Add `WidgetsBindingObserver`
  to refetch on resume, an empty state, and auto-scroll.
- **Files to change** — `apps/rider/lib/screens/trip/trip_chat_screen.dart`;
  `apps/rider/lib/services/trip_ws.dart` (expose a broadcast stream, as the captain's already does).
- **DB** — none. **API contract** — none if `chat.message` is already broadcast by `TripRoom`;
  otherwise add the broadcast on the existing `POST /safety/chat/:id` handler (verify with **T07**).
- **Effort** — S. **Risk** — duplicate renders if WS and poll race; dedupe on message id.
- **Acceptance criteria** — captain sends; the rider's open chat shows it within 6 s without the
  rider typing. Backgrounding and resuming reconciles history.
- **Tests** — integration test with a mock socket; widget test for the dedupe.

### P0.4 — Keep the live socket alive across token rotation
- **Goal** — the live layer survives a refresh, and the rider is told when it does not.
- **Design** — pass a `tokenProvider` callback instead of a captured string so each `_open()` reads
  the current token. Handle `auth.failed` by reconnecting once with a freshly refreshed token, then
  surfacing a "live updates unavailable" chip. Wire the existing `onStatus` callback into the trip
  screen and render connecting/reconnecting state.
- **Files to change** — `apps/rider/lib/services/trip_ws.dart:10-16`, `:49-84`;
  `apps/rider/lib/screens/trip/trip_screen.dart:132-154`; null-guard `:137`.
- **DB / API contract** — none.
- **Effort** — S. **Risk** — a reconnect storm if refresh also fails; cap consecutive auth failures
  at 2, then stop and show the chip.
- **Acceptance criteria** — force a token rotation mid-trip; the socket re-authenticates and the
  captain marker keeps moving. Force an unrecoverable auth failure; the rider sees the degraded chip
  rather than nothing.
- **Tests** — unit tests over the reconnect state machine.

### P0.5 — Give location denial a way out
- **Goal** — no silent dead-end on the permission the product depends on.
- **Design** — return a typed `LocationOutcome` from `_determinePosition` and render a persistent
  banner for `serviceDisabled` / `denied` / `deniedForever`, each with the right action: enable
  location services, ask again, or `Geolocator.openAppSettings()`. Same treatment on saved places
  and, with emphasis, on SOS.
- **Files to change** — `apps/rider/lib/screens/home/home_screen.dart:131-170` and the overlay;
  `apps/rider/lib/screens/places/saved_places_screen.dart:393-401`;
  `apps/rider/lib/screens/safety/sos_screen.dart:59-63`.
- **DB / API contract** — none. **Effort** — S. **Risk** — none.
- **Acceptance criteria** — deny permanently, reopen: a banner explains the state and its button
  opens the OS settings page.
- **Tests** — widget tests over the three denial outcomes.

### P0.6 — Route the bid panel through the authenticated client
- **Goal** — the negotiation screen cannot strand the rider on an expired session.
- **Design** — replace the raw `http` calls with `AppState.apiGet` / `apiPost` so the 401 interceptor,
  the timeout and the retry apply. Stop passing `token`/`baseUrl` into the widget.
- **Files to change** — `apps/rider/lib/screens/ride/captain_bids_sheet.dart:87-170`;
  call site `apps/rider/lib/screens/trip/trip_screen.dart:83-97`.
- **DB / API contract** — none. **Effort** — S. **Risk** — none; strictly fewer code paths.
- **Acceptance criteria** — expire the token while bids are open; the session refreshes and the list
  keeps updating; an unrecoverable failure logs out cleanly instead of looping.
- **Tests** — integration test with a 401-then-200 mock.

### P1.1 — Make payment method real
- **Goal** — the rider's payment choice reaches the trip.
- **Design** — thread `paymentMethod` from `PaymentMethodsScreen` through `FareEstimateSheet` into
  `createTrip`; support `cash` and `wallet` in v1 and hide card until tokenisation exists. Validate
  the wallet balance against the offered price before allowing `wallet`.
- **Files to change** — `app_state.dart:486-508`, `fare_estimate_sheet.dart:170-216`,
  `payment_methods_screen.dart`; server-side validation in `trips.ts` `POST /` (coordinate with **T04**).
- **DB** — none (`trips.payment_method` already exists). **API contract** — `POST /trips` starts
  honouring `paymentMethod: 'cash' | 'wallet'`.
- **Effort** — M. **Risk** — double-charging if wallet debit is not idempotent; **T03** owns the
  ledger guarantee and this must not ship before it.
- **Acceptance criteria** — a wallet-paid trip debits exactly once and shows the method on the receipt.
- **Tests** — API tests for insufficient balance and for repeated submits with the same idempotency key.

### P1.2 — A real notification centre and working deep links
- **Goal** — push becomes a way back into the product.
- **Design** — add `GET /user/notifications` (list, read-state) backed by the existing notifications
  pipeline; replace the mock list. Introduce a `navigatorKey` and a small route table, pass an
  `onTap` to `FcmService.init` at every call site, and map payload `{type, tripId}` to a destination —
  live trip, receipt, or wallet.
- **Files to change** — `apps/rider/lib/main.dart` (navigator key + routes),
  `services/app_state.dart:154,396,410,440`, `screens/notifications_screen.dart`,
  `packages/flutter_shared/lib/services/fcm_service.dart`; new route in `apps/api/src/routes/user.ts`.
- **DB** — a `notifications` table if none exists (confirm with **T19**); otherwise none.
- **API contract** — `GET /user/notifications?cursor=` → `{items:[{id,type,title,body,tripId,readAt,createdAt}],nextCursor}`;
  `POST /user/notifications/:id/read`.
- **Effort** — M. **Risk** — deep-linking into a screen that expects a live trip; guard with P0.1's
  active-trip lookup. **Acceptance criteria** — tapping a trip push opens that trip from cold start.
- **Tests** — integration tests for cold-start and warm-start taps.

### P1.3 — One failure language, and knowing you are offline
- **Goal** — every screen fails the same way, and an outage says so once.
- **Design** — a `ScreenState<T>` wrapper (`loading | empty | error(retry) | data`) applied to all
  list/detail screens, standardising on the existing `ErrorState`/`EmptyState`/`SkeletonList`. Add a
  connectivity listener at the shell level and finally mount `OfflineGuardBanner` in the rider app.
- **Files to change** — the six screens in F-09-10, plus `home_screen.dart` shell for the banner.
- **DB / API contract** — none. **Effort** — M. **Risk** — none. 
- **Acceptance criteria** — airplane mode on any list screen shows the offline banner and a retry;
  restoring connectivity refreshes without a manual tap.
- **Tests** — widget tests per screen across the four states.

### P1.4 — Receipts, and the disputes they prevent
- **Goal** — every completed trip has an itemised, shareable receipt.
- **Design** — persist the fare components at completion, return them on `GET /trips/:id`, and render
  base, distance, time, surge, discount, commission and total in `TripDetailScreen`. Add share-as-image.
- **Files to change** — `apps/api/src/routes/trips.ts` complete handler (`:963-985`),
  `apps/rider/lib/screens/ride/trip_detail_screen.dart:128-146`.
- **DB** — migration `0020_trip_fare_breakdown.sql`:
  `ALTER TABLE trips ADD COLUMN fare_breakdown TEXT;` (JSON: base, perKm, perMin, bookingFee,
  surgeMultiplier, discount, commission, total) — coordinate numbering with **T08**.
- **API contract** — `GET /trips/:id` gains `trip.fare_breakdown`.
- **Effort** — M. **Risk** — historical trips have no breakdown; render "unavailable" rather than zeros.
- **Acceptance criteria** — a completed trip shows components that sum to the charged total.
- **Tests** — API test asserting the sum; widget test for the legacy-null case.

### P1.5 — Reach the scheduling that already exists
- **Goal** — riders can book ahead.
- **Design** — add a "Later" entry point beside the booking CTA, push the orphaned `ScheduleScreen`,
  and pass `scheduledFor` into `createTrip`. Add a "Scheduled" list to history with cancel.
- **Files to change** — `fare_estimate_sheet.dart`, `schedule_screen.dart` (wire `onConfirm`),
  `app_state.dart` (`createTrip` gains `scheduledFor`), `history_screen.dart`.
- **DB** — none (`scheduled_trips` exists — `trips.ts:487`).
- **API contract** — `POST /trips` honours `scheduledFor` (already parsed); add
  `DELETE /trips/scheduled/:id`. **Effort** — M.
- **Risk** — the cron only notifies admins today and does not fan out to captains (see §9 → **T06**);
  do not ship the entry point until dispatch actually runs, or riders will book rides nobody receives.
- **Acceptance criteria** — a trip scheduled for +2 h dispatches to captains at the right minute.
- **Tests** — cron unit test over due/not-due windows.

### P1.6 — Fix the money and language formatting
- **Goal** — one money format, one date format, a language that persists.
- **Design** — a `Money.format(context, amount)` helper over `NumberFormat.currency` with the
  rider's locale, replacing every ad-hoc `toStringAsFixed`. Persist the locale in
  `SharedPreferences` next to the theme and restore it in `bootstrap()`. Register
  `AppLocalizations.delegate` (or delete the ARB pipeline outright — see §10 Q2).
- **Files to change** — `app_state.dart:133-175`, `:532-544`, `main.dart:59-63`, plus the fare and
  date sites in F-09-37/38.
- **DB / API contract** — none. **Effort** — M. **Risk** — none.
- **Acceptance criteria** — switch to English, kill, reopen: still English. Every fare renders
  identically across trip, history, wallet and detail.
- **Tests** — a lint rule or CI grep banning `toStringAsFixed` on money; a persistence test.

### P2.1 — Split the state object and stop rebuilding the map
- **Goal** — the map screen stops rebuilding for events that have nothing to do with it.
- **Design** — split `AppState` into `SessionState`, `ProfileState`, `WalletState` and
  `PreferencesState`; adopt `Selector`/`context.select` on the map screen; hoist the pulsing dot
  behind its own `RepaintBoundary` and stop reallocating markers when `_nearbyCaptains` is unchanged.
- **Files to change** — `services/app_state.dart`, `screens/home/home_screen.dart:489-662`,
  and the five listener sites.
- **DB / API contract** — none. **Effort** — L. **Risk** — a broad refactor of the app's spine;
  do it after the P0 set has stabilised, behind a release train rather than a hotfix.
- **Acceptance criteria** — a wallet fetch causes zero rebuilds of the map subtree; sustained 60 fps
  while panning on a 2 GB device.
- **Tests** — rebuild-count tests; a DevTools timeline capture attached to the PR.

### P2.2 — Cut launch weight and time
- **Goal** — a materially smaller, faster-starting app.
- **Design** — delete `assets/videos/splash.mp4` and its `pubspec` entry; re-encode the oversized
  PNGs to WebP at display resolution; move the iOS icon out of the Flutter asset bundle; bundle the
  Arabic font instead of fetching it; enable ABI splits; make the 2400 ms splash hold a *ceiling*
  rather than a floor once bootstrap has finished.
- **Files to change** — `apps/rider/pubspec.yaml`, `apps/rider/assets/**`,
  `android/app/build.gradle`, `screens/splash_screen.dart:97`, `main.dart:102`.
- **DB / API contract** — none. **Effort** — M.
- **Risk** — WebP re-encoding can soften logo edges; check the wordmark at 1× and 3×.
- **Acceptance criteria** — arm64 APK at least 40% smaller; cold start to first interactive map
  under 3 s on a mid-range device on 4G.
- **Tests** — an APK-size check in CI with a budget that fails the build.

### P2.3 — Close the post-trip loop
- **Goal** — the ride does not end at a single star row.
- **Design** — send the rating comment and tags that are already collected; add re-book from history
  and from the receipt; add tipping (wallet-funded); add a "report an issue with this trip" path that
  opens a ticket against the trip id.
- **Files to change** — `app_state.dart:516-518`, `rating_sheet.dart:34`, `history_screen.dart`,
  `trip_detail_screen.dart`; API: extend `POST /trips/:id/rate`, add `POST /trips/:id/tip` and
  `POST /trips/:id/issue`.
- **DB** — `trip_issues` table; `tips` column or ledger entry (coordinate with **T03**/**T17**).
- **API contract** — `POST /trips/:id/rate {score, comment?, tags?[]}`;
  `POST /trips/:id/tip {amount}` → `{walletBalance}`; `POST /trips/:id/issue {category, body}` → `{ticketId}`.
- **Effort** — L. **Risk** — tipping touches money; gate behind **T03**'s ledger work.
- **Acceptance criteria** — a comment left on a rating is visible in admin against that trip.
- **Tests** — API contract tests; a widget test proving the comment is transmitted.

## 7. Phasing

| Item | Phase | Effort | Owner type |
|---|---|---|---|
| P0.1 Active-trip recovery | P0 | S | Flutter + backend |
| P0.2 Show the agreed price | P0 | S | Flutter |
| P0.3 Two-way chat | P0 | S | Flutter |
| P0.4 Socket token rotation | P0 | S | Flutter |
| P0.5 Location denial recovery | P0 | S | Flutter |
| P0.6 Bids via authenticated client | P0 | S | Flutter |
| P1.1 Real payment method | P1 | M | Flutter + backend |
| P1.2 Notification centre + deep links | P1 | M | Flutter + backend |
| P1.3 Uniform failure + offline banner | P1 | M | Flutter |
| P1.4 Receipts | P1 | M | Flutter + backend + DB |
| P1.5 Scheduling entry point | P1 | M | Flutter + backend |
| P1.6 Money/date/locale formatting | P1 | M | Flutter |
| P2.1 State split + map render | P2 | L | Flutter |
| P2.2 Launch weight and time | P2 | M | Flutter + ops |
| P2.3 Post-trip loop | P2 | L | Flutter + backend + DB |

P0 is six S-sized items. None of them needs a migration and none of them changes an existing API
contract — they are all client-side corrections plus one additive endpoint. That is the argument for
doing all six before any production traffic: the cost is roughly one engineer-week and it removes
every way the rider can be stranded, misinformed about price, or unable to talk to their captain.

## 8. Metrics

| Metric | How | Current | Target |
|---|---|---|---|
| Trip-resume success (reopen during a live trip → trip screen) | client event `trip_resumed` / `trip_orphaned` | 0% by construction (F-09-01) | > 99% |
| Fare mismatch rate (fare shown mid-trip ≠ fare charged) | compare displayed vs `final_fare` at completion | 100% of negotiated trips where estimate ≠ accepted (F-09-02) | 0% |
| Rider chat reply latency (captain sends → rider renders) | client timestamp delta | unbounded (F-09-03) | p95 < 6 s |
| Live-socket uptime during a trip | fraction of trip minutes with an authenticated socket | unmeasured | > 95% |
| Booking funnel: map open → trip created | funnel events per step | unmeasured | baseline, then −20% drop-off |
| Taps to book | instrumented tap count | 6–9 | ≤ 5 |
| Cold start to interactive map | Flutter first-frame + map-ready trace | ≥ 2.4 s floor, worse on 3G (F-09-22) | p90 < 3 s on 4G |
| APK size (arm64) | CI budget check | fat APK, 5.47 MB assets (F-09-21/24) | −40% |
| Screens failing silently into an empty state | static lint over catch blocks | 6 (F-09-10) | 0 |
| Notification tap-through | FCM open → destination reached | 0% (F-09-09) | > 25% |
| Rating submission rate | ratings / completed trips | unmeasured | > 60% |
| Locale retention across restart | client event | 0% for non-Arabic (F-09-15) | 100% |

Nothing above is instrumented today: there is no analytics SDK in `apps/rider/pubspec.yaml`. The
first task in any of this is adding one — **T22** owns that choice.

## 9. Cross-cutting notes

- **→ T27 (cross-app parity).** Measured similarity between the duplicated rider/captain files at
  this commit (identical-line ratio): `trip_chat_screen` 0.22, `trip_ws` 0.57, `sos_screen` 0.18,
  `splash_screen` 0.21, `login_screen` 0.57, `wallet_screen` 0.50, `settings_screen` 0.05,
  `app_state`/`captain_state` 0.20, `main.dart` 0.40. `trip_ws` and `login_screen` are near-copies and
  should be extracted into `flutter_shared`. The others have genuinely diverged, and in most cases the
  captain's version is the better one: the captain's chat has WS + poll + typing indicator + auto-scroll
  where the rider's has none (F-09-03), and the captain's chat uses `AlignmentDirectional` where the
  rider uses physical alignment (F-09-27). Conversely the rider's SOS has a confirmation dialog and the
  captain's fires on one tap — the captain should adopt the rider's guard. Any parity work must pull
  each surface toward the better implementation rather than toward the rider's by default.
- **→ T27 / T10.** `apps/captain/lib/services/captain_state.dart:632` gates high-accuracy GPS on
  `['assigned','accepted','arrived','in_progress']`, but `accepted` is never written by the server
  (§3.3). The captain app is carrying a phantom status; either the server is missing a state or the
  captain has dead code.
- **→ T14 (i18n).** The rider app has two string systems and uses neither properly: 544 keys in
  `packages/flutter_shared/lib/l10n/app_strings.dart` (19 call sites in the rider), 56 keys in an ARB
  pipeline that is not registered at all (F-09-14), and 337 Arabic literals inline across 23 screens.
  A decision is needed before any translation work starts (§10 Q2).
- **→ T15 (accessibility).** Not audited here, but noted in passing: the bid cards and the map
  control buttons carry no `Semantics` labels, and the SOS button is an unlabelled icon
  (`sos_screen.dart:138`). Emergency affordances should be the first thing screen-reader-tested.
- **→ T12 (design system).** The rider SOS screen hardcodes light-mode tokens
  (`sos_screen.dart:31`, `:33`, `:116`, `:145`), so it renders white in dark mode. There are 119 raw
  `Color(0x…)`/`Colors.*` usages across 22 rider files that bypass `GoTheme`.
- **→ T07 (realtime).** The rider ignores five of the seven event types `TripRoom` emits
  (§3.4), and `TripRoom` has no `chat.message` broadcast that the rider chat could subscribe to —
  P0.3 depends on knowing whether one exists or must be added.
- **→ T06 (dispatch).** The scheduled-trip cron notifies admins but does not appear to fan out to
  captains (`apps/api/src/index.ts` scheduled handler), so a trip booked for later while no captains
  were online may never dispatch. This blocks P1.5.
- **→ T03 / T08 (money and schema).** Migration 0005 added `*_piastres` integer columns, but the
  completion handler writes only the REAL `final_fare` (`trips.ts:974`), so the integer columns are
  backfilled once and then permanently stale. The rider reads the REAL columns, so it is correct
  today and would silently show zeros if the server ever switched.
- **→ T02 (authorization).** `shareTripUrl` (`app_state.dart:695`) presumes a public, unauthenticated
  `/trips/:id/track` page. It does not exist. If it is built, it needs a capability token, not a
  guessable trip id.
- **→ T18 (fraud).** Declining a bid is local-only (F-09-28), so a captain cannot be told they were
  passed over and there is no signal to learn from. Repeated declines are a useful abuse signal that
  is currently discarded.
- **→ T19 (growth).** Referral is non-functional: every rider shares the code `'GODRIVE'`
  (F-09-13), so no referral can ever be attributed.

## 10. Open questions

**Q1 — Should the rider be allowed more than one active trip?** The server enforces exactly one
(`trips.ts:362`). Uber allows a scheduled trip alongside a live one; inDrive does not.
*Options:* (a) keep the hard single-trip rule; (b) allow one live plus N scheduled.
**Recommendation: (b)**, but only after P1.5 — the active-trip guard must then exclude scheduled
rows or scheduling will lock riders out of booking entirely.

**Q2 — One string system or two?** There are 544 keys in `AppStrings` (used) and 56 in an
unregistered ARB pipeline (unused).
*Options:* (a) delete the ARB pipeline and standardise on `AppStrings`; (b) register the delegate and
migrate everything to ARB, which is the Flutter-standard, tool-supported path.
**Recommendation: (b)** — ARB is what translation vendors and `flutter gen-l10n` expect, and 337
inline literals have to be extracted regardless. Doing that extraction into ARB costs no more than
doing it into `AppStrings` and ends with a pipeline a translator can actually use. This is **T14**'s
call to make; T09 only insists that the current two-systems-neither-used state is untenable.

**Q3 — What should happen when nobody accepts the rider's price?** Today: nothing, forever
(F-09-30). *Options:* (a) hard timeout that cancels; (b) timed prompt to raise the offer, with a
suggested increment; (c) auto-escalate the price on a schedule with the rider's prior consent.
**Recommendation: (b)** — it preserves the rider's control over price, which is the product's whole
premise, while making the dead end visible. 3 minutes is a reasonable first prompt.

**Q4 — Is cash-only acceptable for launch?** The wallet exists and can be topped up but cannot pay
for a ride (F-09-07). *Options:* (a) launch cash-only and hide the payment surface entirely; (b) ship
wallet payment in P1.1; (c) wait for card tokenisation.
**Recommendation: (b)**, with the card option removed from the UI until it is real. Shipping a
payment screen that cannot change the payment method is worse than shipping no payment screen.

**Q5 — Should the trip screen be a route or the app's root while a trip is live?** Today it is a
pushed route reachable from exactly one place (`fare_estimate_sheet.dart:214`), which is the root
cause of F-09-01. *Options:* (a) keep it a route and add the recovery lookup from P0.1; (b) make an
active trip a root-level state so every path leads back to it.
**Recommendation: (b)** long-term — it also gives notification deep links (P1.2) somewhere safe to
land — with (a) shipped immediately as the P0 fix.

**Q6 — Should nearby captain cars keep using the pricing endpoint?** `POST /trips/estimate` is fired
every 45 s purely to animate cars (F-09-31). *Options:* (a) leave it; (b) add a cheap
`GET /captains/nearby`; (c) drop ambient cars until there is a purpose-built endpoint.
**Recommendation: (b)** — **T06** owns `GeoCell` and should expose a read-only presence endpoint;
the current arrangement pollutes pricing metrics and rate limits with ambience traffic.
