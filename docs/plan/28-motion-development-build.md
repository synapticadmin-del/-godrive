# 28 — Motion Development — Shared Animation Library & Signature Moments

> Track: B — Product surface & experience · Reviewer: chat-20260801-1437-b7e2 · Date: 2026-08-01
> Base commit reviewed: `153210b9e2f65b4bcee4f5acbcd047d197ea8251`

## 1. Scope

This document **builds** the motion layer. T13 audits the motion that exists and writes the
specification; this track delivers the code that specification implies. Where the two overlap I
defer to T13 for judgement and spend my pages on implementation.

`docs/plan/13-motion-micro-interactions.md` **does not exist on `main` at the reviewed commit** —
the `docs/plan/` directory itself is absent. I proceeded without it, as the brief permits. Every
audit statement below is therefore first-hand, from the source at the pinned commit, not inherited
from T13. Where T13 later lands a contradicting judgement, T13 wins on judgement; the measurements
here are reproducible against the commit sha.

**In scope:** the motion token set as real Dart; the shared animation primitives both Flutter apps
import; map-marker interpolation; the six signature moments; the launch sequence and its handoff;
money-in-motion; state-change choreography; gesture physics; per-animation frame cost; the
reduce-motion mechanism; a costed rollout.

**Not in scope, and who owns it:** colour/type/spacing tokens and component visual design (**T12**);
the accessibility conformance call and screen-reader behaviour (**T15**); the systematic
rider↔captain↔admin parity programme (**T27** — I feed it, I do not fix it); Arabic copy and RTL
correctness beyond motion direction (**T14**); map/routing accuracy (**T21**); the realtime
transport itself (**T07**) — I consume its cadence, I do not redesign it.

**One structural warning up front.** The brief asks for a shared animation library living in
`packages/flutter_shared/`. That package **cannot host one today**: it declares no animation
dependency (§4, F-28-02). P0.1 fixes this and everything else depends on it.

## 2. What I actually read

Read in full, at the pinned commit, downloaded to disk and cited by real line number.

**Shared package — `packages/flutter_shared/`**

| File | Note |
|---|---|
| `lib/theme/app_theme.dart` | 40 KB, the whole token system. `AppTokens` (static consts) + `GoTheme` (ThemeExtension). Contains **zero** motion tokens. |
| `lib/flutter_shared.dart` | The export surface. 21 export lines, every widget exported individually, no barrel. |
| `pubspec.yaml` | Dependency list. No `flutter_animate`, no `shimmer`. This is the blocker. |
| `lib/widgets/vehicle_map_marker.dart` | The car silhouette, `CustomPainter`. Stateless. No interpolation. |
| `lib/widgets/go_online_button.dart` | The only well-built animated widget in the package. Pulse + press + container crossfade. |
| `lib/widgets/skeleton_loader.dart` | Hand-rolled shimmer. The **only** shared widget that honours reduce-motion. |
| `lib/widgets/main_bottom_nav.dart` | 24 KB. Indicator tick, crest press, crest shell. Three more hardcoded durations. |
| `lib/widgets/status_chip.dart` | 62 lines, fully static. The most-watched pixel in the product has no motion. |
| `lib/widgets/counter_offer_sheet.dart` | The one shared `showModalBottomSheet`; default transition. |
| `lib/widgets/loading_overlay.dart` | Framework `CircularProgressIndicator`, nothing custom. |
| `lib/widgets/empty_state.dart`, `error_state.dart`, `godrive_wordmark.dart`, `navigation_button.dart`, `go_date_field.dart` | Static. Confirmed by read, not assumed. |
| `lib/widgets/offline_gate.dart`, `offline_guard_banner.dart` | Static shells; delegate motion to embedded `GoOnlineButton`. |
| `lib/widgets/map_controls.dart` | Contains a second, unused `CaptainMapMarker` with heading support. |

**Rider — `apps/rider/`**

| File | Note |
|---|---|
| `lib/main.dart` | `_RootGate` — the app's one genuinely good transition (560 ms fade+scale handoff). |
| `lib/screens/splash_screen.dart` | 3200 ms glow controller, 2400 ms hold timer, reduce-motion gated. |
| `lib/screens/trip/trip_screen.dart` | The live trip. Marker build, status badge, fare reveal, 10 s poll. Highest-value file in this review. |
| `lib/services/trip_ws.dart` | Callback-based socket, 25 s heartbeat, `1<<attempt` backoff. |
| `lib/screens/ride/captain_bids_sheet.dart` | 5 s poll, wholesale list replacement, no keys, no insertion motion. |
| `lib/screens/home/home_screen.dart` | Holds the codebase's only `RepaintBoundary` (line 552). 45 s nearby-captains poll. |
| `lib/screens/home/fare_estimate_sheet.dart`, `vehicle_selector.dart`, `location_search_sheet.dart`, `travel_mode_bottom_bar.dart` | Sheet/strip surfaces. Two `AnimatedContainer`s, otherwise static. |
| `lib/screens/ride/rating_sheet.dart`, `trip_detail_screen.dart` | Static; no haptics on star tap or submit. |
| `lib/screens/wallet/wallet_screen.dart`, `topup_screen.dart` | Money rendering. `toStringAsFixed`, no count-up. |
| `lib/services/app_state.dart`, `location_service.dart` | State + GPS plumbing; read for cadence. |
| `pubspec.yaml` | `flutter_animate ^4.5.0` (line 49), `shimmer ^3.0.0` (line 48), `assets/videos/` (line 63). |

**Captain — `apps/captain/`**

| File | Note |
|---|---|
| `lib/main.dart` | Ternary `home:`, no switcher. Hard cut off splash. |
| `lib/screens/splash_screen.dart` | 3600 ms shared controller, radar rings, road dashes, breathing glow. Not reduce-motion gated. |
| `lib/screens/home/offer_card_entrance.dart` | The one bespoke, well-reasoned animation in the product. Used once. |
| `lib/screens/home/main_shell.dart` | The captain map. `setState` over an `IndexedStack` of five tabs. Heading handling. |
| `lib/screens/home/offer_card.dart` | 15 s countdown controller, per-second haptics in the final 5 s. |
| `lib/screens/home/available_trips_tab.dart`, `nearby_requests_screen.dart` | The two offer lists — with two *different* entrance treatments. |
| `lib/screens/home/active_trip_panel.dart`, `home_tab.dart`, `trips_tab.dart` | Stage stepper, searching pulse, trip list. |
| `lib/services/captain_state.dart` | GPS profiles, offer polling, WS status debounce. Source of the cadence numbers. |
| `lib/services/trip_ws.dart`, `offers_ws.dart` | Stream-based sockets — divergent from the rider's callback shape. |
| `lib/screens/earnings/earnings_screen.dart`, `wallet_screen.dart` | Earnings hero, instant spinner→content swap. |
| `pubspec.yaml` | `flutter_animate ^4.5.0` (line 44), `shimmer ^3.0.0` (line 41), `assets/videos/` (line 59). |

**Skimmed, not read line by line:** `apps/*/lib/l10n/generated/**` (generated), `apps/*/lib/screens/documents/**`,
`profile/**`, `history/**`, `places/**` — opened to confirm they contain no animation constructs, which
they do not. `pubspec.lock` read only for the `flutter_animate` resolution.

**Not read:** `apps/api/**`, `apps/admin/**`, migrations. Nothing in this axis depends on them.

**Method note.** All 80 Dart/YAML files were pulled at commit `153210b9` and analysed on disk, so
every `path:line` below points at that exact snapshot. Whole-tree counts (`Hero(` = 0,
`RepaintBoundary` = 1, `pageTransitionsTheme` = 0) are `grep` over the full 36,326 lines of Dart,
not over a sample.

## 3. How it works today

### 3.1 There is no motion system — there are 24 hardcoded numbers

`app_theme.dart` is a genuinely good token file: a full colour ramp, a 7-step spacing scale
(`space2xs=4` … `space2xl=48`, lines 171–177), a 6-step radius scale (`radiusXs=6` … `radiusPill=999`,
lines 161–166), typography, and a `GoTheme` `ThemeExtension` for brightness-varying values
(`app_theme.dart:302`, resolver at `:373`).

It contains **zero** duration tokens, **zero** curve tokens, and **zero** animation semantics. A
`grep` for `Duration`, `Curve`, `Curves.`, `motion`, `transition` across all 800+ lines returns
nothing.

The consequence is that every duration in the product is a literal typed at the call site. The
values actually in use:

| Duration | Where | Cite |
|---|---|---|
| 120 ms | GoOnlineButton press scale | `go_online_button.dart:127` |
| 140 ms | Bottom-nav crest press | `main_bottom_nav.dart:453` |
| 160 ms | Vehicle selector item | `vehicle_selector.dart:349` |
| 200 ms | Nav indicator tick; category chip | `main_bottom_nav.dart:619`, `vehicle_selector.dart:184` |
| 220 ms | Crest shell | `main_bottom_nav.dart:376` |
| 250 ms | Stage stepper dot | `active_trip_panel.dart:664` |
| 260 ms | GoOnlineButton container | `go_online_button.dart:131` |
| 300 ms | Nearby-requests entrance (flutter_animate default) | `nearby_requests_screen.dart:287` |
| 460 ms / 70 ms stagger | OfferCardEntrance | `offer_card_entrance.dart:26-27` |
| 500 ms | Captain splash brand switcher | `captain/splash_screen.dart:175` |
| 560 ms | Rider root handoff | `rider/main.dart:145` |
| 1400 ms | Online pulse period | `go_online_button.dart:45` |
| 1450 ms | Skeleton sweep period | `skeleton_loader.dart` `_kSweepDuration` |
| 1500 ms | Waiting-for-offers radar | `available_trips_tab.dart:158` |
| 1600 ms | Searching pulse | `home_tab.dart:374` |
| 1800 ms | Captain wordmark shimmer | `captain/splash_screen.dart:232` |
| 2400 ms | Rider splash hold | `rider/splash_screen.dart:97` |
| 3200 ms / 3600 ms | Rider / captain splash controllers | `rider/splash_screen.dart:59`, `captain/splash_screen.dart:45` |

Six near-duplicate values cluster in the 120–260 ms band doing the same job (a press or a small
state change) with no shared meaning. Curves are equally ad hoc: `easeOut`, `easeOutCubic`,
`easeOutBack`, `easeInOut`, `easeInCubic`, `elasticOut` appear across 42 sites with no rule for
which is used when, and several `AnimatedContainer`s specify **no curve at all** — so they run
`Curves.linear`, which is why the nav indicator tick (`main_bottom_nav.dart:619`) and the stage
stepper dot (`active_trip_panel.dart:664`) read mechanical next to the eased widgets beside them.

### 3.2 The shared package cannot hold the shared library

`packages/flutter_shared/pubspec.yaml` declares `http`, `firebase_core`, `firebase_messaging`,
`flutter_local_notifications`, `google_fonts` and `url_launcher`. It does **not** declare
`flutter_animate` or `shimmer`. Both apps do (`rider/pubspec.yaml:48-49`,
`captain/pubspec.yaml:41,44`).

The package's own comments show the team has already been bitten by exactly this class of bug
twice — `google_fonts` at lines 17–19 and `url_launcher` at lines 21–24 were both added
retroactively because "this import resolved only because every consuming app happened to depend on
it, so the package did not analyse standalone."

Today no shared file imports `flutter_animate`, so there is no live bug — `skeleton_loader.dart`
hand-rolls its shimmer with a raw `AnimationController` rather than using the `shimmer` package
that both apps ship. But the moment anyone writes the animation library the brief asks for into
`packages/flutter_shared/`, they reintroduce the same failure. This is why P0.1 exists.

### 3.3 The map: everything teleports

**Cadence.** There is no timer driving position. `CaptainState._startLocationStream()`
(`captain_state.dart:619-626`) sets two `LocationSettings` profiles:

- idle/online, no trip — `LocationAccuracy.medium`, `distanceFilter: 50` m
- active trip (`assigned`/`accepted`/`arrived`/`in_progress`) — `LocationAccuracy.high`, `distanceFilter: 10` m

No `intervalDuration` is set on either, so delivery is event-driven: one push per 10 m travelled
during a trip. Converted to time, that is roughly **one update every 1.2 s at 30 km/h**, ~0.7 s at
50 km/h, and ~7 s at walking pace. Each fix is POSTed to `/captain/location`
(`captain_state.dart:641-657`) with no client-side throttle; the server fans it out to the rider's
trip room as `location.captain`.

**Rendering.** The rider handles that event at `trip_screen.dart:145-151` with
`setState(() => _captainLoc = LatLng(lat, lng))`. `_buildMarkers()` (`:379-393`) then constructs a
fresh `Marker` at the new `point:` and `MarkerLayer` (`:273`) re-renders. There is no `Tween`, no
`AnimationController`, no `TweenAnimationBuilder` anywhere in the marker path of either app.

The result on screen: **the car jumps 10 metres, waits ~1.2 seconds, jumps again.** At city speed
that is a visible hop roughly once per second for the entire duration of the trip, on the screen
the rider stares at while waiting. This is the single largest perceived-quality defect in the
product and it is entirely a client-side rendering choice — the data arriving is fine.

**Bearing.** The captain's own marker gets a heading: `position.heading` is read at
`main_shell.dart:229-231` and passed at `:612`. `VehicleMapMarker` applies it with a bare
`Transform.rotate` (`vehicle_map_marker.dart:44-56`) — no normalisation, so a 359°→1° transition
rotates the car **backwards through 358°**.

The rider gets nothing. `trip_screen.dart:387-390` constructs `VehicleMapMarker(color: go.action,
size: 46)` with **no `heading` argument at all**. `heading` defaults to `null`, `angle` resolves to
0, and the captain's car points **due north for the entire trip** regardless of which way it is
driving. A rider watching a car drive south sees it slide backwards. Confirmed by direct read, not
inference.

