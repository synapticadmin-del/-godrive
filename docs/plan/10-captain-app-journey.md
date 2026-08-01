# 10 — Captain App — End-to-End Journey

> Track: B — Product surface & experience · Reviewer: chat-20260801-1226-ad01 · Date: 2026-08-01 (UTC)
> Base commit reviewed: `697f4347045e67bc488a9c91631d6497ab6511d7`

---

## 1. Scope

This document reviews the **captain-facing product surface** of Synaptic Go end to end: install → registration → document verification → going online → receiving an offer → accepting or countering → driving the trip → getting paid → staying logged in for a ten-hour shift.

It judges the app by the standard the brief sets: **a work tool used one-handed, in traffic, on a cheap Android phone, for ten hours a day.** Where a design choice is defensible at a desk but fails at 60 km/h, it is marked as failing. Section 3.7 is a literal "driving test" walkthrough on that basis.

**In scope**

- The captain Flutter app (`apps/captain`) in full.
- The shared widgets and theme (`packages/flutter_shared`) where the captain consumes them.
- The API endpoints the captain app calls, read specifically to determine what the captain can and cannot see or do.
- Android and iOS platform configuration as it affects a driver's working day (background execution, permissions, notification channels).
- The battery and mobile-data cost of a shift.

**Explicitly out of scope** — owned by sibling tracks:

| Area | Owner |
|---|---|
| Dispatch algorithm, matching quality, wave sizing as a *dispatch* problem | **T06** |
| Durable Objects, WebSocket transport, `GeoCell` presence internals | **T07** |
| Rider app journey | **T09** |
| Payments, PSP integration, payout rails and ledger correctness as a *money-system* problem | **T04** |
| Admin console (document review queue, captain management screens) | **T11 / T12** |
| Design-system consolidation and cross-app duplication as a *systematic* programme | **T27** |

Where this review touches those areas it is because the captain's experience depends on them; findings that properly belong to another track are recorded in §9 rather than fixed here.

**One framing note.** Several findings below are not independent bugs. They compose into a single chain that decides whether this app can be used for work at all, and §3.6 sets that chain out explicitly. Reading the findings table alone will understate the problem.

---

## 2. What I actually read

Files are listed with what I did with each. "Read" means I read the file end to end or read every region relevant to this track with real line numbers in front of me. "Targeted" means I navigated it by structure and grep and read the relevant regions rather than the whole file. "Grepped" means I used it only to confirm the presence or absence of a symbol.

### Captain app — Flutter

| File | Depth | Note |
|---|---|---|
| `apps/captain/lib/screens/home/offer_card.dart` | **Read** | The offer moment. 15-second window, countdown, three actions, haptics. The centre of this review. |
| `apps/captain/lib/services/captain_state.dart` | **Read** | 47 KB god-object: auth, token refresh, GPS lifecycle, offers polling, WS wiring, trip mutations. |
| `apps/captain/lib/models/ride_request_model.dart` | **Read** | 57 lines. Confirms which fields reach the captain at offer time — and which do not. |
| `apps/captain/lib/services/offers_ws.dart` | **Read** | 114 lines, read in full. First-message auth, 25 s ping, jittered backoff. |
| `apps/captain/lib/screens/home/active_trip_panel.dart` | Targeted | Trip state machine, action buttons, call/chat, the `tel:` Android 11+ workaround. |
| `apps/captain/lib/screens/home/main_shell.dart` | Targeted | Lifecycle observer registration, tab structure, SOS placement, online toggle UI. |
| `apps/captain/lib/screens/onboarding/onboarding_screen.dart` | Targeted | 52 KB registration wizard; step structure, prefill/resume, validation. |
| `apps/captain/lib/screens/documents/document_upload_screen.dart` | Targeted | 56 KB; rejection reason rendering, re-upload affordance. |
| `apps/captain/lib/screens/documents/documents_onboarding_screen.dart` | Targeted | Upload path, image quality, the dead help button. |
| `apps/captain/lib/screens/documents/document_status_screen.dart` | Targeted | The limbo screen. |
| `apps/captain/lib/screens/earnings/earnings_screen.dart` | Targeted | The gross → commission → net breakdown. The best screen in the app. |
| `apps/captain/lib/screens/earnings/wallet_screen.dart` | Targeted | Balance, ledger, payout window chip. |
| `apps/captain/lib/screens/home/trips_tab.dart` | Targeted | Trip history cards — what a completed trip shows. |
| `apps/captain/lib/screens/home/home_tab.dart` | Targeted | Online state telltales and empty states. |
| `apps/captain/lib/screens/home/nearby_requests_screen.dart` | Targeted | The standing queue; `showCountdown: false`. |
| `apps/captain/lib/screens/safety/sos_screen.dart` | Targeted | Standalone SOS, 200 dp button. |
| `apps/captain/lib/screens/login_screen.dart` | Targeted | Phone/email registration and login; token persistence. |
| `apps/captain/lib/screens/profile/settings_screen.dart` | Targeted | Search radius, theme, language, SOS shortcut. |
| `apps/captain/lib/screens/home/trip_chat_screen.dart` | Targeted | Typing indicator, poll backstop — compared against the rider's. |
| `apps/captain/lib/main.dart` | Read | 3.5 KB. FCM background handler is an empty stub. |
| `apps/captain/lib/screens/splash_screen.dart`, `screens/home/available_trips_tab.dart`, `screens/home/offer_card_entrance.dart`, `lib/l10n/*.arb` | Grepped | Supporting confirmation only. |

### Shared package

| File | Depth | Note |
|---|---|---|
| `packages/flutter_shared/lib/widgets/navigation_button.dart` | **Read** | 64 lines, read in full. The "turn-by-turn" claim originates here. |
| `packages/flutter_shared/lib/services/fcm_service.dart` | **Read** | 116 lines, read in full. One notification channel, no custom sound. |
| `packages/flutter_shared/lib/theme/app_theme.dart` | Targeted | Colour tokens and tap-target tokens extracted; contrast computed independently (§4, F-10-16). |
| `packages/flutter_shared/lib/widgets/counter_offer_sheet.dart` | Targeted | Preset increments; absence of a net-earning preview. |
| `packages/flutter_shared/lib/widgets/go_online_button.dart`, `offline_gate.dart`, `offline_guard_banner.dart`, `main_bottom_nav.dart` | Targeted | Online-state messaging. |
| `packages/flutter_shared/lib/l10n/app_strings.dart` | Grepped | 184 KB; used to resolve specific copy strings, not read whole. |

### Platform configuration

| File | Depth | Note |
|---|---|---|
| `apps/captain/android/app/src/main/AndroidManifest.xml` | **Read** | 46 lines, read in full. The single most consequential file in this review. |
| `apps/captain/ios/Runner/Info.plist` | **Read** | `UIBackgroundModes` present — the platform asymmetry. |
| `apps/captain/pubspec.yaml` | **Read** | Dependency list; proves the absence of any audio package. |
| `apps/captain/android/app/build.gradle` | Targeted | SDK levels. |

### API — read from the captain's perspective

| File | Depth | Note |
|---|---|---|
| `apps/api/src/lib/jwt.ts` | **Read** | `ACCESS_TTL = "15m"`, `REFRESH_TTL = "30d"`. |
| `apps/api/src/routes/auth.ts` | Targeted | `/auth/refresh` rotation semantics — read closely, it is load-bearing for F-10-02. |
| `apps/api/src/routes/wallet.ts` | Targeted | Balance computation and payout guard — read closely, load-bearing for F-10-04. |
| `apps/api/src/routes/captain.ts` | Targeted | Online toggle, location ingest and its rate limit, offers query, document endpoints. |
| `apps/api/src/routes/trips.ts` | Targeted | 53 KB. `advanceStatus`, completion accounting, cash-commission debit. |
| `apps/api/src/durable-objects/OfferScheduler.ts` | **Read** | Wave sizing and delay — the server half of the offer window. |
| `apps/api/src/lib/routing.ts` | Targeted | Proves no maneuvers are ever requested from OSRM. |
| `apps/api/src/durable-objects/GeoCell.ts`, `CaptainInbox.ts`, `src/index.ts`, `src/lib/notifications.ts`, `src/middleware/rateLimit.ts` | Targeted | Presence expiry, cron contents, push paths. |

### Rider app — parity comparison only (PROTOCOL §4)

`apps/rider/lib/services/app_state.dart` (**read** around the refresh path — it is the reference implementation that proves F-10-02 is a captain-only regression), `apps/rider/lib/screens/safety/sos_screen.dart`, `apps/rider/lib/screens/trip/trip_chat_screen.dart`, `apps/rider/lib/services/trip_ws.dart`, `apps/rider/lib/screens/profile/settings_screen.dart`, `apps/rider/lib/screens/splash_screen.dart` — all targeted, for §9.

### Migrations and docs

`migrations/0008`, `0012`, `0014`, `0015`, `0017`, `0018`, `0001_init.sql` — targeted, for the document catalogue, the online guard, search radius and the trips schema. `docs/ROADMAP.md`, `docs/IMPROVEMENTS.md`, `docs/CHECKLIST.md`, `docs/API.md` — skimmed to avoid restating existing plans.

### Method note

Four analysis subagents were run in parallel across the onboarding funnel, the power/data/lifecycle axis, the earnings axis, and the trip/accessibility axis. **Every load-bearing claim in this document was then re-verified by me directly against the file**, and two of them changed as a result:

- A subagent reported the navigation button deep-links out to Google Maps. It does not — the captain app passes an `onPressed` override (`apps/captain/lib/screens/home/active_trip_panel.dart:418`), so the external path is dead code for this app. The real finding turned out to be worse, not better (F-10-03).
- A subagent reported the session risk as "reactive-only refresh". The actual defect is a dropped token rotation that forces a logout roughly every thirty minutes (F-10-02). I found this by reading `/auth/refresh` against the client's storage writes.

The WCAG ratios in F-10-16 were computed by me from the hex tokens with the WCAG 2.1 relative-luminance formula, not eyeballed and not taken on trust.

---

## 3. How it works today

### 3.1 Registration and document verification

Registration is a **19-step path from install to being able to receive a first offer**. Four screens, roughly seventeen discrete inputs, and one human review gate.

1. Splash → login screen, "Join" mode (`apps/captain/lib/screens/login_screen.dart:69`).
2. Four account fields: display name, Egyptian phone validated against `^01[0125]\d{8}$` (`apps/captain/lib/screens/login_screen.dart:545`), email, password ≥ 6 chars.
3. Mandatory terms checkbox (`apps/captain/lib/screens/login_screen.dart:98`), then `POST /auth/register` (`apps/api/src/routes/auth.ts:347`).
4. Wizard **step 1** — profile photo, then a four-part Arabic name (first / father / grandfather / family) at `apps/captain/lib/screens/onboarding/onboarding_screen.dart:791-803`, plus an optional birth date.
5. Wizard **step 2** — driving licence photo and an optional expiry date (`apps/captain/lib/screens/onboarding/onboarding_screen.dart:838`).
6. Wizard **step 3** — national ID photo, criminal record front (back optional), and a 14-digit national ID number.
7. Wizard **step 4** — vehicle registration front (back optional), optional vehicle photo, and five vehicle fields: make, model, colour, plate, year.
8. Submit for review → `DocumentStatusScreen`. The map does not appear until an admin approves (`apps/captain/lib/screens/home/main_shell.dart:411`).

Two things about this flow are genuinely well built and should not be broken by later work:

- **Progress is server-persisted and resumable.** On mount the wizard fetches `GET /captain/profile` and `GET /captain/documents` in parallel, prefills every controller, and positions the captain at `_firstIncompleteStep()` (`apps/captain/lib/screens/onboarding/onboarding_screen.dart:126-153, 160-175, 186-191`). Each upload registers server-side immediately rather than at "Next". Killing the app mid-wizard loses only the current step's untyped-but-unsaved text.
- **The document catalogue is dynamic, not hardcoded.** `GET /captain/document-types` (`apps/api/src/routes/captain.ts:504-509`) drives the checklist, so adding a document type is a data change. Its limitation is that the catalogue is global — `document_types` has no city or vehicle-type column (`migrations/0014_document_types.sql`), so a motorcycle captain and a van driver see identical requirements.
- **Rejection feedback is fully wired.** `rejection_reason` runs `migrations/0008_rejection_reason_and_online_guard.sql:6` → `apps/api/src/routes/admin.ts:829` → `apps/api/src/routes/captain.ts:512-527` → rendered inline per document at `apps/captain/lib/screens/documents/document_upload_screen.dart:1309` with a re-upload button at `:1323`. There is a fallback string when an admin leaves the reason blank.

