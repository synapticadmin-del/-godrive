# 27 — Cross-App Parity — Rider ↔ Captain ↔ Admin

> Track: B — Product surface & experience · Reviewer: `chat-20260801-1434-07dd` · Date: 2026-08-01 (UTC)
> Base commit reviewed: `bb9d557e6cc1b9e30105e70b6e1446782a6c8d68`

Every `path:line` in this document resolves against that commit. Nothing here was
inferred from a filename.

---

## 1. Scope

This document puts `apps/rider` and `apps/captain` side by side — screen by screen,
state by state, word by word — and records every place where the two halves of one
trip disagree. `apps/admin` is included only as the third surface that must agree on
brand and vocabulary.

**The primary artefact is the paired-state table.** `board/TEMPLATE.md` fixes the ten
section headings and their order, and the protocol makes that ordering a hard rule, so
the table opens §3 rather than sitting between §1 and §2. It is the first substantive
content in the document; §2 is a one-screen credibility list you can skim past.

**In scope:** trip-state agreement between the two apps and the server; the six
duplicated screen/service pairs named in the brief; shared-package discipline;
theme/token adoption; terminology; notification and timing symmetry; the parity
contract and its automated check.

**Explicitly not in scope** (named so nobody thinks I missed it):

| Area | Owner |
|---|---|
| Whether the wallet ledger itself is correct (double-credit, commission arithmetic) | **T03** |
| Payment/PSP mechanics, payout scheduling | **T04** |
| Dispatch/matching quality, offer wave strategy | **T06** |
| WebSocket/Durable Object transport correctness, reconnect storms | **T07** |
| Rider-only journey depth | **T09** · Captain-only journey depth **T10** |
| Admin console function (beyond tokens/vocabulary) | **T11** |
| Design-system internals (token scale design itself) | **T12** |
| i18n infrastructure and RTL correctness as a discipline | **T14** |
| Accessibility | **T15** |
| Safety product design (what SOS *should* do) | **T17** |
| Store/versioning policy | **T26** |
| Building the shared animation library | **T28** |

I report parity defects in those areas and hand them off; I do not design their fixes.

---

## 2. What I actually read

Read in full, with line numbers, at the base commit:

**The duplicated pairs (the brief's core list)**

- `apps/rider/lib/services/trip_ws.dart` (117 lines) — read fully, line by line, against its captain twin.
- `apps/captain/lib/services/trip_ws.dart` (132 lines) — read fully. Near-identical logic, different surface.
- `apps/rider/lib/screens/trip/trip_chat_screen.dart` (150 lines) — read fully.
- `apps/captain/lib/screens/home/trip_chat_screen.dart` (421 lines) — read fully.
- `apps/rider/lib/screens/safety/sos_screen.dart` (163 lines) — read fully.
- `apps/captain/lib/screens/safety/sos_screen.dart` (322 lines) — read fully.
- `apps/rider/lib/screens/wallet/wallet_screen.dart` (497) and `apps/captain/lib/screens/earnings/wallet_screen.dart` (810) — structural read of both balance cards and both ledger lists.
- `apps/rider/lib/screens/login_screen.dart` (1044) / `apps/captain/lib/screens/login_screen.dart` (830) — skimmed for structure and theming, not read line by line.
- `apps/rider/lib/screens/splash_screen.dart` (531) / `apps/captain/lib/screens/splash_screen.dart` (487) — skimmed.
- `apps/rider/lib/main.dart` (173) / `apps/captain/lib/main.dart` (92) — read fully; theme and localisation wiring compared.

**State and server**

- `apps/rider/lib/services/app_state.dart` (696) — read for WS/poll/cancel/FCM paths; skimmed elsewhere.
- `apps/captain/lib/services/captain_state.dart` (1189) — same treatment.
- `apps/captain/lib/services/offers_ws.dart` (114) — read fully; it is the third socket client.
- `apps/api/src/routes/trips.ts` (53 KB) — grepped hard for every status write and every notification; read the cancel, accept, advance and complete handlers.
- `apps/api/src/routes/safety.ts` — read the SOS, chat, chat-ordering and typing handlers.
- `apps/api/src/routes/wallet.ts` — read fully (100 lines of the 5 KB file cover both balance endpoints).
- `apps/api/src/routes/devices.ts` (41 lines) — read fully.
- `packages/shared/src/index.ts` — read; this is the canonical state machine.
- `apps/api/src/durable-objects/TripRoom.ts`, `CaptainInbox.ts`, `OfferScheduler.ts` — read for broadcast/fanout shape.

**Shared package and third surface**

- `packages/flutter_shared/lib/flutter_shared.dart` (the barrel), all 15 widget files by name and usage, `services/api_client.dart`, `services/fcm_service.dart`, `models/trip.dart`, `models/user.dart`.
- `packages/flutter_shared/lib/theme/app_theme.dart` (40 KB) — token surface read; not every widget theme line by line.
- `packages/flutter_shared/lib/l10n/app_strings.dart` (184 KB) — **not** read line by line. Key counts and specific strings were extracted programmatically and by targeted grep; every quoted string was verified at its cited line.
- `apps/admin/src/design/tokens.ts`, `design/globals.css`, `design/ThemeContext.tsx`, `components/ui/Button.tsx`, `Badge.tsx`, `Card.tsx`.
- Both `pubspec.yaml` files, `packages/flutter_shared/pubspec.yaml`, both `analysis_options.yaml`, both `l10n.yaml`, all four `.arb` files and their generated Dart.
- `scripts/check_l10n_parity.py` and `scripts/README.md` — read as the precedent for the check proposed in §6.

**Correction on the record.** An early sweep flagged `apps/api/src/routes/devices.ts` as
missing, which would have made every push notification undeliverable. That was an
artefact of my own partial checkout, not the repository. The file exists at 41 lines and
implements `POST/DELETE /user/device` correctly, including an `app_role` column the two
apps never send. No such finding appears below.

---

## 3. How it works today

### 3.1 The paired-state table — primary artefact

The server's canonical vocabulary is seven statuses, defined once in
`packages/shared/src/index.ts:3-10` and gated by `TRIP_TRANSITIONS` at
`packages/shared/src/index.ts:40-48`:

```
searching → offered | assigned | cancelled
offered   → assigned | searching | cancelled
assigned  → arrived | cancelled
arrived   → in_progress | cancelled
in_progress → completed | cancelled
completed → (terminal)
cancelled → (terminal)
```

`canTransition` (`packages/shared/src/index.ts:50-52`) is enforced on cancel
(`apps/api/src/routes/trips.ts:723`), on advance (`:906`) and on complete (`:962`).
**This machine is TypeScript. Neither Flutter app can import it**, and neither tries —
each re-declares the vocabulary in Dart by hand. That single fact is the root cause of
most of the table below.

Legend: **✓** the three agree · **≈** agree on status, diverge in what the user is told ·
**✗** genuinely different stories · **∅** the state does not exist server-side.

| # | State | Rider sees | Captain sees | Server truth | Agree |
|---|---|---|---|---|---|
| 1 | **searching** | Spinner + «جارٍ البحث عن كابتن…»; badge «جارٍ البحث» `apps/rider/lib/screens/trip/trip_screen.dart:743` | No trip surface. Offer waves are being pushed into the inbox `apps/api/src/durable-objects/OfferScheduler.ts` | `status='searching'` written at `apps/api/src/routes/trips.ts:450`; immediately flipped to `offered` if captains exist `:534-537` | ≈ |
| 2 | **offers arriving** | Bids overlay, badge «عروض متاحة» `trip_screen.dart:744`; bids polled every **5 s** `captain_bids_sheet.dart:75` | Offer card with a 15 s countdown; offers via inbox socket, polled every **8 s** (socket down) / **60 s** (socket up) `captain_state.dart:758,763` | `status='offered'` `trips.ts:537` and `:1177` | ≈ |
| 3 | **offer accepted** | Bids panel unmounts, driver card appears | `activeTrip` populated via inbox `trip.assigned` then `refreshOffers()` | `status='assigned'`, `captain_id`, `accepted_price` set `trips.ts:1306`; captain-accepts path at `:862` | ✓ |
| 4 | **captain en route** | Driver card, «الكابتن في الطريق إليك», live captain dot from `location.captain` `trip_screen.dart:145-150` | Stepper step 1, CTA «أعلن الوصول», navigation to pickup | `status='assigned'`, `assigned_at` set | ✓ |
| 5 | **captain arrived** | «وصل الكابتن — تفضّل بالنزول». **No timer.** | Same status, plus a **1 s ticking clock** from `arrived_at` `active_trip_panel.dart:53,82,93,238` | `status='arrived'`, `arrived_at` set `trips.ts:944` | ≈ |
| 6 | **waiting** | Shares the `arrived` branch — rider is never told how long the captain has waited | Clock keeps running; no waiting-fee indicator | No distinct status; `arrived` *is* waiting | ✗ |
| 7 | **trip started** | «الرحلة جارية»; cancel button removed | Stepper step 3, CTA «إنهاء الرحلة» behind a confirm dialog `active_trip_panel.dart:498-515` | `status='in_progress'`, `started_at` `trips.ts:948` | ✓ |
| 8 | **in transit** | Same panel for the whole journey | Same panel; navigation retargeted to dropoff | No sub-state | ✓ |
| 9 | **destination changed** | No UI, no event handler | No UI, no event handler | **No endpoint.** `waypoints` is write-once at creation `trips.ts:475` | ∅ |
| 10 | **trip completed** | Full completion screen: checkmark, «وصلت بسلامة!», final fare, rate CTA `trip_screen.dart:550-564` | `activeTrip` set to `null`, panel vanishes, back to the map. **No in-app summary.** `captain_state.dart:883-890` | `status='completed'`, `final_fare` `trips.ts:974` | ✗ |
| 11 | **payment settled** | Final fare on the completion screen; no distinct state | Nothing in-app; FCM body carries the payout figure `trips.ts:1074-1086` | Settled as a side effect of `complete`; no status | ≈ |
| 12 | **cancelled by rider** | Explicit «تم إلغاء الرحلة» screen `trip_screen.dart:567` | Card/panel silently disappears on inbox `trip.cancelled` → `refreshOffers()` `captain_state.dart:834`. No explicit screen. | `status='cancelled'` `trips.ts:728`; nearby-captain fanout `:753-796` | ✗ |
| 13 | **cancelled by captain** | Receives «نعتذر — تم إلغاء رحلتك» `trips.ts:816-820` | **Cannot reach this state.** The captain app never calls `/trips/:id/cancel` — only the rider does `app_state.dart:513` | Server fully supports it | ✗ |
| 14 | **no captain found** | «جارٍ البحث عن كابتن…» forever. No timeout, no failure state, no push. | Nothing | **No expiry anywhere.** No status, no cron | ✗ |
| 15 | **network lost mid-trip** | 10 s poll backstop `trip_screen.dart:172`; captain's map dot freezes (location is socket-only); **no connection indicator** | Trip socket auto-reconnects `captain/…/trip_ws.dart:102-115`; state refreshed by the 8/60 s offers poll; **no connection indicator during a trip** (one exists on the offers screen `home_tab.dart:205`) | TripRoom retains state | ≈ |

Rows 6, 10, 12, 13 and 14 are the ones where the two people in the car are looking at
genuinely different realities.

### 3.2 The three sockets

There are three WebSocket clients in the monorepo and no shared base class:

| | `rider/…/trip_ws.dart` | `captain/…/trip_ws.dart` | `captain/…/offers_ws.dart` |
|---|---|---|---|
| Endpoint | `/ws/trips/:id` `:41` | `/ws/trips/:id` `:58` | captain inbox |
| Auth | first-frame `{type:auth}` `:57` | first-frame `{type:auth}` `:73` | same pattern |
| Heartbeat | 25 s `:76` | 25 s `:92` | 25 s `:73` |
| Backoff | 1→16 s + jitter `:93-95` | 1→16 s + jitter `:110-111` | 1→16 s + jitter `:90-96` |
| Delivery | callback `onMessage` | broadcast `Stream` `:45-47` | callback |
| **Status surface** | `onStatus` **exists** `:22` | **absent entirely** | `onStatus` exists `:20` |
| Status actually used? | **No** — `trip_screen.dart:134-153` wires only `onMessage` | n/a | **Yes** — `home_tab.dart:205`, `available_trips_tab.dart:262` |

Three implementations of one behaviour, with the reconnect maths copy-pasted three
times. The rider's status callback is built and never connected; the captain's trip
socket cannot report status even if someone wanted it. During an active trip neither
person is told the connection dropped.

### 3.3 Chat — one conversation, two very different clients

The server stores one thread and returns it **newest-first**:

```
SELECT id, sender_id, sender_role, body, read_at, created_at
FROM trip_chat_messages WHERE trip_id = ? ORDER BY created_at DESC LIMIT ?
```
`apps/api/src/routes/safety.ts:230-231`

| Behaviour | Rider `…/trip/trip_chat_screen.dart` | Captain `…/home/trip_chat_screen.dart` |
|---|---|---|
| Live socket | **none** | `activeTripWsMessages` `:65-75` |
| Poll backstop | **none** | 6 s `:78-80` |
| How new messages arrive | only by re-entering the screen, or as a side effect of sending `:64` | instantly, plus 6 s safety net |
| List order | `ListView.builder`, **not reversed** `:90` | `reverse: true` `:228`, with the DESC contract documented `:134` |
| Result | **history renders backwards** | correct chronology |
| Bubble alignment | `Alignment.centerLeft` / `centerRight` `:97` — physical, does not mirror | `AlignmentDirectional.centerEnd` / `Start` `:249-251` — mirrors |
| Typing: send | never (zero `typing` references in `apps/rider/lib`) | throttled 2 s `:112-126` |
| Typing: render | never | `_TypingBubble` with 4 s self-expiry `:96-108`, `:375` |
| Empty state | blank list | `strings.chatEmptyBody` `:217` |
| Scroll to newest | no | yes `:150-159` |
| Double-send guard | no | `_sending` `:163` |
| Bubble max width | unconstrained | 74 % of screen `:258-260` |
| Error text | raw `e.toString()` `:67` | `Exception:` stripped `:180` |
| Strings | hardcoded «المحادثة», «اكتب رسالة...» `:81,:127` | `AppStrings` throughout `:196,:308` |
| Timestamps | **none** | **none** |
| Read receipts | none (server selects `read_at` `safety.ts:230` and nobody uses it) | none |

Two consequences worth stating plainly. First, the rider reads the conversation in
reverse. Second, the typing feature is a closed loop with one end missing: the captain
POSTs `/safety/chat/:tripId/typing` (`safety.ts:256`, broadcast at `:278`) and renders
incoming typing from a rider who never sends it — so the captain's typing bubble is
unreachable code, and the captain's own typing signal is broadcast to a client that
ignores it.

### 3.4 SOS — two screens, one endpoint, no mutual awareness

Both call `POST /safety/sos` (rider `:78`, captain `:86`). The server inserts the alert
and fans out to administrators only:

```
SELECT id FROM users WHERE role = 'admin'
```
`apps/api/src/routes/safety.ts:29`, pushed at `:31`

| | Rider | Captain |
|---|---|---|
| Confirmation before firing | yes — dialog «تأكيد الطوارئ» / «إلغاء» `:28-39` | **no** — single tap fires |
| Visual register | light AppBar, static red circle | full-bleed `AppTokens.sosBackdrop`, pulsing glow `:118` |
| Dark-mode correct | **no** — hardcodes `AppTokens.lightPanel/lightText/lightMuted` `:31,:33,:116,:145` | yes |
| After sending | snackbar, screen pops `:84` | persistent `_sent` state `:96,:138,:160` |
| Share trip link | yes, `POST /safety/share` + `Share.share` `:94-104,:150` | **absent** |
| GPS pre-flight | explicit service+permission checks with distinct messages `:52-64` | exception-catch only, falls back to possibly stale `last_lat/last_lng` |
| `tripId` in payload | always (required constructor arg `:9`) | only when a trip is active `:87` |
| Cancel a false alarm | **impossible** — no endpoint exists | **impossible** |
| Strings | hardcoded Arabic | `AppStrings` |
| Other person in the car told | **no** | **no** |

A safety feature where one party's panic button is one tap and the other's is two, where
one can share a tracking link and the other cannot, and where neither the passenger nor
the driver learns that the person sitting next to them just called for help.

### 3.5 Money vocabulary — one label, two computations

- Rider balance: `SELECT wallet_balance FROM users` → returned as `balance`
  `apps/api/src/routes/wallet.ts:19-24,:34`.
- Captain balance: re-aggregated on the fly —
  `SUM(amount) WHERE direction='credit' AND type IN ('commission','payout','adjustment')`
  minus payout debits `apps/api/src/routes/wallet.ts:58-72`, returned as `balance` `:84`.

Both screens render that field under «الرصيد المتاح» in a card that PR #52 made
pixel-identical (same gradient, radii, blooms, 42 pt `AppTokens.money`, same animation
curve; the only intended deltas are the label key and top-up vs withdraw). The card
converged; the **definition of the number in it did not**. A captain top-up (`type='topup'`)
would be invisible to the captain's own balance, and the payout guard reads
`users.wallet_balance` — a third source — so screen and guard can disagree.

### 3.6 Shared package discipline

15 widgets, all exported from `packages/flutter_shared/lib/flutter_shared.dart:11-24`:

| Widget | Rider | Captain | Verdict |
|---|---|---|---|
| `empty_state`, `error_state`, `skeleton_loader`, `status_chip`, `vehicle_map_marker`, `godrive_wordmark`, `main_bottom_nav` | ✓ | ✓ | shared — working as intended (7) |
| `counter_offer_sheet`, `go_date_field`, `go_online_button`, `navigation_button`, `offline_guard_banner`, `map_controls` | — | ✓ | captain-only (6) |
| `loading_overlay` | — | — | **dead** |
| `offline_gate` | — | — | **dead** |

Also exported and used by nobody: `services/api_client.dart`, `models/trip.dart`
(`TripModel`), `models/user.dart` (`UserModel`). Both apps pass raw
`Map<String, dynamic>` around and hand-roll their own HTTP layer on `package:http`
(`app_state.dart:5`, `captain_state.dart:7`). The one genuinely shared service is
`fcm_service.dart`.

Zero rider-only widgets is itself the finding: the rider app has been the one *not*
contributing to the shared package.

### 3.7 Theme, tokens and the third surface

Both apps install the shared theme identically — `AppTheme.light()`, `AppTheme.dark()`,
`themeMode: state.themeMode` (rider `main.dart:87-89`, captain `main.dart:79-81`), with no
local `ThemeData` overrides. Adoption is genuinely good; the drift is in the details:

| Metric | Rider | Captain |
|---|---|---|
| `AppTokens.` references | 561 | 988 |
| Raw `Color(0x…)` | 10 (all vehicle-colour data, `trip_screen.dart:592-601`) | 0 |
| Hardcoded `EdgeInsets` numerics | 99 | 61 |
| Hardcoded `BorderRadius.circular(N)` | 26 | 8 |
| Primary CTA shape | `radiusPill` (999) `fare_estimate_sheet.dart:366` | `radiusMd` (14) `document_upload_screen.dart:458` |
| Card radius | 14 `history_screen.dart:69` | 18 (theme default) |

The admin console is the outlier. `apps/admin/src/design/tokens.ts:32` declares the brand
green as `#4e842d` — matching Flutter's `AppTokens.primary` — but
`apps/admin/src/design/globals.css:167` sets `--primary-500: #6bb522`, and the CSS
variable is what `Button.tsx` actually renders. The admin ships a different green from
both apps. Radii are compressed across the board (4/8/12/16 px against Flutter's
10/14/18/26 dp), the typeface is IBM Plex Sans Arabic against Flutter's Cairo, and
although `ThemeContext.tsx` toggles a `dark` class, `globals.css` defines only `:root` —
there is no `.dark {}` block, so the admin's dark mode is a switch wired to nothing.

### 3.8 Localisation topology

Three string systems, one of them real:

1. **`packages/flutter_shared/lib/l10n/app_strings.dart`** — hand-written, not generated.
   `abstract class AppStrings` `:46` with `AppStringsAr` `:1777` and `AppStringsEn` `:3721`;
   resolved by `AppStrings.of(context)` `:52`, defaulting to Arabic. **544 keys** (495
   getters + 49 methods). This is the live system.
2. **`apps/rider/lib/l10n/*.arb`** — 56 keys, generated Dart present, `AppLocalizations.of`
   **never called**, delegate **never registered** in `main.dart:59-63`. Vestigial.
3. **`apps/captain/lib/l10n/*.arb`** — 48 keys, same story (`main.dart:53-56`), except the
   captain pubspec does set `generate: true` `:54` while the rider's does not.

19 keys appear in both `.arb` sets; 37 are rider-only, 29 captain-only, and two collide
with different values (`appTitle`, `appSlogan`). None of it runs.

Against that, hardcoded Arabic literals still sitting in screen files: **302 lines across
20 rider files** versus **30 lines across 4 captain files**. The rider's
`trip_screen.dart:741-752` re-declares every trip-status label locally instead of calling
`AppStrings`, which is precisely how the vocabulary in §4 drifted.

---

## 4. Findings

| ID | Sev | Finding | Evidence | Impact | Confidence |
|---|---|---|---|---|---|
| F-27-01 | S1 | Rider renders chat history in reverse chronological order; captain renders it correctly | API `ORDER BY created_at DESC` `apps/api/src/routes/safety.ts:231`; captain `reverse: true` `apps/captain/lib/screens/home/trip_chat_screen.dart:228`; rider has no `reverse` `apps/rider/lib/screens/trip/trip_chat_screen.dart:90` | The two people in one car read the same conversation in opposite directions. Instructions invert. | confirmed |
| F-27-02 | S1 | Rider chat has no realtime path and no poll — captain messages never arrive while the screen is open | rider `initState` fetches once `apps/rider/lib/screens/trip/trip_chat_screen.dart:22,34`; captain has socket `:65` + 6 s poll `:78` | Captain types «أنا واقف عند البوابة», rider sees nothing until they send a message or reopen the screen. | confirmed |
| F-27-03 | S1 | SOS notifies administrators only; the other occupant of the vehicle is never told | `apps/api/src/routes/safety.ts:29-39` — fanout is `WHERE role = 'admin'` | The person best placed to help, or to be escaped from, is the one person not informed. | confirmed |
| F-27-04 | S1 | "Available balance" is two different computations behind one label | rider = `users.wallet_balance` `apps/api/src/routes/wallet.ts:19-24`; captain = re-aggregated ledger sum `:58-72`; payout guard reads a third source | Support cannot answer "what is my balance"; the two numbers can legitimately disagree. | confirmed |
| F-27-05 | S2 | Captain cannot cancel a trip from the app at all | only `apps/rider/lib/services/app_state.dart:513` calls `/trips/:id/cancel`; no such call anywhere in `apps/captain/lib`; the panel's only `cancelAction` is a dialog "no" button `active_trip_panel.dart:506` | Breakdown, accident, wrong pickup → the captain abandons the trip. The server's cancelled-by-captain notification `trips.ts:816-820` is unreachable. | confirmed |
| F-27-06 | S2 | A trip with no captain never resolves — no timeout, no status, no notification | no expiry logic in `apps/api/src/routes/trips.ts`; rider stays on «جارٍ البحث عن كابتن…» `trip_screen.dart:743` | Rider waits indefinitely on a request that will never be filled. | confirmed |
| F-27-07 | S2 | Typing indicator is a half-built loop: captain sends and renders, rider does neither | endpoint `safety.ts:256`, broadcast `:278`; captain `:112-126`, `:375`; **zero** `typing` references in `apps/rider/lib` | Captain's typing bubble can never appear; captain's own signal is broadcast to a client that ignores it. Feature is 100 % cost, 0 % delivery. | confirmed |
| F-27-08 | S2 | Rider is never told how long the captain has been waiting; the captain watches a clock | captain 1 s tick from `arrived_at` `active_trip_panel.dart:53,82,93,238`; rider has no timer, only a 10 s poll `trip_screen.dart:172` | The single most common ride-hailing argument, engineered in. | confirmed |
| F-27-09 | S2 | Captain gets no in-app trip-completion summary; rider gets a full screen | rider `trip_screen.dart:550-564`; captain nulls `activeTrip` `captain_state.dart:883-890` | The captain's payout confirmation lives only in a push notification they may have dismissed. | confirmed |
| F-27-10 | S2 | Cancellation is explicit for the rider and silent for the captain | rider `trip_screen.dart:567`; captain's card simply disappears on `refreshOffers()` `captain_state.dart:834` | Captain who was driving to a pickup gets no in-app explanation. | confirmed |
| F-27-11 | S2 | SOS confirmation is asymmetric: rider must confirm, captain fires on one tap | rider dialog `sos_screen.dart:28-39`; captain has none | Accidental alerts skew to the driving party; admin trust in the alert stream degrades. | confirmed |
| F-27-12 | S2 | Captain SOS cannot share a tracking link; rider's can | rider `sos_screen.dart:94-104,:150`; no equivalent in the captain screen | Captain in distress has no way to bring a third party in. | confirmed |
| F-27-13 | S2 | No SOS can be cancelled by either party | no cancel/close route in `apps/api/src/routes/safety.ts`; rider pops `:84`, captain shows a terminal `_sent` state `:96` | False alarms are permanent, which is how alert fatigue starts. | confirmed |
| F-27-14 | S2 | The canonical state machine is TypeScript-only; both Flutter apps re-declare it by hand | `packages/shared/src/index.ts:40-48`; rider re-declares all 7 labels at `trip_screen.dart:741-752`; captain handles only 3 in `active_trip_panel.dart:445-466` | Every future status change requires three synchronised edits in two languages. This is the mechanism that produced most of this table. | confirmed |
| F-27-15 | S2 | Admin ships a different brand green from both apps | `apps/admin/src/design/tokens.ts:32` = `#4e842d`; `apps/admin/src/design/globals.css:167` = `#6bb522`, and the CSS variable wins | One product, two greens, visible side by side in any screenshot. | confirmed |
| F-27-16 | S2 | Admin dark mode is a switch wired to nothing | `ThemeContext.tsx` adds a `dark` class; `globals.css` defines only `:root`, no `.dark {}` block | Toggle exists, does nothing. | confirmed |
| F-27-17 | S2 | 302 hardcoded Arabic lines in rider screens vs 30 in captain | worst: `profile_screen.dart` (40), `trip_screen.dart` (43), `location_search_sheet.dart` (23), `captain_bids_sheet.dart` (17) | Rider copy cannot be changed centrally; it is where vocabulary drifts. | confirmed |
| F-27-18 | S2 | Pickup point has four Arabic names across the two apps | «نقطة الانطلاق» (rider UI), «نقطة الالتقاط» (`app_strings.dart:1835`), «موقف الراكب» (captain ARB), «موقع الانطلاق» (`ride_request_model.dart:47`) | The two apps name the same physical kerb differently while both people stand on it. | confirmed |
| F-27-19 | S2 | «سائق» appears where every other string says «كابتن» — in the rider's captain-chooser | `app_strings.dart:2706,:2710`; hardcoded twins at `captain_bids_sheet.dart:344,:362` | The brand word breaks at the exact moment the rider is choosing a person. | confirmed |
| F-27-20 | S2 | «عميل» leaks into captain-facing copy where the rest of the product says «راكب» | `app_strings.dart:1820,:1851,:1855`; `counter_offer_sheet.dart:125,:157`; `ride_request_model.dart:42` | Two words for the passenger, one of them in the *shared* widget. | confirmed |
| F-27-21 | S2 | Admin typography diverges: IBM Plex Sans Arabic vs Cairo in both apps | `apps/admin/src/design/tokens.ts` font stack vs `AppTokens.font()` → `GoogleFonts.cairo` | Arabic renders visibly differently across the three surfaces. | confirmed |
| F-27-22 | S3 | Three WebSocket clients duplicate the same reconnect maths; only one exposes status, and the rider never wires the one it has | `rider/…/trip_ws.dart:22,:93-95` vs `captain/…/trip_ws.dart:110-111` (no status) vs `offers_ws.dart:20`; rider wires only `onMessage` `trip_screen.dart:134-153` | No connection indicator during a trip on either side; three places to fix one bug. | confirmed |
| F-27-23 | S3 | Rider chat bubbles use physical alignment that does not mirror | `Alignment.centerLeft/centerRight` `trip_chat_screen.dart:97` vs captain's `AlignmentDirectional` `:249-251` | Correct by luck in Arabic, wrong in English. | confirmed |
| F-27-24 | S3 | Chat message text is destroyed when a send fails, on both sides | rider clears at `:54` before `await` `:62`; captain clears at `:164` before `:174` | Typed message lost with no retry affordance. Symmetrically bad. | confirmed |
| F-27-25 | S3 | Rider surfaces raw exception strings to users | `trip_chat_screen.dart:67`, `sos_screen.dart:88,:107`; captain strips the prefix `:180` | English `Exception: …` text inside an Arabic UI. | confirmed |
| F-27-26 | S3 | Two shared widgets and three shared types are dead | `loading_overlay`, `offline_gate`, `ApiClient`, `TripModel`, `UserModel` — zero usages in either app | The package looks richer than it is; both apps duplicate an HTTP layer instead. | confirmed |
| F-27-27 | S3 | Rider SOS is hardcoded to the light palette | `AppTokens.lightPanel/lightText/lightMuted` at `sos_screen.dart:31,:33,:116,:145` | White emergency screen in dark mode; the captain's is correct. | confirmed |
| F-27-28 | S3 | «مكتملة» / «وصلت» / «اكتملت» all label the completed state | `app_strings.dart:2410,:2542,:1952` | Three words for one status inside one string file. | confirmed |
| F-27-29 | S3 | Primary CTA shape and card radius differ between apps | rider pill `fare_estimate_sheet.dart:366` and 14 dp cards `history_screen.dart:69`; captain 14 dp CTAs and 18 dp cards | The two apps do not look like one product at the button level. | confirmed |
| F-27-30 | S3 | Captain lint config does not exclude generated l10n; rider's does | rider `analysis_options.yaml:5-9`; captain has no `exclude` | `flutter analyze` noise on generated files for one app only. | confirmed |
| F-27-31 | S3 | Admin radius scale is systematically compressed vs Flutter | 4/8/12/16 px vs 10/14/18/26 dp | Every corner in the admin is sharper than the same component on mobile. | confirmed |
| F-27-32 | S4 | `StatusChip`, a *shared* widget, hardcodes four light-mode colours | `packages/flutter_shared/lib/widgets/status_chip.dart:52-58` | Light chips on near-black panels in dark mode, in both apps at once. | confirmed |
| F-27-33 | S4 | Both apps register every device as `platform: 'android'`, and neither sends `appRole` | `app_state.dart:527`, `captain_state.dart:1113`; server accepts both `devices.ts:27` | iOS devices mislabelled; the `app_role` column the server supports is never populated. | confirmed |
| F-27-34 | S4 | `counter_offer_sheet.dart` — a shared widget — carries 9 hardcoded Arabic literals | `packages/flutter_shared/lib/widgets/counter_offer_sheet.dart:68,78,125,134,157,162,174,198,221,257` | Untranslatable strings inside the shared layer. | confirmed |
| F-27-35 | S4 | `read_at` is selected by the API and used by neither app | `apps/api/src/routes/safety.ts:230` | Read receipts are half-built at the data layer. | confirmed |

**Not a finding.** Dependency hygiene is genuinely clean: all 23 shared packages carry
byte-identical version constraints across both apps, both are `version: 1.0.0+1`, both
target `sdk: '>=3.3.0 <4.0.0'`. The only asymmetry is `webview_flutter ^4.8.0` in the
rider, required by the Paymob top-up WebView and correctly absent from the captain. I
went looking for dependency drift and there is none — that discipline should be
protected by the check in §6, not assumed.

### The S1s, in prose

**F-27-01 + F-27-02 — the rider's chat is a different product from the captain's.**
These belong together because they have one cause: the captain's chat screen was
written second, by someone who knew what the endpoint actually returns, and the rider's
was never revisited. The server hands back `ORDER BY created_at DESC`
(`safety.ts:231`). The captain's screen documents that contract in a comment and sets
`reverse: true` (`trip_chat_screen.dart:134,:228`). The rider's screen pushes the same
newest-first array into a plain `ListView.builder` (`:90`), so the newest message renders
at the top and the conversation reads bottom-to-top. Layer on the delivery gap: the
captain has both a socket subscription (`:65`) and a 6 s poll (`:78`); the rider fetches
exactly once in `initState` (`:22`) and again only as a side effect of sending (`:64`).
So the rider both fails to receive the captain's messages and mis-orders the ones they
do have. In production this reads as "الرسايل مش بتظهر" — the same complaint the
captain-side comment at `:10-14` says was already fixed once, now living on the other
side of the car.

**F-27-03 — SOS tells head office and not the passenger.** `POST /safety/sos` writes the
alert and then selects administrators — `SELECT id FROM users WHERE role = 'admin'`
(`safety.ts:29`) — and pushes only to them (`:31`). There is no lookup of the trip's other
party, no `pushToUser` to the counterpart, and no TripRoom broadcast, even though the
handler already has `tripId` and the trip row carries both `rider_id` and `captain_id`.
Consider the two real scenarios. A rider presses SOS because of a medical emergency: the
captain, the one person who could pull over, is told nothing. A captain presses SOS
because of a threatening passenger: no one else in the vehicle's context is alerted, and
the alert cannot be withdrawn afterwards (F-27-13). Whatever the product decision about
*who* should be notified — and T17 owns that decision — the current behaviour is that the
two people physically present are the two people kept in the dark.

**F-27-04 — one label, two definitions of money.** `GET /user/wallet` returns the stored
column: `SELECT wallet_balance FROM users` (`wallet.ts:19-24`). `GET /captain/wallet`
never reads that column; it recomputes from the ledger, summing credits restricted to
`type IN ('commission','payout','adjustment')` and subtracting payout debits (`:58-72`).
Both are returned as `balance` and both render under «الرصيد المتاح» in a card that PR
#52 made pixel-identical. The convergence was real but cosmetic: it aligned the gradient,
the blooms, the 42 pt figure and the animation curve, and left the semantics untouched.
Three concrete consequences. A captain who tops up (`type='topup'`) sees no change in
their balance card, because `topup` is not in the `IN` list. The payout endpoint checks
`users.wallet_balance`, a third source, so the screen can offer a withdrawal the guard
refuses — or vice versa. And support has no single answer to "how much do I have".
Whether the ledger is *arithmetically* right is **T03**'s call; what belongs to me is
that two surfaces of one product answer the same question differently.

### Why the S2 set matters more than its label suggests

Five of the S2s (F-27-05, 06, 08, 09, 10) share a shape: **the captain app treats the
captain as an actor and never as a recipient.** The rider gets an explicit screen for
every terminal state — completed, cancelled, searching. The captain gets a panel that
appears when there is work and silently vanishes when there is not (`captain_state.dart:883-890`).
That is a coherent design choice for a driving UI, but it has been applied without the
counterpart: no completion summary, no cancellation explanation, no way to cancel, no
resolution when no captain is found. The captain is treated as a function the rider
calls, rather than the second user of a two-sided product.

---

## 5. Benchmark gap

**Uber.** Rider and driver apps are generated from one design system (Base) and, more
importantly, one trip-state definition: a single state enum with per-role presentation
mapped from it, so a state cannot exist that one app renders and the other does not.
*Confident.* Uber's driver app shows an explicit waiting timer with the fee accruing, and
the rider is shown the same timer — the number both people argue about is the same
number on both screens. *Confident.* Both sides can cancel with a reason taxonomy, and
each cancellation renders an explicit screen to the counterpart. *Confident.*
Synaptic Go has: a shared state machine that only one of three clients can import
(F-27-14), a waiting clock visible to one party (F-27-08), and cancellation available to
one party (F-27-05).

**inDrive.** The closest comparator, because the bidding model matches. inDrive's two
apps are deliberately near-identical in visual language so the brand reads as one
product; the offer/counter-offer surface in particular is the same component from both
sides, because it is literally the same negotiation. *Confident.* Synaptic Go has the
right instinct here — `counter_offer_sheet.dart` **is** shared — but it is the one shared
widget carrying hardcoded Arabic (F-27-34) and it calls the passenger «عميل» while the
rest of the product says «راكب» (F-27-20). The shared component became the vocabulary
leak.

**Careem.** Operating in the same region and the same language, Careem maintains a single
Arabic glossary across rider, captain and support tooling — the word for the driver does
not change between screens. *Assumed* in mechanism, confident in outcome. Synaptic Go
changes the word for the driver at the moment of choosing one (F-27-19) and has four
words for the pickup point (F-27-18).

**Where Synaptic Go is genuinely ahead.** Worth saying, because a review that only
subtracts is not useful. Dependency versions are perfectly aligned across both apps —
better hygiene than most monorepos of this age. Both apps install the same theme with no
local overrides, which is the hard part of a design system. `main_bottom_nav` is properly
shared and configured differently per app rather than forked. And the captain's chat
screen is, on its own merits, better than most: socket plus poll backstop, typing
indicator with self-expiry, RTL-correct alignment, guarded sends. The problem is not
capability. It is that the good work was done once, on one side, and never mirrored.

**The practical test from the brief** — two phones, one trip, filmed — would show
disagreement at these moments: the captain arrives (one clock, one static label), the
rider cancels (one screen, one silent disappearance), a chat is exchanged (one
chronological, one reversed, one live, one frozen), the trip completes (one summary, one
empty map), and at any point one presses SOS (neither phone tells the other).

---

## 6. Improvement plan

### P0.1 — Give Flutter the canonical state machine

- **Goal.** A trip status can never be added, renamed or re-labelled in one app only.
- **Design.** Add `packages/flutter_shared/lib/models/trip_status.dart` defining
  `enum TripStatus { searching, offered, assigned, arrived, inProgress, completed, cancelled }`,
  a `TripStatus.parse(String)` that throws on unknown input, a `transitions` map mirroring
  `packages/shared/src/index.ts:40-48`, and **two** label functions —
  `riderLabel(TripStatus, AppStrings)` and `captainLabel(TripStatus, AppStrings)` — because
  the two perspectives legitimately differ («كابتن في الطريق» vs «في الطريق إلى الراكب»)
  and that difference should be declared in one file rather than discovered in two.
  Delete `_statusConfig` from the rider and the `switch` in the captain panel; both call
  the shared function. Keep the Dart enum honest with the TypeScript source via the CI
  check in P0.6.
- **Files.** new `packages/flutter_shared/lib/models/trip_status.dart`; export it in
  `flutter_shared.dart`; `apps/rider/lib/screens/trip/trip_screen.dart:741-752` (delete);
  `apps/captain/lib/screens/home/active_trip_panel.dart:431-474`;
  `apps/captain/lib/services/captain_state.dart:879-890`.
- **DB.** none. **API contract.** none.
- **Effort.** M. **Risk.** A strict `parse` turns an unknown status into a crash; ship it
  with a `TripStatus.unknown` fallback that renders the raw string and logs, then tighten.
- **Acceptance.** No trip-status string literal exists in either app (grep proves it);
  adding a status to `packages/shared/src/index.ts` fails CI until the Dart enum matches.
- **Tests.** Unit test asserting the Dart transition map equals the TS one, parsed from source.

### P0.2 — Fix the rider's chat, then extract the screen

- **Goal.** Both people read the same conversation, in the same order, at the same time.
- **Design.** Two steps, in this order. **(a) Repair:** set `reverse: true` on the rider's
  list, switch to `AlignmentDirectional`, subscribe to the trip socket and add the same
  6 s poll the captain has. **(b) Extract:** move the captain's screen — which is the
  better implementation — to `packages/flutter_shared/lib/widgets/trip_chat_view.dart`,
  parameterised by `myRole` (`'rider'`/`'captain'`), an `apiGet`/`apiPost` pair, and a
  `Stream<Map<String,dynamic>>` of room events. Both apps then render
  `TripChatView(myRole: …)`. Do (a) first: it is a two-line fix to a live defect and
  should not wait for the refactor.
  While extracting, close F-27-24 by keeping the composer text until the POST succeeds
  and offering a retry affordance on failure, and add the message timestamp both sides
  currently lack.
- **Files.** `apps/rider/lib/screens/trip/trip_chat_screen.dart:90,:97,:22`;
  `apps/captain/lib/screens/home/trip_chat_screen.dart` → new shared widget; both call sites.
- **DB.** none. **API contract.** none for (a). For read receipts, `read_at` already
  exists in the select (`safety.ts:230`) and needs a `POST /safety/chat/:tripId/read` —
  propose, do not build, and coordinate with T17.
- **Effort.** S for (a), M for (b). **Risk.** Low; the shared widget is additive and the
  two call sites can migrate one at a time.
- **Acceptance.** A message sent by either party appears on the other device within 6 s
  without user action, in correct chronological order, in both Arabic and English layouts.
- **Tests.** Widget test asserting a DESC-ordered fixture renders oldest-at-top; golden
  tests in `ar` and `en` for bubble alignment.

### P0.3 — Make SOS symmetric and mutually aware

- **Goal.** Two people in one car have the same emergency affordances, and neither is
  unaware that the other has raised an alarm.
- **Design.** Extract one `SosView` into `flutter_shared` from the captain's screen (the
  stronger visual treatment) plus the rider's confirmation dialog, GPS pre-flight and
  share action (the stronger behaviours) — the union, not either one. Server-side, extend
  the `POST /safety/sos` handler to resolve the trip's counterpart from `rider_id`/
  `captain_id` and notify them, and broadcast to the TripRoom so an open app reacts
  immediately. Add `POST /safety/sos/:id/cancel` so a false alarm can be withdrawn, with
  the alert row moving to `status='cancelled'` and administrators notified of the
  withdrawal.
  **The product decision of *whether* the counterpart should be notified, and in what
  wording, belongs to T17** — this item builds the mechanism and makes the two clients
  identical; T17 sets the policy.