**Camera.** Every camera move is instant. `_mapController.move(...)` at `main_shell.dart:130, 158,
238, 294` and `fitCamera(...)` at `:303` and `trip_screen.dart:122-129`. `animatedMove` appears
nowhere. So the follow-me camera snaps at the same 1.2 s beat as the marker, doubling the jolt.

**Route.** `PolylineLayer` receives the full point list in one shot
(`trip_screen.dart:255-272`, `main_shell.dart:538-555`). Route geometry is parsed once at load and
never trimmed as the captain advances — no progressive reveal, no travelled/remaining split.

**Rebuild scope.** `setState` on the rider sits in `_TripScreenState`, so a position update rebuilds
`Scaffold → Stack → FlutterMap + status badge + bottom panel` (`trip_screen.dart:220-315`). On the
captain it sits in `_MainShellState`, rebuilding the map **plus an `IndexedStack` holding all five
tab screens** (`main_shell.dart:399-492`). Neither has a `RepaintBoundary`.

The codebase's only `RepaintBoundary` is `home_screen.dart:552`, wrapping the rider's *home* map —
the pre-trip booking map fed by a 45 s poll (`home_screen.dart:197-205`). It is on the one map that
barely updates, and absent from the two that update every second.

### 3.4 Lists and sheets

**No sheet in the product is a real sheet.** Nothing in either app uses `DraggableScrollableSheet`.
`captain_bids_sheet.dart:224` returns a plain `Container` (its own comment at line 18 notes "this
used to be a modal bottom sheet"); `fare_estimate_sheet.dart:231`, `location_search_sheet.dart:126`
(fixed height `0.82 × screen`), `rating_sheet.dart:62` and `counter_offer_sheet.dart:40` are plain
`Container`s handed to `showModalBottomSheet` with no `transitionAnimationController`. So they all
inherit Flutter's default 250 ms `linearToEaseOut` and have **no snap points, no velocity-aware
settling, and no drag physics of their own**. Only three `ScrollPhysics` are specified in the whole
sheet surface: `BouncingScrollPhysics` at `vehicle_selector.dart:86` and `:331`, and
`AlwaysScrollableScrollPhysics` at `available_trips_tab.dart:136`.

**The bid list — the rider's decisive moment.** `captain_bids_sheet.dart:75-78` polls every 5 s.
On each response `setState` replaces `_bids` **wholesale** (`:104-108`); `_buildBody` rebuilds a
`ListView.separated` (`:282`) whose `itemBuilder` (`:287`) returns a bare `_BidCard` (`:290`) with
**no key**. There is no `AnimatedList`, no insertion animation, no cross-fade from the searching
spinner to the list.

What the rider sees when a bid lands: every card on screen **jumps down one row height**, with no
indication which row is new. If the server returns a different order next poll, every row swaps
position at once. This is the moment the rider chooses who drives them, and it currently reads as a
page refresh.

**The offer lists — two different answers to one question.** `OfferCardEntrance`
(`offer_card_entrance.dart:21`) is the best-reasoned piece of motion code in the repo: RTL-aware
slide direction (`:48,54`), an 8-step stagger cap so long lists do not crawl (`:44,49`),
fade+slideX+scaleXY on `easeOutCubic` (`:56-74`). It has **exactly one call site** —
`available_trips_tab.dart:113`.

`nearby_requests_screen.dart:287-291` shows the same kind of list and instead inlines
`.animate().fadeIn(delay: (50*i).ms).slideY(begin: 0.12, end: 0, curve: Curves.easeOut)` — a
different direction, different stagger, different duration, no cap, not RTL-aware. Two screens,
same content, two motion languages. And the rider's bid list, which needs it most, gets neither.

Keys are inconsistent in the same way: `available_trips_tab.dart:115` and
`nearby_requests_screen.dart:280` pass `ValueKey(id)`; `captain_bids_sheet.dart:290`,
`location_search_sheet.dart:300-354`, `saved_destinations_sheet.dart:278` and both
`vehicle_selector.dart` lists pass none. Without stable keys, any insertion animation added later
will animate the wrong rows.

### 3.5 Money and state changes are instant swaps

Every currency amount in the product is a static `Text` built once per `setState`, formatted with
`toStringAsFixed` — `earnings_screen.dart:66,149`, `captain/wallet_screen.dart:683`,
`rider/wallet_screen.dart:412`, `trip_screen.dart:559,738`, `trip_detail_screen.dart:89,189`. `intl`
is imported in both wallet screens but used **only** for `DateFormat` timestamps, never for
currency. There is no count-up anywhere.

`AppTokens.money()` (`app_theme.dart:278-289`) is a `TextStyle` factory — weight 900, `height: 1.1`,
`letterSpacing: -0.5` — so the product already has money *typography*. It has no money *motion*.

**The fare reveal.** On completion, `_completedContent` (`trip_screen.dart:550-565`) renders a
`const Icon(Icons.check_circle, size: 48)`, a headline, and the fare at 28 pt in brand green. The
panel is a plain `Container` in a `Positioned`; `_buildPanelContent` (`:449-457`) is a `switch` that
returns a different child list per status. There is no `AnimatedSwitcher`. The trip's emotional
climax — the number the rider pays — appears at full opacity in a single frame, replacing the
in-progress panel with a hard cut.

**The status chip.** `_statusConfig` (`trip_screen.dart:741-751`) maps seven statuses to label,
colour and icon:

| status | label | colour |
|---|---|---|
| `searching` | جارٍ البحث | warning |
| `offered` | عروض متاحة | success |
| `assigned` | كابتن في الطريق | primary |
| `arrived` | وصل الكابتن | primary |
| `in_progress` | الرحلة جارية | primary |
| `completed` | وصلت | success |
| `cancelled` | ملغية | danger |

`_statusBadge()` (`:412-426`) returns a plain `Container`. The transition the brief calls "the
most-watched pixel in the app" — `كابتن في الطريق` → `وصل الكابتن` — is an instant text-and-colour
swap between two frames. `StatusChip` in the shared package (`status_chip.dart`, 62 lines) is
likewise fully static, so nothing downstream can inherit a fix.

**Success feedback** is uniformly `ScaffoldMessenger.showSnackBar` with no `behavior`, `duration` or
`action` override — `captain/wallet_screen.dart:229,248,253`, `trip_screen.dart:61`,
`topup_screen.dart:71,101`. Errors sometimes set `backgroundColor: AppTokens.danger`, successes
never set anything. There is no animated confirmation of any kind in the product.

### 3.6 Launch: two apps, two philosophies

The captain splash's header comment (`captain/splash_screen.dart:12-16`) records that a video splash
was **already removed** in favour of a static brand PNG, because "the decode took a visible moment."
That decision was correct and is already shipped.

The asset was never deleted. `apps/rider/assets/videos/splash.mp4` and
`apps/captain/assets/videos/splash.mp4` are both still in the tree at **875,855 bytes each —
1.67 MB of dead weight**, still declared via `- assets/videos/` at `rider/pubspec.yaml:63` and
`captain/pubspec.yaml:59`, so Flutter bundles both into every build. Neither app declares
`video_player` in any pubspec, so nothing in either app could play them even if it tried.

The two launch experiences then diverge completely:

| | Rider | Captain |
|---|---|---|
| Controller | `_glowCtrl` 3200 ms (`rider/splash_screen.dart:59`) | `_motion` 3600 ms `..repeat()` (`captain/splash_screen.dart:43-46`) |
| Backdrop | one radial, breathing radius 0.70→0.86 (`:223-278`) | two radials on `sin/cos` orbits (`:373-412`) |
| Radar rings | none | `_RadarPainter`, 3 staggered rings (`:418-446`) |
| Road dashes | none | `_RoadDashesPainter` (`:452-487`) |
| Shimmer | on the brand image, single-shot (`:309`) | on the wordmark, repeating (`:231-234`) |
| Progress | standard `LinearProgressIndicator` (`:407`) | custom translated gradient beam (`:276-281`) |
| Exit trigger | `Timer(2400 ms)` **and** `state.loading == false` (`:97`, `rider/main.dart:102`) | `state.loading == false` only, no timer |
| Handoff | `_RootGate` `AnimatedSwitcher` 560 ms, fade + scale 0.985→1, `easeOutCubic`/`easeInCubic` (`rider/main.dart:143-172`) | **hard cut** — ternary on `home:` (`captain/main.dart:82-86`) |
| Reduce-motion | gated (`:73-77`) | **not gated** |
| Theme-aware | yes (`:130-131,155`) | no, always `AppTokens.splashBg` |

The rider handoff is the best motion in the product: the splash dissolves and scales back a hair
while the destination fades up — the comment at `rider/main.dart:164` correctly calls it "a handoff
rather than a zoom." The captain, arriving at the same moment in the same brand, gets a single-frame
cut from an elaborate animated splash to a login form.

The captain splash also contradicts its own documentation. Lines 20–21 claim "a single
`AnimationController` drives every looping element so the whole screen costs one ticker" — but
`:230` calls `.animate(onPlay: (c) => c.repeat()).shimmer(...)`, and `flutter_animate` allocates
its own controller. The screen runs **two** tickers.

### 3.7 Navigation and reduce-motion

`pageTransitionsTheme` is **not set** in the `ThemeData` built at `app_theme.dart:614-804`. Both
apps call `AppTheme.light()`/`AppTheme.dark()` identically (`rider/main.dart:87-89`,
`captain/main.dart:79-81`). So all **21 `MaterialPageRoute` call sites** across 14 files get the
platform default — `ZoomPageTransitionsBuilder` on Android under M3. `PageRouteBuilder` and
`CupertinoPageRoute` appear nowhere. `Hero()` appears nowhere: **zero** shared-element transitions
in the product.

Reduce-motion is handled in exactly **6 files** out of the whole tree: `skeleton_loader.dart` (the
only shared widget), `rider/main.dart`, `rider/splash_screen.dart`, `rider/login_screen.dart`,
`rider/wallet_screen.dart`, and `captain/earnings/wallet_screen.dart`. The pattern where it exists
is good — `MediaQuery.maybeOf(context)?.disableAnimations ?? false`, controller stopped *and* a
still fallback rendered (`skeleton_loader.dart:58,75,120-121,160`).

It is absent from every other animated surface: `GoOnlineButton`'s 1400 ms infinite pulse, the
bottom nav, the entire captain splash (an unbounded full-screen loop of orbiting gradients,
expanding rings and scrolling dashes), `OfferCardEntrance`, the searching pulses, and the offer
countdown. A user who has switched on "reduce motion" at the OS level sees almost all of it anyway.

## 4. Findings

**No S1 in this axis, and I am not going to invent one.** Severity 1 in this protocol means money
lost, auth bypassed, data corrupted, or the platform cannot go live. Motion does none of those.
What it does is decide whether a rider who has three ride-hailing apps installed opens this one
again. The S2 set below is where that is currently being lost.

| ID | Sev | Finding | Evidence (`path:line`) | Impact | Confidence |
|---|---|---|---|---|---|
| F-28-01 | S2 | Map markers teleport. Zero interpolation; the car hops ~10 m roughly once per second for the whole trip. | `trip_screen.dart:145-151,379-393`; `vehicle_map_marker.dart:19-56`; `captain_state.dart:623-626` | The main tracking screen reads as a prototype. Largest single perceived-quality defect. | confirmed |
| F-28-02 | S2 | `flutter_shared` declares no animation dependency, so the shared animation library the product needs cannot live in the shared package. | `packages/flutter_shared/pubspec.yaml:10-24` vs `rider/pubspec.yaml:48-49`, `captain/pubspec.yaml:41,44` | Blocks this entire track. Guarantees motion keeps being duplicated per app. | confirmed |
| F-28-03 | S2 | The rider never receives or renders the captain's heading — the car points north for the entire trip. | `trip_screen.dart:387-390` (no `heading:` arg); cf. `main_shell.dart:612` | A car driving south slides backwards on screen. Actively wrong, not merely plain. | confirmed |
| F-28-04 | S2 | Zero motion tokens. 24 hardcoded durations and 6 curves scattered across call sites, six of them duplicating one another. | `app_theme.dart` (no `Duration`/`Curve` in 800+ lines); table in §3.1 | No consistency is achievable and no reduce-motion switch can be applied centrally. | confirmed |
| F-28-05 | S2 | Reduce-motion honoured in only 6 files. The captain splash runs an unbounded full-screen loop with no still fallback. | `skeleton_loader.dart:120-121` (the good pattern); `captain/splash_screen.dart:43-46` (ungated) | Vestibular-accessibility failure on the first screen every captain sees. Hand-off to T15. | confirmed |
| F-28-06 | S2 | Bid arrival is a wholesale list replacement with no keys and no insertion animation. | `captain_bids_sheet.dart:75-78,104-108,282-290` | The rider's decision moment reads as a page refresh; rows jump with no cue which is new. | confirmed |
| F-28-07 | S2 | Position updates rebuild the whole screen; the only `RepaintBoundary` is on the one map that barely changes. | `trip_screen.dart:220-315`; `main_shell.dart:399-492`; `home_screen.dart:552` | Every GPS tick repaints tiles, panel and (captain) five stacked tabs. Frame-budget risk on low-end Android. | confirmed |
| F-28-08 | S2 | 1.67 MB of dead `splash.mp4` shipped in both bundles; no `video_player` dependency exists to play it. | `apps/rider/assets/videos/splash.mp4` + `apps/captain/…` (875,855 B each); `rider/pubspec.yaml:63`, `captain/pubspec.yaml:59` | Pure install-size waste on a price-sensitive Android market. Free to remove. | confirmed |
| F-28-09 | S2 | The status chip — the most-watched element in the trip — swaps text and colour instantly. | `trip_screen.dart:412-426,741-751`; `status_chip.dart` (fully static) | The arrival moment, which should be the trip's emotional beat, is a single-frame flicker. | confirmed |
| F-28-10 | S2 | Captain splash hard-cuts to the next screen; the rider has a designed 560 ms handoff. | `captain/main.dart:82-86` vs `rider/main.dart:143-172` | Two apps, one brand, opposite launch quality. Hand-off to T27. | confirmed |
| F-28-11 | S3 | Money never animates. Every amount is a static `toStringAsFixed` `Text`. | `earnings_screen.dart:66,149`; `trip_screen.dart:559`; `captain/wallet_screen.dart:683` | Earnings and fare reveal feel like a receipt, not a reward. | confirmed |
| F-28-12 | S3 | No sheet uses `DraggableScrollableSheet`; no snap points, no velocity-aware settling anywhere. | `captain_bids_sheet.dart:224`; `location_search_sheet.dart:126-127`; `fare_estimate_sheet.dart:231` | Sheets are modal rectangles, not manipulable surfaces. Fails the Uber/inDrive baseline. | confirmed |
| F-28-13 | S3 | Two different entrance treatments for the same content; the good one is used once. | `offer_card_entrance.dart:21` used only at `available_trips_tab.dart:113`; `nearby_requests_screen.dart:287-291` | Motion vocabulary is already forking. Cheapest possible fix. | confirmed |
| F-28-14 | S3 | Camera moves are instant at every call site. | `main_shell.dart:130,158,238,294,303`; `trip_screen.dart:122-129` | Follow-me snaps in time with the marker, compounding F-28-01. | confirmed |
| F-28-15 | S3 | No `pageTransitionsTheme`, no `PageRouteBuilder`, zero `Hero` widgets across 21 route pushes. | `app_theme.dart:636-804`; whole-tree grep | Navigation is platform-default; no continuity between screens. | confirmed |
| F-28-16 | S3 | Several `AnimatedContainer`s specify no curve and therefore run linear. | `main_bottom_nav.dart:619`; `active_trip_panel.dart:664`; `vehicle_selector.dart:349` | Mechanical motion sitting directly beside eased motion. | confirmed |
| F-28-17 | S3 | Bearing has no shortest-arc handling: 359°→1° spins the car backwards through 358°. | `vehicle_map_marker.dart:44` | Visible wrong-way spin on the captain's own marker at north-facing turns. | confirmed |
| F-28-18 | S3 | Missing keys on four lists will break any insertion animation added later. | `captain_bids_sheet.dart:290`; `location_search_sheet.dart:300-354`; `saved_destinations_sheet.dart:278`; `vehicle_selector.dart:93,344` | Latent defect that turns P1 work into P2 debugging. | confirmed |
| F-28-19 | S4 | Captain splash documents "one ticker" but runs two — `flutter_animate`'s shimmer allocates its own. | `captain/splash_screen.dart:20-21` vs `:230-234` | Comment drift; a second ticker at cold start. | confirmed |
| F-28-20 | S4 | Rider's most consequential tap (accept a bid) has no haptic; captain's equivalents all do. | `captain_bids_sheet.dart:124,172` (none) vs `offer_card.dart:141,167,202` | Asymmetric physical feedback between the two apps. | confirmed |
| F-28-21 | S4 | Loading→loaded is an instant ternary swap on the earnings screen despite a skeleton system existing. | `earnings_screen.dart:90-91`; `skeleton_loader.dart` unused there | Spinner-to-content pop; the shared skeleton is already built and ignored. | confirmed |
| F-28-22 | S4 | Animated `BoxShadow.blurRadius` (52→70) on a 220 dp container every frame at cold start. | `captain/splash_screen.dart:157-163` | Shadow re-rasterises per frame at the worst moment for frame budget. | likely |

### The S2 set, in prose

**F-28-01 — the car teleports.** This is the finding to fix first after the plumbing. The data is
not the problem: the captain's device emits a fix every 10 m during a trip
(`captain_state.dart:623-626`), which at city speed is roughly one per 1.2 s. The problem is that
the rider's client renders each fix as a discrete position. `setState` writes the new `LatLng`
(`trip_screen.dart:149`), `_buildMarkers()` builds a `Marker` at that exact point (`:379-393`), and
flutter_map places it there on the next frame. Nothing bridges the gap between fix *n* and fix
*n+1*. Uber's map looks continuous not because Uber has better GPS but because Uber tweens between
fixes; this codebase has never had that layer. Everything else in this document is worth less than
this one component.

**F-28-02 — the shared package cannot hold the shared library.** The brief asks for
`packages/flutter_shared/lib/motion/go_motion.dart` and a set of primitives both apps import. Today
that package declares no animation dependency. Pure `Duration`/`Curve` tokens would technically
compile against `flutter/animation.dart`, but the primitives (staggered entrance, shimmer, spring
sheets) will not. The team has already hit this twice — the retroactive `google_fonts` and
`url_launcher` additions documented at `pubspec.yaml:17-24` are the scar tissue. If P0.1 is skipped,
whoever builds this library will put it in one app, the other app will copy it, and the parity
problem T27 owns gets one item longer.

**F-28-03 — the rider's car points north.** `main_shell.dart:612` passes `heading: _heading` for
the captain's own marker. `trip_screen.dart:387-390` omits the argument entirely, so the rider's
view of the captain uses the `null` default and renders at 0°. This is not a missing polish item;
it is a *wrong* rendering. A rider watching their captain drive south sees a car sliding backwards
down the street. It needs a server field (heading on the `location.captain` payload — flag to T07)
plus the client change, and it should ship in the same release as the interpolation, because
tweening a wrongly-oriented car just makes the wrongness smoother.

**F-28-04 — no tokens.** 24 duration literals, six of them (120/140/160/200/220/260 ms) doing the
same job. There is no way to make the product feel coherent while every developer picks a number,
and — more importantly — no way to implement reduce-motion centrally. F-28-05 is a direct
consequence: you cannot switch off what you cannot name.

**F-28-05 — reduce-motion is 6 files deep.** The pattern that exists is correct
(`skeleton_loader.dart:120-121` reads `MediaQuery.maybeOf(context)?.disableAnimations`, stops the
controller, and renders a flat fill). It just is not applied anywhere else. The worst instance is
the captain splash: an unbounded loop of two orbiting radial gradients, three expanding radar rings
and scrolling road dashes, with no gate and no exit timer — it runs until `bootstrap()` finishes.
For a user with a vestibular disorder that is the first thing the app does. I am marking this S2 and
handing the conformance judgement to **T15**; if T15 decides Egypt's accessibility posture or the
store review makes it a launch blocker, it escalates to S1 in their document, not mine.

**F-28-06 — bids land like a page refresh.** The rider is choosing a driver and a price. Every 5 s
(`captain_bids_sheet.dart:75-78`) the entire list is replaced (`:104-108`) and rebuilt without keys
(`:290`). Cards shift down by a row with nothing marking the new one. The captain side already
solved this exact problem — `OfferCardEntrance` exists and is good — and the rider side does not
import it. Fixing this is mostly a matter of moving code that is already written.

**F-28-07 — repaint scope.** On the rider, one GPS tick rebuilds `Scaffold → Stack → FlutterMap +
badge + panel`. On the captain it additionally rebuilds an `IndexedStack` holding all five tabs
(`main_shell.dart:399-492`), four of which are off-screen. Neither map has a `RepaintBoundary`,
while the home map that updates every 45 s has the only one in the codebase
(`home_screen.dart:552`). Adding interpolation without fixing this would take the rebuild from
~1/second to 60/second and turn a cosmetic problem into a thermal one. P0.3 therefore lands the
boundaries *before* P1.1 lands the tweening.

**F-28-08 — 1.67 MB of dead video.** Two identical 875,855-byte `splash.mp4` files, one per app,
still bundled via the `assets/videos/` directory declarations. No `video_player` dependency exists
in any pubspec, and both splash screens were already rewritten to use a static PNG
(`captain/splash_screen.dart:12-16`). This is a two-line deletion that removes 1.67 MB from the
download on a market where install size costs installs. It is the highest ratio of value to effort
in this entire document.

**F-28-09 — the arrival moment flickers.** `وصل الكابتن` is the payoff of the whole waiting
experience. `_statusBadge()` (`trip_screen.dart:412-426`) is a plain `Container` and
`_buildPanelContent` (`:449-457`) is a `switch` returning different children — so status change is a
single-frame swap of text, icon and colour, with the bottom panel changing under it at the same
instant. The shared `StatusChip` is static too, so there is no upstream fix to inherit.

**F-28-10 — one brand, two launches.** The rider's `_RootGate` (`rider/main.dart:143-172`) is a
560 ms fade-and-scale handoff that is genuinely well made. The captain's `home:` ternary
(`captain/main.dart:82-86`) cuts on a single frame. Same company, same splash brand assets, opposite
craft. Handed to **T27** as a parity item, with the fix specified in P1.4 so T27 does not have to
re-derive it.

## 5. Benchmark gap

**Uber — marker interpolation.** Uber's rider map receives location at a comparable cadence and
renders continuous movement by tweening between fixes and rotating the car to the direction of
travel, with the camera easing rather than snapping. Their restraint elsewhere is the other half of
the lesson: the map moves, the chrome mostly does not. *Confident* — this is observable behaviour in
the shipping app and the standard approach documented for their mobile map layer. Synaptic Go has
the same data cadence and none of the interpolation: `trip_screen.dart:379-393` places a marker at a
raw coordinate, `:387-390` omits heading, and `main_shell.dart:238` snaps the camera. **The gap
here is not data or infrastructure — it is one missing widget.**

**inDrive — speed as a discipline.** inDrive's captain-facing surfaces are fast and functional;
motion never sits between a driver and a tap. *Assumed* in the specific numbers, *confident* in the
direction. This gives us the right ceiling: nothing in the captain app should exceed ~240 ms, and
anything on the accept/decline path should be ≤140 ms and fully interruptible. Synaptic Go is
currently *accidentally* compliant here — the captain app is fast because it barely animates, not
because anyone set a budget. `offer_card.dart`'s 15 s countdown with per-second haptics in the final
five (`:112`) is the one place the captain app does apply real urgency, and it is well judged.

**Material 3 — the structural baseline.** M3 specifies duration tokens (short 50–200 ms, medium
250–400 ms, long 450–600 ms) and an emphasised easing set. Synaptic Go's real values map onto that
scale reasonably well by instinct — 120/140/160 ms presses, 200–260 ms state changes, 460–560 ms
entrances — which is a good sign: the numbers are sane, they are just anonymous. Naming them costs
one file. Where we should deliberately exceed M3 is the six signature moments in §6.4; everywhere
else M3 is the right ceiling.

**Revolut / Cash App — money in motion.** The reference behaviour is a short count-up on a value the
user *earned* or *received*, never on a value they are about to be charged, and never blocking the
next tap. *Confident* on the pattern, *assumed* on their exact durations. Synaptic Go has zero
count-up (F-28-11) but already has the typography for it (`AppTokens.money()`,
`app_theme.dart:278-289`). The captain's earnings hero is the single best candidate in the product;
the rider's fare is explicitly the wrong place, and §6.5 draws that line.

**Where Synaptic Go actually sits.** Below all three benchmarks on the tracking map, which is the
screen that matters most. At parity with inDrive on captain-app speed, by accident. Ahead of
nothing. But the distance is short: the product already ships `flutter_animate`, already has one
excellent entrance animation, one excellent screen handoff, a correct reduce-motion pattern, and a
mature token file with a motion-shaped hole in it. This is a track where a small amount of
disciplined work moves the product a long way, which is exactly what the brief claims — and after
reading the code, it is true.

## 6. Improvement plan

Ordered. P0.1–P0.4 are plumbing and deletions that unblock everything else and can land in one
sprint. P1 is the visible product change. P2 is craft.

### P0.1 — Give `flutter_shared` an animation dependency

- **Goal** — make it possible for the shared library to exist at all. Without this, every primitive
  below gets built twice.
- **Design** — add `flutter_animate` and `shimmer` to the shared package's own manifest, matching the
  versions both apps already resolve, so the package analyses standalone. Follow the precedent the
  file itself sets for `google_fonts` and `url_launcher` (`pubspec.yaml:17-24`), including the
  explanatory comment — this team documents why a dependency is declared, and the next person
  deserves the same note.
- **Files to change** — `packages/flutter_shared/pubspec.yaml`: add under `dependencies:` after
  `url_launcher` (line 24):

  ```yaml
    # The shared motion library (lib/motion/) and the animated primitives in
    # lib/widgets/ use flutter_animate's effect chain. Declared here so the
    # package analyses standalone rather than resolving only because both
    # consuming apps happen to depend on it — the same trap google_fonts and
    # url_launcher above were previously caught by.
    flutter_animate: ^4.5.0
    # skeleton_loader.dart currently hand-rolls its sweep. Declared so the
    # planned GoShimmer consolidation (P2.2) has it available.
    shimmer: ^3.0.0
  ```
- **DB** — none. **API contract** — none.
- **Effort** — S (0.25 developer-days including a clean `pub get --enforce-lockfile` on all three
  packages).
- **Risk** — near zero. Both versions are already resolved in both app lockfiles, so no version
  solve changes. Rollback is deleting two lines.
- **Acceptance criteria** — `dart pub get --enforce-lockfile` succeeds in
  `packages/flutter_shared/`; `flutter analyze` passes there with no unresolved-import warnings;
  both app lockfiles are byte-identical after the change.
- **Tests** — CI runs `flutter analyze` in the shared package as a standalone unit (it currently
  does not — flag to **T23**).

### P0.2 — `go_motion.dart`: the token file

- **Goal** — one name per motion decision, so the product can be consistent and reduce-motion can be
  implemented once.
- **Design** — mirror the existing token architecture exactly: a `const`-private-constructor class of
  `static const` members, same as `AppTokens` (`app_theme.dart:29`). Motion values do not vary by
  brightness, so this is **not** a `ThemeExtension` — `GoTheme` stays for colour. Naming follows the
  established scale vocabulary (`Xs/Sm/Md/Lg/Xl`) so `GoMotion.durationMd` reads native next to
  `AppTokens.spaceMd`. Semantic aliases sit on top of the raw scale, and screens use the semantic
  names.
- **Files to change** — new file `packages/flutter_shared/lib/motion/go_motion.dart`; add
  `export 'motion/go_motion.dart';` to `packages/flutter_shared/lib/flutter_shared.dart`
  immediately after line 9 (`export 'theme/app_theme.dart';`) so motion sits beside theme.

Complete file content, ready to paste:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

/// Motion tokens for Synaptic Go.
///
/// The companion to [AppTokens]. Colour, spacing and radius are named there;
/// duration, easing and choreography are named here. Nothing in either app
/// should type a `Duration(milliseconds: …)` or a `Curves.…` literal again —
/// if a value is missing from this file, add it here rather than inline, or
/// the product drifts the way it did before this file existed.
///
/// Motion does not vary by brightness, so unlike [GoTheme] this is a flat
/// static class rather than a ThemeExtension. No context required.
///
/// ## The scale
///
/// The raw scale mirrors the spacing scale's vocabulary (xs → xl). Screens
/// should almost always use the *semantic* names below it — [enter], [exit],
/// [press] — because those carry intent and can be retuned globally.
class GoMotion {
  const GoMotion._();

  // ── Raw duration scale ──────────────────────────────────────────────
  /// Immediate. Reserved for reduce-motion fallbacks.
  static const Duration durationNone = Duration.zero;

  /// 90ms — touch acknowledgement. Below this a change is not perceived as
  /// motion at all, which is exactly what a press-down wants.
  static const Duration durationXs = Duration(milliseconds: 90);

  /// 140ms — small state change on a single element.
  static const Duration durationSm = Duration(milliseconds: 140);

  /// 220ms — the workhorse. Colour, size and cross-fade on one component.
  static const Duration durationMd = Duration(milliseconds: 220);

  /// 320ms — an element entering or leaving the screen.
  static const Duration durationLg = Duration(milliseconds: 320);

  /// 460ms — a surface (sheet, panel, page) entering.
  static const Duration durationXl = Duration(milliseconds: 460);

  /// 720ms — reserved for the signature moments in §6.4 only. Anything this
  /// long on a routine interaction is a bug.
  static const Duration duration2xl = Duration(milliseconds: 720);

  // ── Semantic roles — prefer these at call sites ────────────────────
  /// An element arriving on screen.
  static const Duration enter = durationLg;

  /// An element leaving. Always faster than [enter]: the user has already
  /// decided, and waiting on an exit is what makes an app feel slow.
  static const Duration exit = durationSm;

  /// Touch-down / touch-up scale feedback.
  static const Duration press = durationXs;

  /// A component changing state in place — chip colour, toggle, badge.
  static const Duration stateChange = durationMd;

  /// A bottom sheet or panel entering.
  static const Duration sheet = durationXl;

  /// A full page transition.
  static const Duration page = durationLg;

  /// A deliberate, brand-carrying beat. Signature moments only.
  static const Duration emphasis = duration2xl;

  /// The hard ceiling for anything on the captain's critical path
  /// (accept / decline / navigate). Benchmarked against inDrive: motion must
  /// never sit between a driver and a tap. Assert against this in review.
  static const Duration captainCeiling = Duration(milliseconds: 240);

  // ── Looping periods ─────────────────────────────────────────────────
  /// Live-state pulse. Matches the existing GoOnlineButton value so adopting
  /// the token changes no behaviour.
  static const Duration pulsePeriod = Duration(milliseconds: 1400);

  /// Skeleton shimmer sweep. Matches skeleton_loader's _kSweepDuration.
  static const Duration shimmerPeriod = Duration(milliseconds: 1450);

  /// Ambient "searching" loops (radar rings, dispatch pulses).
  static const Duration searchPeriod = Duration(milliseconds: 1600);

  // ── Choreography ────────────────────────────────────────────────────
  /// Gap between consecutive items in a staggered list entrance.
  static const Duration stagger = Duration(milliseconds: 45);

  /// Cap on stagger steps. Past this the delay stops growing, so a long list
  /// never leaves the last row waiting seconds. Preserves the reasoning
  /// already in offer_card_entrance.dart.
  static const int staggerMaxSteps = 8;

  /// How far an entering list item travels, as a fraction of its own extent.
  static const double enterOffset = 0.14;

  /// Scale an item starts at when entering. Subtle: the item should read as
  /// arriving, not as zooming.
  static const double enterScale = 0.96;

  /// Scale on touch-down.
  static const double pressScale = 0.96;

  // ── Curves ──────────────────────────────────────────────────────────
  /// Default for anything entering or settling. Decelerates into place.
  static const Curve enterCurve = Curves.easeOutCubic;

  /// Default for anything leaving. Accelerates away.
  static const Curve exitCurve = Curves.easeInCubic;

  /// In-place state change, both directions.
  static const Curve standard = Curves.easeOut;

  /// Slight overshoot. Signature moments and confirmations only — overshoot
  /// on routine UI reads as unserious.
  static const Curve overshoot = Curves.easeOutBack;

  /// Continuous ambient loops (breathing, orbiting).
  static const Curve ambient = Curves.easeInOut;

  /// Constant velocity. Correct for map-marker position between GPS fixes:
  /// a vehicle in traffic moves at roughly constant speed between two
  /// samples, so easing each segment would make it appear to brake and
  /// accelerate at every fix. Linear is the honest choice here.
  static const Curve linearTravel = Curves.linear;

  // ── Physics ─────────────────────────────────────────────────────────
  /// Sheet settle. Critically damped: reaches rest without a visible bounce,
  /// but is velocity-aware, so a fast flick settles faster than a slow drag.
  static const SpringDescription sheetSpring = SpringDescription(
    mass: 1,
    stiffness: 520,
    damping: 42,
  );

  // ── Map interpolation ───────────────────────────────────────────────
  /// Floor for a marker tween. Below this the tween is pointless.
  static const Duration markerTweenMin = Duration(milliseconds: 350);

  /// Ceiling for a marker tween. If updates stop, the marker must not keep
  /// gliding for longer than this — a car that glides on stale data lies to
  /// the rider about where their captain is.
  static const Duration markerTweenMax = Duration(milliseconds: 2500);

  /// Fallback tween when no inter-update interval has been measured yet.
  /// Derived from the trip-mode GPS profile: distanceFilter 10m at typical
  /// Cairo traffic speed lands near this value.
  static const Duration markerTweenDefault = Duration(milliseconds: 1200);

  /// After this long with no update the marker stops interpolating and the
  /// vehicle is treated as stale (see AnimatedVehicleMarker.onStale).
  static const Duration markerStaleAfter = Duration(seconds: 12);

  /// Camera ease when following a vehicle. Shorter than the marker tween so
  /// the camera leads slightly rather than dragging behind.
  static const Duration cameraFollow = Duration(milliseconds: 900);

  // ── Money ───────────────────────────────────────────────────────────
  /// Count-up duration for an earned or received amount.
  static const Duration countUp = Duration(milliseconds: 850);

  /// Count-up easing: fast start, long settle, so the final digits land
  /// legibly instead of blurring past.
  static const Curve countUpCurve = Curves.easeOutQuart;

  // ── Reduce motion ───────────────────────────────────────────────────
  /// True when the OS asks for reduced motion.
  ///
  /// Every animated widget in this codebase must consult this. Uses
  /// `maybeOf` so widgets built without a MediaQuery ancestor (tests,
  /// isolated goldens) degrade to "animate" rather than throwing.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  /// Collapses [d] to zero when reduced motion is on.
  ///
  /// This is the single mechanism the whole product uses. Pass every duration
  /// through it at the call site:
  ///
  /// ```dart
  /// AnimatedContainer(
  ///   duration: GoMotion.adapt(context, GoMotion.stateChange),
  ///   curve: GoMotion.standard,
  ///   …
  /// )
  /// ```
  ///
  /// Note the contract: reduced motion means *no movement*, not *no change*.
  /// A cross-fade collapsed to zero still swaps the content correctly; a
  /// looping animation must additionally be stopped, which [reduced] above
  /// is for.
  static Duration adapt(BuildContext context, Duration d) =>
      reduced(context) ? durationNone : d;

  /// Stagger delay for item [index], capped at [staggerMaxSteps] and
  /// collapsed to zero under reduced motion.
  static Duration staggerFor(BuildContext context, int index) {
    if (reduced(context)) return durationNone;
    final steps = index < staggerMaxSteps ? index : staggerMaxSteps;
    return stagger * steps;
  }
}
```

- **DB** — none. **API contract** — none.
- **Effort** — S (0.5 developer-days to write; migrating existing call sites is P2.1, not this item).
- **Risk** — none on its own; it is additive. The risk is social: if the team keeps typing literals,
  the file rots. Mitigated by the lint in P2.1 and the review rule in §7.
- **Acceptance criteria** — file exists and is exported; `flutter analyze` clean in all three
  packages; a widget in either app can `import 'package:flutter_shared/flutter_shared.dart';` and
  reference `GoMotion.enter` with no additional import.
- **Tests** — a unit test asserting `GoMotion.exit < GoMotion.enter`, that every captain-path
  semantic token is `<= captainCeiling`, and that `adapt()` returns `Duration.zero` under a
  `MediaQuery(disableAnimations: true)` wrapper. Cheap, and it pins the intent.

### P0.3 — Repaint boundaries and the reduce-motion sweep

- **Goal** — make the frame budget safe *before* adding 60 fps animation to the map, and make the
  accessibility switch real.
- **Design** — two mechanical passes.

  *Boundaries.* Wrap `FlutterMap` in a `RepaintBoundary` on both live-trip surfaces, matching what
  `home_screen.dart:552` already does for the home map. Then narrow the rebuild: on the captain, move
  the position-driven `setState` out of `_MainShellState` so it no longer rebuilds the five-tab
  `IndexedStack`. The mechanism is a `ValueNotifier<VehicleFix>` owned by the shell and consumed by a
  `ValueListenableBuilder` wrapping only the `MarkerLayer` — the tab stack then never sees the
  update.

  *Reduce motion.* Route every animated widget through `GoMotion.adapt`. Priority order: the captain
  splash (currently a wholly ungated full-screen loop), `GoOnlineButton`'s infinite pulse,
  `MainBottomNav`, `OfferCardEntrance`, the searching pulses, the offer countdown.

- **Files to change**
  - `apps/rider/lib/screens/trip/trip_screen.dart` — wrap the `FlutterMap` at `:220-315` in
    `RepaintBoundary`; hoist `_captainLoc` to a `ValueNotifier` so `:149` no longer calls `setState`.
  - `apps/captain/lib/screens/home/main_shell.dart` — `RepaintBoundary` around `_buildMap()`;
    convert `_applyPosition` (`:223-240`) from `setState` to notifier writes.
  - `apps/captain/lib/screens/splash_screen.dart` — gate `_motion` on `GoMotion.reduced`; when
    reduced, do not `..repeat()`, and render the brand image with the glow at its mid value.
    Also collapse the second ticker (F-28-19) by dropping the `flutter_animate` shimmer at `:230-234`
    in favour of the existing shared clock.
  - `packages/flutter_shared/lib/widgets/go_online_button.dart` — gate `_pulse.repeat()` (`:57`) and
    pass `GoMotion.adapt` to the `AnimatedScale` (`:127`) and `AnimatedContainer` (`:131`).
  - `packages/flutter_shared/lib/widgets/main_bottom_nav.dart` — `:376, :453, :619` through `adapt`,
    and add `GoMotion.standard` to the two that currently run linear.
  - `apps/captain/lib/screens/home/offer_card_entrance.dart` — use `GoMotion.staggerFor`.
- **DB** — none. **API contract** — none.
- **Effort** — M (2 developer-days).
- **Risk** — the notifier refactor on `main_shell.dart` touches the captain's main screen; a mistake
  shows up as a marker that stops updating. Mitigated by shipping the `RepaintBoundary` half first
  (pure addition, no behaviour change) and the notifier half behind its own commit so it reverts
  cleanly.
- **Acceptance criteria** — with the OS reduce-motion switch on, no looping animation runs anywhere
  in either app and every transition is instant but every state change still completes; a Flutter
  DevTools timeline over a 60 s simulated trip shows the tab `IndexedStack` outside the rebuilt
  subtree; the trip map's raster time per position update drops measurably against the pre-change
  baseline.
- **Tests** — widget test wrapping each animated widget in `MediaQuery(disableAnimations: true)` and
  asserting no ticker is active after `pumpAndSettle`; a golden on the captain splash in reduced mode.

### P0.4 — Delete 1.67 MB of dead video

- **Goal** — remove 1.67 MB from both app downloads for effectively no work.
- **Design** — both splash screens already render a static PNG
  (`captain/splash_screen.dart:12-16` documents the decision). Delete both `splash.mp4` files and
  both `assets/videos/` declarations. Nothing references them; no `video_player` dependency exists in
  any pubspec, so there is not even a code path that could load them.
- **Files to change** — delete `apps/rider/assets/videos/splash.mp4` (875,855 B) and
  `apps/captain/assets/videos/splash.mp4` (875,855 B); remove line 63 of `apps/rider/pubspec.yaml`
  and line 59 of `apps/captain/pubspec.yaml`.
- **DB** — none. **API contract** — none.
- **Effort** — S (0.25 developer-days).
- **Risk** — none that survives a grep; both files are unreferenced from any Dart source. Rollback is
  a `git revert`.
- **Acceptance criteria** — `flutter build apk --analyze-size` shows the asset section down by
  ~856 KB per app; both apps launch unchanged.
- **Tests** — existing splash goldens must not move. Hand the size delta to **T26**.

### P1.1 — `AnimatedVehicleMarker`: make the car move

The highest-value component in this document. Everything else is polish next to it.

- **Goal** — a captain's car that moves continuously across the map instead of hopping once a second,
  and that points where it is going.

- **The constraint that kills the naive approach.** In `flutter_map`, `Marker.point` is resolved by
  `MarkerLayer` at layer-build time — the layer projects the `LatLng` to a screen offset and
  positions the child. Wrapping the marker's *child* in an `AnimatedContainer` or a `TweenAnimation`
  therefore animates the car **inside its own 46 dp box** and not across the map. Any implementation
  that does not rebuild the layer will look like it works in a static screenshot and do nothing in
  practice. The tween has to drive the `LatLng` that the layer reads.

  Equally, rebuilding the whole screen 60 times a second to achieve it would trade a cosmetic defect
  for a thermal one — which is why P0.3 lands first.

  The resolution: a small controller object owns the ticker and exposes the interpolated fix as a
  `Listenable`; a `ValueListenableBuilder`/`AnimatedBuilder` wraps **only the `MarkerLayer`**. The
  tile layer, the polyline layer, the panel and the status chip stay outside the rebuilt subtree.

- **Design — three pieces.**

  *1. `LatLngTween`* — Flutter has no `Tween<LatLng>`. Linear interpolation of lat/lng is correct at
  these distances (a 10 m segment; great-circle error is far below a pixel) and is what we want:
  constant velocity between fixes, because a car in traffic moves at roughly constant speed between
  two samples. Easing each segment would make the car appear to brake and accelerate at every GPS
  fix — the classic mistake.

  *2. `VehicleTrack`* — owns the `AnimationController`, measures the real interval between incoming
  fixes and tweens over *that* measured interval rather than a fixed guess, so the animation
  self-tunes to whatever cadence the trip actually produces (§3.3: ~1.2 s at 30 km/h, ~7 s walking).
  Handles bearing with shortest-arc, and declares the vehicle stale rather than gliding on dead data.

  *3. `AnimatedVehicleMarker`* — the drop-in widget that reads the track and renders the existing
  `VehicleMapMarker`. The painter is unchanged; it is already good.

- **Behaviour decisions, and why**
  - **Tween over the *measured* interval, clamped to `[markerTweenMin, markerTweenMax]`.** A fixed
    duration is wrong at both ends: too long and the car lags reality; too short and it arrives early
    then freezes, which reads worse than not animating.
  - **Never extrapolate.** If the next fix is late, the car finishes its current segment and stops.
    Guessing ahead means telling the rider their captain is somewhere they are not — unacceptable on
    a screen someone is standing on a kerb watching.
  - **Stale after `markerStaleAfter` (12 s).** Fire `onStale` so the host can mute the car's colour.
    The widget deliberately does not restyle itself: colour is `GoTheme`'s business.
  - **Bearing by shortest arc.** `((target - current + 540) % 360) - 180` gives the signed delta in
    `(-180, 180]`, fixing F-28-17.
  - **Derive bearing locally when the server omits it.** Until the API adds heading to
    `location.captain` (T07), compute it from the previous and current fix. Below a 3 m segment the
    computed bearing is noise, so hold the last good value — otherwise a stationary car spins.

```dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:latlong2/latlong.dart';

import '../motion/go_motion.dart';

/// Linear interpolation between two coordinates.
///
/// Linear (not great-circle) is deliberate: segments here are ~10m, where the
/// difference is far below one pixel, and constant velocity is exactly the
/// read we want between two GPS samples.
class LatLngTween extends Tween<LatLng> {
  LatLngTween({required LatLng super.begin, required LatLng super.end});

  @override
  LatLng lerp(double t) => LatLng(
        begin!.latitude + (end!.latitude - begin!.latitude) * t,
        begin!.longitude + (end!.longitude - begin!.longitude) * t,
      );
}

/// Owns the interpolation clock for one vehicle.
///
/// Feed it raw fixes with [push]; read [position] and [bearing], which are
/// plain Listenables — so a host can rebuild *only* its MarkerLayer instead of
/// its whole screen. That scoping is the difference between this being a
/// quality win and a battery regression.
class VehicleTrack extends ChangeNotifier {
  VehicleTrack({required TickerProvider vsync, this.onStale})
      : _ctrl = AnimationController(
          vsync: vsync,
          duration: GoMotion.markerTweenDefault,
        ) {
    _ctrl.addListener(_tick);
  }

  final AnimationController _ctrl;

  /// Called when no fix has arrived for [GoMotion.markerStaleAfter]. The host
  /// decides what stale looks like; this class does not own colour.
  final VoidCallback? onStale;

  LatLng? _from;
  LatLng? _to;
  double _bearing = 0;
  double _bearingFrom = 0;
  double _bearingDelta = 0;
  DateTime? _lastFixAt;
  Duration _interval = GoMotion.markerTweenDefault;
  bool _stale = false;

  /// Interpolated position for the current frame. Null until the first fix.
  LatLng? get position {
    if (_from == null || _to == null) return _to ?? _from;
    return LatLngTween(begin: _from!, end: _to!).lerp(_ctrl.value);
  }

  /// Interpolated bearing in degrees clockwise from north.
  double get bearing => _bearingFrom + _bearingDelta * _ctrl.value;

  bool get isStale => _stale;

  /// Feed a fix from the socket.
  ///
  /// [serverBearing] should be passed once the API carries heading on
  /// `location.captain`; until then it is derived from the travelled segment.
  void push(LatLng fix, {double? serverBearing}) {
    final now = DateTime.now();

    // Measure the real cadence and tween over it, so the animation matches
    // whatever this trip is actually producing rather than a fixed guess.
    if (_lastFixAt != null) {
      final measured = now.difference(_lastFixAt!);
      _interval = Duration(
        milliseconds: measured.inMilliseconds.clamp(
          GoMotion.markerTweenMin.inMilliseconds,
          GoMotion.markerTweenMax.inMilliseconds,
        ),
      );
    }
    _lastFixAt = now;
    _stale = false;

    // Start the new segment from wherever the car is *now*, not from the last
    // target. Without this, a fix arriving mid-tween snaps the car backwards.
    final start = position ?? fix;

    final target = serverBearing ?? _derivedBearing(start, fix) ?? _bearing;
    _bearingFrom = _bearing;
    _bearingDelta = _shortestArc(_bearing, target);
    _bearing = target;

    _from = start;
    _to = fix;
    _ctrl
      ..duration = _interval
      ..forward(from: 0);

    _scheduleStaleCheck();
  }

  /// Signed smallest rotation from [a] to [b], in (-180, 180].
  /// Fixes the 359 -> 1 case, which otherwise spins the car 358 the wrong way.
  static double _shortestArc(double a, double b) =>
      ((b - a + 540) % 360) - 180;

  /// Bearing of the segment, or null when the movement is too small to trust.
  /// Below ~3m a GPS delta is noise and would make a parked car spin.
  static double? _derivedBearing(LatLng a, LatLng b) {
    const rad = math.pi / 180;
    final dLon = (b.longitude - a.longitude) * rad;
    final lat1 = a.latitude * rad;
    final lat2 = b.latitude * rad;
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    if (y.abs() < 1e-9 && x.abs() < 1e-9) return null;

    const earthMetresPerDegree = 111320.0;
    final dy = (b.latitude - a.latitude) * earthMetresPerDegree;
    final dx = (b.longitude - a.longitude) *
        earthMetresPerDegree *
        math.cos(lat1);
    if (math.sqrt(dx * dx + dy * dy) < 3.0) return null;

    return (math.atan2(y, x) / rad + 360) % 360;
  }

  void _scheduleStaleCheck() {
    final at = _lastFixAt;
    Future.delayed(GoMotion.markerStaleAfter, () {
      if (_lastFixAt != at || _stale) return; // superseded or already stale
      _stale = true;
      notifyListeners();
      onStale?.call();
    });
  }

  void _tick() => notifyListeners();

  @override
  void dispose() {
    _ctrl
      ..removeListener(_tick)
      ..dispose();
    super.dispose();
  }
}

/// A vehicle that glides between GPS fixes instead of teleporting.
///
/// Drop-in replacement for the marker child built at trip_screen.dart:387.
/// Wrap the *MarkerLayer* — not the screen — in a listener on [track], so a
/// 60fps tween repaints one layer rather than the whole Scaffold.
class AnimatedVehicleMarker extends StatelessWidget {
  const AnimatedVehicleMarker({
    super.key,
    required this.track,
    this.color,
    this.size = 46,
    this.showBearing = true,
  });

  final VehicleTrack track;
  final Color? color;
  final double size;

  /// False for the rider's own dot, which has no meaningful heading.
  final bool showBearing;

  @override
  Widget build(BuildContext context) {
    // Reduced motion: render at the latest fix with no tween. The car still
    // moves — it just does not animate. Suppressing the update entirely would
    // withhold information, which is not what the setting asks for.
    if (GoMotion.reduced(context)) {
      return RepaintBoundary(
        child: VehicleMapMarker(
          heading: showBearing ? track.bearing : null,
          color: color,
          size: size,
        ),
      );
    }

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: track,
        builder: (context, _) => VehicleMapMarker(
          heading: showBearing ? track.bearing : null,
          color: color,
          size: size,
        ),
      ),
    );
  }
}
```

Host wiring, replacing `trip_screen.dart:145-151` and `:379-393`:

```dart
// _TripScreenState with SingleTickerProviderStateMixin
late final VehicleTrack _captainTrack = VehicleTrack(
  vsync: this,
  onStale: () => setState(() {}), // only a stale flip rebuilds the screen
);