The failures are on the waiting side, and they are covered in §4.

### 3.2 Going online

The online toggle is **not optimistic**, and that is the right call: `apps/captain/lib/services/captain_state.dart:576-582` awaits `POST /captain/online` before assigning `online = value`, so a failed call cannot leave the captain believing they are earning when the server thinks they are parked. The server checks `approval_status` and coordinates (`apps/api/src/routes/captain.ts:131-155`).

Once online, three mechanisms run concurrently:

| Mechanism | Cadence | Source |
|---|---|---|
| GPS position stream | `medium` accuracy, 50 m filter when idle; `high`, 10 m when on a trip | `apps/captain/lib/services/captain_state.dart:619-626` |
| Offers WebSocket | connect + 25 s ping, jittered exponential backoff | `apps/captain/lib/services/offers_ws.dart:73, 83-96` |
| REST offers poll | 60 s while the socket is up, 8 s while it is down | `apps/captain/lib/services/captain_state.dart:758-765` |

The poll cadence is correctly re-armed whenever the socket's status changes (`apps/captain/lib/services/captain_state.dart:793-800`), and the GPS stream is a single subscription fanned out to both the map camera and the server push (`apps/captain/lib/services/captain_state.dart:645-651`). Both are good engineering.

### 3.3 The offer moment

An offer reaches the captain through `OfferScheduler`, which releases it in distance-ordered waves of three, fifteen seconds apart (`apps/api/src/durable-objects/OfferScheduler.ts:62-63`).

The card (`apps/captain/lib/screens/home/offer_card.dart`) presents, in the order the file's own doc comment says it intends: the rider's photo and name, the fare as an oversized numeral, the pickup distance, the trip distance and duration, the route, and three actions — **accept at the rider's price**, **counter-offer**, or **skip**.

The three-way action set is the right product decision. A marketplace built on negotiation should not present a binary. The counter-offer sheet even ships preset increments — `[5, 10, 15, 20, 30]` at `packages/flutter_shared/lib/widgets/counter_offer_sheet.dart:19` — so countering is two taps, not a keyboard.

The timing model is where it comes apart:

- The client window is **15 seconds**, held as `_window = 15` (`apps/captain/lib/screens/home/offer_card.dart:69`).
- The countdown is an `AnimationController` started in `initState` (`apps/captain/lib/screens/home/offer_card.dart:102`) — it is anchored to **when the widget mounted**, not to when the server issued the offer.
- The offer payload carries an issue timestamp `at` (`apps/api/src/durable-objects/OfferScheduler.ts:57`) and the model carries `createdAt` (`apps/captain/lib/models/ride_request_model.dart:54`). Neither is read by the card — grep for `createdAt`, `created_at`, or `DateTime.parse` in `offer_card.dart` returns nothing.
- On expiry the card calls `decline()` (`apps/captain/lib/screens/home/offer_card.dart:117-126`), and `decline()` is **purely local**: it adds to an in-memory set and removes the card (`apps/captain/lib/services/captain_state.dart:1041-1045`). No network call. There is no server-side decline endpoint anywhere in the API.

### 3.4 Driving the trip

The trip state machine the captain drives is three transitions, all backed by real endpoints:

| Status | Captain action | Endpoint |
|---|---|---|
| `assigned` | "وصلت لموقع الانطلاق" | `POST /trips/:id/arrived` (`apps/api/src/routes/trips.ts:944`) |
| `arrived` | "ابدأ الرحلة" | `POST /trips/:id/start` (`apps/api/src/routes/trips.ts:948`) |
| `in_progress` | "إنهاء الرحلة", behind a confirm dialog | `POST /trips/:id/complete` (`apps/api/src/routes/trips.ts:951`) |

`advanceStatus` (`apps/api/src/routes/trips.ts:891-941`) enforces ownership and a `canTransition` state guard, and nothing else. There is no proximity check before `arrived` and no rider-presented code before `start`.

Navigation is the part that matters most and delivers least. `NavigationButton` (`packages/flutter_shared/lib/widgets/navigation_button.dart`) can deep-link to Google Maps, but the captain app never uses that path: it passes an `onPressed` override at `apps/captain/lib/screens/home/active_trip_panel.dart:418` which calls `CaptainState.startInAppNavigation`. That method, in full, is:

```dart
void startInAppNavigation(double lat, double lng, bool headingToPickup) {
  navigationTarget = { 'lat': lat, 'lng': lng, 'toPickup': headingToPickup };
  if (!_navigationStartCtrl.isClosed) _navigationStartCtrl.add(null);
  notifyListeners();
}
```
— `apps/captain/lib/services/captain_state.dart:178-186`

It sets a destination and emits an event. The map camera then follows the captain along a polyline. That polyline comes from OSRM, requested at `apps/api/src/lib/routing.ts:30` as `?overview=full&geometries=geojson` — **`steps=true` is never requested**, so no maneuvers, no street names and no turn instructions are ever fetched, and the `RouteResult` type has no field to hold them (`apps/api/src/lib/routing.ts:11`). There is no text-to-speech anywhere in the repository.

### 3.5 Getting paid

The `EarningsScreen` is the strongest screen in the app and deserves saying so plainly. It shows **gross → commission → net** as explicit arithmetic (`apps/captain/lib/screens/earnings/earnings_screen.dart:199-241`), and its own doc comment states the reasoning: a driver who cannot see where the deduction went does not trust the number. That is exactly right.

The problem is that this clarity exists **only at the seven-day aggregate level**. The per-trip card in history renders `final_fare` alone (`apps/captain/lib/screens/home/trips_tab.dart:241-243`) even though `commission` is present in the row. The offer card shows no commission before the captain commits, and the counter-offer sheet shows no net preview.

Two different balances also exist. `GET /captain/wallet` computes a balance by summing wallet transactions (`apps/api/src/routes/wallet.ts:57-72`), while `POST /captain/wallet/payout` guards against `users.wallet_balance` (`apps/api/src/routes/wallet.ts:101-108`). These are different numbers, and §4 F-10-04 shows how far apart they drift.

### 3.6 The chain that decides everything

Six of the findings below are usually read as separate defects. They are one failure:

1. In-app "navigation" has no turn instructions and no voice (§3.4). A captain cannot drive an unfamiliar Cairo address from a polyline at 60 km/h.
2. So the captain opens Google Maps. Every captain will. This is not a hypothetical.
3. Backgrounding the app fires `AppLifecycleState.paused`, and the handler stops the GPS stream and cancels the offers poll (`apps/captain/lib/services/captain_state.dart:1081-1092`). The handler treats `inactive` and `hidden` identically, so even pulling down the notification shade does it.
4. There is **no Android foreground service** to keep any of it alive. The manifest says so in a comment: *"Background location removed: no foreground service is implemented yet"* (`apps/captain/android/app/src/main/AndroidManifest.xml:6`).
5. The code comments reassure that "FCM still wakes the app for real work" (`apps/captain/lib/services/captain_state.dart:1080`). The FCM background handler initialises Firebase and does nothing else (`apps/captain/lib/main.dart:13-16`). It cannot wake anything.
6. Meanwhile the access token expires every 15 minutes and the refresh path silently discards the rotated refresh token, so the session dies roughly every 30 minutes (F-10-02).

The result: **the captain switches to Google Maps to drive the trip they just accepted, and while they are there their location stops being reported, so the rider watches a frozen car on the map for the entire journey, and no new offer can reach them.** Then they come back to a login screen.

Every one of those six links is independently confirmed. This is the finding that matters; the rest is detail.

### 3.7 The driving test

The brief asks for the app judged as if used at 60 km/h. Taking each moment in turn:

| Moment | What the captain must do | Verdict at speed |
|---|---|---|
| Offer arrives | Notice it | **Fail.** Silent. No audio package exists in the app (F-10-06). Haptics only, from a phone in a dash mount, in a car with engine and road noise. |
| Read the offer | Fare, pickup distance, destination | **Pass.** Fare is an oversized numeral and is correctly the visual priority. |
| Judge the offer | Is it worth taking? | **Fail.** Commission is never shown, so the captain cannot know their net (F-10-10). No rider rating (F-10-14). |
| Decide | 15 seconds | **Marginal.** 15 s is defensible; the countdown lying about how much is left is not (F-10-07). |
| Tap accept | Hit a 46 dp target while moving | **Fail.** Below the 48 dp Material floor and below the app's own 56 dp primary-action token (F-10-09). |
| Counter-offer | Two taps via presets | **Pass on mechanics, fail on information** — no net preview before committing. |
| Navigate to pickup | Follow directions | **Fail.** No turn instructions, no voice (F-10-03). Captain leaves for Google Maps. |
| Stay reachable while navigating | Keep receiving offers, keep the rider informed | **Fail.** Everything stops (§3.6). |
| Confirm arrival | One tap | Pass mechanically; unvalidated (F-10-12). |
| Read trip status labels | Glance at the stepper | **Fail.** Stage labels are 10.5 sp (F-10-15) at 4.17:1 contrast (F-10-16). |
| Emergency | Reach SOS | **Pass from the map tab** — one tap to a 200 dp button. Two taps from any other tab (F-10-21). |
| Finish the shift | Still be logged in | **Fail.** Roughly 20 forced re-logins (F-10-02). |

Four passes, eight failures, and the failures cluster at exactly the moments that determine income and safety.

### 3.8 Battery and data budget

Assumptions stated so the arithmetic can be argued with: a 3,500 mAh mid-range Android battery; continuous high-accuracy GPS ≈ 150 mAh/h and medium-accuracy ≈ 80 mAh/h; active cellular ≈ 50 mAh/h and idle ≈ 25 mAh/h; screen at driving brightness ≈ 200 mAh/h; a ten-hour shift split six hours on-trip and four idle; city speed ≈ 30 km/h on trip and slow repositioning when idle.

**Data — current**

| Source | Rate | Payload | Per hour | Per 10 h shift |
|---|---|---|---|---|
| Location push, on trip (rate-limited to 30/min) | 30/min | ~230 B | 414 KB | 2.5 MB (6 h) |
| Location push, idle (50 m filter) | ~1.7/min | ~230 B | 23 KB | 0.1 MB (4 h) |
| Offers REST poll, socket up | 1/min | ~5 KB | 300 KB | 3.0 MB |
| `/trips` refresh inside the same poll | 1/min | ~2 KB | 120 KB | 1.2 MB |
| `/auth/me` approval poll (30 s, never stops) | 2/min | ~1 KB | 120 KB | 1.2 MB |
| WebSocket pings, two sockets | ~5/min | ~50 B | 14 KB | 0.1 MB |
| **Total** | | | **~570 KB/h** | **~8 MB** |

If the socket is down the offers poll goes to 8 s and hourly data rises to roughly **2.6 MB/h** — about 26 MB across a shift, which on an Egyptian prepaid bundle is a real cost the captain pays to be available.

**Battery — current**

| Drain | On trip (6 h) | Idle (4 h) |
|---|---|---|
| GPS (high 10 m / medium 50 m) | 900 mAh | 320 mAh |
| Cellular | 300 mAh | 100 mAh |
| App CPU (timers, WS, JSON, map) | 180 mAh | 120 mAh |
| Screen | 1,200 mAh | 400 mAh |
| **Subtotal** | **2,580 mAh** | **940 mAh** |
| **Shift total (2,580 + 940)** | | **≈ 3,520 mAh** |

**A 3,500 mAh phone does not survive the shift.** It dies right at the end of hour ten, with no margin, before accounting for the map render load or a single phone call.

**Targets after the §6 plan**

| Metric | Current | Target | Principal lever |
|---|---|---|---|
| Battery, 10 h shift | ≈ 3,520 mAh | ≤ 2,700 mAh | Idle filter 50 m → 100 m; client-side location-push throttle; `/auth/me` 30 s → 300 s once approved; dim-on-idle |
| Data, 10 h shift (socket up) | ≈ 8 MB | ≤ 4 MB | Kill the redundant `/auth/me` poll; push approval instead; slim the offers payload |
| Data, 10 h shift (socket down) | ≈ 26 MB | ≤ 10 MB | Backoff the 8 s poll to 15 s after the first minute |
| Survives a 10 h shift on 3,500 mAh | No | Yes, with ~20 % margin | All of the above |

Note the perverse consequence of the current design: the app's *only* battery-saving mechanism is stopping work when backgrounded (`apps/captain/lib/services/captain_state.dart:1081-1092`). It saves power by ceasing to be a driver app. A foreground service will *increase* measured drain while making the product function — the battery targets above assume that trade and pay for it elsewhere.

---

## 4. Findings