- **Files.** new `packages/flutter_shared/lib/widgets/sos_view.dart`; both
  `sos_screen.dart` files reduced to thin wrappers; `apps/api/src/routes/safety.ts:15-51`.
- **DB.** migration `0020_sos_cancellation.sql` — add `cancelled_at TEXT`,
  `cancelled_by TEXT` to `sos_alerts`; widen the `status` check to include `'cancelled'`.
- **API contract.** `POST /safety/sos/:id/cancel` → `200 {ok:true}` / `409 {code:"ALREADY_RESOLVED"}`.
- **Effort.** M. **Risk.** Notifying the counterpart is a safety-policy change and could be
  wrong in a coercion scenario — ship it behind a config flag, default off, until T17 rules.
- **Acceptance.** Both apps render the same SOS screen, both require confirmation, both
  can share a tracking link, both can withdraw an alert, and both are correct in dark mode.
- **Tests.** Integration test: rider SOS → counterpart notification row exists; cancel → status flips.

### P0.4 — Reconcile the two definitions of balance

- **Goal.** One number, one definition, three surfaces.
- **Design.** Make `users.wallet_balance` the single authority and change
  `GET /captain/wallet` to read it, keeping the ledger aggregation only as a
  reconciliation figure returned alongside (`balanceLedger`) so a mismatch is detectable
  rather than invisible. Log a warning when they differ by more than a piastre.
  **The correctness of the underlying ledger is T03's**; this item is only about the two
  apps agreeing on which field they display.