// socket handler — note: no setState. The track notifies its own listeners.
void _onCaptainLocation(Map<String, dynamic> data) {
  final lat = (data['lat'] as num?)?.toDouble();
  final lng = (data['lng'] as num?)?.toDouble();
  if (lat == null || lng == null) return;
  _captainTrack.push(
    LatLng(lat, lng),
    serverBearing: (data['heading'] as num?)?.toDouble(), // null until T07 ships it
  );
}

// map — only the MarkerLayer sits inside the rebuild scope
RepaintBoundary(
  child: FlutterMap(
    mapController: _mapController,
    options: _mapOptions,
    children: [
      _tileLayer,
      PolylineLayer(polylines: _routePolylines),
      AnimatedBuilder(
        animation: _captainTrack,
        builder: (context, _) {
          final p = _captainTrack.position;
          return MarkerLayer(markers: [
            ..._staticMarkers,
            if (p != null)
              Marker(
                point: p,
                width: 46,
                height: 46,
                child: AnimatedVehicleMarker(
                  track: _captainTrack,
                  color: _captainTrack.isStale ? go.muted : go.action,
                ),
              ),
          ]);
        },
      ),
    ],
  ),
)

@override
void dispose() {
  _captainTrack.dispose();
  super.dispose();
}
```

- **Files to change**
  - new `packages/flutter_shared/lib/widgets/animated_vehicle_marker.dart` (all three classes above);
    export it from `flutter_shared.dart` after line 22.
  - `apps/rider/lib/screens/trip/trip_screen.dart` — replace the `setState` at `:149` with
    `_captainTrack.push(...)`; replace the marker construction at `:387-390`; add the ticker mixin
    and `dispose`.
  - `apps/captain/lib/screens/home/main_shell.dart` — same treatment for the captain's own marker at
    `:612`, passing `serverBearing: position.heading` since the captain already has it locally
    (`:229-231`); this also fixes the backwards-spin (F-28-17) for free.
  - `packages/flutter_shared/lib/widgets/vehicle_map_marker.dart` — unchanged. The painter is good.
- **DB** — none.
- **API contract** — one additive change, owned by **T07**: include heading on the `location.captain`
  WebSocket payload.
  `{ "type": "location.captain", "lat": 30.0444, "lng": 31.2357, "heading": 217.4, "at": 1754059021 }`
  `heading` is degrees clockwise from north, nullable. The client already degrades correctly when it
  is absent (derives from the segment), so this can land in either order.
- **Effort** — M (3 developer-days: 1.5 for the component and its tests, 1 for the two host
  integrations, 0.5 for on-device tuning against a real drive).
- **Risk** — a 60 fps ticker running for the whole trip is the real risk. Three mitigations are built
  in: the `RepaintBoundary`, the layer-scoped rebuild, and the fact that the controller only runs
  during a segment and idles between them. Rollback is a feature flag on the marker child — one line
  in each host. Measure battery over a 30-minute trip before and after; if the delta exceeds 2%,
  drop the tween to 30 fps by ticking every other frame rather than abandoning the feature.
- **Acceptance criteria** — on a simulated 20-minute drive, the marker shows no visible discontinuity
  at any fix; heading is correct within one segment of travel and never rotates the long way round;
  after 12 s of socket silence the car stops and mutes rather than gliding; Flutter DevTools shows
  the tile and polyline layers outside the per-frame rebuild; sustained 60 fps on the low-end
  reference device (§6 note below).
- **Tests** — unit tests on `_shortestArc` (359→1 = +2, 1→359 = -2, 180→0 = -180); unit test that
  `push` mid-tween starts the new segment from the current interpolated position, not the previous
  target; a fake-async test that `onStale` fires exactly once after 12 s and not again; a widget test
  asserting zero tickers under `disableAnimations: true`.

### P1.2 — The shared primitive set

Five reusable widgets, all in `packages/flutter_shared/lib/motion/`, all exported from
`flutter_shared.dart`, all reduce-motion aware by construction so no screen author has to remember.

**(a) `GoEntrance` — staggered list entrance**

Promotes `OfferCardEntrance` (`offer_card_entrance.dart:21`) into the shared package verbatim in
spirit, generalised in axis, and retires the divergent inline treatment at
`nearby_requests_screen.dart:287-291` (F-28-13).

```dart
/// Entrance choreography for an item at [index] in a list.
///
/// Direction follows text direction: in Arabic RTL an item entering on [Axis.horizontal]
/// arrives from the right, the side the reading eye starts from. Hardcoding a side
/// makes the motion fight the layout in one of the two locales.
class GoEntrance extends StatelessWidget {
  const GoEntrance({
    super.key,
    required this.index,
    required this.child,
    this.axis = Axis.vertical,
    this.duration,          // defaults to GoMotion.enter
    this.stagger,           // defaults to GoMotion.stagger
    this.scale = true,      // adds the 0.96 -> 1 arrival settle
  });