| ID | Sev | Finding | Evidence (`path:line`) | Impact | Confidence |
|---|---|---|---|---|---|
| F-10-01 | S1 | No Android foreground service: GPS and offer polling stop whenever the app is not in front | `apps/captain/android/app/src/main/AndroidManifest.xml:6`; `apps/captain/lib/services/captain_state.dart:1081-1092` | Captain silently stops receiving work and the rider sees a frozen car | confirmed |
| F-10-02 | S1 | The rotated refresh token is discarded, forcing a logout roughly every 30 minutes | `apps/captain/lib/services/captain_state.dart:266-267` vs `apps/api/src/routes/auth.ts:292-305` | ~20 forced re-logins per shift, typed while driving | confirmed |
| F-10-03 | S1 | "Turn-by-turn navigation" has no turns and no voice | `apps/captain/lib/services/captain_state.dart:178-186`; `apps/api/src/lib/routing.ts:11,30` | Captain must leave for Google Maps, which triggers F-10-01 | confirmed |
| F-10-04 | S1 | Wallet balance omits cash-trip commission debt and disagrees with the payout guard | `apps/api/src/routes/wallet.ts:57-72` vs `:101-108`, `apps/api/src/routes/trips.ts:1017-1034` | Captain sees money that is not there and is refused withdrawal with no explanation | confirmed |
| F-10-05 | S1 | No rider-presented code at trip start | `apps/api/src/routes/trips.ts:891-948` | Ghost rides: a trip can be started and charged with no rider aboard | confirmed |
| F-10-06 | S1 | Offer arrival is completely silent | `apps/captain/pubspec.yaml:10-42`; `packages/flutter_shared/lib/services/fcm_service.dart:15-20` | Offers missed inside a 15 s window because nothing is audible in a moving car | confirmed |
| F-10-07 | S2 | Offer countdown is anchored to widget mount, not to the server's issue time | `apps/captain/lib/screens/home/offer_card.dart:102`; `apps/api/src/durable-objects/OfferScheduler.ts:57` | Captain acts on a card that says 9 s left when the offer is already with the next wave | confirmed |
| F-10-08 | S2 | Decline is client-only; no server decline endpoint exists | `apps/captain/lib/services/captain_state.dart:1041-1045`; `apps/api/src/durable-objects/OfferScheduler.ts:63` | Rider waits the full 15 s per wave even when all three captains declined instantly | confirmed |
| F-10-09 | S2 | Offer card tap targets are 46/42/42 dp, below the app's own 48/56 dp tokens | `apps/captain/lib/screens/home/offer_card.dart:609,656,705`; `packages/flutter_shared/lib/theme/app_theme.dart:180-181` | Mis-taps on the highest-stakes control in the product | confirmed |
| F-10-10 | S2 | Net-after-commission is never shown before the captain commits | `apps/captain/lib/screens/home/offer_card.dart` (no `commission`); `packages/flutter_shared/lib/widgets/counter_offer_sheet.dart` (no net preview) | Captain cannot price their own work | confirmed |
| F-10-11 | S2 | Trip history shows fare only — no commission, no net, no detail view | `apps/captain/lib/screens/home/trips_tab.dart:241-243` | The number the captain remembers never matches the money they received | confirmed |
| F-10-12 | S2 | No proximity check before `arrived` | `apps/api/src/routes/trips.ts:891-944` | "Arrived" can be pressed from anywhere; rider waits at the wrong place | confirmed |
| F-10-13 | S2 | No waiting timer and no waiting charge | repo-wide grep: no `wait_fee`/`waiting_fee`/`wait_charge` | Captain absorbs pickup dwell time unpaid; incentive to abandon riders | confirmed |
| F-10-14 | S2 | Rider rating is never shown before accepting | `apps/captain/lib/models/ride_request_model.dart:1-57`; `apps/api/src/routes/captain.ts:375-398` | Captain accepts blind; no way to avoid known-bad riders | confirmed |
| F-10-15 | S2 | Hot-path type sizes of 10–12.5 sp on driving screens | `apps/captain/lib/screens/home/active_trip_panel.dart:597,698`; `apps/captain/lib/screens/home/offer_card.dart:401,572` | Unreadable at a glance at speed | confirmed |
| F-10-16 | S2 | Brand and muted colours fail WCAG AA on the app's own off-white surfaces | `packages/flutter_shared/lib/theme/app_theme.dart:36,101,103,106` | Status and secondary text illegible in Cairo daylight | confirmed |
| F-10-17 | S2 | No client-side upload size check and no byte progress | `apps/captain/lib/screens/documents/documents_onboarding_screen.dart:227,239-252`; `apps/api/src/routes/captain.ts:631` | Minute-long silent upload on 3G then a raw error code | confirmed |
| F-10-18 | S2 | No push notification when documents are approved or rejected | `apps/api/src/routes/admin.ts:820-858`; `apps/captain/lib/main.dart:13-16` | Approved captains stay idle for hours; onboarding conversion lost | confirmed |
| F-10-19 | S2 | No offline queue for `arrived` / `start` / `complete` | `apps/captain/lib/services/captain_state.dart:1047-1065` | Trip mutations lost in a tunnel or dead cell; manual retry required | confirmed |
| F-10-20 | S2 | Multi-stop is unsupported although waypoints exist in the schema | `apps/api/src/routes/trips.ts:476`; no waypoint UI in `active_trip_panel.dart` | Multi-stop and intercity trips cannot be driven correctly | confirmed |
| F-10-21 | S2 | SOS is only reachable from the map tab | `apps/captain/lib/screens/home/main_shell.dart:739-752` | Two taps in an emergency if the captain is on any other tab | confirmed |
| F-10-22 | S2 | Location pushes are silently dropped above roughly 20 km/h | `apps/api/src/routes/captain.ts:190-197`; `apps/captain/lib/services/captain_state.dart:623-626,682` | Rider's live map degrades exactly when the car is moving fastest | confirmed |
| F-10-23 | S2 | Stale `is_online` is cleaned only when an admin opens the dashboard | `apps/api/src/routes/admin.ts:237`; `apps/api/src/index.ts:267-333` | Supply metrics and the admin view overstate live captains indefinitely | confirmed |
| F-10-24 | S2 | Approval and other failures are surfaced as GPS errors | `apps/captain/lib/services/captain_state.dart:600-607`; `apps/captain/lib/screens/home/main_shell.dart:359-365` | Captain is told to fix their GPS when the real problem is their account | confirmed |
| F-10-25 | S2 | Earnings use a rolling UTC 7-day window and there is no daily total | `apps/api/src/routes/captain.ts:275`; `apps/api/src/routes/wallet.ts:78` | "Today" — the number every driver checks — does not exist; week totals shift with UTC | confirmed |
| F-10-26 | S2 | No debt gate and no debt visibility for cash commission owed | `apps/api/src/routes/captain.ts:131-155`; `migrations/0003_global_transport.sql:45` | Captains accrue unrecoverable commission debt and are never told | confirmed |
| F-10-27 | S3 | The payout window is a hardcoded string | `apps/api/src/routes/wallet.ts:88` | Wrong the first time the schedule changes | confirmed |
| F-10-28 | S3 | The help button on the documents screen is an empty callback | `apps/captain/lib/screens/documents/documents_onboarding_screen.dart:367` | A stuck captain taps help and nothing happens | confirmed |
| F-10-29 | S3 | The limbo screen gives no expected wait time | `apps/captain/lib/screens/documents/document_status_screen.dart:227` | No expectation anchor during review; support load | confirmed |
| F-10-30 | S3 | Account-level rejection is a dead end on the documents grid | `apps/captain/lib/screens/documents/documents_onboarding_screen.dart:341-344` | Rejected captain is trapped with no message and no way forward | confirmed |
| F-10-31 | S3 | The document catalogue is global, not per city or vehicle type | `apps/api/src/routes/captain.ts:504-509`; `migrations/0014_document_types.sql` | A tuk-tuk driver is asked for van paperwork as the fleet diversifies | confirmed |
| F-10-32 | S3 | Uncached `Image.network` for rider avatars in the offer list | `apps/captain/lib/screens/home/offer_card.dart:891` | Memory pressure and wasted data on 2 GB devices | confirmed |
| F-10-33 | S3 | Declined offers reappear after an app restart | `apps/captain/lib/services/captain_state.dart:1039` | Captain re-declines the same trips after any crash | confirmed |
| F-10-34 | S3 | No acceptance or cancellation scorecard | repo-wide grep: no `acceptance_rate`/`cancellation_rate` | No lever for supply quality, and no parity with Uber/Careem expectations | confirmed |
| F-10-35 | S4 | `lightFaint` #9CA3AF is 2.54:1 on white | `packages/flutter_shared/lib/theme/app_theme.dart:107` | Hint and placeholder text invisible outdoors | confirmed |
| F-10-36 | S4 | Star colour #F5B301 is 1.85:1 on white | `packages/flutter_shared/lib/theme/app_theme.dart:50` | Ratings invisible in sunlight | confirmed |
| F-10-37 | S4 | `NavigationButton` still pre-checks `canLaunchUrl`, a known Android 11+ trap | `packages/flutter_shared/lib/widgets/navigation_button.dart:32,38` vs the fix at `apps/captain/lib/screens/home/active_trip_panel.dart:128-131` | Dead path for the captain today, but it will silently fail for the next surface that uses it | confirmed |

### S1 — blockers

**F-10-01 — No Android foreground service.**
The manifest declares `INTERNET`, `ACCESS_COARSE_LOCATION`, `ACCESS_FINE_LOCATION`, `ACCESS_NETWORK_STATE`, `POST_NOTIFICATIONS` and `VIBRATE`, and then documents its own gap in a comment at line 6: *"Background location removed: no foreground service is implemented yet. Re-add with a real foreground service when background tracking ships."* There is no `<service>` element, no `FOREGROUND_SERVICE` permission, no `foregroundServiceType="location"`, and no `ACCESS_BACKGROUND_LOCATION`. A repo-wide grep finds no `flutter_foreground_task`, `flutter_background_geolocation`, `workmanager` or equivalent.

The client behaves accordingly. `handleAppLifecycleState` stops the GPS stream and cancels the offers timer on `paused`, `inactive` **and** `hidden` (`apps/captain/lib/services/captain_state.dart:1083-1092`). `inactive` fires for transient interruptions — the notification shade, a permission dialog, an incoming call — so the radio goes quiet on events that are not even app switches.

The asymmetry is the tell: **iOS is configured correctly.** `apps/captain/ios/Runner/Info.plist:56-61` declares `UIBackgroundModes` of `location`, `remote-notification` and `fetch`. Somebody understood the requirement and implemented it on the platform that is *not* the primary market. On Android — where essentially all Egyptian captains are — the OS suspends the Dart isolate within seconds of the screen going off, and the two WebSockets follow within about a minute of Doze. The captain's phone in their pocket between fares is not an online captain; it is an offline one that still reads `is_online = 1` in the database (see F-10-23).

The comment at `apps/captain/lib/services/captain_state.dart:1080` — "FCM still wakes the app for real work" — is not true. `fcmBackgroundHandler` calls `Firebase.initializeApp()` and returns (`apps/captain/lib/main.dart:13-16`). It fetches nothing, updates nothing and wakes nothing.

**F-10-02 — The rotated refresh token is discarded.**
`ACCESS_TTL` is 15 minutes and `REFRESH_TTL` is 30 days (`apps/api/src/lib/jwt.ts:8-9`). `POST /auth/refresh` rotates: it revokes the presented token (`apps/api/src/routes/auth.ts:292-294`), mints a fresh pair through `issueTokens` (`:304`, minting at `:34-44`) and returns both in the response body (`:305`).

The captain client sends the refresh token and then stores only half the answer:

```dart
token = (data['accessToken'] ?? data['token']) as String?;
if (token != null) {
  await _secureStorage.write(key: 'token', value: token!);
  return await reqFn();
}
```
— `apps/captain/lib/services/captain_state.dart:263-268`

A complete grep of `refreshToken` in `captain_state.dart` returns lines 252, 253, 259, 335, 340, 349, 354 and 1170: it is *read* at 252, *sent* at 259, *written* only in `loginWithPhone` (340) and `loginWithEmail` (354), and *deleted* at logout (1170). **There is no write in the refresh path.**

So the stored refresh token is revoked server-side the moment it is first used. Fifteen minutes later the access token expires again, the client presents the now-revoked token, the server answers 401 `REFRESH_REVOKED` (`apps/api/src/routes/auth.ts:287`), the `statusCode < 400` branch is skipped, and control reaches `await logout()` at `apps/captain/lib/services/captain_state.dart:272`. The captain is thrown to the login screen roughly **every thirty minutes** — about twenty times in a ten-hour shift, each time re-entering credentials in a car.