- **Files.** `apps/api/src/routes/wallet.ts:56-90`;
  `apps/captain/lib/screens/earnings/wallet_screen.dart:78`.
- **DB.** none. **API contract.** `GET /captain/wallet` gains `balanceLedger: number`;
  `balance` semantics change to match the rider's.
- **Effort.** S. **Risk.** If the two genuinely disagree today, captains' displayed balances
  will visibly move on deploy. Run the comparison as a read-only report first — that report
  is the deliverable that tells T03 whether there is a real ledger bug.
- **Acceptance.** `GET /user/wallet` and `GET /captain/wallet` return the same `balance`
  for the same user id; the payout guard reads the same field the screen displays.
- **Tests.** Fixture captain with topup + commission + payout rows; assert all three agree.

### P0.5 — Close the captain's missing actions

- **Goal.** The captain can act on the trip they are driving.
- **Design.** Add a cancel affordance to `ActiveTripPanel` — destructive styling, confirm
  dialog, reason picker matching the rider's `{'reason': …}` payload — calling the
  `/trips/:id/cancel` endpoint that already exists and already notifies the rider
  (`trips.ts:816-820`). Add a completion summary sheet on the `completed` transition
  before `activeTrip` is nulled, showing the fare, the commission and the net, mirroring
  the rider's completion screen. Add an explicit cancellation notice for the captain when
  the rider cancels, instead of the panel silently disappearing.