  final int index;
  final Widget child;
  final Axis axis;
  final Duration? duration;
  final Duration? stagger;
  final bool scale;
}
```

Behaviour: `fadeIn` + slide along `axis` from `GoMotion.enterOffset` + optional
`scaleXY` from `GoMotion.enterScale`, all on `GoMotion.enterCurve`, delayed by
`GoMotion.staggerFor(context, index)` — which already caps at 8 steps and collapses to zero under
reduced motion. Horizontal slide sign is derived from `Directionality.of(context)`.

**(b) `GoStateSwap` — in-place state change**

The fix for F-28-09 and the generic answer to "content changed, do not flicker".

```dart
/// Cross-fades between states of the same component in place.
///
/// Unlike a bare AnimatedSwitcher this (a) sizes to the larger of the two children
/// so the layout does not jump mid-transition, (b) collapses to an instant swap under
/// reduced motion while still completing the change, and (c) defaults to the product's
/// stateChange timing rather than Flutter's 200ms.
class GoStateSwap extends StatelessWidget {
  const GoStateSwap({
    super.key,
    required this.stateKey,   // change this to trigger the swap
    required this.child,
    this.duration,            // defaults to GoMotion.stateChange
    this.slide = true,        // subtle vertical lift on the incoming child
  });

  final Object stateKey;
  final Widget child;
  final Duration? duration;
  final bool slide;
}
```

Sketch: an `AnimatedSwitcher` with `duration: GoMotion.adapt(context, duration ?? GoMotion.stateChange)`,
`switchInCurve: GoMotion.enterCurve`, `switchOutCurve: GoMotion.exitCurve`, a `layoutBuilder` that
stacks with `alignment: Alignment.center`, and a `transitionBuilder` combining `FadeTransition` with
a 0.15-extent `SlideTransition` when `slide` is true. The child is keyed on `stateKey`.

**(c) `GoMoney` — count-up for an amount**

```dart
/// An animated currency amount.
///
/// Counts from the previous value to [value] whenever [value] changes and
/// [animate] is true. Renders with AppTokens.money() typography so it is
/// visually identical to every static amount in the product.
class GoMoney extends StatelessWidget {
  const GoMoney({
    super.key,
    required this.value,
    this.fontSize = 28,
    this.color,
    this.decimals = 0,
    this.suffix = ' ج.م',
    this.animate = true,     // false for amounts the user is about to be charged
  });