The `catch (_) {}` at line 270 widens the blast radius: a timeout or a dropped packet during the refresh call is indistinguishable from a rejection, and also ends in `logout()`.

This is a captain-only regression, and the fix already exists in the repository. The rider app reads the rotated token — `final rotated = data['refreshToken'] as String?;` at `apps/rider/lib/services/app_state.dart:206` — and persists it at `:227-228`. The captain app should do what the rider app already does.

**F-10-03 — "Turn-by-turn navigation" has no turns.**
Three separate places in the codebase call this feature turn-by-turn navigation: `packages/flutter_shared/lib/widgets/navigation_button.dart:5`, `apps/captain/lib/services/captain_state.dart:173` and `apps/captain/lib/screens/home/main_shell.dart:78`. What is implemented is a camera that follows the captain along a line.

`startInAppNavigation` sets a target and emits an event; its full body is quoted in §3.4. The route behind it is fetched at `apps/api/src/lib/routing.ts:30` with `?overview=full&geometries=geojson`. OSRM only returns maneuvers when asked with `steps=true`, and it is never asked — the `RouteResult` type at `apps/api/src/lib/routing.ts:11` has `geometry`, `distanceKm`, `durationMin` and `source`, with nowhere to put a maneuver if one arrived. A grep for `tts`, `flutter_tts`, `speak(`, `maneuver` or `instruction` across both apps and the shared package returns nothing but unrelated comment text.

A captain driving to an unfamiliar address in Cairo cannot use a polyline. They will open Google Maps — and F-10-01 turns that reasonable act into a silent outage. These two findings must be fixed as a pair or neither is fixed.

**F-10-04 — The wallet balance omits cash-trip commission debt.**
On completion of a **cash** trip the platform records the commission it is owed as a wallet transaction with `type='commission'` and `direction='debit'`, and decrements `users.wallet_balance` by the same amount (`apps/api/src/routes/trips.ts:1017-1034`). That accounting is correct and idempotent — it is guarded by `INSERT OR IGNORE` on `idempotency_key` and only moves the balance when `changes === 1`.

`GET /captain/wallet` then computes the balance it shows the captain from a different place, and with filters that exclude that row:

```sql
-- credits
WHERE user_id = ? AND direction = 'credit' AND type IN ('commission','payout','adjustment')
-- minus
WHERE user_id = ? AND direction = 'debit' AND type = 'payout'
```
— `apps/api/src/routes/wallet.ts:57-70`, netted at `:72`

A `direction='debit'`, `type='commission'` row matches neither clause. Every cash trip therefore leaves the displayed balance untouched while the real balance falls. The two numbers diverge by the entire commission on every cash trip, in the direction that flatters the platform's screen and misleads the captain.

The withdrawal path then guards against the *other* number — `SELECT COALESCE(wallet_balance, 0) FROM users` at `apps/api/src/routes/wallet.ts:101-105` — and returns `INSUFFICIENT_BALANCE` when it disagrees. The captain reads a balance of, say, 500 EGP, requests 400, and is refused with a bare Arabic error toast. In a cash-heavy market where the captain is already holding the platform's money in their pocket, there is no faster way to convince a driver they are being cheated. This is the single most trust-destructive defect in the track, and it is a display bug sitting on top of correct accounting, which makes it cheap to fix.

**F-10-05 — No rider-presented code at trip start.**
`advanceStatus` checks that the requesting captain owns the trip and that `canTransition` permits the move, and nothing else (`apps/api/src/routes/trips.ts:891-941`); `/start` is a thin wrapper at `:948`. Greps for `otp`, `pin_code`, `start_pin` and `tripOtp` across `trips.ts` return nothing. A captain can therefore accept a trip, never collect the rider, press "start" and then "complete", and the rider is charged for a journey that never happened. Combined with F-10-12 — no proximity check on `arrived` — the entire trip lifecycle can be driven from a parked car. Uber, Careem and inDrive all gate trip start on either a rider-presented PIN or rider-side confirmation for exactly this reason.

**F-10-06 — Offer arrival is completely silent.**
`apps/captain/pubspec.yaml` lists no audio dependency of any kind: no `audioplayers`, no `just_audio`, no `soundpool`. The entire captain app and shared package contain thirteen `HapticFeedback` calls and zero sound calls. When an offer arrives over the WebSocket while the app is foregrounded — the normal case for a working captain — the app produces **a vibration and nothing else**, and then starts a 15-second clock.

The FCM path is no better. `FcmService` registers exactly one channel, `synaptic_go_default`, described as "Trip updates, offers and payments" (`packages/flutter_shared/lib/services/fcm_service.dart:15-20`). It is `Importance.high` but sets no custom sound, so an offer gets the same default blip as a receipt. Because there is one channel for all three categories, a captain who mutes payment noise also mutes their income, and no per-category sound can be configured in Android settings.

A phone in a dashboard mount, in a car with the engine running, a window down and Cairo traffic outside, needs a loud, distinctive, repeating alert. This is table stakes in every competing driver app and it is absent.

### S2 — major

**F-10-07 — The countdown is anchored to the wrong clock.** `_countdown.forward()` runs in `initState` (`apps/captain/lib/screens/home/offer_card.dart:102`), so the 15 seconds begin when the widget mounts. The server's window begins when the wave is pushed (`WAVE_DELAY_MS = 15_000`, `apps/api/src/durable-objects/OfferScheduler.ts:63`). The gap between them is push latency plus render time — on a congested 3G cell, one to two seconds. The offer payload carries `at` (`:57`) and the model carries `createdAt` (`apps/captain/lib/models/ride_request_model.dart:54`); the card reads neither. Consequences: an offer that arrives late still shows a full 15 s; a widget rebuild restarts the clock; and because the client and server windows are the same nominal length, wave 2 is always already live while wave 1's card still claims time remains. The captain races a countdown that has no authority.

**F-10-08 — Decline never reaches the server.** `decline()` adds the id to an in-memory set and removes the card (`apps/captain/lib/services/captain_state.dart:1041-1045`). No request is made, and there is no decline endpoint in the API to make one to. The comment at `apps/captain/lib/screens/home/offer_card.dart:120-121` — "Tell the server so it can re-offer" — describes behaviour that does not exist. The dispatch cost is concrete: `OfferScheduler` advances only on its 15-second alarm, so if all three captains in a wave skip the offer in two seconds, the rider still waits thirteen seconds of pure dead air, and 39 s across three waves. A decline endpoint that lets the scheduler advance early is the single cheapest latency win available to dispatch. *(Dispatch tuning itself belongs to T06 — see §9.)*

**F-10-09 — The most important button is too small.** `app_theme.dart` defines `tapTarget = 48` and `primaryActionHeight = 56` (`packages/flutter_shared/lib/theme/app_theme.dart:180-181`), and the file's own header states the intent: "One dominant action per screen, at a 56 dp touch target" (`:14`). The offer card ignores both, hardcoding `height: 46` for accept (`apps/captain/lib/screens/home/offer_card.dart:609`) and `height: 42` for counter, skip and the two bid-sent buttons (`:656, :705, :790, :830`). The rider avatar is 44 dp (`:877`). Every one of these is below the 48 dp floor, on the one card the captain operates while moving. Elsewhere the app gets this right — the active trip panel uses the tokens properly (`apps/captain/lib/screens/home/active_trip_panel.dart:259, 388`) — which makes the offer card an isolated regression rather than a systemic gap. The `FittedBox(fit: BoxFit.scaleDown)` wrappers compound it: with a long Arabic label on a 360 dp screen the text shrinks without any floor.

**F-10-10 — The captain cannot price their own work.** `commission` appears nowhere in `offer_card.dart`, and the counter-offer sheet has no net calculation (grep for `commission`/`net` in `packages/flutter_shared/lib/widgets/counter_offer_sheet.dart` returns nothing). So the captain is asked to accept 85 EGP, or to counter at 100 EGP, without being shown what either leaves them after the platform's cut. The presets at `:19` make countering fast and uninformed. Showing "you keep ~68 EGP" under each preset is a small change with a large effect on trust, and the arithmetic already exists server-side.

**F-10-11 — Trip history hides the deduction.** `_TripCard` renders `final_fare` with an `estimated_fare` fallback (`apps/captain/lib/screens/home/trips_tab.dart:241-243`). The `commission` column is selected into the row (`migrations/0001_init.sql:75`) but never displayed, and there is no tap-through detail screen. A captain who completed a 120 EGP trip and received 96 EGP sees "120" in their history forever. The aggregate screen does this correctly (`apps/captain/lib/screens/earnings/earnings_screen.dart:199-241`); the per-trip view simply never got the same treatment.

**F-10-12 — "Arrived" is unvalidated.** No distance comparison exists between the captain's last known position and `pickup_lat`/`pickup_lng` before the `arrived` transition is accepted (`apps/api/src/routes/trips.ts:891-944`). Beyond the fraud angle covered in F-10-05, the honest failure matters more: a captain who taps arrived while still three streets away starts the rider's "your captain is here" expectation early, and the rider walks out to an empty kerb.

**F-10-13 — Waiting time is free to the rider and unpaid to the captain.** No `wait_fee`, `waiting_fee`, `wait_charge` or waiting timer exists anywhere in the repository. `per_min` pricing bills from `started_at`, not from `arrived_at`, so every minute the captain waits at the pickup is uncompensated. The behavioural consequence is predictable and well documented in this market: captains stop waiting, cancel, and the rider bears it.

**F-10-14 — The captain accepts blind.** `RideRequestModel` carries rider id, name, phone and avatar, and no rating (`apps/captain/lib/models/ride_request_model.dart:1-57`). The nearby-requests query joins `users` for name, email, phone and avatar only (`apps/api/src/routes/captain.ts:375-398`). Ratings exist in the schema (`migrations/0001_init.sql:105`) and the rider is shown the captain's rating, but the reverse is never surfaced. In a market where captains carry real personal risk, one-way rating visibility is both a safety gap and an equity problem.

**F-10-15 — Hot-path text is too small to read at speed.** The trip stepper labels are 10.5 sp (`apps/captain/lib/screens/home/active_trip_panel.dart:698`), badge counts 10 sp (`:597`), the offer card's route labels 10.5 sp (`apps/captain/lib/screens/home/offer_card.dart:572`) and its address lines 11 sp (`:401`). For information a driver must absorb in a glance, 14 sp is the practical floor and 16 sp is better. These sizes are legible on a desk and not in a car.

**F-10-16 — The brand colour fails WCAG AA on the app's own surfaces.** Ratios computed from the tokens with the WCAG 2.1 formula:

| Foreground | Background | Ratio | AA body (4.5:1) |
|---|---|---|---|
| `primary` #4E842D | `lightPanel` #FFFFFF | 4.50 | pass, by 0.00 |
| `primary` #4E842D | `lightBg` #F7F6F4 | **4.17** | **fail** |
| `primary` #4E842D | `lightSurface` #F3F4F6 | **4.09** | **fail** |
| `lightMuted` #6B7280 | `lightPanel` #FFFFFF | 4.83 | pass |
| `lightMuted` #6B7280 | `lightBg` #F7F6F4 | **4.48** | **fail** |
| `lightMuted` #6B7280 | `lightSurface` #F3F4F6 | **4.39** | **fail** |
| white | `lime` #C1F11D | **1.32** | **fail** |

Tokens at `packages/flutter_shared/lib/theme/app_theme.dart:36, 101, 103, 106, 137`. The brand green passes on pure white by a margin of zero and fails on both of the app's other light surfaces — which is where the stepper labels, meta chips and status text actually sit. Direct Cairo sunlight cuts effective contrast further; 7:1 is the realistic target outdoors, and nothing in the light theme except dark-on-lime reaches it. The white-on-lime pairing at 1.32:1 is invisible, and a comment at `apps/captain/lib/screens/home/active_trip_panel.dart:265` shows this has already been hit once as a live bug.

**F-10-17 — Uploads are silent and unbounded.** None of the three upload paths checks file size before sending (`apps/captain/lib/screens/documents/documents_onboarding_screen.dart:227`, `apps/captain/lib/screens/onboarding/onboarding_screen.dart:309`, `apps/captain/lib/screens/documents/document_upload_screen.dart:738`); the server rejects at 10 MB (`apps/api/src/routes/captain.ts:631`). `imageQuality: 75` on a 12 MP phone camera still yields 3–6 MB. On 3G that is 30–90 seconds during which the UI shows an indeterminate spinner with no byte count (`apps/captain/lib/screens/documents/documents_onboarding_screen.dart:239-252`), because the `StreamedResponse` is never inspected for progress. The captain cannot distinguish "uploading" from "frozen", and a size rejection arrives only after the whole file has crossed the network.