- **Files.** `apps/captain/lib/screens/home/active_trip_panel.dart:441-474`;
  `apps/captain/lib/services/captain_state.dart:879-890` (retain the trip long enough to
  render the summary).
- **DB.** none. **API contract.** none — the endpoint exists and is unused.
- **Effort.** M. **Risk.** Captain-initiated cancellation is abusable; rate-limit it and
  count it against the captain's reliability metric. Flag to **T18**.
- **Acceptance.** Every terminal state produces an explicit in-app surface for the captain.
- **Tests.** Widget tests for the three terminal transitions.

### P0.6 — `scripts/check_app_parity.py`, wired into CI

- **Goal.** The drift this document catalogues cannot silently return.
- **Design.** A Python checker in the style of the existing
  `scripts/check_l10n_parity.py`, with four independent checks and a `--json` mode:
  1. **Duplicate widget/class names** — any `class X` declared in both `apps/rider/lib` and
     `apps/captain/lib` that is not in `packages/flutter_shared`. Seeded allowlist for
     legitimate twins during migration; the allowlist may only shrink.
  2. **Duplicate string literals** — any Arabic literal ≥ 8 characters appearing in both
     apps and absent from `app_strings.dart`.
  3. **Hardcoded Arabic budget** — count Arabic literals in each app's `screens/`; fail if
     the count *increases* against a committed baseline (rider 302, captain 30). A ratchet,
     not a cliff — it lets the 302 be paid down without blocking every PR.
  4. **Dependency lockstep** — every package in both pubspecs must carry an identical
     constraint; deltas must be listed in an explicit `PARITY_ALLOWED_DEPS` set
     (currently `webview_flutter`).
  5. **Status vocabulary** — parse `TRIP_TRANSITIONS` from `packages/shared/src/index.ts`
     and the Dart enum from P0.1; fail on any difference.
  The full script is at `docs/plan/assets/27-check-app-parity.py.txt` and reproduced in
  §6.7 below. It is delivered as an asset rather than as `scripts/check_app_parity.py`
  because this phase is review-and-plan only and my PR must not add product code.