  final double value;
  final double fontSize;
  final Color? color;
  final int decimals;
  final String suffix;
  final bool animate;
}
```

Sketch: `TweenAnimationBuilder<double>` with `duration: GoMotion.adapt(context, GoMotion.countUp)`,
`curve: GoMotion.countUpCurve`, tweening from the previous value; the builder renders
`Text('${v.toStringAsFixed(decimals)}$suffix', style: AppTokens.money(fontSize: fontSize, color: color))`.
When `animate` is false or motion is reduced the tween duration is zero and the value renders
directly — the widget is then behaviourally identical to today's `Text`, which makes it safe to adopt
everywhere and enable selectively.

**(d) `GoPulse` — live-state indicator**

Extracts the `_LivePulse` already inside `go_online_button.dart:211-218` so the searching pulses at
`home_tab.dart:374` and `available_trips_tab.dart:158` — currently two more bespoke implementations —
collapse onto one.

```dart
/// A breathing ring around a solid dot. The product's single "this is live" signal.
class GoPulse extends StatefulWidget {
  const GoPulse({
    super.key,
    this.color,
    this.dotSize = 10,
    this.ringSize = 20,
    this.period,            // defaults to GoMotion.pulsePeriod
    this.active = true,
  });
}
```

Behaviour: one `AnimationController` on `GoMotion.pulsePeriod`, `repeat(reverse: true)`, ring
diameter `dotSize → ringSize` with opacity `0.35 → 0`. When `!active` or motion is reduced the
controller is stopped and only the solid dot renders — the state is still legible, it just does not
move. Wrapped internally in a `RepaintBoundary`: an always-on looping animation must never invalidate
its parent.

**(e) `GoSuccessCheck` — the confirmation the product has never had**

```dart
/// A checkmark that draws itself, with an optional expanding ring.
///
/// Deliberately a CustomPainter and not a Lottie/Rive asset: ~40 lines of Dart,
/// zero bytes of bundle, recolours from tokens, and no new runtime dependency
/// (see §6.6 on the asset pipeline).
class GoSuccessCheck extends StatefulWidget {
  const GoSuccessCheck({
    super.key,
    this.size = 48,
    this.color,
    this.onComplete,
  });
}
```

Behaviour: a single controller over `GoMotion.emphasis`; a `CustomPainter` strokes the tick path with
`PathMetric.extractPath(0, length * t)` on `GoMotion.enterCurve`, while a ring scales `0.6 → 1` and
fades out. Under reduced motion it paints the completed tick immediately and calls `onComplete` on the
next frame. Replaces the `const Icon(Icons.check_circle)` at `trip_screen.dart:552`.

- **Files to change** — five new files under `packages/flutter_shared/lib/motion/`; five export lines
  in `flutter_shared.dart`; delete `apps/captain/lib/screens/home/offer_card_entrance.dart` and
  repoint `available_trips_tab.dart:113`; repoint `nearby_requests_screen.dart:287-291` to
  `GoEntrance`; repoint `home_tab.dart:374` and `available_trips_tab.dart:158` to `GoPulse`;
  `go_online_button.dart` uses `GoPulse` instead of its private `_LivePulse`.
- **DB / API** — none.
- **Effort** — M (3 developer-days for all five with tests).
- **Risk** — low; each is additive and adopted per call site. `GoEntrance` changes the visual of
  `nearby_requests_screen` (that is the point — it is the inconsistency being removed). Keep
  `kOfferListPadding` (`offer_card_entrance.dart:80-85`) when deleting that file — it is unrelated
  layout state that two screens depend on.
- **Acceptance criteria** — no screen in either app constructs a raw `AnimationController` for a
  pulse, shimmer or list entrance; every primitive renders a correct still state under
  `disableAnimations: true`.
- **Tests** — a golden per primitive in both motion modes; a widget test that `GoMoney` displays the
  exact final value after `pumpAndSettle` (a count-up that lands on the wrong number is worse than no
  count-up).

### P1.3 — Make bids arrive

- **Goal** — fix F-28-06: the rider should see *which* offer is new and never watch the list jump.
- **Design** — three changes, in order of importance. (1) Give `_BidCard` a stable
  `ValueKey(bid['id'])` — without it nothing else works (F-28-18). (2) Diff incoming bids against the
  current list instead of replacing wholesale: keep existing rows identical, and wrap only genuinely
  new rows in `GoEntrance`. (3) Wrap the searching→list branch switch in `GoStateSwap` so the spinner
  cross-fades into the first result rather than popping.

  Do **not** reach for `AnimatedList` here. It requires the data source and the list state to stay in
  lockstep, and the source is a 5 s poll that replaces the array (`captain_bids_sheet.dart:104-108`).
  Keyed rebuilds plus per-row entrance gets ~90% of the effect for ~20% of the risk. Revisit if the
  bid feed moves onto the socket (a T07 question).
- **Files to change** — `apps/rider/lib/screens/ride/captain_bids_sheet.dart`: keys at `:290`; diff
  logic around `:104-108` and `:220`; `GoEntrance` in the `itemBuilder` at `:287`; `GoStateSwap`
  around `_buildBody` at `:253`. Also add the missing `HapticFeedback.mediumImpact()` on accept
  (`:124`) and `lightImpact()` on decline (`:172`) to match the captain side (F-28-20).
- **DB / API** — none.
- **Effort** — S (1 developer-day).
- **Risk** — the diff must key on a stable server id; if `bid['id']` is ever absent the entrance
  re-fires on every poll and the list strobes. Guard: fall back to no-animation when the id is null,
  and assert its presence in the API contract with **T05**.
- **Acceptance criteria** — with the poll running, existing rows do not rebuild or move when a new bid
  arrives; the new row animates in; declining a bid removes exactly that row.
- **Tests** — widget test driving three poll cycles and asserting that unchanged rows keep their
  `Element` identity across rebuilds.

### P1.4 — One launch, two apps

- **Goal** — fix F-28-10; give the captain the handoff the rider already has.
- **Design** — lift the rider's `_RootGate` (`rider/main.dart:143-172`) into the shared package
  as `GoRootGate`, since it is already correct: `AnimatedSwitcher`, fade + `0.985 → 1` scale,
  `easeOutCubic` in / `easeInCubic` out, reduce-motion aware. Adopt it in `captain/main.dart:82-86`
  in place of the bare ternary. Tokenise its 560 ms as `GoMotion.emphasis`-adjacent — it becomes
  `GoMotion.duration2xl` minus nothing; keep 560 ms by adding `static const Duration rootHandoff =
  Duration(milliseconds: 560);` rather than bending an existing token to fit.

  Also give the captain splash a **minimum** dwell. Today it exits the instant `bootstrap()` resolves
  (`captain_state.dart:226`), which on a warm start can be under 200 ms — so an elaborate 3600 ms
  animation flashes and vanishes, which is worse than not having it. Match the rider's contract:
  hold for `max(2400ms, bootstrap)`. On the same pass, gate the loop on reduce-motion (P0.3) and drop
  the second ticker (F-28-19).

  **On `splash.mp4` and authored assets:** the video is already gone from both code paths and P0.4
  deletes the files. Do not bring it back, and do not replace it with Rive or Lottie. The numbers:
  the MP4 was 855 KB per app and needed a `video_player` dependency neither app has; a Rive runtime
  adds ~400 KB of native code plus the artboard; Lottie adds a JSON parser plus a file that, for a
  full-screen sequence at this complexity, would run 80–200 KB. The current hand-written screen costs
  **zero** additional bundle bytes, paints on the first frame with no decode, recolours from tokens,
  and is already built and good. The decode-cost argument the team already made in
  `captain/splash_screen.dart:12-16` was right; it applies just as well to an authored-asset runtime
  on a 2 GB Android device. Recommendation: **hand-written Flutter, no new animation runtime.**
- **Files to change** — new `packages/flutter_shared/lib/motion/go_root_gate.dart`;
  `apps/rider/lib/main.dart` (use the shared gate, delete the local one);
  `apps/captain/lib/main.dart:82-86` (adopt it); `apps/captain/lib/screens/splash_screen.dart` (min
  dwell + reduce-motion + single ticker); `apps/rider/lib/screens/splash_screen.dart:97` (tokenise
  the 2400 ms).
- **DB / API** — none.
- **Effort** — S (1 developer-day).
- **Risk** — adding a minimum dwell makes the captain's warm start *slower* in wall-clock terms. That
  is the correct trade for brand coherence, but it is a product call — logged in §10.
- **Acceptance criteria** — both apps hold the splash for the same minimum and hand off with the same
  560 ms transition; under reduced motion both cut instantly with no loop running.
- **Tests** — an integration test asserting the splash is on screen ≥2400 ms in both apps and that
  the destination is mounted after.

### P1.5 — Money, and where not to animate it

- **Goal** — fix F-28-11 with a rule, not a sprinkle.
- **The rule.** Count up an amount the user **earned or received**. Never count up an amount the user
  is **about to pay**, and never let a count-up gate the next tap.
  - **Yes:** captain earnings hero (`earnings_screen.dart:66,149`) — the reward moment, and the
    single best candidate in the product; captain wallet balance after a payout
    (`captain/wallet_screen.dart:683`); rider wallet balance after a successful top-up
    (`rider/wallet_screen.dart:412`).
  - **No:** the fare estimate before booking, the counter-offer amount, and — importantly — the
    **final fare at trip completion** (`trip_screen.dart:559`). Animating a number someone is paying
    reads as a slot machine. The completion moment gets its emphasis from `GoSuccessCheck` and the
    panel transition instead (§6.4, moment 6).
- **Files to change** — `apps/captain/lib/screens/earnings/earnings_screen.dart:149` →
  `GoMoney(value: net, fontSize: 44)`; `apps/captain/lib/screens/earnings/wallet_screen.dart:683` and
  `apps/rider/lib/screens/wallet/wallet_screen.dart:412` → `GoMoney(..., decimals: 2)`; every other
  amount adopts `GoMoney(animate: false)` for consistency of typography and to make future changes a
  one-flag decision.
  Also replace the instant spinner→content ternary at `earnings_screen.dart:90-91` with the existing
  `SkeletonList` and a `GoStateSwap` (F-28-21) — the skeleton system is already built, already
  reduce-motion aware, and currently unused on this screen.
- **DB / API** — none.
- **Effort** — S (1 developer-day).
- **Risk** — a count-up that starts from a stale previous value looks like the balance dropped and
  recovered. Seed the tween from the *previous rendered* value, and from the target (no animation) on
  first mount.
- **Acceptance criteria** — the earnings total counts up on refresh and lands exactly on the server
  value; the rider's final fare does not animate; every amount in the product uses one widget.
- **Tests** — as P1.2(c), plus a test that first mount does not animate.

### P1.6 — The arrival moment

- **Goal** — fix F-28-09: make `وصل الكابتن` land.
- **Design** — `StatusChip` (`status_chip.dart`) becomes an `AnimatedContainer` on
  `GoMotion.stateChange`/`GoMotion.standard` for background, border and foreground, with its label
  and icon inside a `GoStateSwap` keyed on the variant — so colour tweens while text cross-fades.
  `trip_screen.dart:412-426` adopts it, and `_buildPanelContent` (`:449-457`) is wrapped in
  `GoStateSwap` keyed on `_status` so the panel cross-fades with a small lift instead of hard-cutting
  under the chip. One `HapticFeedback.mediumImpact()` fires on transition into `arrived` — the phone
  is in the rider's hand and they are probably not looking at it, which is exactly when a haptic is
  worth more than a pixel.
- **Files to change** — `packages/flutter_shared/lib/widgets/status_chip.dart`;
  `apps/rider/lib/screens/trip/trip_screen.dart:412-426, 449-457`; the captain's equivalent stage
  stepper `AnimatedContainer` at `active_trip_panel.dart:664` gains `GoMotion.standard` (it currently
  runs linear, F-28-16).
- **DB / API** — none.
- **Effort** — S (1 developer-day).
- **Risk** — the panel cross-fade must not fight the sheet resize when content height changes between
  statuses; `GoStateSwap`'s stacking `layoutBuilder` handles this, but verify on the
  `in_progress → completed` transition, which is the largest height change.
- **Acceptance criteria** — chip colour tweens and label cross-fades on every status change; the
  arrival haptic fires exactly once per trip.
- **Tests** — widget test stepping the full status sequence and asserting one haptic on `arrived`.

### P1.7 — Sheets that behave like surfaces

- **Goal** — fix F-28-12 where it pays: the two sheets the rider manipulates most.
- **Design** — convert `captain_bids_sheet` and `location_search_sheet` to
  `DraggableScrollableSheet` with real snap points (`0.35 / 0.7 / 0.95` for bids; `0.5 / 0.92` for
  search), `snap: true`, and `BouncingScrollPhysics`. Introduce a shared `GoSheetRoute` that supplies
  `transitionAnimationController` driven by `GoMotion.sheetSpring` so entrance is velocity-aware and
  interruptible, and use it for the four `showModalBottomSheet` call sites
  (`home_screen.dart:407,460`, `trip_screen.dart:205`, `counter_offer_sheet.dart:40`).
  Leave `fare_estimate_sheet` and `rating_sheet` as fixed-height modals — they are decision points,
  not surfaces to explore, and making them draggable adds a way to fail.
- **Files to change** — new `packages/flutter_shared/lib/motion/go_sheet_route.dart`; the two sheets
  above; the four call sites.
- **DB / API** — none.
- **Effort** — M (2 developer-days).
- **Risk** — the bids sheet currently renders as an inline `Container` inside the trip screen
  (`captain_bids_sheet.dart:224`, comment at `:18` notes it was demoted from a modal). Restoring it as
  a real sheet re-opens whatever caused that demotion; find out why before rebuilding it. Marked
  `needs-check` — the git history for that change was not in scope for this review.
- **Acceptance criteria** — both sheets snap, follow the finger, are interruptible mid-animation, and
  settle with velocity-aware physics.
- **Tests** — a gesture test flinging to each snap point and asserting the resting extent.

### P1.8 — The six signature moments

These are the beats that define how the product feels. Everything above is the vocabulary; this is
the sentence. Each is specified beat by beat, and each is built from the primitives above — no moment
requires a bespoke controller.

**Moment 1 — App launch → first screen.** *The feeling: this is a real company, and it is already
working.*

| Beat | t | What moves | From → to | Duration / curve | Haptic | Sound |
|---|---|---|---|---|---|---|
| 1 | 0 ms | Brand image | opacity 0→1, scale 0.86→1 | 600/700 ms · `overshoot` | — | — |
| 2 | 0 ms | Radar rings (captain) / glow (rider) | begin ambient loop | `searchPeriod` · `ambient` | — | — |
| 3 | 250 ms | Wordmark + badge | fade + slideY 0.25→0 | `enter` · `enterCurve` | — | — |
| 4 | 500 ms | Progress beam | fade in, begin sweep | `enter` | — | — |
| 5 | 700 ms | Studio footer | fade + slideY 0.3→0 | `enter` · `enterCurve` | — | — |
| 6 | ≥2400 ms, once booted | Whole splash | fade 1→0, scale 1→0.985 | 560 ms · `exitCurve` | — | — |
| 7 | same frame as 6 | Destination screen | fade 0→1, scale 0.985→1 | 560 ms · `enterCurve` | — | — |

Beats 1–5 already exist and are good; the work is beats 6–7 on the captain (P1.4) and the minimum
dwell. No sound at launch — an unexpected noise from a ride-hailing app is a uninstall, and Egypt's
usage context is frequently public.

**Moment 2 — Captain goes online.** *The feeling: I am in the system, work is coming.*

| Beat | t | What moves | From → to | Duration / curve | Haptic | Sound |
|---|---|---|---|---|---|---|
| 1 | 0 | Button | scale 1→0.96 | `press` · `standard` | `mediumImpact` | — |
| 2 | 0 | Button label | → spinner | `stateChange` (`GoStateSwap`) | — | — |
| 3 | on 200 OK | Fill + shadow | ink → `go.action`, shadow → brand glow | `stateChange` · `standard` | `selectionClick` | — |
| 4 | +0 ms | `GoPulse` | begins breathing | `pulsePeriod` · `ambient` | — | — |
| 5 | +60 ms | Map dims 4%, ambient captain dots fade in | opacity | `enter` | — | — |

Beats 1–4 exist (`main_shell.dart:348-362`, `go_online_button.dart`) and are the product's best
interaction today. Beat 5 is new and cheap: it converts a button state into a *world* state. Total
elapsed under `captainCeiling` excluding network.

**Moment 3 — A bid lands on the rider's screen.** *The feeling: someone real just offered to come
get me.*

| Beat | t | What moves | From → to | Duration / curve | Haptic | Sound |
|---|---|---|---|---|---|---|
| 1 | 0 | New row | height 0→full | `enter` · `enterCurve` | `lightImpact` | — |
| 2 | 0 | New row content | fade 0→1, slideY 0.14→0, scale 0.96→1 | `enter` · `enterCurve` | — | — |
| 3 | 0 | Existing rows | translate down by row height | `enter` · `enterCurve` | — | — |
| 4 | +120 ms | Price on new row | brief 1→1.04→1 | `stateChange` · `overshoot` | — | — |
| 5 | on first bid only | Searching spinner → list | cross-fade | `stateChange` | `mediumImpact` | — |

The critical detail is beat 3: existing rows must **animate** down, not jump. That is what makes the
new row read as *inserted* rather than the list read as *replaced*, and it is exactly what stable
keys (P1.3) buy. Haptic on every bid, because the rider is often not looking at the screen while
waiting.

**Moment 4 — Rider accepts a captain.** *The feeling: decided. It is happening.*

| Beat | t | What moves | From → to | Duration / curve | Haptic | Sound |
|---|---|---|---|---|---|---|
| 1 | 0 | Chosen row | scale 1→0.97 | `press` · `standard` | `mediumImpact` | — |
| 2 | +90 ms | All other rows | fade 1→0, slideY 0→0.1 | `exit` · `exitCurve` | — | — |
| 3 | +140 ms | Chosen row | expands to fill the panel | `sheet` · `enterCurve` | — | — |
| 4 | +200 ms | Captain marker | fades in at last known position | `enter` | — | — |
| 5 | +320 ms | Status chip | → `كابتن في الطريق`, colour → primary | `stateChange` | — | — |
| 6 | +320 ms | Route polyline | draws from rider toward captain | `emphasis` · `enterCurve` | — | — |

Beat 2 is the point: the losing options leave *before* the winner expands, so the screen reads as a
choice being resolved rather than a layout being rearranged. Beat 6 is the one place progressive
polyline drawing earns its cost (see §6.9) — it happens once per trip and it explains the geometry.

**Moment 5 — The captain arrives.** *The feeling: they are here — look up.*

| Beat | t | What moves | From → to | Duration / curve | Haptic | Sound |
|---|---|---|---|---|---|---|
| 1 | 0 | Status chip background | primary → primary-emphasis | `stateChange` · `standard` | `mediumImpact` | — |
| 2 | 0 | Chip label | `كابتن في الطريق` → `وصل الكابتن` | `stateChange` cross-fade | — | — |
| 3 | +80 ms | Chip | scale 1→1.06→1 | `emphasis` · `overshoot` | — | — |
| 4 | +80 ms | Captain marker | pulse ring expands once | `emphasis` | — | — |
| 5 | +200 ms | Bottom panel | cross-fade + 0.06 lift to arrived content | `stateChange` | — | — |
| 6 | +200 ms | Plate + car colour | scale 0.96→1 into prominence | `enter` · `enterCurve` | — | — |

This is the most-watched pixel in the product and today it is a single-frame flicker (F-28-09). The
haptic on beat 1 matters more than any of the visuals: the phone is usually in a pocket or a hand at
this moment.

**Moment 6 — Trip complete, fare reveal.** *The feeling: that went well, and I know exactly what I
paid.*

| Beat | t | What moves | From → to | Duration / curve | Haptic | Sound |
|---|---|---|---|---|---|---|
| 1 | 0 | Map | dims to 60%, camera eases to destination | `cameraFollow` · `enterCurve` | — | — |
| 2 | +100 ms | Panel | previous content fades out | `exit` · `exitCurve` | — | — |
| 3 | +200 ms | `GoSuccessCheck` | ring 0.6→1 + tick strokes 0→1 | `emphasis` · `enterCurve` | `mediumImpact` | — |
| 4 | +420 ms | `وصلت بسلامة!` | fade + slideY 0.2→0 | `enter` · `enterCurve` | — | — |
| 5 | +520 ms | Fare | fade + slideY 0.2→0, **no count-up** | `enter` · `enterCurve` | — | — |
| 6 | +680 ms | Rate CTA | fade + slideY 0.3→0 | `enter` · `enterCurve` | — | — |

Beat 5 is a deliberate restraint (§P1.5): the amount the rider is paying appears with dignity, not
with a slot-machine roll. The celebration lives in beat 3, which is about the journey being
completed safely — the phrase the product already uses.

### P1.9 — Asset pipeline: the recommendation is "no pipeline"

The brief asks what to specify if Rive or Lottie is recommended. **Neither is recommended for v1**,
and the decision should be recorded rather than revisited every sprint.

The evidence: the one authored asset the product ever shipped for motion was `splash.mp4`, it was
removed from both code paths because of decode cost (`captain/splash_screen.dart:12-16`), and its
875,855 bytes are *still* in both bundles because nobody deleted the file (F-28-08). That is the
actual cost of an authored-asset pipeline in this team's current state: bytes that outlive the
decision that created them.

Against that, every moment specified above is achievable with `flutter_animate` (already shipped),
`CustomPainter` (already used well — `_RadarPainter`, `_CarPainter`), and the five primitives in
P1.2. Adding Rive costs a native runtime (~400 KB) plus per-artboard bytes; adding Lottie costs a
JSON parser plus 80–200 KB per full-screen sequence, and Lottie's rasterisation on low-end Android is
precisely where the frame budget in §6.9 is tightest.

**Revisit only if all three become true:** a designer joins who authors in Rive; a moment is
specified that genuinely cannot be expressed in Flutter primitives; and the bundle has room after
T26's size work. If that happens, the pipeline is: assets in `assets/motion/`, ≤120 KB each, ≤500 KB
total, checked in with the `.riv` source beside the export, version-pinned in the same PR as the code
that loads them, and **every** asset load wrapped in a fallback to a static token-coloured widget —
because an animation that fails to load must degrade to a still, never to an empty box.

### P2 — Craft (after the above ships)

**P2.1 — Retire the literals.** Migrate all 24 hardcoded durations (§3.1) to `GoMotion`, then add a
custom lint (or a CI `grep` gate) rejecting `Duration(milliseconds:` and `Curves.` inside
`apps/*/lib/**` and `packages/flutter_shared/lib/widgets/**`. Without the gate the token file rots
within two sprints. **Effort:** M (2 days including the lint). Coordinate the CI hook with **T23**.

**P2.2 — Consolidate shimmer.** `skeleton_loader.dart` hand-rolls a sweep while both apps ship the
`shimmer` package unused. Pick one — the hand-rolled version is RTL-aware and reduce-motion-aware, so
the likely answer is to keep it and **drop** `shimmer` from both app pubspecs rather than adopt it.
Verify no other usage first. **Effort:** S (0.5 days). Feeds **T26** on bundle size.

**P2.3 — Page transitions and one hero.** Set `pageTransitionsTheme` in `AppTheme._build()`
(`app_theme.dart:636-804`) so all 21 routes share one motion. Then add the product's first `Hero`:
the captain's avatar/car card from the bids list into the trip screen. That single shared element
does more for perceived continuity than the other 20 routes combined. **Effort:** M (1.5 days).

**P2.4 — Progressive route trimming.** Split the polyline into travelled and remaining as the captain
advances (`trip_screen.dart:255-272`). Real product value — the rider sees progress — but it
recomputes geometry on every fix, so it lands only after P0.3's repaint scoping is proven.
**Effort:** M (2 days). Overlaps **T21**; coordinate before starting.

**P2.5 — Camera easing.** Replace the six instant `move`/`fitCamera` calls (F-28-14) with an eased
move over `GoMotion.cameraFollow`, slightly shorter than the marker tween so the camera leads.
**Effort:** S (1 day).

### 6.9 Performance discipline

Every animation above is specified against a **low-end reference device**: a 2 GB RAM Android running
a mid-tier SoC, which is the realistic floor for this market. The budget is 16.6 ms per frame; the
working target is **≤8 ms of UI+raster** on that device, leaving headroom for the map's own tile work.

| Animation | Frame cost | What keeps it cheap |
|---|---|---|
| Marker tween (P1.1) | ~0.4 ms | `RepaintBoundary` + rebuild scoped to `MarkerLayer`; `Transform.rotate` is a matrix op, no repaint of the painter |
| `GoEntrance` | ~0.3 ms/item, ≤8 concurrent | Stagger cap; opacity+transform only, no layout |
| `GoStateSwap` | ~0.5 ms | Two children alive only during the transition |
| `GoMoney` | ~0.2 ms | Text layout on a short string; fixed decimals so width does not reflow |
| `GoPulse` | ~0.2 ms | Own `RepaintBoundary`; one circle |
| `GoSuccessCheck` | ~0.6 ms, one-shot | `PathMetric` extraction on a 3-point path |
| Splash loop | **~2–4 ms** | The expensive one: animated `blurRadius` (F-28-22) re-rasterises a shadow per frame |

**The rules, in review-checkable form:**

1. **Any widget that animates on a loop wraps itself in a `RepaintBoundary`.** Non-negotiable —
   `GoPulse` and `AnimatedVehicleMarker` do this internally so call sites cannot forget.
2. **`AnimatedBuilder`'s `builder` contains only what actually changes.** Everything static goes in
   the `child:` parameter. The captain splash already does this correctly
   (`captain/splash_screen.dart:128-191, 273-295`) — that is the pattern to copy.
3. **Never animate `blurRadius`, `elevation`, or anything behind a `BackdropFilter`.** Animate opacity
   over a pre-rendered shadow instead. Fixing F-28-22 means holding `blurRadius` constant at 60 and
   breathing the shadow *colour's* alpha.
4. **Implicit for one property on one widget; explicit for anything choreographed or interruptible.**
   `AnimatedContainer` for a chip; an `AnimationController` for a sequence.
5. **Every `AnimatedContainer` specifies a curve.** Omitting it silently selects `Curves.linear`
   (F-28-16), which is never the intent.
6. **Nothing on the captain's critical path exceeds `GoMotion.captainCeiling` (240 ms).**
7. **`setState` never sits above a `FlutterMap`.** Position updates go through a `Listenable` consumed
   as close to the marker as possible.
8. **Every animated widget answers `disableAnimations`**, via `GoMotion.adapt` or `GoMotion.reduced`.

## 7. Phasing

**P0 — before any production traffic.** There are no S1 findings in this axis, so nothing here
*blocks* launch in the protocol's sense. What P0 contains is the work that must land before any other
motion work, plus one free bundle win. All four items together are under a week and unblock
everything in P1.

| Item | Phase | Effort (dev-days) | Owner type |
|---|---|---|---|
| P0.1 — animation dependency in `flutter_shared` | P0 | 0.25 | Flutter |
| P0.2 — `go_motion.dart` token file | P0 | 0.5 | Flutter |
| P0.3 — repaint boundaries + reduce-motion sweep | P0 | 2 | Flutter |
| P0.4 — delete 1.67 MB of dead video | P0 | 0.25 | Flutter |
| **P0 total** | | **3** | |
| P1.1 — `AnimatedVehicleMarker` | P1 | 3 | Flutter (+ backend for heading) |
| P1.2 — five shared primitives | P1 | 3 | Flutter |
| P1.3 — bid arrival choreography | P1 | 1 | Flutter |
| P1.4 — unified launch handoff | P1 | 1 | Flutter |
| P1.5 — money in motion | P1 | 1 | Flutter |
| P1.6 — the arrival moment | P1 | 1 | Flutter |
| P1.7 — sheet physics | P1 | 2 | Flutter |
| P1.8 — signature moments assembly | P1 | 2 | Flutter |
| **P1 total** | | **14** | |
| P2.1 — retire literals + lint gate | P2 | 2 | Flutter + CI |
| P2.2 — consolidate shimmer | P2 | 0.5 | Flutter |
| P2.3 — page transitions + first hero | P2 | 1.5 | Flutter |
| P2.4 — progressive route trimming | P2 | 2 | Flutter |
| P2.5 — camera easing | P2 | 1 | Flutter |
| **P2 total** | | **7** | |

**Total: 24 developer-days**, one Flutter engineer, plus roughly half a day of backend work for the
heading field (**T07**).

**The three that ship first, and why.** If only three things happen: **P0.4** (free, 1.67 MB, ship it
this week), **P0.1+P0.2** (nothing else is possible without them), then **P1.1**. The marker is the
whole ballgame — it is the difference between a map that looks like a prototype and one that looks
like Uber, on the screen riders spend the most time staring at.

**How motion changes get reviewed.** A written spec cannot be code-reviewed for feel, and a GIF in a
PR description is not evidence on a 2 GB device. The process:

1. **Every motion PR attaches a screen recording from the low-end reference device**, not the
   simulator. No recording, no review.
2. **Every motion PR attaches a DevTools timeline** over the animation, showing UI and raster below
   8 ms. This is the only claim in a motion PR that can be objectively checked, so it is mandatory.
3. **Every motion PR includes the reduced-motion recording too.** Two clips, same PR. This is what
   stops F-28-05 from recurring.
4. **Review asks one question about intent** — "what should the user be feeling here?" — and checks
   the answer against the storyboard in §P1.8. If the moment is not in that table, the PR should
   either add it there or use an existing primitive unchanged.
5. **No new `Duration` literal passes review** once P2.1's lint is in place. Before then, it is a
   reviewer's job.

## 8. Metrics

Motion is usually instrumented badly — "engagement" tells you nothing about whether a car looked
smooth. These are the ones that actually move when this work lands.

| Metric | How | Current | Target |
|---|---|---|---|
| Trip-map jank rate — % of frames >16.6 ms on the reference device during an active trip | Flutter `SchedulingStrategy` / `dart:developer` timeline sampled in a debug build over a scripted 20-min drive | unmeasured (`needs-check`; no perf harness exists) | <1% |
| Marker discontinuity events per trip — visible jumps >3 px between frames | Instrument in the widget test harness against a recorded fix stream | ~1 per GPS fix ≈ 50/min at 30 km/h | 0 |
| Cold-start to first interactive frame | Existing Flutter startup trace, both apps | unmeasured | no regression from P1.4's minimum dwell (measure the *interactive* frame, not the splash exit) |
| APK/AAB size, both apps | `flutter build --analyze-size` | baseline at commit `153210b9` | −856 KB per app from P0.4 alone |
| Reduce-motion coverage — animated widgets consulting `disableAnimations` | `grep` count over `flutter_analyze` targets | 6 files | 100% of animated widgets |
| Duration literals outside `go_motion.dart` | CI `grep` gate (P2.1) | 24 | 0 |
| Battery delta over a 30-min trip, rider app | On-device measurement, before/after P1.1 | baseline | <2% increase |
| Bid-to-accept time (rider) | Client analytics on the bids sheet | unmeasured | watch for regression; P1.3 must not slow the decision |
| Captain accept-tap latency | Time from tap to visual acknowledgement | unmeasured | ≤240 ms (`captainCeiling`) |

The first two are the ones that prove this track worked. Everything else is guardrail. Note that
**no performance harness exists today** — building the scripted-drive fixture is itself ~1 day and is
folded into P1.1's estimate; flag the CI half to **T23**.

## 9. Cross-cutting notes

**→ T07 (Realtime).** The `location.captain` payload carries no heading, which is why the rider's
captain marker points north for entire trips (F-28-03). Requested additive change:
`{ "type": "location.captain", "lat": …, "lng": …, "heading": 217.4, "at": … }`, degrees clockwise
from north, nullable. The client degrades correctly without it, so there is no ordering constraint.
Separately: the two apps' `trip_ws.dart` have **diverged in shape** — the rider's is callback-based
with an `onStatus` hook (`rider/trip_ws.dart:14,51,61,87,116`), the captain's is a broadcast
`StreamController` with no status reporting at all (`captain/trip_ws.dart:44-47,81,102-114`). Backoff
(`1<<attempt.clamp(0,4)` + jitter) and the 25 s heartbeat are identical, so this is pure API-shape
drift, not behavioural. Also worth T07's attention: the bid feed is a 5 s REST poll
(`captain_bids_sheet.dart:75-78`), not a socket — moving it to the trip room would let P1.3 use a
real insertion animation instead of a diff.

**→ T27 (Cross-app parity).** Six concrete motion divergences, all confirmed:
(1) launch handoff — rider has a 560 ms `AnimatedSwitcher` (`rider/main.dart:143-172`), captain hard-cuts
(`captain/main.dart:82-86`);
(2) splash implementations are entirely separate designs — 3200 ms vs 3600 ms controllers, radar rings
and road dashes on captain only, shimmer on different elements, standard vs custom progress
indicator, and only the rider's is reduce-motion gated and theme-aware;
(3) rider holds the splash 2400 ms, captain has no minimum dwell;
(4) two entrance treatments for identical list content — `OfferCardEntrance`
(`available_trips_tab.dart:113`) vs an inline `.animate()` (`nearby_requests_screen.dart:287-291`);
(5) `MaterialApp` builders differ — rider wraps `AnnotatedRegion`, captain wraps a textScaler clamp
(0.9–1.3) that the rider lacks entirely (`captain/main.dart:71-74`);
(6) haptic coverage is asymmetric — every captain decision has one, the rider's accept-a-bid has none
(`captain_bids_sheet.dart:124,172`). P1.2 and P1.4 fix (1)(3)(4)(6) by construction; (2) and (5) are
T27's call.

**→ T15 (Accessibility).** Reduce-motion is honoured in 6 files out of the whole codebase. The
pattern that exists is correct and reusable (`skeleton_loader.dart:120-121`). The exposure worth your
judgement: the captain splash is an unbounded full-screen loop — two orbiting radial gradients, three
expanding radar rings, scrolling road dashes — with no gate and no exit timer, and it is the first
thing every captain sees. I have ranked it S2 and specified the fix (P0.3); if your read of
conformance or store review makes it a launch blocker, it is an S1 in your document. Also: the
captain app clamps `textScaler` to 0.9–1.3 (`captain/main.dart:71-74`) and the rider app does not
clamp at all — that asymmetry is yours, not mine.

**→ T13 (Motion audit).** `docs/plan/13-motion-micro-interactions.md` is absent from `main` at
`153210b9`, so this document contains a first-hand audit (§3, §4) rather than a cross-reference. The
inventory is reusable: 24 duration literals with call sites (§3.1), the per-widget motion table
(§2), zero motion tokens, zero `Hero`s, one `RepaintBoundary`, and no `pageTransitionsTheme`. Where
we disagree on judgement, defer to T13; the measurements are reproducible against the commit sha.

**→ T12 (Design system).** `AppTokens` is in good shape and `GoMotion` is deliberately built to
mirror it (static consts, same scale vocabulary, not a `ThemeExtension` because motion does not vary
by brightness). One note for you: several `AnimatedContainer`s omit their curve and therefore run
linear (F-28-16), which makes tokenised colour changes read mechanically even where the colours are
right.

**→ T26 (Mobile release).** P0.4 removes 856 KB per app. Also for your ledger: `GODRIVE.png` at the
repo root is **4,031,597 bytes** (3.85 MB) and is not referenced by either app's asset declarations —
it appears to be a source-of-truth brand file living in the repo rather than a shipped asset. Worth
confirming it is excluded from builds. `splash_brand.png` differs between apps (999,730 B rider vs
806,390 B captain) for what should be the same brand moment.

**→ T23 (Testing/CI).** Three asks: run `flutter analyze` against `packages/flutter_shared` as a
standalone package (it currently is not, which is how the dependency gap in F-28-02 survived); add
the `Duration`/`Curves` literal gate from P2.1; and host the scripted-drive performance fixture from
§8 so the jank metric is tracked per-PR rather than measured once.

**→ T05 (Pricing/bidding).** P1.3's insertion animation depends on a stable `id` on every bid object
returned by the bids endpoint. If that field is ever absent or unstable across polls, the rider's list
will strobe. Please treat it as part of the contract.

## 10. Open questions

**Q1 — Does the captain splash get a minimum dwell?**
P1.4 proposes holding the captain splash for `max(2400 ms, bootstrap)` to match the rider. Today it
exits the moment `bootstrap()` resolves (`captain_state.dart:226`), which on a warm start can be
under 200 ms — an elaborate 3600 ms animation that flashes and disappears.
*Options:* (a) match the rider at 2400 ms; (b) a shorter captain-specific hold, ~1200 ms; (c) leave it
state-driven and accept the flash.
**Recommendation: (b).** The captain is a professional opening the app many times a day, and inDrive's
lesson is that motion must never sit between a driver and their work. 1200 ms is long enough for the
brand to register and short enough not to become a tax. The rider, who opens the app occasionally and
is being sold to, keeps 2400 ms.

**Q2 — Does the final fare count up?**
§P1.5 says no: count-up is for money earned, not money owed.
*Options:* (a) no animation on the rider's final fare (recommended); (b) count up everything for
consistency; (c) count up only above a threshold.
**Recommendation: (a).** Animating a charge reads as a slot machine. The completion moment gets its
emphasis from `GoSuccessCheck` instead. This is a brand-voice decision, so it is the product owner's.

**Q3 — Rive/Lottie, ever?**
§P1.9 recommends no authored-animation runtime for v1.
*Options:* (a) hand-written Flutter only (recommended); (b) adopt Rive now for the splash and success
moments; (c) revisit after a designer joins.
**Recommendation: (a), formally revisited only when all three conditions in §P1.9 hold.** The
`splash.mp4` story — shipped, replaced, and still costing 1.67 MB a year later — is the argument.

**Q4 — Is the bids sheet allowed to become a real sheet again?**
`captain_bids_sheet.dart:18` records that it "used to be a modal bottom sheet" and was demoted to an
inline container. P1.7 proposes restoring it as a `DraggableScrollableSheet`. I could not determine
*why* it was demoted — that history was out of scope. Marked `needs-check`.
*Options:* (a) restore it as a snapping sheet; (b) keep it inline and add only the entrance
choreography from P1.3.
**Recommendation: find the original reason first.** If the demotion fixed a real bug, (b) still
delivers most of the value at a fraction of the risk, and P1.3 does not depend on P1.7.

**Q5 — Sound?**
Every storyboard in §P1.8 specifies "no sound". The product currently has none.
*Options:* (a) stay silent (recommended); (b) a single confirmation tone on trip completion; (c) a
fuller audio identity.
**Recommendation: (a) for now.** Ride-hailing is used in shared taxis, on the street, and in
meetings; an unexpected sound is a settings-menu visit at best. Haptics carry the same information
and cost nothing socially. Revisit only alongside an accessibility review, where audio confirmation
has genuine value for low-vision users — a T15 conversation, not a brand one.

**Q6 — Who owns the low-end reference device?**
The entire performance budget in §6.9 is stated against "a 2 GB Android on a mid-tier SoC", and the
review process in §7 requires recordings from it. No such device is named anywhere in the repo and no
performance harness exists.
*Options:* (a) name a specific handset, buy two, keep one on a desk and one in CI; (b) use a Firebase
Test Lab low-end profile; (c) leave it to each engineer's judgement.
**Recommendation: (a).** Roughly $250 of hardware makes every performance claim in this document
checkable. Without it, §6.9 is aspiration.