**F-10-18 — Approval is not pushed.** The admin review endpoint updates the database and flips `approval_status` without sending anything (`apps/api/src/routes/admin.ts:820-858`). The captain learns of approval only from the 30-second `/auth/me` poll (`apps/captain/lib/services/captain_state.dart:107`), which is skipped while backgrounded. A captain approved at 09:00 may not discover it until they next open the app. Approval is the highest-intent moment in the entire funnel and the app stays silent through it.

**F-10-19 — Trip mutations are lost offline.** `arrived()`, `startTrip()` and `complete()` post directly and throw on failure (`apps/captain/lib/services/captain_state.dart:1047-1065`); there is no queue, no retry and no local persistence — `activeTrip` is an in-memory map and the only `SharedPreferences` keys are `user`, `searchRadiusKm` and `themeMode`. The trip itself survives, because `refreshOffers()` re-reads server state on resume, so this is not data loss. But a captain who completes a trip in an underground car park gets an error, and must remember to press the button again once they surface.

**F-10-20 — Multi-stop cannot be driven.** `trips.waypoints` is stored and populated at creation (`apps/api/src/routes/trips.ts:476`), but `active_trip_panel.dart` has no waypoint rendering and the state machine has no "advance to next stop" transition. Any multi-stop or intercity trip sold to a rider cannot be executed correctly by the captain.

**F-10-21 — SOS is one tap only from one tab.** The SOS control is a floating button on the map tab (`apps/captain/lib/screens/home/main_shell.dart:739-752`), positioned bottom-end within thumb reach — genuinely good when the captain is on the map, which is the default. From the earnings, trips, requests or settings tabs it requires returning to the map first. The settings entry (`apps/captain/lib/screens/profile/settings_screen.dart:431`) is also two taps. An emergency control should be reachable in one action from every screen.

**F-10-22 — Location pushes are dropped exactly when they matter.** `/captain/location` is rate-limited to 30 requests per 60 seconds (`apps/api/src/routes/captain.ts:190-197`). On a trip the distance filter is 10 m (`apps/captain/lib/services/captain_state.dart:623-626`), so at 30 km/h (8.3 m/s) the client generates roughly 50 pushes per minute and at 50 km/h roughly 84. Everything above 30 is refused, and the client swallows the failure silently (`:682`). The faster the captain drives, the more of their track is discarded — the opposite of what the rider's live map needs. Either the client should throttle to match the server's budget, or the endpoint should accept batched fixes.

**F-10-23 — Presence goes stale in the database.** The sweep that clears `is_online` for captains last seen more than five minutes ago lives inside `GET /admin/captains` (`apps/api/src/routes/admin.ts:237`). The cron handler runs expired-data cleanup and scheduled dispatch but no presence sweep (`apps/api/src/index.ts:267-333`). Dispatch itself is protected because `GeoCell` expires presence on a three-minute alarm (`apps/api/src/durable-objects/GeoCell.ts:31-34`), so this is not a matching bug — but `captains.is_online` stays `1` indefinitely after an OS kill, so every supply metric and the admin roster overstate the live fleet until someone happens to load a dashboard page.

**F-10-24 — The app blames GPS for account problems.** Every failure from the online toggle is written to `gpsError` regardless of cause (`apps/captain/lib/services/captain_state.dart:600-607`) and surfaced through `_showGpsDialog` (`apps/captain/lib/screens/home/main_shell.dart:359-365`). A captain rejected with 403 `NOT_APPROVED` is told to check their location settings. They will restart their phone, toggle GPS, and eventually call support about the wrong problem.

**F-10-25 — "Today" does not exist.** Earnings use `new Date(Date.now() - 7 * 864e5)` (`apps/api/src/routes/captain.ts:275`) and the wallet uses SQLite `datetime('now','-7 days')` (`apps/api/src/routes/wallet.ts:78`) — both rolling seven-day UTC windows. Egypt is UTC+2/+3, so a Sunday-evening trip lands in a different bucket depending on the hour the captain opens the app, and there is no daily figure at all. Every driver in this market checks today's take before they decide whether to keep driving. The label is at least honest ("آخر ٧ أيام"), but honest about the wrong number.

**F-10-26 — Commission debt is invisible and unenforced.** `POST /captain/online` checks `approval_status` and coordinates only (`apps/api/src/routes/captain.ts:131-155`); there is no balance check. `wallet_balance` is `REAL NOT NULL DEFAULT 0` with no non-negative constraint (`migrations/0003_global_transport.sql:45`). So a cash-heavy captain accrues arbitrary negative balance, is never shown it (F-10-04 hides it), is never blocked, and is never asked to settle. Careem's Egyptian captains see their debt balance on the home screen precisely because this is how a cash marketplace leaks revenue.

---

## 5. Benchmark gap

Competitor mechanisms are marked **confident** where they are directly observable in the driver apps, and **assumed** where they are inferred from public documentation or reporting.

### The offer moment

| Mechanism | Uber Driver | inDrive Driver | Careem Captain | Synaptic Go |
|---|---|---|---|---|
| Audible alert | Loud, distinct, repeating (confident) | Yes, distinct per offer type (confident) | Yes (confident) | **None** |
| Alert configurable | Volume + sound choice (confident) | Yes (assumed) | Yes (assumed) | Single shared channel, no sound |
| Decision window | ~10–15 s with a visible ring (confident) | Longer; bid-based, less time-critical (confident) | ~15 s (assumed) | 15 s, unanchored |
| Net earning shown pre-accept | Yes — driver-facing payout, not rider fare (confident) | Yes, driver sets the price (confident) | Yes (confident) | **No** |
| Rider rating pre-accept | Yes (confident) | Yes (confident) | Yes (assumed) | **No** |
| Accept target size | Full-width, ≥ 56 dp (confident) | Full-card tap (confident) | Full-width (assumed) | 46 dp |
| Decline reaches dispatch | Yes — immediate re-dispatch (confident) | Yes (confident) | Yes (assumed) | **No endpoint exists** |

The gap that matters is not the 15-second window; it is that Synaptic Go asks a captain to make a financial decision without telling them the financial outcome, and then does not make a sound when it asks. inDrive is the closest model for this product, and its whole premise is that the driver names a price they understand.

### Navigation

Uber embeds turn-by-turn with voice and hands off to Google Maps or Waze as a preference (confident). inDrive and Careem both hand off to external navigation with a persistent return affordance (confident for inDrive, assumed for Careem). All three keep a foreground service alive so the driver remains dispatchable while navigating (confident — this is what the persistent Android notification in each app is).

Synaptic Go has neither the embedded navigation nor the safe hand-off. It has a follow-me camera called turn-by-turn, and leaving the app costs the captain their connection. This is the widest single gap in the review.

### Earnings

Uber's weekly summary breaks out fares, tips, promotions and deductions, and every trip has a per-trip receipt (confident). Careem shows commission owed and a running debt balance for cash captains, and blocks going online past a debt threshold (confident — it is a standard cash-market control). inDrive takes commission per accepted order and shows the balance prominently (confident).

Synaptic Go's aggregate breakdown is genuinely competitive — gross, commission and net, stated as arithmetic. Then it stops. There is no per-trip receipt, no "today", no debt visibility, and the balance it does show is wrong for cash trips. The app is one screen away from parity and three findings away from being trusted.

### Working conditions

| Dimension | Competitors | Synaptic Go |
|---|---|---|
| Stays dispatchable with screen off | Yes, foreground service (confident) | **No** |
| Survives a 10 h shift without re-login | Yes (confident) | **No — ~20 logouts** |
| Waiting time compensated | Uber and Careem: yes after a threshold (confident) | No |
| Trip start verified | PIN or rider confirmation (confident for Uber, assumed for Careem) | No |
| Acceptance/cancellation scorecard | Uber: yes, with consequences (confident) | No |

### Where Synaptic Go is ahead

Worth stating, because a review that only lists deficits is not accurate. The three-way offer response — accept, counter, skip — with preset counter increments is better than Uber's binary and is a genuine expression of the inDrive model. The gross → commission → net arithmetic on the earnings screen is more transparent than Careem's default view. The document rejection loop, with a reason rendered per document and a re-upload button in place, is better than most local competitors manage. And the online toggle's refusal to be optimistic is a small, correct decision that many larger apps get wrong.

---

## 6. Improvement plan

Ordered by the sequence in which they should be done, not by severity alone: P0.1 and P0.6 are paired because fixing either alone leaves the captain disconnected, and P0.4 precedes any payout work because everything downstream reads that balance.

Migrations are numbered from `0020` — `0019_trips_captain_status_index.sql` is the current head.

### P0.1 — A real Android foreground service