- **Files.** new `scripts/check_app_parity.py` (implementation phase); CI wiring —
  proposed YAML at `docs/plan/assets/27-parity-ci.yml.txt`, because the GitHub App has no
  `workflows` permission.
- **DB / API.** none.
- **Effort.** S for the script, S for CI wiring.
- **Risk.** A noisy checker gets disabled. Ship checks 1, 4 and 5 as hard failures
  (currently green or nearly so) and checks 2 and 3 as warnings for the first two sprints.
- **Acceptance.** CI fails a PR that adds a class to both apps, or that adds an Arabic
  literal to a screen, or that bumps a dependency in one app only.
- **Tests.** Fixture repos for each check, pass and fail.

### P1.1 — Extract the socket client

One `TripSocket` in `flutter_shared` with `Stream<Map<String,dynamic>> messages` **and**
`Stream<SocketStatus> status`, replacing all three clients
(`rider/…/trip_ws.dart`, `captain/…/trip_ws.dart`, `captain/…/offers_ws.dart` — the last
parameterised by path). Wire the status stream to a shared connection banner shown during
an active trip in both apps, which is currently shown in neither. **Effort M.** Transport
semantics are **T07**'s; this is deduplication and surfacing only.

### P1.2 — Extract wallet, splash and login shells

In that order, because it is the order of behavioural risk. The wallet balance card is
already pixel-identical (PR #52) and should become one `BalanceCard` widget with an
`action` slot (top-up vs withdraw) — an hour's work that permanently prevents the two
cards diverging again. Splash and login are larger (531/487 and 1044/830 lines) and
mostly differ in hero imagery and copy; extract the scaffold and keep per-app content
slots. **Effort:** S (wallet), M (splash), L (login).

### P1.3 — Ratify and enforce the glossary

Adopt §6.6 as the canonical glossary, fix the violations it lists, then let check 2 of
the parity script hold the line.

### P1.4 — Unify the third surface

Delete the colour ramp from `apps/admin/src/design/globals.css` and generate the CSS
variables from `tokens.ts` so there is one declaration; correct the brand green to
`#4e842d`; add the missing `.dark {}` block; align the radius scale to Flutter's; and
resolve the Cairo-vs-IBM-Plex decision (see §10). **Effort M.** Coordinate with **T12**.

### P1.5 — Kill the dead code

Remove `loading_overlay`, `offline_gate`, `ApiClient`, `TripModel`, `UserModel` — or adopt
them. Adopting `ApiClient` is the higher-value path: it would delete two hand-rolled HTTP
layers and one duplicated auth-refresh implementation. Decide, then act; leaving exported
dead code in a shared package actively misleads the next contributor.

### P2.1 — Retire the ARB pipeline

104 `.arb` keys across four files, two `l10n.yaml` files, two generated directories and a
`generate: true` flag, none of which runs. Either delete it or migrate `AppStrings` onto
it. Recommendation and rationale in §10; the decision belongs to **T14**.

### P2.2 — Destination change, end to end

Row 9 of the paired-state table is empty on all three columns. Designing it is **T16**'s
job (feature gap); what §6 records is the parity requirement: whatever is built must emit
a state change both apps consume, and must be in the shared state machine from day one
rather than added to one app first.

### 6.6 The canonical glossary

Arabic is the product's primary language; English is secondary. Identifiers stay English.

| Concept | Canonical AR | Canonical EN | Violations to fix |
|---|---|---|---|
| The driver | **كابتن** | captain | «سائق» at `app_strings.dart:2706,:2710`; `captain_bids_sheet.dart:344,:362` |
| The passenger | **راكب** | rider | «عميل» at `app_strings.dart:1820,:1851,:1855`; `counter_offer_sheet.dart:125,:157`; `ride_request_model.dart:42` |
| The journey | **رحلة** | trip | none — already consistent |
| Money charged for a trip | **أجرة** | fare | «سعر» used for estimates at `app_strings.dart:1823,:3165` — allowed **only** for a negotiated offer amount |
| A captain's price proposal | **عرض** | offer | consistent; keep «مزايدة» out |
| Pickup point | **نقطة الانطلاق** | pickup point | «نقطة الالتقاط» `app_strings.dart:1835`; «موقف الراكب» captain ARB; «موقع الانطلاق» `ride_request_model.dart:47` |
| Dropoff | **الوجهة** | destination | «نقطة الوصول» used interchangeably in rider strings |
| Vehicle | **مركبة** formal / **سيارة** in «رخصة السيارة» | vehicle | mixed within `app_strings.dart:2445` vs `:3425` |
| Rider's money | **الرصيد** | balance | consistent |
| Captain's money | **الأرباح** gross, **الرصيد المتاح للسحب** withdrawable | earnings / available balance | consistent by design — keep the distinction |
| Platform's cut | **عمولة** | commission | consistent |
| Adding money | **شحن** | top-up | rider-only, correct |
| Taking money out | **سحب** | withdrawal | captain-only, correct |
| Status: searching | **جارٍ البحث** | searching | consistent |
| Status: en route | rider «كابتن في الطريق» / captain «في الطريق إلى الراكب» | en route | intentional per-perspective difference — declare it in P0.1 |
| Status: arrived | rider «وصل الكابتن» / captain «في انتظار الراكب» | arrived / waiting | intentional |
| Status: in progress | **الرحلة جارية** | in progress | consistent |
| Status: completed | **مكتملة** | completed | «وصلت» `:2410` and «اكتملت» `:1952` — keep «وصلت بسلامة!» only as the congratulation, not the status |
| Status: cancelled | **ملغية** | cancelled | consistent |
| Cancel / accept / decline | **إلغاء / قبول / رفض** | cancel / accept / decline | consistent |

### 6.7 The parity check

```python
#!/usr/bin/env python3
"""check_app_parity.py — fail the build when rider and captain drift apart.

Companion to check_l10n_parity.py. Five checks, each independently skippable:

  widgets  a class defined in BOTH apps but not in packages/flutter_shared
  strings  an Arabic literal >= 8 chars in BOTH apps but not in app_strings.dart
  arabic   hardcoded Arabic literals per app, ratcheted against a baseline
  deps     a package whose version constraint differs between the two pubspecs
  status   the Dart TripStatus enum vs TRIP_TRANSITIONS in packages/shared

Exit 0 clean, 1 on a hard failure, 0 with warnings when --warn-only.
"""
from __future__ import annotations
import argparse, json, re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RIDER, CAPTAIN = ROOT / "apps/rider/lib", ROOT / "apps/captain/lib"
SHARED = ROOT / "packages/flutter_shared/lib"
STRINGS = SHARED / "l10n/app_strings.dart"
TS_STATE = ROOT / "packages/shared/src/index.ts"

# Twins that may legitimately exist in both apps while extraction is in flight.
# This set may only ever SHRINK. Adding to it requires a reviewer's sign-off.
ALLOWED_TWIN_CLASSES = {
    "SosScreen", "TripChatScreen", "SplashScreen", "LoginScreen", "WalletScreen",
}
ALLOWED_DEP_DELTAS = {"webview_flutter"}   # rider-only: Paymob top-up WebView
ARABIC_BASELINE = {"rider": 302, "captain": 30}

ARABIC = re.compile(r"[؀-ۿ]")
CLASS_RE = re.compile(r"^\s*class\s+([A-Z]\w+)", re.M)
LITERAL_RE = re.compile(r"'([^'\n]*)'|\"([^\"\n]*)\"")
DEP_RE = re.compile(r"^  ([a-z_0-9]+):\s*(\S+)\s*$", re.M)


def dart_files(root: Path):
    return [p for p in root.rglob("*.dart") if "/l10n/generated/" not in p.as_posix()]


def classes(root: Path) -> dict[str, str]:
    found = {}
    for f in dart_files(root):
        for m in CLASS_RE.finditer(f.read_text(encoding="utf-8")):
            found.setdefault(m.group(1), f"{f.relative_to(ROOT)}:{f.read_text(encoding='utf-8')[:m.start()].count(chr(10)) + 1}")
    return found


def arabic_literals(root: Path) -> dict[str, str]:
    """Arabic string literals in screen code, keyed by literal -> first path:line."""
    out = {}
    for f in dart_files(root):
        if "/screens/" not in f.as_posix():
            continue
        for i, line in enumerate(f.read_text(encoding="utf-8").splitlines(), 1):
            if line.lstrip().startswith("//") or not ARABIC.search(line):
                continue
            for m in LITERAL_RE.finditer(line):
                lit = m.group(1) or m.group(2) or ""
                if ARABIC.search(lit):
                    out.setdefault(lit.strip(), f"{f.relative_to(ROOT)}:{i}")
    return out


def deps(pubspec: Path) -> dict[str, str]:
    body = pubspec.read_text(encoding="utf-8")
    body = body.split("dev_dependencies:")[0]
    return {m.group(1): m.group(2) for m in DEP_RE.finditer(body)}


def check_widgets(fail, warn):
    shared = set(classes(SHARED))
    both = set(classes(RIDER)) & set(classes(CAPTAIN))
    for name in sorted(both - shared - ALLOWED_TWIN_CLASSES):
        fail(f"widgets: `{name}` is defined in BOTH apps and is not in flutter_shared")
    for name in sorted(ALLOWED_TWIN_CLASSES & (both - shared)):
        warn(f"widgets: `{name}` still duplicated (allowlisted — extract it)")


def check_strings(fail, warn):
    known = STRINGS.read_text(encoding="utf-8") if STRINGS.exists() else ""
    r, c = arabic_literals(RIDER), arabic_literals(CAPTAIN)
    for lit in sorted(set(r) & set(c)):
        if len(lit) >= 8 and lit not in known:
            fail(f"strings: {lit!r} is hardcoded in both apps ({r[lit]}, {c[lit]}) "
                 f"and absent from app_strings.dart")


def check_arabic(fail, warn):
    for app, root in (("rider", RIDER), ("captain", CAPTAIN)):
        n = len(arabic_literals(root))
        base = ARABIC_BASELINE[app]
        if n > base:
            fail(f"arabic: {app} hardcoded literals rose {base} -> {n}; "
                 f"use AppStrings for new copy")
        elif n < base:
            warn(f"arabic: {app} improved {base} -> {n}; lower the baseline")


def check_deps(fail, warn):
    r, c = deps(ROOT / "apps/rider/pubspec.yaml"), deps(ROOT / "apps/captain/pubspec.yaml")
    for pkg in sorted(set(r) & set(c)):
        if r[pkg] != c[pkg]:
            fail(f"deps: {pkg} is {r[pkg]} (rider) vs {c[pkg]} (captain)")
    for pkg in sorted(set(r) ^ set(c)):
        if pkg not in ALLOWED_DEP_DELTAS and pkg != "flutter_shared":
            fail(f"deps: {pkg} exists in only one app and is not allowlisted")


def check_status(fail, warn):
    ts = TS_STATE.read_text(encoding="utf-8")
    block = re.search(r"TRIP_TRANSITIONS[^{]*\{(.*?)\n\};", ts, re.S)
    if not block:
        warn("status: could not parse TRIP_TRANSITIONS — skipping")
        return
    canonical = set(re.findall(r"^\s*(\w+):", block.group(1), re.M))
    dart = SHARED / "models/trip_status.dart"
    if not dart.exists():
        warn("status: trip_status.dart not present yet (see plan P0.1)")
        return
    body = dart.read_text(encoding="utf-8")
    enum = re.search(r"enum\s+TripStatus\s*\{(.*?)\}", body, re.S)
    got = {re.sub(r"([A-Z])", lambda m: "_" + m.group(1).lower(), v.strip()).lstrip("_")
           for v in enum.group(1).split(",") if v.strip()} if enum else set()
    for s in sorted(canonical - got):
        fail(f"status: `{s}` is in TRIP_TRANSITIONS but missing from the Dart enum")
    for s in sorted(got - canonical):
        fail(f"status: `{s}` is in the Dart enum but not in TRIP_TRANSITIONS")


CHECKS = {"widgets": check_widgets, "strings": check_strings, "arabic": check_arabic,
          "deps": check_deps, "status": check_status}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="*", choices=sorted(CHECKS), default=sorted(CHECKS))
    ap.add_argument("--warn-only", action="store_true")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    failures: list[str] = []
    warnings: list[str] = []
    for name in args.only:
        CHECKS[name](failures.append, warnings.append)

    if args.json:
        print(json.dumps({"failures": failures, "warnings": warnings}, ensure_ascii=False, indent=2))
    else:
        for w in warnings:
            print(f"WARN  {w}")
        for f in failures:
            print(f"FAIL  {f}")
        print(f"\n{len(failures)} failure(s), {len(warnings)} warning(s)")
    return 1 if failures and not args.warn_only else 0


if __name__ == "__main__":
    sys.exit(main())
```

### 6.8 The parity contract

The rule set that keeps the two apps aligned. Short enough to be read, specific enough to
be enforced.

**Always shared — a PR adding these to one app only should be rejected:**

1. Anything that renders trip state, or maps a status to a label, colour or icon.
2. Any widget whose class name would exist in both apps.
3. Any user-visible string. Copy lives in `app_strings.dart`, never in a screen.
4. Transport clients: sockets, the API client, auth refresh, FCM registration.
5. Money formatting and the meaning of every money word.
6. Safety surfaces. SOS and chat are shared components; per-app divergence needs a
   written product reason in the PR body.
7. Design tokens. No `Color(0x…)`, no bare `BorderRadius.circular(n)` where a token exists.
8. Dependency versions.

**May legitimately differ — no justification required:**

1. Navigation structure and tab composition (`main_bottom_nav` is already configured
   per-app and that is correct).
2. Screens only one role has: documents/onboarding/earnings for the captain, saved
   places/promos/top-up for the rider.
3. Copy *perspective* for the same state — «كابتن في الطريق» vs «في الطريق إلى الراكب» —
   provided both come from the shared per-perspective label function in P0.1.
4. Hero imagery, launch assets, store metadata.
5. `webview_flutter` and any future dependency listed in `PARITY_ALLOWED_DEPS`.

**Reviewer checklist — paste into the PR template:**

- [ ] Does this change a trip state, a status label, or a state transition? If yes, is the
      shared `TripStatus` updated and are **both** apps' labels reviewed?
- [ ] Does it touch chat, SOS, wallet, splash or login? If yes, what is the counterpart
      app doing about the same change?
- [ ] Any new user-visible string — is it in `app_strings.dart` with both `ar` and `en`?
- [ ] Any new widget — could the other app need it? If yes, it goes in `flutter_shared`.
- [ ] Any new dependency — added to both pubspecs at the same version, or allowlisted?
- [ ] Does it add a notification? Is the counterpart notified, and is the wording register
      consistent?
- [ ] `python3 scripts/check_app_parity.py` passes.

---

## 7. Phasing

| Item | Phase | Effort | Owner type |
|---|---|---|---|
| P0.2(a) rider chat order + live delivery | **P0** | S | Flutter |
| P0.4 reconcile balance definition | **P0** | S | backend |
| P0.6 parity script + CI | **P0** | S | ops |
| P0.1 shared Dart state machine | **P0** | M | Flutter |
| P0.3 SOS symmetry + mutual awareness | **P0** | M | Flutter + backend |
| P0.5 captain cancel + completion summary | **P0** | M | Flutter |
| P0.2(b) extract `TripChatView` | **P1** | M | Flutter |
| P1.1 extract socket client | **P1** | M | Flutter |
| P1.2 extract wallet card / splash / login | **P1** | S / M / L | Flutter |
| P1.3 glossary ratification + fixes | **P1** | M | Flutter + content |
| P1.4 unify admin tokens, green, dark mode, radii | **P1** | M | admin |
| P1.5 remove or adopt dead shared code | **P1** | S | Flutter |
| F-27-06 no-captain-found resolution | **P1** | M | backend (with T06) |
| F-27-27 rider SOS dark mode | **P1** | S | Flutter |
| F-27-30 captain lint exclude | **P1** | S | Flutter |
| F-27-32 `StatusChip` dark mode | **P1** | S | Flutter |
| P2.1 retire or adopt the ARB pipeline | **P2** | M | Flutter (T14 decides) |
| P2.2 destination change | **P2** | L | backend + Flutter (T16 owns) |
| F-27-33 platform/appRole in device registration | **P2** | S | Flutter |
| F-27-35 read receipts | **P2** | M | backend + Flutter |

**P0 rationale.** The six P0 items are the ones where the two apps actively mislead the
people using them — a chat that reads backwards, an emergency the other occupant never
hears about, and two different answers to "what is my balance" — plus the two structural
pieces (shared state machine, CI check) without which every fix below them decays. The
three S-effort items are a day's work between them and should not wait for the M ones.

---

## 8. Metrics

Nothing in this document is provable without instrumentation. Name the metric, the value
today, the target.

| Metric | How | Today | Target |
|---|---|---|---|
| Duplicate classes across apps not in `flutter_shared` | `check_app_parity.py --only widgets` | 6 allowlisted twins | 0 by end of P1 |
| Hardcoded Arabic literals in screens | `check_app_parity.py --only arabic` | rider 302 · captain 30 | rider < 50 · captain 0 |
| Shared-package usage | `AppTokens.` references | rider 561 · captain 988 | within 25 % of each other, normalised per screen |
| Dead exports in `flutter_shared` | usage grep per export | 5 (2 widgets, 3 types) | 0 |
| Chat delivery latency, per role | client timestamp on render minus `created_at` | rider: unbounded (no live path) · captain: < 6 s | p95 < 3 s **both roles** |
| Chat ordering defects | golden test | rider reversed | 0 |
| State-label divergence | count of status strings declared outside the shared enum | 7 (rider) + 3 (captain) | 0 |
| Counterpart-notified rate on SOS | server: alerts with a counterpart notification row | 0 % | 100 % (subject to T17 policy) |
| SOS false-alarm withdrawals | `sos_alerts.status='cancelled'` | not possible | measurable at all |
| Balance disagreement | nightly job diffing the two computations | unknown — **measure first** | 0 accounts differing |
| Captain terminal-state coverage | terminal states with an explicit captain surface | 0 of 3 | 3 of 3 |
| Dependency lockstep | `check_app_parity.py --only deps` | 0 violations | hold at 0 |
| Brand-colour agreement | token diff Flutter vs admin | 1 mismatch (`#4e842d` vs `#6bb522`) | 0 |
| Two-phone test | filmed trip, count disagreement moments | 5 known | 0 |

The last row is the brief's own test and the only one that matters to a passenger.

---

## 9. Cross-cutting notes

Findings outside my axis, addressed to their owners. I have not fixed any of these.

- **→ T03 (Money integrity).** Two things. (1) `GET /captain/wallet`
  (`apps/api/src/routes/wallet.ts:58-72`) recomputes a balance from
  `type IN ('commission','payout','adjustment')` — a captain top-up (`type='topup'`) is
  therefore invisible in their own balance, and the payout guard reads a third source,
  `users.wallet_balance`. (2) `type='commission'` is used for **both** directions — the
  captain's credit on a non-cash trip and the captain's debit on a cash trip — so the
  ledger renders the same icon and label for money in and money out. Both are parity
  symptoms of what may be a deeper ledger problem that is yours, not mine.
- **→ T03 / T04.** At trip completion the rider debit records `txnStatus='failed'` when the
  balance is insufficient, and the captain credit block appears to execute regardless. I
  did not fully trace the guard and I am **not** asserting a double-spend — flagging it
  because if true it is an S1 on your axis. Start at `apps/api/src/routes/trips.ts:993-1054`.
- **→ T06 (Dispatch).** No trip ever expires. There is no timeout, no terminal
  "no captain found" status and no cron that ages out a `searching` trip
  (F-27-06). The rider-facing symptom is mine; the dispatch policy is yours.
- **→ T07 (Realtime).** Three socket clients duplicate the same backoff maths
  (`rider/…/trip_ws.dart:93-95`, `captain/…/trip_ws.dart:110-111`, `offers_ws.dart:90-96`),
  none has a maximum attempt count, and captain location reaches the rider's map only over
  the socket with no HTTP fallback — so the marker freezes silently on a drop. Also: the
  rider's `TripWebSocketService` exposes `onStatus` that no caller wires
  (`trip_screen.dart:134-153`), and the captain's equivalent has no status surface at all.
- **→ T09 (Rider journey).** The rider app carries 302 hardcoded Arabic lines and
  surfaces raw `Exception:` strings to users (`trip_chat_screen.dart:67`,
  `sos_screen.dart:88,:107`). Both are rider-app quality debt beyond the parity angle.
- **→ T10 (Captain journey).** The captain has no in-app surface for any terminal state:
  no completion summary, no cancellation notice, no cancel action. Detail in F-27-05,
  F-27-09, F-27-10.
- **→ T11 / T12 (Admin, Design system).** `apps/admin/src/design/globals.css:167` overrides
  the brand green declared in `tokens.ts:32`; the radius scale is compressed against
  Flutter; `.dark {}` is missing entirely so the dark toggle does nothing; and
  `Badge.tsx` hardcodes hex values that match Flutter's badge tokens today only by
  coincidence.
- **→ T12 (Design system).** `StatusChip` — a *shared* widget — hardcodes four light-mode
  colours at `packages/flutter_shared/lib/widgets/status_chip.dart:52-58`, so both apps
  render light chips on dark panels at once.
- **→ T14 (i18n).** The whole ARB pipeline is inert: 104 keys across four files, generated
  Dart present, delegate never registered in either `main.dart`. Meanwhile 544 real keys
  live in a hand-written `app_strings.dart`. Two `.arb` keys collide with different values
  (`appTitle`, `appSlogan`). The decision to delete or adopt is yours; §10 has my
  recommendation.
- **→ T15 (Accessibility).** Rider SOS is hardcoded to the light palette
  (`sos_screen.dart:31,:33,:116,:145`) — a white emergency screen at night. The captain
  app clamps text scale (`main.dart:69-76`); the rider does not.
- **→ T16 (Feature gap).** Destination change does not exist anywhere: no endpoint, no
  event, no UI, `waypoints` write-once at `trips.ts:475`. Row 9 of my table is empty in
  all three columns.
- **→ T17 (Safety).** The policy question behind F-27-03: *should* the counterpart be told
  when SOS fires, and does that change in a coercion scenario? I have specified the
  mechanism and flagged it off-by-default; the rule is yours. Also yours: no SOS can be
  withdrawn, and `read_at` exists in the chat schema unused.
- **→ T18 (Fraud).** If P0.5 gives captains a cancel button, it needs a rate limit and a
  reliability-score consequence, or it becomes a cherry-picking tool.
- **→ T19 (Notifications).** Asymmetries I found but did not chase: the rider gets no push
  when their accepted bid confirms (socket only); captain document approval/rejection has
  no push at all and relies on a 30 s `/auth/me` poll (`captain_state.dart:107`); the
  promo notification in `notifications_screen.dart` is a hardcoded local mock with no
  server delivery path; and FCM send failures are logged without retry or DLQ.
- **→ T26 (Release engineering).** Both apps are `version: 1.0.0+1` with nothing coupling
  them. Nothing prevents rider 1.2 and captain 1.0 sharing a trip, and the first divergent
  socket event or status string will break the older one. A minimum-supported-version
  handshake belongs on your axis; the parity contract in §6.8 assumes one exists.

---

## 10. Open questions

**Q1 — Should the counterpart be notified when SOS fires?**
*Options.* (a) Always notify the other occupant. (b) Never — administrators only, as
today. (c) Notify by role and reason: tell the captain when a rider reports a medical
issue, stay silent when the reported threat is the captain.
*Recommendation:* **(c)**, built as (a) behind a config flag so the mechanism ships now and
the policy can be set without another release. Alerting the person you may be escaping
from is the failure mode that makes (a) unsafe; telling nobody in the vehicle is the
failure mode that makes (b) negligent. **Owner: product, with T17.**

**Q2 — Delete the ARB pipeline, or migrate onto it?**
*Options.* (a) Delete all four `.arb` files, both `l10n.yaml`, both generated directories
and the `generate: true` flag. (b) Migrate all 544 `AppStrings` keys into ARB and adopt
the standard Flutter pipeline.
*Recommendation:* **(a) now, (b) later if a translation vendor arrives.** The hand-written
class is compile-safe, works today, and 544 keys is a large migration for zero user-visible
gain. Keeping dead scaffolding costs more than deleting it — it is why the rider and
captain `.arb` files already disagree about `appTitle`. **Owner: T14.**

**Q3 — Cairo or IBM Plex Sans Arabic?**
The apps use Cairo, the admin uses IBM Plex Sans Arabic. One must go.
*Recommendation:* **Cairo everywhere.** It is what customers actually see; the admin is
internal and cheaper to change. **Owner: T12.**

**Q4 — Is the pill CTA a rider-specific brand decision or drift?**
The rider uses `radiusPill`, the captain and the shared theme default use `radiusMd`.
*Recommendation:* **treat it as drift and standardise on `radiusMd`**, unless design
asserts the pill. Either answer is fine; what is not fine is the theme default saying one
thing and a whole app overriding it silently.

**Q5 — How far does "one component, two roles" go?**
P0.2 and P0.3 extract chat and SOS as shared components parameterised by role. Taken to
its conclusion, the two apps become one binary with a role switch.
*Recommendation:* **stop at the component layer.** Share chat, SOS, wallet card, sockets,
state machine and tokens; keep two apps, two store listings, two navigation shells. A
single binary would couple release cadences that have good reasons to differ — and that
coupling is **T26**'s problem to weigh in on.

**Q6 — What is the waiting-time policy?**
The captain has watched a clock since `arrived_at` for as long as this app has existed
and the rider has never seen it. Before P0.5 surfaces that timer to the rider, someone
must decide whether waiting is free, and if not, when the meter starts and who is told.
*Recommendation:* show the same timer to both sides immediately — that is a parity fix and
costs nothing — and treat the waiting *fee* as a pricing decision for **T05**.