- **Goal** — A captain who is online stays online: dispatchable, and visible to their rider, with the screen off or another app in front.
- **Design** — Add a bound foreground service with `foregroundServiceType="location"`, started from `setOnline(true)` and stopped from `setOnline(false)` and on trip completion when offline. It owns the GPS subscription and the location push. Its persistent notification is not chrome — make it the captain's status line: "Online · 3 offers today · tap to return", and keep it accurate. Then narrow `handleAppLifecycleState`: stop treating `inactive` and `hidden` as backgrounding at all (they fire on notification shades and permission dialogs), and on `paused` keep the GPS stream and location push running under the service while pausing only the map camera and any UI-only timers. Delete the "FCM still wakes the app" comment or make it true by giving `fcmBackgroundHandler` a real job.
- **Files to change** — `apps/captain/android/app/src/main/AndroidManifest.xml` (service element, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_LOCATION`, `ACCESS_BACKGROUND_LOCATION`, `WAKE_LOCK`); a new Kotlin service under `apps/captain/android/app/src/main/kotlin/tech/synapticstudio/synaptic_go_captain/`; `apps/captain/lib/services/captain_state.dart:1081-1104` (lifecycle), `:637-660` (stream ownership); `apps/captain/lib/main.dart:13-16` (background handler); `apps/captain/pubspec.yaml` (a foreground-task package unless the service is written natively).
- **DB** — none.
- **API contract** — none. Consider accepting a batched body on `POST /captain/location` (`{fixes:[{lat,lng,at}]}`) to pair with P1.7.
- **Effort** — L.
- **Risk** — Android 14+ requires the `FOREGROUND_SERVICE_LOCATION` permission and a matching declared type; getting this wrong is a Play Store rejection, not a runtime bug. Background-location access also needs a Play Console declaration and a demo video. Battery drain will *rise* — that is the intended trade, but it must be measured (P1.7) and not discovered by captains. Rollback is a feature flag that reverts to foreground-only behaviour.
- **Acceptance criteria** — With the screen locked for 10 minutes and the captain online: location continues to reach `/captain/location`; an offer pushed over FCM or WebSocket is received and alerts; `last_seen_at` stays fresh. Switching to Google Maps for 5 minutes during a trip keeps the rider's view of the captain moving. Pulling down the notification shade changes nothing.
- **Tests** — Instrumented test on an Android 13 and an Android 14 device covering screen-off, app-switch and Doze (`adb shell dumpsys deviceidle force-idle`). A soak test asserting continuous location coverage across a simulated 10-hour shift.

### P0.2 — Persist the rotated refresh token

- **Goal** — One login lasts a whole shift.
- **Design** — In the 401 branch, read `refreshToken` from the response and write it to secure storage before retrying, exactly as the rider app does at `apps/rider/lib/services/app_state.dart:206, 227-228`. Separate genuine auth rejection from transport failure: only call `logout()` on a 401/403 from the refresh endpoint itself; on a timeout or socket error, retry with backoff and keep the session. Add a proactive refresh timer at ~12 minutes so expiry is not discovered through a user-visible failure. Guard against concurrent refreshes with a single-flight future so parallel 401s do not each burn a rotation.
- **Files to change** — `apps/captain/lib/services/captain_state.dart:249-276`.
- **DB** — none.
- **API contract** — none; the server already returns the rotated token.
- **Effort** — S. This is the highest value-to-cost fix in the document.
- **Risk** — Very low. The single-flight guard is the only subtle part: without it, two simultaneous 401s can rotate twice and revoke the token that the second response is about to store.
- **Acceptance criteria** — A 10-hour authenticated session with traffic every few minutes never reaches the login screen. Airplane mode for 60 seconds spanning an access-token expiry does not log the captain out. Two concurrent requests hitting 401 together produce exactly one rotation.
- **Tests** — Unit test with a mocked 401 → refresh → retry sequence asserting the new refresh token was written. Unit test asserting a network exception during refresh does *not* call `logout()`. Integration test running three rotation cycles back to back.

### P0.3 — Make the offer audible

- **Goal** — A captain with the phone mounted, engine running and a window down notices every offer.
- **Design** — Add an audio dependency and play a distinct, looping alert for the duration of the offer window, ducking to respect the captain's media but not their silent switch — an offer is an alarm, not a notification. Split the FCM channels: `offers` (max importance, custom sound, bypass Do Not Disturb), `trip_updates` (high), `payments` (default), so the captain can mute money noise without muting income. Keep the existing haptic ladder and escalate it in the final five seconds. Add a volume/sound preference in settings.
- **Files to change** — `apps/captain/pubspec.yaml`; `packages/flutter_shared/lib/services/fcm_service.dart:15-20, 78-98`; `apps/captain/lib/screens/home/offer_card.dart:92-115`; `apps/captain/android/app/src/main/AndroidManifest.xml:36-38` (default channel id); `apps/captain/lib/screens/profile/settings_screen.dart`; add `apps/captain/assets/audio/offer.ogg` and register it in `pubspec.yaml`.
- **DB** — none.
- **API contract** — FCM payloads must set `android_channel_id: "offers"` for offer pushes — `apps/api/src/lib/notifications.ts`.
- **Effort** — M.
- **Risk** — Channel importance is immutable after creation on Android; shipping the wrong settings means a new channel id is required to correct it, so get the definition right before release. Bypassing Do Not Disturb needs an explicit user grant.
- **Acceptance criteria** — An offer arriving with the app foregrounded, backgrounded or the screen off produces an audible alert on a device at 50 % media volume. Muting the payments channel leaves the offer alert audible.
- **Tests** — Manual matrix across foreground/background/screen-off and ringer/vibrate/DND. Automated check that offer pushes carry the `offers` channel id.

### P0.4 — One balance, computed one way

- **Goal** — The number on the wallet screen is the number the captain can withdraw.
- **Design** — Make `users.wallet_balance` the single source of truth and have `GET /captain/wallet` return it, rather than recomputing from a filtered transaction sum. Keep the ledger as the audit trail and add a reconciliation job that asserts `SUM(credits) - SUM(debits) == users.wallet_balance` per captain and alerts on drift. Surface a negative balance explicitly as "commission owed" rather than as a negative number, and pair the withdrawal refusal with the actual available figure instead of a bare error.
- **Files to change** — `apps/api/src/routes/wallet.ts:57-72` (balance), `:101-120` (refusal message); `apps/captain/lib/screens/earnings/wallet_screen.dart:255-262, 337-345`.
- **DB** — `0020_wallet_balance_reconciliation.sql`: a `wallet_reconciliation` table (`user_id`, `ledger_sum`, `stored_balance`, `delta`, `checked_at`), plus `CHECK` documentation of the intended invariant. Do not add a non-negative constraint yet — debt is legitimate; see P2.4.
- **API contract** — `GET /captain/wallet` response gains `available: number`, `commissionOwed: number`, and `ledgerSum: number` for debugging; `balance` retained as an alias for one release, then removed. `POST /captain/wallet/payout` 409 body gains `{available: number}`.
- **Effort** — M.
- **Risk** — Any existing captain whose displayed balance was inflated will see it drop on release. That is the correct value, but it needs a comms plan and an audit of live data before deploy, not after.
- **Acceptance criteria** — After a cash trip with commission C, the wallet balance falls by exactly C. The wallet figure and the maximum successful withdrawal are always equal. The reconciliation job reports zero drift across a seeded set of 1,000 mixed cash and card trips.
- **Tests** — Integration test: complete a cash trip, assert wallet response matches `users.wallet_balance`, attempt a withdrawal of exactly that amount and assert success. Property test over random trip sequences asserting the ledger invariant.

### P0.5 — Trip integrity: proximity on arrival, code on start

- **Goal** — A trip cannot be started without the rider, and "arrived" means arrived.
- **Design** — Generate a four-digit code per trip at assignment, show it to the rider, and require it on `POST /trips/:id/start`. Provide a rider-side "confirm captain arrived" fallback so a rider without the app open is not stranded, and an ops override with an audit entry. Separately, gate the `arrived` transition on a server-side haversine check between the captain's last known fix and the pickup, with a generous radius (250 m) to allow for GPS error in dense Cairo streets, returning a specific error code the app can explain.
- **Files to change** — `apps/api/src/routes/trips.ts:891-948`; `apps/api/src/lib/schemas.ts`; `apps/captain/lib/screens/home/active_trip_panel.dart:441-475`; `apps/captain/lib/services/captain_state.dart:1047-1062`; rider-side display of the code (T09 to own the rider screen).
- **DB** — `0021_trip_start_code.sql`: `ALTER TABLE trips ADD COLUMN start_code TEXT`, `ADD COLUMN start_code_verified_at TEXT`, `ADD COLUMN arrived_lat REAL`, `ADD COLUMN arrived_lng REAL`.
- **API contract** — `POST /trips/:id/start` accepts `{startCode: string}`; returns 400 `INVALID_START_CODE`. `POST /trips/:id/arrived` returns 400 `TOO_FAR_FROM_PICKUP` with `{distanceM}`.
- **Effort** — M.
- **Risk** — A rider whose phone is dead cannot present a code; the fallback and override paths are mandatory, not optional. The proximity radius will need tuning — too tight and honest captains are blocked in urban canyons. Ship the check in log-only mode first and measure the distribution before enforcing.
- **Acceptance criteria** — `start` without a valid code is refused. `arrived` beyond 250 m is refused with a distance in the error. Both refusals render as human-readable Arabic in the app, not raw codes.
- **Tests** — API tests for the happy path, wrong code, missing code and override. A log-only shadow period with a report on the observed arrival-distance distribution before enforcement is enabled.

### P0.6 — Navigation the captain can actually follow

- **Goal** — The captain can drive to the pickup and the destination without losing offers, without losing the rider's live view, and without guessing at junctions.
- **Design** — Two stages, and the first ships in P0. **Stage one (P0):** stop calling the follow-me camera "turn-by-turn". Add an explicit hand-off to Google Maps or Waze as the captain's stored preference, launched with the destination pre-filled, and rely on P0.1 so leaving the app costs nothing. Add a persistent return affordance — the foreground-service notification from P0.1 becomes "Trip in progress · tap to return", and an Android bubble or a re-entry banner brings them back for the next action. Follow the `tel:` precedent at `apps/captain/lib/screens/home/active_trip_panel.dart:128-131`: launch directly and handle the failure rather than pre-checking `canLaunchUrl`, and declare the map intents in `<queries>` so any remaining checks work on Android 11+. **Stage two (P2.5):** real embedded guidance.
- **Files to change** — `packages/flutter_shared/lib/widgets/navigation_button.dart:29-45`; `apps/captain/android/app/src/main/AndroidManifest.xml:40-45` (`<queries>` for `google.navigation:`, `geo:` and the Waze package); `apps/captain/lib/screens/home/active_trip_panel.dart:414-421`; `apps/captain/lib/screens/profile/settings_screen.dart` (preferred navigation app); rename `startInAppNavigation` and the three comments that overclaim it.
- **DB** — none.
- **API contract** — none.
- **Effort** — M for stage one.
- **Risk** — Depends entirely on P0.1; shipping the hand-off without the foreground service makes the problem worse by encouraging the captain to leave. Do not ship these separately.
- **Acceptance criteria** — Tapping navigate opens the captain's chosen app with the destination set, on Android 11, 13 and 14. Returning to the app is one tap from the notification. Location and offers continue throughout.
- **Tests** — Device matrix with and without Google Maps and Waze installed. An end-to-end test that backgrounds the app for five minutes mid-trip and asserts continuous location coverage.

### P1.1 — Show the money before the commitment

- **Goal** — The captain never accepts or counters a price without knowing what they keep.
- **Design** — Return a `captainNet` and `commissionRate` on every offer payload and render the net under the fare on the offer card, with the gross available but secondary. Under each counter-offer preset, show the resulting net. The arithmetic already exists server-side in the pricing path; this is a plumbing and layout change, not a new calculation.
- **Files to change** — `apps/api/src/routes/captain.ts:375-398` (offers query and shape); `apps/api/src/lib/pricing.ts`; `apps/captain/lib/screens/home/offer_card.dart:390-460, 600-650`; `packages/flutter_shared/lib/widgets/counter_offer_sheet.dart:180-200`; `apps/captain/lib/models/ride_request_model.dart`.
- **DB** — none.
- **API contract** — Offer payload gains `captainNet: number`, `commission: number`, `commissionRate: number`.
- **Effort** — S.
- **Risk** — Showing commission plainly will provoke questions the platform must be ready to answer. That is a feature.
- **Acceptance criteria** — Offer card shows net for every offer. Each counter preset shows its net. Net plus commission equals gross in every rendered case.
- **Tests** — Widget tests over a fare matrix; a golden test at the smallest supported width with the longest Arabic string.

### P1.2 — Per-trip receipts and "today"

- **Goal** — Every completed trip explains itself, and the captain can see today's earnings.
- **Design** — Make each history card tappable to a receipt showing gross, commission with its rate, any adjustment or promotion, and net. Add a `today` block to the earnings endpoint computed in Africa/Cairo, and switch the weekly figure from a rolling UTC 7-day window to a Cairo-local calendar week with the previous week available for comparison.
- **Files to change** — `apps/captain/lib/screens/home/trips_tab.dart:200-260`; a new `apps/captain/lib/screens/earnings/trip_receipt_screen.dart`; `apps/api/src/routes/captain.ts:270-300`; `apps/api/src/routes/wallet.ts:73-90`.
- **DB** — none; `trips.commission` already carries the value.
- **API contract** — `GET /captain/earnings` gains `today: {trips, gross, commission, net}` and `week` becomes calendar-week with an explicit `from`/`to`. `GET /trips/:id/receipt` returns the per-trip breakdown.
- **Effort** — M.
- **Risk** — Timezone handling must be done with a real zone (`Africa/Cairo`), not a fixed `+02:00` offset, or it breaks on the DST transition.
- **Acceptance criteria** — A trip completed at 23:30 Cairo time appears in that day's total and not the next. Receipt net matches the wallet movement for the same trip, to the piastre.
- **Tests** — Unit tests across the DST boundary and around local midnight. Reconciliation test asserting the sum of receipts equals the period aggregate.

### P1.3 — An honest offer clock and a real decline

- **Goal** — The countdown means something, and skipping an offer helps the next rider.
- **Design** — Send `expiresAt` on the offer payload and drive the ring from `expiresAt - now` rather than from mount, clamping to zero and reconciling clock skew against the server time in the response. Add `POST /trips/:id/decline`, record it, and have `OfferScheduler` advance the wave as soon as every captain in the current wave has declined instead of waiting out its alarm. Persist declined ids so a restart does not resurrect them.
- **Files to change** — `apps/api/src/durable-objects/OfferScheduler.ts:44-60, 91-135`; `apps/api/src/routes/trips.ts`; `apps/captain/lib/screens/home/offer_card.dart:69-115`; `apps/captain/lib/services/captain_state.dart:1039-1045`.
- **DB** — `0022_trip_offer_declines.sql`: `trip_offer_declines(trip_id, captain_id, declined_at, reason)` with a unique pair, for dispatch analytics as well as scheduling.
- **API contract** — Offer payload gains `expiresAt: string` and `serverTime: string`. New `POST /trips/:id/decline` accepting an optional `{reason}`.
- **Effort** — M.
- **Risk** — Fast wave advancement interacts with dispatch fairness — this changes matching behaviour and must be agreed with **T06** before it ships, not after.
- **Acceptance criteria** — A card rendered 3 s after issue shows ~12 s, not 15. All three captains declining advances the wave in under a second. Restarting the app does not re-show a declined offer.
- **Tests** — Unit tests with an injected clock and a simulated 2 s delivery delay. A dispatch simulation comparing time-to-match before and after.

### P1.4 — Driving-grade touch targets and type

- **Goal** — Every control the captain uses in motion is hittable, and every label is readable, at a glance.
- **Design** — Replace the hardcoded heights in the offer card with `AppTokens.primaryActionHeight` for accept and `AppTokens.tapTarget` for counter and skip. Raise every hot-path label to a 14 sp floor and give the `FittedBox` wrappers a `minFontSize` so nothing scales into illegibility. Add a lint or a widget test that fails when a button in a driving surface is built with a literal height.
- **Files to change** — `apps/captain/lib/screens/home/offer_card.dart:609, 656, 705, 790, 830, 877, 401, 572, 441`; `apps/captain/lib/screens/home/active_trip_panel.dart:597, 698`; `packages/flutter_shared/lib/theme/app_theme.dart` (a documented driving type scale).
- **DB** — none.
- **API contract** — none.
- **Effort** — S.
- **Risk** — Larger type and targets need more vertical space; the offer card will need a layout pass to avoid overflow at 360 dp width in Arabic. Golden tests at the smallest supported size are the guard.
- **Acceptance criteria** — No interactive element under 48 dp on the offer card or the active trip panel. No text under 14 sp on either. Both render without overflow at 360×640 in Arabic and English.
- **Tests** — Golden tests at 360×640 and 320×568 in both locales; an automated audit walking the widget tree for undersized targets.

### P1.5 — Contrast for daylight

- **Goal** — Text is readable through a windscreen in Cairo at midday.
- **Design** — Darken `primary` until it clears 4.5:1 on `lightBg` and `lightSurface`, not merely on pure white — roughly `#3F6B24` reaches ~5.6:1 on `lightBg`. Darken `lightMuted` to clear 4.5:1 on every light surface it is used on. Restrict `lightFaint` to non-informational decoration by policy and enforce it in review. Add a unit test that computes the ratio for every foreground/background token pair the theme permits and fails the build below threshold — this class of bug should never be found by reading code again.
- **Files to change** — `packages/flutter_shared/lib/theme/app_theme.dart:36, 50, 101-107, 137`; a new `packages/flutter_shared/test/contrast_test.dart`.
- **DB** — none.
- **API contract** — none.
- **Effort** — S for the tokens, M including the brand conversation.
- **Risk** — `primary` is the brand colour; changing it is a brand decision, not only an engineering one. If marketing will not move it, the alternative is to stop using it for text and keep it for fills only. Either resolution is acceptable; the current state is not. See §10.
- **Acceptance criteria** — Every text token/background pair used in the light theme is ≥ 4.5:1, and every pair used on the offer card and active trip panel is ≥ 7:1. The contrast test passes in CI.
- **Tests** — The generated pairwise contrast test; a manual outdoor read of the offer card and trip stepper in direct sun.

### P1.6 — Close the onboarding leaks

- **Goal** — Nobody is lost to a silent upload, an unexplained wait or a dead button.
- **Design** — Check file size before upload and compress or refuse locally with a clear message. Show real byte progress by reading the `StreamedResponse` rather than an indeterminate spinner. Push an FCM notification on every approval or rejection decision. Give the status screen a concrete expectation ("usually reviewed within 24 hours") and a support contact. Wire the dead help button to the sheet the wizard already has, and give the documents grid the account-level rejection banner the other two screens already render.
- **Files to change** — `apps/captain/lib/screens/documents/documents_onboarding_screen.dart:227, 239-252, 341-344, 367`; `apps/captain/lib/screens/onboarding/onboarding_screen.dart:309-332`; `apps/captain/lib/screens/documents/document_upload_screen.dart:738`; `apps/captain/lib/screens/documents/document_status_screen.dart:227`; `apps/api/src/routes/admin.ts:820-858` (send push on decision); `apps/api/src/lib/notifications.ts`.
- **DB** — none.
- **API contract** — none; reuses the existing device-token push path.
- **Effort** — M.
- **Risk** — Client-side compression must not degrade a licence photo below what a reviewer can read. Cap the longest edge rather than lowering quality further, and have ops confirm legibility on a sample before rollout.
- **Acceptance criteria** — A 6 MB photo is compressed or refused in under a second with a clear message. Upload progress advances visibly on a throttled 3G profile. An approval decision produces a push within 30 seconds with the app closed. No screen in the document flow has an interactive control that does nothing.
- **Tests** — Upload tests at 1/5/12 MB on a throttled profile. Push delivery test with the app terminated.

### P1.7 — Offline queue, and the battery and data budget

- **Goal** — A tunnel does not cost a trip transition, and a shift does not cost a battery or a data bundle.
- **Design** — Persist `activeTrip` and queue `arrived`/`start`/`complete` mutations with their idempotency keys, replaying on reconnect with the server as the arbiter. Then take the budget: batch location fixes into a single request every 5 s under the server's 30/min limit rather than firing per fix and losing the excess (F-10-22); widen the idle distance filter to 100 m; drop the `/auth/me` poll from 30 s to 300 s once the captain is approved and replace its onboarding role with the P1.6 push; back the socket-down offers poll off from 8 s to 15 s after the first minute. Instrument the result.
- **Files to change** — `apps/captain/lib/services/captain_state.dart:107, 619-626, 660-690, 758-800, 1047-1065`; `apps/api/src/routes/captain.ts:190-197` (accept batched fixes).
- **DB** — none client-side beyond local storage; consider `shared_preferences` for the queue or a light local store if the queue grows.
- **API contract** — `POST /captain/location` accepts `{fixes: [{lat, lng, at}]}` alongside the current single-fix shape.
- **Effort** — M.
- **Risk** — Replaying a queued `complete` after the server already completed the trip must be a no-op; the existing idempotency keys make this safe if they are reused rather than regenerated.
- **Acceptance criteria** — Five minutes offline mid-trip, then reconnect: every action taken offline is applied exactly once. A measured 10-hour shift draws ≤ 2,700 mAh and ≤ 4 MB with the socket up. No location fix is dropped by the rate limiter at 80 km/h.
- **Tests** — Airplane-mode integration test across each transition. An instrumented shift measured with Battery Historian and a proxy byte counter, reported against the §3.8 table.

### P2.1 — Waiting timer and waiting charge

- **Goal** — The captain is paid for time the rider costs them, and has no incentive to abandon a pickup.
- **Design** — Start a visible timer at `arrived`, free for a grace period (3 minutes is the regional norm), then accrue a per-minute wait fee into the fare, shown live to both sides. Add a "rider not here" path after the grace period that cancels with the wait fee retained and no cancellation penalty.
- **Files to change** — `apps/api/src/routes/trips.ts` (completion pricing, cancellation), `apps/api/src/lib/pricing.ts`; `apps/captain/lib/screens/home/active_trip_panel.dart`; rider-side display (**T09**).
- **DB** — `0023_waiting_time.sql`: `trips.waiting_seconds INTEGER DEFAULT 0`, `trips.wait_fee REAL DEFAULT 0`; wait-fee rate into `system_config` (`migrations/0016_system_config.sql`).
- **API contract** — Completion response includes `waitFee` and `waitingSeconds`; new `POST /trips/:id/rider-no-show`.
- **Effort** — M.
- **Risk** — A wait fee is a rider-visible price change and needs a product and comms decision before it ships. Grace period and rate belong in config, not code.
- **Acceptance criteria** — Timer starts on `arrived` and is visible to both parties. Fee accrues only past the grace period and appears on the receipt from P1.2.
- **Tests** — Pricing unit tests across grace boundaries; end-to-end test of the no-show path.

### P2.2 — Multi-stop execution

- **Goal** — Trips sold with waypoints can be driven.
- **Design** — Render the waypoint list in the trip panel with per-stop arrive/depart transitions, extend the state machine to advance through stops, and route to the next stop rather than the final destination.
- **Files to change** — `apps/captain/lib/screens/home/active_trip_panel.dart`; `apps/api/src/routes/trips.ts:891-948` (state machine); `packages/flutter_shared/lib/widgets/navigation_button.dart` (next-stop target).
- **DB** — `0024_trip_stop_progress.sql`: `trip_stops(trip_id, seq, lat, lng, arrived_at, departed_at)` normalising the current `waypoints` blob.
- **API contract** — `POST /trips/:id/stops/:seq/arrive` and `.../depart`.
- **Effort** — L.
- **Risk** — Interacts with pricing and with intercity (**T13**); agree the fare model for stops first.
- **Acceptance criteria** — A three-stop trip can be completed with correct per-stop timestamps and correct total fare.
- **Tests** — End-to-end multi-stop trip; state-machine unit tests over out-of-order transitions.

### P2.3 — Rider rating before accepting

- **Goal** — The captain can make an informed and safer decision.
- **Design** — Join the rider's aggregate rating and completed-trip count into the offers query and render them next to the rider's name, with a "new rider" state rather than a misleading zero.
- **Files to change** — `apps/api/src/routes/captain.ts:375-398`; `apps/captain/lib/models/ride_request_model.dart`; `apps/captain/lib/screens/home/offer_card.dart:430-460`.
- **DB** — none if rider aggregates already exist on `users`; otherwise `0025_rider_rating_aggregate.sql` adding `rider_rating_avg` and `rider_rating_count` maintained on rating insert.
- **API contract** — Offer payload gains `riderRating: number|null` and `riderTrips: number`.
- **Effort** — S.
- **Risk** — Ratings can encode bias; pair with a policy on how low a rating may fall before a rider is addressed directly, and do not let captains see individual ratings, only the aggregate.
- **Acceptance criteria** — Rating and trip count render on every offer, with an explicit new-rider state.
- **Tests** — Query test for the join; widget test for all three states.

### P2.4 — Commission debt: visible, then enforced

- **Goal** — A cash captain always knows what they owe, and the platform stops leaking commission.
- **Design** — Once P0.4 makes the balance honest, surface "commission owed" on the home screen with a settlement path. Then introduce a configurable debt ceiling: past it, going online is refused with a specific, human message and a link to settle — never a silent failure, and never the GPS dialog of F-10-24.
- **Files to change** — `apps/api/src/routes/captain.ts:131-155` (online guard); `apps/captain/lib/screens/home/home_tab.dart`; `apps/captain/lib/screens/earnings/wallet_screen.dart`; `apps/captain/lib/services/captain_state.dart:600-607` (typed errors, not `gpsError`).
- **DB** — debt ceiling into `system_config`; `0026_wallet_settlement.sql` for settlement records if settlement is in-app.
- **API contract** — `POST /captain/online` returns 403 `DEBT_LIMIT_EXCEEDED` with `{owed, limit}`.
- **Effort** — M.
- **Risk** — Blocking a captain from earning is the most severe action the platform can take against its own supply. Ship visibility for a full cycle before enforcement, set the ceiling generously, and give ops an override.
- **Acceptance criteria** — Owed amount visible on the home screen. Past the ceiling, the refusal states the amount and the limit in Arabic and offers a settlement route.
- **Tests** — API tests around the ceiling; UI test asserting the refusal is not routed to the GPS dialog.

### P2.5 — Embedded turn-by-turn guidance

- **Goal** — The captain never has to leave the app to drive.
- **Design** — Request `steps=true` from OSRM, extend `RouteResult` with maneuvers and street names, render an instruction banner and a next-turn card on the trip map, add TTS in Arabic and English, and detect off-route to trigger a re-request. This is the point at which the "turn-by-turn" name becomes accurate.
- **Files to change** — `apps/api/src/lib/routing.ts:11, 30, 47-60`; `apps/captain/lib/screens/home/main_shell.dart` (nav overlay); new guidance widgets in `packages/flutter_shared`; `apps/captain/pubspec.yaml` (TTS).
- **DB** — none.
- **API contract** — Route response gains `steps: [{instruction, maneuver, distanceM, streetName}]`.
- **Effort** — L. Realistically a project, not a ticket.
- **Risk** — OSRM instruction quality for Egyptian street data is unproven and must be evaluated on real Cairo routes before committing; if it is poor, the honest answer is to keep the P0.6 hand-off permanently and drop this item. Voice guidance done badly is worse than none.
- **Acceptance criteria** — A Cairo route renders correct sequential instructions with voice, and re-routes within 10 seconds of a wrong turn.
- **Tests** — Route-quality evaluation over a sampled set of real Cairo trips before any UI work begins.

### P2.6 — Remaining moderate items

Grouped because each is small and none needs its own design: SOS reachable from every tab (F-10-21); move the presence sweep into cron (F-10-23); typed error routing so nothing else surfaces as a GPS problem (F-10-24); `nextPayoutWindow` from `system_config` (F-10-27); per-vehicle-type document catalogue (F-10-31); `CachedNetworkImage` for rider avatars (F-10-32); persist declined offer ids (F-10-33); acceptance and cancellation scorecard (F-10-34); `lightFaint` and star colour (F-10-35, F-10-36); remove the `canLaunchUrl` pre-check from `NavigationButton` (F-10-37). Effort: S each, M in aggregate.

---

## 7. Phasing

| Item | Findings closed | Phase | Effort | Owner type |
|---|---|---|---|---|
| P0.1 Foreground service | F-10-01 | **P0** | L | Flutter + Android native |
| P0.2 Persist rotated refresh token | F-10-02 | **P0** | S | Flutter |
| P0.3 Audible offer alert | F-10-06 | **P0** | M | Flutter + backend (push channel) |
| P0.4 One wallet balance | F-10-04 | **P0** | M | Backend |
| P0.5 Trip integrity | F-10-05, F-10-12 | **P0** | M | Backend + Flutter |
| P0.6 Navigation hand-off | F-10-03, F-10-37 | **P0** | M | Flutter |
| P1.1 Net before commitment | F-10-10 | P1 | S | Backend + Flutter |
| P1.2 Receipts and "today" | F-10-11, F-10-25 | P1 | M | Backend + Flutter |
| P1.3 Honest clock, real decline | F-10-07, F-10-08, F-10-33 | P1 | M | Backend + Flutter |
| P1.4 Touch targets and type | F-10-09, F-10-15 | P1 | S | Flutter |
| P1.5 Contrast | F-10-16, F-10-35, F-10-36 | P1 | S–M | Flutter + brand |
| P1.6 Onboarding leaks | F-10-17, F-10-18, F-10-28, F-10-29, F-10-30 | P1 | M | Flutter + backend |
| P1.7 Offline queue and budget | F-10-19, F-10-22 | P1 | M | Flutter + backend |
| P2.1 Waiting timer and charge | F-10-13 | P2 | M | Backend + Flutter |
| P2.2 Multi-stop | F-10-20 | P2 | L | Backend + Flutter |
| P2.3 Rider rating pre-accept | F-10-14 | P2 | S | Backend + Flutter |
| P2.4 Debt visibility and gate | F-10-26 | P2 | M | Backend + Flutter |
| P2.5 Embedded guidance | — (completes F-10-03) | P2 | L | Flutter + backend |
| P2.6 Remaining moderate items | F-10-21, F-10-23, F-10-24, F-10-27, F-10-31, F-10-32, F-10-34 | P2 | M | Mixed |

**P0 is six items and is not negotiable.** Without P0.1 and P0.2 the app cannot be used for a working day; without P0.3 the captain misses the offers it does deliver; without P0.4 the first cash captain to request a payout concludes the platform is stealing; without P0.5 the trip lifecycle is unverified; and P0.6 is what makes P0.1 worth having. Everything in P1 is about trust and legibility, and everything in P2 is competitive depth.

One sequencing constraint: **P0.1 and P0.6 must ship together.** Shipping the navigation hand-off without the foreground service actively worsens the product by encouraging captains to leave an app that cannot survive being left.

---

## 8. Metrics

Nothing in §6 should be called done on the strength of a merged PR. Each item has a number attached to it.

| Metric | How to measure | Current | Target |
|---|---|---|---|
| Forced logouts per captain-shift | Count `logout()` calls not initiated by the user | ~20 (derived from a 15 min TTL and a dropped rotation; **needs-check** against telemetry once instrumented) | < 0.1 |
| Location coverage while online | Share of online minutes with a fix in the preceding 60 s | Unknown; zero while backgrounded on Android | > 98 % |
| Offer notice rate | Offers with any captain interaction ÷ offers delivered | Unknown | > 90 % |
| Offer acceptance latency | Median seconds from delivery to accept | Unknown | < 6 s |
| Offer expiry rate | Offers expiring with no interaction | Unknown | < 15 % |
| Time to match | Rider request → captain assigned, p50 and p90 | p90 bounded below by 15 s per wave | p90 < 20 s |
| Wallet dispute contacts | Support tickets tagged balance or payout, per 1,000 trips | Unknown | < 2 |
| Withdrawal refusal rate | `INSUFFICIENT_BALANCE` ÷ payout attempts | Unknown; structurally elevated by F-10-04 | < 1 % |
| Battery per 10 h shift | Battery Historian on a reference device | ≈ 3,520 mAh (estimated, §3.8) | ≤ 2,700 mAh |
| Data per 10 h shift | Proxy byte count, socket up | ≈ 8 MB (estimated, §3.8) | ≤ 4 MB |
| Onboarding completion | Registrations reaching "submitted for review" | Unknown | > 70 % |
| Time in review limbo | Submission → decision, p50 and p90 | Unknown | p90 < 24 h |
| Approval-to-first-trip | Approval → first accepted offer | Unknown; unbounded above by the missing push | p50 < 2 h |
| Ghost-trip rate | Trips started beyond 250 m from pickup | Unmeasurable today | Measured, then < 0.1 % |

The honest headline is that **almost every number in the "current" column is unknown**, because the captain app emits no product analytics. Before P1 begins, instrument: offer delivered / seen / accepted / declined / expired, session start and forced logout, online and offline transitions with reason, and each trip transition with its position. Without that, the P0 fixes cannot be shown to have worked.

---

## 9. Cross-cutting notes

Findings outside this track's axis, addressed to their owners. Not fixed here.

**To T09 — Rider app.** The rider's SOS screen requires a `tripId` (`apps/rider/lib/screens/safety/sos_screen.dart:9-10`), so a rider cannot raise an emergency before a trip starts or after it ends — precisely the windows in which they are alone at a kerb with a stranger. The captain's equivalent is standalone and correctly does not require one. This looks like a genuine liability gap rather than a design choice. The rider SOS also puts a confirmation dialog in front of the trigger, adding a tap in a panic, where the captain's is a single press on a 200 dp target.

**To T09 — Rider app.** The rider's chat screen uses fixed `Alignment.centerLeft`/`centerRight` for message bubbles (`apps/rider/lib/screens/trip/trip_chat_screen.dart:98`) rather than `AlignmentDirectional`, so bubble sides are wrong in Arabic — the primary locale. The captain's version handles this correctly and additionally has typing indicators, a scroll controller and a poll backstop that the rider's lacks. The captain implementation is the better one; the rider should adopt it rather than the reverse.

**To T06 — Dispatch.** Two items from this track land in yours. First, there is no server-side decline, so `OfferScheduler` cannot advance a wave early and every wave costs its full `WAVE_DELAY_MS = 15_000` even when all three captains skipped instantly (`apps/api/src/durable-objects/OfferScheduler.ts:63`); P1.3 proposes the endpoint but the fairness implications of fast advancement are yours to rule on. Second, `WAVE_DELAY_MS` and the client's `_window` are both exactly 15 s, so wave *n+1* goes live at the moment wave *n*'s card claims to expire, and delivery latency means the overlap is real rather than notional.

**To T07 — Realtime.** Presence is written but only conditionally reaped: the stale-`is_online` sweep lives inside `GET /admin/captains` (`apps/api/src/routes/admin.ts:237`) rather than in the cron handler (`apps/api/src/index.ts:267-333`). `GeoCell`'s three-minute alarm protects dispatch, so this is a data-hygiene and metrics problem rather than a matching one, but `captains.is_online` is unreliable for any consumer that trusts it. Also: neither socket is explicitly reconnected on foreground resume — recovery depends on `refreshOffers()` noticing a null trip socket (`apps/captain/lib/services/captain_state.dart:950-957`), which works but is incidental rather than designed.

**To T04 — Payments.** F-10-04 is a captain-visible symptom of a ledger question that belongs to you: `GET /captain/wallet` derives a balance from a filtered transaction sum (`apps/api/src/routes/wallet.ts:57-72`) while the payout guard trusts `users.wallet_balance` (`:101-108`), and cash-commission debits (`apps/api/src/routes/trips.ts:1017-1034`) are counted by the second and invisible to the first. I have proposed making `users.wallet_balance` authoritative with a reconciliation job (P0.4), but which of the two is the system of record is your call and should be settled once for every consumer. Note also that `amount_piastres` exists alongside the `REAL` columns and is written but never read by any client — a live trap for the next developer who reads it and forgets to divide by 100.

**To T11/T12 — Admin.** The document review endpoint updates status without notifying the captain (`apps/api/src/routes/admin.ts:820-858`). The push belongs on the admin write path, so P1.6's notification work needs a small change in your surface.

**To T27 — Cross-app consistency.** Concrete duplications found while comparing the two apps, beyond the two rider items above:

| Entity | Captain | Rider | Divergence |
|---|---|---|---|
| Trip WebSocket | `apps/captain/lib/services/trip_ws.dart` | `apps/rider/lib/services/trip_ws.dart` | Same 25 s ping and same backoff formula, independently written; field names differ (`_heartbeat`/`_pingTimer`, `_closed`/`_disposed`, `_attempt`/`_reconnectAttempts`) and the rider exposes `onStatus` while the captain does not. Extract to `flutter_shared`. |
| Token refresh | `captain_state.dart:249-276` | `app_state.dart:183-230` | Same intent, and the rider's is correct while the captain's drops the rotation (F-10-02). A single shared auth client would have prevented this outright. |
| SOS screen | `screens/safety/sos_screen.dart` | `screens/safety/sos_screen.dart` | Different scaffolds, different trigger ergonomics, different requirements; the rider additionally has trip-share, the captain does not. |
| Splash | `screens/splash_screen.dart` (both) | | Both replaced video with a static asset independently, with parallel implementations of the same idea. |
| Settings | `screens/profile/settings_screen.dart` (both) | | Captain uses switches for theme and language, rider uses dropdowns; captain has an SOS shortcut, rider has none. |
| Chat | `screens/home/trip_chat_screen.dart` | `screens/trip/trip_chat_screen.dart` | Different directories, different capability levels; see the T09 note. |

The pattern is consistent: the same feature written twice, drifting, with the better implementation in whichever app touched it last. The refresh-token bug is the clearest cost of that pattern so far, because it is a security-adjacent defect that exists in one app and is already fixed in the other.

---

## 10. Open questions

Decisions the product owner has to make. Each with the options and a recommendation.

**Q1 — Is the brand green negotiable?**
`primary` #4E842D fails WCAG AA on the app's own off-white surfaces (F-10-16). Options: (a) darken the token to roughly #3F6B24 and accept a slightly different brand green; (b) keep the colour but forbid it for text, using it only for fills and strokes; (c) accept the failure. **Recommend (a)** — the shift is small enough that most people will not notice it, and this is a work tool used outdoors. (b) is an acceptable second if the brand is fixed. (c) is not acceptable for a driving app.

**Q2 — Should the offer window stay at 15 seconds?**
The current 15 s matches the server's wave delay exactly, which is why waves overlap (F-10-07). Options: (a) keep 15 s for the captain and lengthen `WAVE_DELAY_MS` to ~18 s so the client window closes first; (b) shorten the client window to 12 s and keep the server at 15 s; (c) make both configurable and tune against time-to-match. **Recommend (c)**, starting at the (a) values. This must be agreed with T06.

**Q3 — Rider PIN, rider confirmation, or both?**
P0.5 assumes a four-digit code. Options: (a) PIN only — strongest, but blocks riders with a dead phone; (b) rider in-app confirmation only — friendlier, useless when the rider's app is closed; (c) both, with an ops override. **Recommend (c)**. Egypt's cash market makes ghost trips a live fraud vector, and the fallback prevents the fix from stranding honest riders.

**Q4 — Does the captain pay for their own data?**
The battery and data budget (§3.8) assumes yes, which makes ~8 MB/shift — and ~26 MB when the socket is unstable — a real cost the captain absorbs to stay available. Options: (a) treat it as their cost and optimise hard (the P1.7 targets); (b) subsidise via a carrier bundle; (c) ignore it. **Recommend (a)**, and publish the number in the captain-facing FAQ. Drivers in this market watch their bundles closely and a transparent figure earns more trust than silence.

**Q5 — Wait fee: charge the rider, absorb it, or split it?**
P2.1 proposes charging the rider after a grace period. Options: (a) rider pays in full past 3 minutes; (b) platform absorbs it as a supply incentive; (c) split. **Recommend (a)** with a generous grace period, matching regional norms and preserving the captain's incentive to wait rather than cancel. This is a pricing decision, not an engineering one.

**Q6 — How hard should the debt gate be?**
P2.4 proposes a ceiling past which a captain cannot go online. Options: (a) hard block; (b) soft warning with escalating friction; (c) visibility only. **Recommend** visibility for one full settlement cycle, then (b), and only then consider (a). Blocking supply is the most damaging lever available and should not be the first one pulled.

**Q7 — Embedded navigation, or hand-off permanently?**
P2.5 is a large project whose value depends entirely on OSRM instruction quality for Egyptian street data. Options: (a) build embedded guidance; (b) perfect the hand-off and never build it; (c) evaluate route quality first and decide on evidence. **Recommend (c)** — run the evaluation before any UI work. If OSRM's Cairo instructions are poor, (b) is the honest answer and the money is better spent elsewhere.

**Q8 — Which balance is the system of record?**
Raised for T04 in §9 but it needs a product owner's ruling because it determines what "your balance" means to a captain. Options: (a) `users.wallet_balance` authoritative with the ledger as audit; (b) ledger authoritative with the column as a cache; (c) status quo, two numbers. **Recommend (a)** — it is what the payout path already trusts, and it makes the displayed number the withdrawable number, which is the property that matters to the captain.
