# 13 — Motion, Micro-interactions & Perceived Performance

> Track: B — Product surface & experience · Reviewer: chat-20260801-1327-783d · Date: 2026-08-01 (UTC)
> Base commit reviewed: `697f4347045e67bc488a9c91631d6497ab6511d7`

## 1. Scope

This document covers the **motion layer** of Synaptic Go: every animation that
exists today in the two Flutter apps and the shared package, the tokens that
should govern them and do not, the choreography the product's key moments
deserve, and the use of motion to mask latency the architecture cannot remove.

Concretely, in scope:

- Animation inventory: durations, curves, and whether values are tokens or literals.
- The launch/splash mechanism and its cold-start cost.
- Map marker movement and bearing.
- Bottom-sheet presentation, gesture behaviour and keyboard handling.
- List insertion (rider bid list, captain offer list).
- Skeletons vs spinners; what fills the three longest waits.
- Haptics, on both platforms and both apps.
- Frame budget: repaint scope, rebuild scope, animated-subtree cost.
- Reduce-motion behaviour.
- The motion token set to add to the shared theme.

Explicitly **not** in scope, with the sibling track that owns it:

| Not covered here | Owner |
|---|---|
| Colour, type, spacing, elevation tokens and component visual specs | **T12** — Design System & Visual Language |
| The accessibility programme as a whole (contrast, semantics, screen-reader, tap targets). This document specifies reduce-motion behaviour only, as motion's own obligation | **T15** — Accessibility & Inclusive Design |
| Systematically de-duplicating rider/captain screens and unifying vocabulary | **T27** — Cross-App Parity |
| Building the shared animation library as an implementation project | **T28** — Motion Development |
| Rider and captain journey/flow correctness | **T09**, **T10** |
| Map/routing accuracy, GPS quality, route geometry | **T21** |
| Backend latency itself (dispatch time, estimate time) — this document treats latency as a given and covers only how it is *presented* | **T06**, **T24** |
| App size/store limits as a release concern | **T26** |

**Relationship to T28.** T13 (this document) is the *specification*: what should
move, when, for how long, on what curve, with what haptic. T28 is the *build*.
Section 6 is written so that T28 can implement from it without further design
input. Where I specify a constant, it is intended to be copied literally.

**Relationship to existing docs.** I grepped `docs/ROADMAP.md`,
`docs/IMPROVEMENTS.md` and `docs/CHECKLIST.md` for `motion|animat|haptic|shimmer|
skeleton|interpolat`. **Zero matches in all three.** Motion has never been
written down as an axis in this project. There is nothing to write on top of; this
is the first pass, which is also why the findings below are as basic as they are.

---

## 2. What I actually read

All reads are at base commit `697f4347045e67bc488a9c91631d6497ab6511d7`. Every
line number in this document refers to that snapshot.

### Read line by line

| File | Note |
|---|---|
| `packages/flutter_shared/lib/theme/app_theme.dart` | 1055 lines. The whole token system. Read specifically for motion tokens — there are none. |
| `packages/flutter_shared/lib/widgets/skeleton_loader.dart` | Custom shimmer, shared sweep controller, correct reduce-motion gating. The best-engineered motion code in the repo. |
| `packages/flutter_shared/lib/widgets/loading_overlay.dart` | 38 lines, quoted in full in §3. |
| `packages/flutter_shared/lib/widgets/vehicle_map_marker.dart` | Stateless, `Transform.rotate`, no interpolation. |
| `packages/flutter_shared/lib/widgets/go_online_button.dart` | Press scale, colour tween, ungated infinite pulse. |
| `packages/flutter_shared/lib/widgets/main_bottom_nav.dart` | 23 KB. Tab indicator, crest, press feedback, haptics. |
| `packages/flutter_shared/lib/widgets/status_chip.dart` | 61 lines. No animation at all. |
| `apps/captain/lib/screens/home/offer_card_entrance.dart` | The centrepiece entrance animation. 3079 bytes, read completely. |
| `apps/captain/lib/screens/home/offer_card.dart` | 34 KB. Countdown controller, haptics, the per-frame `BackdropFilter`. |
| `apps/rider/lib/screens/ride/captain_bids_sheet.dart` | 27 KB. The bid list. Read closely because it is the S1. |
| `apps/rider/lib/screens/trip/trip_screen.dart` | 34 KB. Marker updates, WS handler, wait states. |
| `apps/rider/lib/screens/splash_screen.dart` | 16 KB. Reduce-motion done properly. |
| `apps/captain/lib/screens/splash_screen.dart` | 15 KB. The same screen with reduce-motion absent. |
| `apps/rider/pubspec.yaml`, `apps/captain/pubspec.yaml` | Dependency and asset declarations. |

### Read in full, analysis delegated to subagents and then spot-verified by me

`apps/rider/lib/screens/home/home_screen.dart` (48 KB) ·
`apps/rider/lib/screens/home/fare_estimate_sheet.dart` ·
`apps/rider/lib/screens/home/vehicle_selector.dart` ·
`apps/rider/lib/screens/home/location_search_sheet.dart` ·
`apps/rider/lib/screens/home/travel_mode_bottom_bar.dart` ·
`apps/rider/lib/screens/ride/rating_sheet.dart` ·
`apps/rider/lib/screens/ride/trip_detail_screen.dart` ·
`apps/rider/lib/main.dart` · `apps/captain/lib/main.dart` ·
`apps/captain/lib/screens/home/active_trip_panel.dart` ·
`apps/captain/lib/screens/home/main_shell.dart` (28 KB) ·
`apps/captain/lib/screens/home/home_tab.dart` ·
`apps/captain/lib/screens/home/available_trips_tab.dart` ·
`apps/captain/lib/screens/home/nearby_requests_screen.dart` ·
`apps/captain/lib/screens/home/trips_tab.dart` ·
`packages/flutter_shared/lib/widgets/` — `counter_offer_sheet.dart`,
`empty_state.dart`, `error_state.dart`, `navigation_button.dart`,
`offline_gate.dart`, `offline_guard_banner.dart`, `godrive_wordmark.dart`,
`go_date_field.dart`, `map_controls.dart`.

**On the subagents.** Three ran in parallel over the rider surface, the captain
surface and the shared package. I re-verified every claim that carries S1 or S2
severity below with my own grep against the downloaded snapshot. One subagent
claim was **wrong and is not in this document**: it reported
`apps/rider/lib/screens/trip/trip_chat_screen.dart` as a dangling import at
`trip_screen.dart:10`. The file exists (5016 bytes) — it simply had not been
downloaded at that point. The real finding in that area is divergence, not
absence, and it is in §9.

### Skimmed, not read

- `docs/ROADMAP.md`, `docs/IMPROVEMENTS.md`, `docs/CHECKLIST.md` — grepped for
  motion vocabulary only (zero hits). I did not read them end to end.
- `apps/admin/**` — not opened. The admin console is T11's surface and has no
  Flutter motion layer.
- `apps/api/**` — not opened except as noted. Backend latency is T06/T24.

### Could not verify

- **Real device frame timings.** No profiling artefacts exist in the repo and I
  cannot run a Flutter profile build. Every performance claim below is a
  static-analysis inference from widget-tree shape, and is labelled `likely`
  rather than `confirmed` where it depends on runtime cost.
- **The actual cold-start delta** of the splash. Same reason. What I can prove
  is the payload, and that is enough to act on.
- **`pubspec.lock`** — not read; I did not verify resolved transitive versions
  of `flutter_animate` / `shimmer`.

---

## 3. How it works today

### 3.1 There is no motion system — there are 30 unrelated numbers

`packages/flutter_shared/lib/theme/app_theme.dart` is a genuinely good token
file. It defines a full colour system (brand, semantic, three surface families,
day/night badge pairs, map colours), a radius scale at
`app_theme.dart:161`–`166` (`radiusXs 6` → `radiusPill 999`), a spacing scale at
`app_theme.dart:171`–`177` (`space2xs 4` → `space2xl 48`), four named shadow
sets, and typography helpers. Widgets reach it through
`GoTheme.of(context)` — a `ThemeExtension` lookup declared at
`app_theme.dart:373`–`374`, with a non-throwing fallback to the light theme.

It contains **no duration and no curve**. A grep of all 1055 lines for
`Duration|Curve|milliseconds|easeIn|easeOut` returns nothing.

The consequence is that every animated value in the product is a literal typed
at its call site. Across `apps/` and `packages/` there are **30 distinct
animation duration values**:

`70, 120, 140, 160, 180, 200, 220, 250, 260, 420, 460, 480, 500, 520, 560, 600,
620, 680, 700, 820, 1150, 1200, 1400, 1450, 1500, 1600, 1800, 2400, 3200, 3600` ms

and 5 curves, unevenly applied: `Curves.easeOut` (10 uses),
`Curves.easeOutCubic` (6), `Curves.easeOutBack` (3), `Curves.easeInOut` (2),
`Curves.easeInCubic` (1). A significant number of animated widgets specify no
curve at all and therefore silently run `Curves.linear`.

The clearest proof that this is drift rather than design is two pairs of
widgets that do the *same* job with different numbers:

| Job | Widget A | Widget B |
|---|---|---|
| Press feedback on a large pill | `go_online_button.dart:129` — 120 ms, scale 0.96, `easeOut` | `main_bottom_nav.dart:457` — 140 ms, scale 0.94, `easeOut` |
| "This item is now selected" | `main_bottom_nav.dart:620` — 200 ms, **no curve → linear** | `main_bottom_nav.dart:377` — 220 ms, `easeOut` |

The second pair is inside a single file: the nav tick and the nav crest
disagree with each other by 20 ms and by an entire easing philosophy.

### 3.2 Launch: the video is already gone, the payload is not

The brief asks whether a video is the right splash mechanism. It is the wrong
question for this commit, because **the video is no longer played**.

`apps/rider/lib/screens/splash_screen.dart:9`–`16` documents the change
explicitly: the MP4 was replaced by a static brand image because the aspect
ratio never matched, decode was visible, and low-end devices showed a white gap.
The screen now precaches `assets/images/splash_brand.png`
(`splash_screen.dart:85`–`88`) and holds for 2400 ms
(`splash_screen.dart:97`).

What was never done is deleting the asset. At the reviewed commit:

- `splash.mp4` — 875,855 bytes — exists at the repo root,
- **and** at `apps/rider/assets/videos/splash.mp4`,
- **and** at `apps/captain/assets/videos/splash.mp4`.

Both apps still declare the folder in their manifests —
`apps/rider/pubspec.yaml:63` and `apps/captain/pubspec.yaml:59` both list
`- assets/videos/` — so Flutter bundles the file into **both** shipped
binaries. Neither app depends on `video_player`, and a grep across every Dart
file for `mp4|video_player|VideoPlayer|assets/videos` returns **only those two
pubspec lines**. Nothing decodes it. Nothing references it.

That is ~855 KB of dead weight in each app download and ~2.5 MB in the
repository, for an asset the code deliberately stopped using.

### 3.3 Two splash screens, one of which forgot accessibility

The rider splash is careful work. It reads
`MediaQuery.maybeOf(context)?.disableAnimations` at
`apps/rider/lib/screens/splash_screen.dart:81`, gates the halo ticker on it at
`:73`–`:77`, collapses the switcher duration to zero at `:173`, and passes a
`reduceMotion` flag down into every sub-widget, each of which returns a still
fallback (`:296`, `:356`, `:434`, `:523`).

The captain splash renders the same brand moment and does none of it.
`apps/captain/lib/screens/splash_screen.dart:43`–`46` starts its master
controller with an unconditional `..repeat()`, and `:232` runs
`.animate(onPlay: (c) => c.repeat())` for a shimmer. There is no
`disableAnimations` check anywhere in `apps/captain/lib` — a grep of the entire
captain app returns nothing.

### 3.4 The captain's car teleports, and always points north

This is the single most visible craft gap in the product.

On the rider's trip screen the captain position arrives over the websocket and
is written straight to state:

```dart
// apps/rider/lib/screens/trip/trip_screen.dart:145-150
} else if (type == 'location.captain') {
  final lat = (ev['lat'] as num?)?.toDouble();
  final lng = (ev['lng'] as num?)?.toDouble();
  if (lat != null && lng != null) {
    setState(() => _captainLoc = LatLng(lat, lng));
  }
}
```

There is no tween, no `AnimationController`, no `TweenAnimationBuilder`. The
marker is repositioned on the next frame. Between GPS fixes the car does not
move at all; on each fix it jumps the whole distance.

The fallback path makes it worse. `trip_screen.dart:170`–`189` runs a
`Timer.periodic(const Duration(seconds: 10), ...)`. If the socket is down —
and `trip_screen.dart:163`–`169` records that `TripRoom` has failed closed
before — the rider's only positional refresh is that poll, so the jump covers
up to ten seconds of travel in one frame.

Second defect, in the same place. The marker is constructed like this:

```dart
// apps/rider/lib/screens/trip/trip_screen.dart:383-391
markers.add(Marker(
  point: _captainLoc!,
  width: 46,
  height: 46,
  child: VehicleMapMarker(
    color: go.action,
    size: 46,
  ),
));
```

`VehicleMapMarker` accepts a `heading` and rotates the silhouette to it —
`vehicle_map_marker.dart:44` computes `(heading ?? 0) * math.pi / 180` and
`:49`–`:50` applies `Transform.rotate`. The trip screen **never passes
`heading`**, so the expression evaluates to `0` and the car points due north for
the entire trip regardless of travel direction.

The captain's own app does pass it — `main_shell.dart:613` supplies
`heading: _heading` from the geolocator fix. So the driver sees a correctly
oriented car and the rider does not. Even there, `VehicleMapMarker` is a
`StatelessWidget` with no rotation animation, so bearing changes snap.

### 3.5 Sheets are panels wearing a sheet costume

Every rider sheet is presented with `showModalBottomSheet(isScrollControlled: true)`
— `home_screen.dart:407`–`434` (location search), `:460`–`472` (fare estimate),
`trip_screen.dart:205`–`213` (rating). None supplies a
`transitionAnimationController` or duration, so all three ride Flutter's default
modal curve.

None uses `DraggableScrollableSheet` or a `DraggableScrollableController`. Each
is a fixed-height `Container` — the location sheet is pinned at
`size.height * 0.82`. They cannot be dragged, cannot be flung, and cannot be
interrupted mid-transition. `location_search_sheet.dart:137`–`143` draws a drag
handle; it is decoration with no gesture behind it.

Keyboard handling is inconsistent across the three:

| Sheet | Keyboard | Evidence |
|---|---|---|
| Location search | Correct | `location_search_sheet.dart:125` — `EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom)` |
| Rating | Correct | `rating_sheet.dart:70` — `bottom: MediaQuery.of(context).viewInsets.bottom + 24` |
| **Fare estimate** | **Missing** | No `viewInsets` anywhere in the file, yet it hosts a numeric price field at `fare_estimate_sheet.dart:699`–`735` |

The fare sheet is where the rider types a counter-price. It is the one sheet
that most needs the treatment and the only one without it.

The bid panel is not a sheet at all: `trip_screen.dart:296`–`307` places it as a
`Positioned` child of a `Stack`, conditionally rendered from trip status. It has
no enter or exit transition — it appears between two frames.

### 3.6 The bid list replaces itself under the rider's thumb

`apps/rider/lib/screens/ride/captain_bids_sheet.dart` polls every five seconds
and replaces the entire list:

```dart
// captain_bids_sheet.dart:75-78
_poller = Timer.periodic(
  const Duration(seconds: 5),
  (_) => _fetchBids(silent: true),
);
```
```dart
// captain_bids_sheet.dart:104-108
setState(() {
  _bids = List<Map<String, dynamic>>.from(data['bids'] ?? []);
  _loading = false;
  _error = null;
});
```

The rendered list is `_bids` minus locally declined ids
(`captain_bids_sheet.dart:219`–`220`), drawn by a plain `ListView.separated`
(`:282`–`:302`). There is **no `AnimatedList`**, **no sort**, and — confirmed by
grep over the whole file — **no `ValueKey` or `ObjectKey` on any row**. Order is
whatever the server returned.

Nothing animates. A bid that arrives mid-poll simply exists on the next frame,
and every row beneath an inserted or withdrawn bid shifts position instantly.

The accept path commits immediately, with no confirmation:

```dart
// captain_bids_sheet.dart, _acceptBid
Future<void> _acceptBid(String bidId) async {
  setState(() => _accepting = bidId);
  ...
  final res = await http.post(
    Uri.parse('${widget.baseUrl}/trips/${widget.tripId}/accept-bid'),
    headers: _headers,
    body: jsonEncode({'bidId': bidId}),
  );
```

There is a busy guard — `busy: _accepting != null` at `:296`, with
`onPressed: busy ? null : onAccept` at `:570` — which correctly prevents
double-submission. It does not address the ordering problem. §4 works through
what that combination does to a rider.

### 3.7 Haptics exist in one app only

| Surface | `HapticFeedback` calls |
|---|---|
| `apps/captain/lib` + `packages/flutter_shared/lib` | **11** |
| `apps/rider/lib` | **0** |

The captain app is reasonably wired: `mediumImpact` on accept
(`offer_card.dart:141`), `lightImpact` on decline (`:167`), `mediumImpact` on
counter-offer (`:202`), a per-second `lightImpact` tick in the final five
seconds of the countdown (`:112`), `mediumImpact` on every trip-stage action
(`active_trip_panel.dart:108`), `mediumImpact` on assignment
(`main_shell.dart:153`), online toggle and confirmation (`:351`, `:362`),
`heavyImpact` on SOS (`:747`), and `lightImpact` on a nav crest tap
(`main_bottom_nav.dart:447`).

The rider app has none. Not on bid arrival, not on accepting a bid, not on
captain assignment, not on arrival, not on trip completion.

And the one moment the captain app most needs is also missing: **a new offer
arriving fires no haptic**. The first vibration a driver gets is the one caused
by their own tap. A driver in a mounted phone at speed has no non-visual signal
that money just appeared on screen.

### 3.8 What is on screen during the three long waits

| Wait | What the rider sees | Timeout | Evidence |
|---|---|---|---|
| Fare estimate | Spinner + "جارٍ حساب الأجرة…" in a blank 190 px box, replacing the whole sheet body — including the route data the app already has | none | `fare_estimate_sheet.dart:514`–`539`; unconstrained `await` at `:138`–`145` |
| Dispatch / finding a captain | 48 px spinner + "جارٍ البحث عن كابتن…" + Cancel. No elapsed time, no bid count, no progress | none — the poll only stops on `completed`/`cancelled` | `trip_screen.dart:460`–`471`; `:172`–`180` |
| Payment | No async payment step exists — the product is cash-only at this commit (`fare_estimate_sheet.dart:344`–`356`); the receipt renders statically on completion | n/a | `trip_screen.dart:550`–`564` |

Skeletons are used well in two places and not at all where the wait is longest.
`location_search_sheet.dart:229`–`233` renders five result-shaped skeletons
(icon box + two bars) that genuinely match the real row, and
`home_screen.dart:1427`–`1457` uses a two-bar skeleton for the resolving pin
address. The fare sheet — a longer, more anxious wait — gets a bare spinner in
an empty box.

`skeleton_loader.dart` itself is the best motion code in the repository: a
shared `AnimationController` hosted by `_SweepHost` so all rows sweep in phase
(`:127`–`:176`), RTL-aware direction (`:99`–`:100`), semantic colours from
`GoTheme` rather than hardcoded greys (`:87`–`:93`), and a correct reduce-motion
gate that returns a flat fill (`:58`–`:63`, `:75`, `:120`–`:121`). It exports
only two primitives though — `SkeletonBox` and a generic `SkeletonList` whose
row is a 48 px circle plus two bars — so every screen that wants a
content-shaped skeleton has to assemble one by hand, which is why most do not.

`LoadingOverlay` is the opposite. Thirty-eight lines, and it is the whole
loading story for several screens:

```dart
// packages/flutter_shared/lib/widgets/loading_overlay.dart:11-14
Widget build(BuildContext context) {
  return Container(
    color: Colors.black.withOpacity(0.4),
```

It pops in with no fade, has no minimum display time (so a fast response makes
it flash), hardcodes `Colors.black.withOpacity(0.4)` instead of the `go.scrim`
token that exists at `app_theme.dart:392`, and hardcodes white for both the
spinner (`:23`) and the label (`:30`), bypassing `AppTokens.font()` so the text
is not even Cairo.

### 3.9 Frame budget

There is **one** `RepaintBoundary` in the entire codebase —
`home_screen.dart:552`–`577`, wrapping the rider's `FlutterMap`. That one is
correct and valuable. There are none in `packages/flutter_shared`, which means
every animated shared widget repaints in its parent's layer.

The most expensive animated subtree in the product is the captain's offer card:

```dart
// apps/captain/lib/screens/home/offer_card.dart:286-302
return AnimatedBuilder(
  animation: _countdown,
  ...
        child: BackdropFilter(
```

`_countdown` is a 15-second controller (`offer_card.dart:71`–`74`) that ticks
every frame. The builder's `child` argument is unused, so nothing is hoisted out
of the rebuild, and a `BackdropFilter` with an 18-sigma blur is reconstructed
and re-evaluated ~900 times per offer. This is the screen a driver sees while
driving.

Rebuild scope is broad elsewhere too:

- `main_shell.dart:400` calls `context.watch<CaptainState>()` at the root of
  `build`, so every GPS tick, every socket event and every status change
  rebuilds the entire shell — `Stack`, five-tab `IndexedStack`, map, map
  controls and banner. No `Selector`, no `Consumer` scoping.
- `trip_screen.dart:144`, `:149`, `:184` — three `setState` calls from the
  socket and the poll, each rebuilding the full trip screen including all
  markers.
- `captain_bids_sheet.dart:104` — the 5-second poll rebuilds the whole panel.
- `home_screen.dart:97`–`100` — `_pulseController` repeats forever at 2 s and
  drives an `AnimatedBuilder` (`:847`–`:882`) whose invariant inner dot is
  rebuilt every frame because it is not passed as `child`.

That last controller is also the rider app's only infinite animation outside the
splash, and it has no reduce-motion gate. The captain app has five such ungated
loops: `splash_screen.dart:45` and `:232`, `home_tab.dart:375`–`376`,
`available_trips_tab.dart:158`–`164`, and `go_online_button.dart:57`.

---

## 4. Findings

| ID | Sev | Finding | Evidence (`path:line`) | Impact | Confidence |
|---|---|---|---|---|---|
| F-13-01 | S1 | Rider bid list is replaced wholesale every 5 s with no insertion animation, no stable keys and no confirmation on accept — the rider can commit to a fare they did not choose | `captain_bids_sheet.dart:75`, `:104`, `:219`, `:282`, `_acceptBid` | Wrong price, wrong captain, no undo. Money-touching | confirmed |
| F-13-02 | S2 | No duration or curve tokens exist; 30 distinct ad-hoc duration literals and 5 inconsistently applied curves | `app_theme.dart` (1055 lines, zero matches); scales at `:161`, `:171` | Nothing can be tuned centrally; the product cannot feel coherent | confirmed |
| F-13-03 | S2 | Captain marker teleports between GPS fixes on the rider's trip screen; no interpolation | `trip_screen.dart:145`–`150`; poll `:172` | The core "my ride is coming" moment reads as broken | confirmed |
| F-13-04 | S2 | The rider's captain marker is built without `heading`, so the car always points north | `trip_screen.dart:383`–`391`; `vehicle_map_marker.dart:44` | Cheap, visible wrongness on the highest-attention screen | confirmed |
| F-13-05 | S2 | 855 KB `splash.mp4` is bundled into both app binaries (and a third copy sits at repo root) with zero code references and no `video_player` dependency | `apps/rider/pubspec.yaml:63`; `apps/captain/pubspec.yaml:59`; grep: only those 2 hits | ~855 KB of dead download per app, ~2.5 MB in the repo | confirmed |
| F-13-06 | S2 | Zero `HapticFeedback` calls in the entire rider app | grep `apps/rider/lib` → 0; captain+shared → 11 | Every rider confirmation is silent; the two apps feel like different products | confirmed |
| F-13-07 | S2 | A new offer arriving in the captain app fires no haptic and no sound; the first feedback is the driver's own tap | `offer_card_entrance.dart` (none); first haptic at `offer_card.dart:141` | A driving captain can miss offers → lost revenue, and eyes-on-screen pressure | confirmed |
| F-13-08 | S2 | Zero reduce-motion gating anywhere in the captain app; five looping animations run unconditionally | `apps/captain/lib` grep → 0; `splash_screen.dart:45`, `:232`; `home_tab.dart:375`; `available_trips_tab.dart:158`; `go_online_button.dart:57` | Vestibular-disorder users have no escape in the captain app | confirmed |
| F-13-09 | S2 | The offer card rebuilds a `BackdropFilter` blur every frame for 15 s; `AnimatedBuilder.child` unused | `offer_card.dart:286`–`302`, controller `:71` | Jank on the driver's most important screen, on mid-range Android | likely |
| F-13-10 | S3 | The fare estimate sheet does not offset for the keyboard, though it hosts the price input | no `viewInsets` in `fare_estimate_sheet.dart`; field at `:699`–`735` | Keyboard covers the field the rider must type in | confirmed |
| F-13-11 | S3 | No sheet is draggable or interruptible; the drag handle is decorative | `home_screen.dart:407`, `:460`; handle at `location_search_sheet.dart:137`–`143` | Sheets feel like web modals, not native surfaces | confirmed |
| F-13-12 | S3 | The bid panel has no enter/exit transition — it appears between two frames | `trip_screen.dart:296`–`307` | The most emotionally loaded arrival in the app is unmarked | confirmed |
| F-13-13 | S3 | `LoadingOverlay`: no fade-in, no minimum display time, ignores `go.scrim`, hardcodes white text and spinner, bypasses `AppTokens.font()` | `loading_overlay.dart:13`, `:23`, `:30`; token at `app_theme.dart:392` | Flash-on-fast-response; off-system in dark mode | confirmed |
| F-13-14 | S3 | Only one `RepaintBoundary` in the whole codebase; none in the shared package | `home_screen.dart:552` is the only one | Animated widgets dirty their parents' layers | confirmed |
| F-13-15 | S3 | Whole-screen rebuilds driven by socket/timer ticks | `main_shell.dart:400`; `trip_screen.dart:144`,`:149`,`:184`; `home_screen.dart:223` | Wasted frames during exactly the moments that must stay smooth | likely |
| F-13-16 | S3 | The dispatch wait has no elapsed time, no progress, no bid count and no timeout | `trip_screen.dart:460`–`471`, `:172`–`180` | Indefinite spinner is the highest-abandonment state in the funnel | confirmed |
| F-13-17 | S3 | Two widgets that perform the same job disagree: press feedback 120 ms/0.96 vs 140 ms/0.94; selected-state 200 ms linear vs 220 ms easeOut | `go_online_button.dart:129` vs `main_bottom_nav.dart:457`; `main_bottom_nav.dart:620` vs `:377` | Visible inconsistency inside one nav bar | confirmed |
| F-13-18 | S3 | The rider's only infinite animation outside splash is ungated, and rebuilds an invariant child every frame | `home_screen.dart:97`–`100`, `:847`–`:882` | Battery + reduce-motion violation | confirmed |
| F-13-19 | S3 | `StatusChip` hard-swaps colour and label with no transition | `status_chip.dart:5`–`61` | Trip-state changes go unnoticed | confirmed |
| F-13-20 | S4 | Nav tab icon and colour hard-swap; only a 3 dp tick animates; no haptic on regular tabs | `main_bottom_nav.dart:604`, `:632`, `:620`; haptic only at `:447` | Tab changes feel unacknowledged | confirmed |
| F-13-21 | S4 | The skeleton library exports only two primitives, so most screens fall back to spinners | `skeleton_loader.dart` (`SkeletonBox`, `SkeletonList`); e.g. `fare_estimate_sheet.dart:514` | Content-shaped loading is the exception, not the default | confirmed |
| F-13-22 | S4 | Two independent entrance-animation implementations for the same card; `AvailableTripsTab` appears to be dead code | `offer_card_entrance.dart:26`–`27` used only at `available_trips_tab.dart:113`; inline variant at `nearby_requests_screen.dart:287`–`292`; shell mounts `NearbyRequestsScreen` at `main_shell.dart:443` | Divergent behaviour, dead maintenance surface | likely |

---

### F-13-01 (S1) — The rider can accept a fare they did not choose

This is the only S1 in this document, and it is a motion finding that has become
a money finding.

**What happens.** The bids panel polls silently every five seconds and swaps the
whole list for whatever the server returned:

```dart
// captain_bids_sheet.dart:75-78
_poller = Timer.periodic(
  const Duration(seconds: 5),
  (_) => _fetchBids(silent: true),
);
```

The rendered list is derived fresh on every build
(`captain_bids_sheet.dart:219`–`220`) and drawn by a plain `ListView.separated`
with no keys (`:282`–`:302`). Rows carry no identity across rebuilds and nothing
animates, so an insertion or a withdrawal shifts every row below it with no
visual event.

Tapping accept is immediate and final — `_acceptBid` POSTs to
`/trips/{id}/accept-bid` with no confirmation dialog and no undo.

**Why it bites.** Be precise about the mechanism, because the obvious version of
this bug is *not* the one present here. The accept closure captures its id at
build time — `onAccept: () => _acceptBid(bidId)` at
`captain_bids_sheet.dart:298` — so the tap always sends the id of the row *as
last built*. There is no id/row mismatch.

The failure is one level up, in human time. The rider reads the list, decides on
the 62 EGP bid sitting second from top, and moves their thumb. Somewhere in the
200–400 ms that takes, the poll fires. A cheaper bid arrived, or the one they
were looking at was withdrawn. The list is rebuilt; a different bid now occupies
that position; and the tap lands on a correctly-bound closure for **a bid the
rider never evaluated**. They have just agreed a price and a captain by
accident, silently, with no confirmation step in the way.

At five-second intervals over a dispatch window where bids arrive in bursts,
this is not a rare race. It is a routine one.

**Why it belongs to T13.** Every one of the mitigations is a motion or
interaction-design mechanism: animate insertions so the eye tracks displacement,
never reorder under an active pointer, and mark the moment of commitment. The
protection is choreography, not backend work. P0.1 in §6 specifies it.

**Cross-reference.** T03 owns money integrity and T05 owns bidding economics;
both should know that the client can commit to the wrong bid regardless of how
correct the server-side ledger is. Flagged in §9.

---

### F-13-02 (S2) — Thirty numbers where there should be six

`app_theme.dart` tokenises colour, radius, spacing, elevation and type, and
exposes them through `GoTheme.of(context)`. It does not tokenise time. The
result is 30 distinct duration literals scattered across call sites, and curves
chosen ad hoc — including a number of animated widgets with no `curve:` argument
at all, which silently run `Curves.linear`, the one curve that never appears in
nature.

The two same-job disagreements in §3.1 are the proof this is entropy rather than
intent: a 20 ms and easing difference between the nav tick and the nav crest
inside one file cannot be a decision.

This finding is the reason most of the others are cheap to fix. Once
`AppTokens.durationFast` and `AppTokens.curveStandard` exist, the corrections in
§6 are mostly one-line substitutions.

---

### F-13-03 / F-13-04 (S2) — The car teleports, and it faces the wrong way

`trip_screen.dart:145`–`150` writes each websocket fix straight into state. No
tween. The marker holds still between fixes and jumps the whole gap on arrival.
With the socket down, `trip_screen.dart:172` is the only refresh at ten-second
intervals, so the jump can span ten seconds of driving in a single frame.

Separately, `trip_screen.dart:383`–`391` omits `heading`. `VehicleMapMarker`
defaults it to `0` at `vehicle_map_marker.dart:44`, so the silhouette points
north for the entire trip. The captain's own app passes it correctly at
`main_shell.dart:613` — so the two apps disagree about which way the same car is
facing.

These two together are what the brief calls the difference between amateur and
professional, and they are the highest ratio of perceived quality to engineering
cost in this document. P0.2 specifies both, plus the bearing derivation for when
the payload has no heading field.

---

### F-13-05 (S2) — 855 KB of video that nothing plays

The rider splash's own header comment (`splash_screen.dart:9`–`16`) explains
that the MP4 was deliberately replaced by a static image. The replacement
shipped; the deletion did not.

`splash.mp4` (875,855 bytes) exists three times — repo root,
`apps/rider/assets/videos/`, `apps/captain/assets/videos/` — and both manifests
still declare `- assets/videos/` (`apps/rider/pubspec.yaml:63`,
`apps/captain/pubspec.yaml:59`), so the bundler packs it into both binaries.
Neither app depends on `video_player`. A grep for
`mp4|video_player|VideoPlayer|assets/videos` across every Dart file in the
repository returns those two pubspec lines and nothing else.

This is a one-line change per app plus three file deletions. It is in P0 because
it is free.

---

### F-13-06 / F-13-07 (S2) — Silence on both sides, for different reasons

The rider app contains zero `HapticFeedback` calls. Bid arrived, bid accepted,
captain assigned, captain arrived, trip complete: all silent. The captain app
and shared package contain eleven, which makes this an asymmetry rather than an
oversight — one app got the treatment and the other did not.

The captain app's own gap is narrower but sharper. Its haptics all fire on
*self-initiated* actions: accept (`offer_card.dart:141`), decline (`:167`),
counter (`:202`), stage transitions (`active_trip_panel.dart:108`), online
toggle (`main_shell.dart:351`). The one event the driver does not initiate — a
new offer arriving — produces nothing. There is a countdown tick at ≤5 s
(`offer_card.dart:112`), which helps only if the driver is already looking.

For a driver at speed with the phone mounted, an offer that arrives without a
haptic is an offer that can expire unseen. That is direct revenue loss for both
the captain and the platform, and it pushes drivers to watch the screen instead
of the road.

---

### F-13-08 (S2) — One app respects reduce-motion; the other has never heard of it

`apps/rider/lib/screens/splash_screen.dart` handles this properly, reading
`disableAnimations` at `:81` and threading a `reduceMotion` flag through every
child so each has a still fallback (`:296`, `:356`, `:434`, `:523`).
`apps/rider/lib/main.dart:141` does the same for the root transition. The shared
`skeleton_loader.dart:120`–`121` does it correctly too.

A grep for `disableAnimations|accessibleNavigation` across all of
`apps/captain/lib` returns **nothing**. Five loops run unconditionally:

| Location | Animation |
|---|---|
| `splash_screen.dart:45` | master controller, `..repeat()`, 3600 ms |
| `splash_screen.dart:232` | wordmark shimmer, `.animate(onPlay: (c) => c.repeat())` |
| `home_tab.dart:375`–`376` | searching pulse, 1600 ms, loops |
| `available_trips_tab.dart:158`–`164` | radar pulse, 1500 ms, loops |
| `go_online_button.dart:57` | live dot, 1400 ms, `repeat(reverse: true)` — in the **shared** package, so it leaks into the rider app too |

The last one matters most: it is shared code, so fixing it fixes both apps.
T15 owns accessibility overall; the reduce-motion contract for animations is
motion's own obligation and is specified in P0.4.

---

### F-13-09 (S2) — A blur re-evaluated 900 times per offer

```dart
// apps/captain/lib/screens/home/offer_card.dart:286
return AnimatedBuilder(
  animation: _countdown,
```
```dart
// apps/captain/lib/screens/home/offer_card.dart:302
child: BackdropFilter(
```

`_countdown` runs for 15 seconds (`offer_card.dart:71`–`74`), ticking every
frame. The builder ignores its `child` parameter, so nothing is hoisted; the
entire card — `Opacity` → `Padding` → `ClipRRect` → `BackdropFilter`(σ=18) →
`Container` — is rebuilt ~900 times per offer.

Only the ring and the seconds integer actually change. Everything else is
static for the life of the card.

Marked `likely` rather than `confirmed` because I cannot profile a build from
here; the widget-tree shape is confirmed, the frame cost is inferred. A
backdrop blur on a per-frame rebuild path on mid-range Android is a
well-established jank source, and this is the screen a moving driver looks at.
P1.2 scopes the fix; it is small.

---

## 5. Benchmark gap

Confidence is marked per claim. `confident` = well-documented, widely observed
behaviour. `assumed` = my inference about their implementation, stated as such.

### Marker movement

**Uber** interpolates the vehicle marker between location updates, animating
position and bearing so a ~4 s GPS cadence reads as continuous travel; the
marker also rotates to heading (`confident` — this is the single most-copied
detail in the category). Their driver-position pipeline additionally snaps the
point to the road graph before animating (`assumed`).

**inDrive** does the same interpolation with a plainer marker (`assumed`).

**Synaptic Go** does neither: the rider's marker teleports
(`trip_screen.dart:145`–`150`) and never rotates
(`trip_screen.dart:383`–`391`). This is the widest single gap in this document.

### Offer / bid arrival

**Uber** driver-side: full-screen takeover, distinct sound, sustained haptic,
draining countdown ring — designed to be actionable without the driver
initiating a look (`confident`).

**inDrive**: a rider-facing list of driver bids that animates rows in and holds
position while the rider decides, and driver-side offers with audible alerts
(`confident` for the bid-list model, which is inDrive's core mechanic;
`assumed` for the exact animation).

**Synaptic Go** captain-side is closer than expected: it has a real draining
ring (`offer_card.dart:964`, `:453`), an urgency colour flip at ≤5 s (`:289`–`:295`),
a final-five-seconds haptic tick (`:112`), and a staggered entrance
(`offer_card_entrance.dart:26`–`27`). What it lacks is the arrival signal
itself — no sound, no haptic at t=0 (F-13-07).

Rider-side is the weak half: bids appear with no animation and no haptic, and
the list is unstable under polling (F-13-01). Since price negotiation is the
product's differentiator, this is the surface that most needs to feel
trustworthy.

### Perceived performance during dispatch

**Uber** fills the search wait with staged, honest progress — "contacting
nearby drivers", radar sweep, then driver detail — so the wait is narrated
(`confident`).

**Synaptic Go** shows an unchanging 48 px spinner with no elapsed time, no bid
count and no timeout (`trip_screen.dart:460`–`471`). The information to narrate
it already exists client-side: the bid poll knows how many bids have arrived
(`captain_bids_sheet.dart:105`).

### Motion tokens

Material 3 ships a duration scale (`short1`–`extraLong4`) and an emphasised
easing set, and Flutter exposes them. A team can either adopt those or define
their own. **Synaptic Go has done neither** (F-13-02) — it is below the Material
baseline the brief names as the floor, not above it.

### Reduce motion

Both Uber and inDrive respect the platform reduce-motion setting (`assumed` —
both are large enough to be under active accessibility review). Synaptic Go
respects it in the rider splash and the shared skeleton, and nowhere in the
captain app (F-13-08).

### Where Synaptic Go is already competitive

Worth stating plainly, because it changes what P0 should be:

- The **skeleton system** (`skeleton_loader.dart`) — phase-synchronised shared
  controller, RTL-aware sweep, semantic colours, correct reduce-motion gate — is
  at or above what most apps in this category ship.
- The **captain countdown ring** with its urgency flip and haptic ticks is a
  genuine piece of craft.
- The **rider splash** is a well-choreographed, accessibility-correct launch.

The problem is not that this team cannot do motion. It is that the motion they
did is unevenly distributed and untokenised. That is a much cheaper problem.

---

## 6. Improvement plan

Ordered. P0 items are the S1 plus the free wins plus the two that most change
perceived quality.

### P0.1 — Make the bid list safe to tap

- **Goal** — a rider can never commit to a bid they did not evaluate.
- **Design** — four mechanisms, in order of importance:
  1. **Freeze during interaction.** Hold incoming poll results in a pending
     buffer while a pointer is down or the list has scrolled in the last 800 ms.
     Apply on release. A `Listener` at the list root drives an `_interacting`
     flag; `_fetchBids` writes to `_pendingBids` when set.
  2. **Never reorder silently.** Render in stable arrival order — new bids
     append, they do not insert above evaluated rows. If the server returns a
     different order, reconcile by id and keep existing positions.
  3. **Animate insertion.** Move the list to `AnimatedList` keyed by bid id, with
     a 260 ms `easeOutCubic` size+fade insertion, so displacement is a visible
     event rather than a discontinuity.
  4. **Mark commitment.** `HapticFeedback.mediumImpact()` on accept, and an
     accepted-row state (row lifts, others dim) held for 400 ms before the panel
     swaps out. On a bid ≥15% above the cheapest available, require a
     press-and-hold or a confirm — an accidental tap should not be able to cost
     the rider materially more.
- **Files to change** — `apps/rider/lib/screens/ride/captain_bids_sheet.dart`
  (list, poll buffer, keys, haptic, confirm); optionally hoist the reusable
  buffered-list behaviour into `packages/flutter_shared/lib/widgets/`.
- **DB** — none.
- **API contract** — none. Everything is client-side.
- **Effort** — M (1–3 days).
- **Risk** — the pending buffer can stale the list if the release condition is
  never met; bound it (force-apply after 3 s idle). Rollback is reverting one
  file.
- **Acceptance criteria**
  - A poll landing while a pointer is down does not change row order.
  - Every row has a `ValueKey(bid.id)`; no row is ever rebuilt with a different
    bid's content.
  - New bids animate in over 260 ms; no row jumps position without animation.
  - Accept fires a `mediumImpact` and shows a committed state before teardown.
  - Accepting a bid ≥15% above the cheapest requires a second deliberate action.
- **Tests** — widget test: pump a list, put a pointer down, deliver a poll with
  reordered bids, assert order unchanged and that the accept callback carries
  the id under the finger. Widget test: deliver an insertion, assert
  `AnimatedList.insertItem` was called and order is append-only.

### P0.2 — Interpolate the vehicle marker and give it a bearing

- **Goal** — the captain's car moves continuously and faces where it is going.
- **Design** — a `SmoothVehicleMarker` in the shared package holding the last
  and current `LatLng`, driving a `TweenAnimationBuilder` on each new fix.
  - Position: `LatLngTween` over a duration matched to the observed update
    interval, clamped to `[1200 ms, 4000 ms]`, `Curves.linear` (constant travel
    must not ease — easing a position tween reintroduces the stutter it exists
    to remove).
  - Bearing: `Tween<double>` over 400 ms `easeOut`, shortest-arc across the
    0°/360° seam.
  - If the payload carries no heading, derive it from the vector between the
    previous and current fix, and hold the last known bearing when the
    displacement is under ~5 m so a stationary car does not spin on GPS noise.
  - Wrap in a `RepaintBoundary` so marker frames do not dirty the map layer.
- **Files to change** — new
  `packages/flutter_shared/lib/widgets/smooth_vehicle_marker.dart`; export from
  `packages/flutter_shared/lib/flutter_shared.dart`;
  `apps/rider/lib/screens/trip/trip_screen.dart:383`–`391` (use it, pass
  heading); `apps/rider/lib/screens/home/home_screen.dart` (nearby captains);
  `apps/captain/lib/screens/home/main_shell.dart:608`–`620` (adopt for parity).
- **DB** — none.
- **API contract** — none required. The websocket `location.captain` payload is
  consumed at `trip_screen.dart:145`–`150`; if it already carries a heading
  field, pass it, otherwise derive. Adding `heading` to that payload later is a
  pure improvement, not a prerequisite — flag to **T07**.
- **Effort** — M (1–3 days including the two adoption sites).
- **Risk** — a tween longer than the real update interval makes the marker lag
  reality; the clamp plus "snap if the new fix is >250 m away" handles both
  teleports and stalls.
- **Acceptance criteria**
  - Between two fixes the marker's rendered position changes every frame.
  - The silhouette's rotation matches the direction of travel within ~15°.
  - A stationary vehicle does not rotate.
  - A >250 m jump snaps rather than gliding across the city.
- **Tests** — widget test with pumped fixes asserting intermediate positions
  differ frame to frame; unit test on the bearing helper for the 350°→10° seam
  and for the sub-5 m hold.

### P0.3 — Delete the dead splash video

- **Goal** — remove ~855 KB from each app download for zero product change.
- **Design** — delete `splash.mp4` at the repo root, at
  `apps/rider/assets/videos/` and at `apps/captain/assets/videos/`; remove the
  `- assets/videos/` line from `apps/rider/pubspec.yaml:63` and
  `apps/captain/pubspec.yaml:59`.
- **Files to change** — the two pubspecs; three asset deletions.
- **DB / API** — none.
- **Effort** — S (well under an hour).
- **Risk** — essentially none. Verified: no Dart file references `mp4`,
  `video_player`, `VideoPlayer` or `assets/videos`. Rollback is a revert.
- **Acceptance criteria** — release APK/IPA is ~855 KB smaller; both apps build;
  the splash is visually unchanged.
- **Tests** — `flutter build apk --analyze-size` before and after.

### P0.4 — Motion tokens, and a reduce-motion contract

- **Goal** — one place to tune time, and one rule every animation obeys.
- **Design** — add a motion block to `AppTokens` beside the radius scale
  (`app_theme.dart:161`) and the spacing scale (`:171`), reachable exactly as
  colour is today via `GoTheme.of(context)`.

```dart
// packages/flutter_shared/lib/theme/app_theme.dart — add to AppTokens

// ── Motion: duration ──────────────────────────────────────────────
// Six values. If a new animation does not fit one, the animation is
// wrong before the token is.
static const Duration durationInstant = Duration(milliseconds: 100);
static const Duration durationFast    = Duration(milliseconds: 180);
static const Duration durationNormal  = Duration(milliseconds: 260);
static const Duration durationSlow    = Duration(milliseconds: 400);
static const Duration durationSheet   = Duration(milliseconds: 320);
static const Duration durationAmbient = Duration(milliseconds: 1600);

// ── Motion: curves ────────────────────────────────────────────────
static const Curve curveStandard   = Curves.easeOutCubic; // most things
static const Curve curveDecelerate = Curves.easeOut;      // entering
static const Curve curveAccelerate = Curves.easeIn;       // leaving
static const Curve curveEmphasised = Curves.easeOutBack;  // celebration only
static const Curve curveLinear     = Curves.linear;       // travel + shimmer

// ── Motion: stagger ───────────────────────────────────────────────
static const Duration staggerStep = Duration(milliseconds: 60);
static const int      staggerMax  = 6; // cap so long lists stay responsive
```

  The rule, to be written into the design-system doc:

  | Use | Duration | Curve |
  |---|---|---|
  | Press / release feedback, ripple, tick | `durationInstant` | `curveStandard` |
  | Colour, opacity, small size, chip and badge changes | `durationFast` | `curveStandard` |
  | Element enters or leaves, list insertion, card expand | `durationNormal` | `curveDecelerate` entering, `curveAccelerate` leaving |
  | Full-panel or route transition | `durationSlow` | `curveStandard` |
  | Bottom sheets | `durationSheet` | `curveDecelerate` |
  | Ambient loops (pulse, shimmer, radar) | `durationAmbient` | `curveLinear` |
  | Celebration only — trip complete, payment success | `durationSlow` | `curveEmphasised` |
  | Continuous travel (marker position) | matched to update interval | `curveLinear` |

  Plus a shared reduce-motion helper, so the contract is one call rather than a
  convention people forget:

```dart
// packages/flutter_shared/lib/theme/motion.dart
bool reduceMotion(BuildContext c) =>
    MediaQuery.maybeOf(c)?.disableAnimations ?? false;

/// Collapses any duration to zero when the platform asks for reduced motion.
Duration motionOf(BuildContext c, Duration d) =>
    reduceMotion(c) ? Duration.zero : d;
```

  **Contract:** every animation either uses `motionOf(context, ...)`, or is an
  ambient loop that is not started when `reduceMotion(context)` is true. No
  exceptions. Every animation must have a still fallback that is a legitimate
  end state, not a blank.

- **Files to change** — `app_theme.dart` (tokens); new `theme/motion.dart`;
  export from `flutter_shared.dart`; then substitution at the 30 literal sites,
  and gates at the six ungated loops (`captain/splash_screen.dart:45`, `:232`;
  `home_tab.dart:375`; `available_trips_tab.dart:158`;
  `go_online_button.dart:57`; `rider/home_screen.dart:97`).
- **DB / API** — none.
- **Effort** — M. Tokens are S; the substitution sweep is the bulk.
- **Risk** — low and visual. Do it as one reviewable commit so the diff is
  legible.
- **Acceptance criteria**
  - No `Duration(milliseconds:` literal remains in an animation call site in
    `apps/**` or `packages/**` (timers, polls and timeouts are exempt).
  - With reduce-motion on, no looping animation runs in either app, and every
    screen still reaches a correct visual state.
  - The two same-job disagreements in F-13-17 resolve to identical tokens.
- **Tests** — a lint/grep CI step failing on new animation duration literals
  (proposed YAML in §6, P2.3). Widget tests with
  `MediaQueryData(disableAnimations: true)` asserting zero-duration behaviour on
  splash, nav, offer card and go-online button.

### P0.5 — Wake the rider app up: haptics

- **Goal** — the rider app confirms things happened.
- **Design** — add the rider haptics named in the §6.1 table: bid arrived
  (`selectionClick`, coalesced to at most one per 2 s so a burst is one tap),
  bid accepted (`mediumImpact`), captain assigned (`mediumImpact`), captain
  arrived (`heavyImpact` — the one the rider must not miss), trip complete
  (`mediumImpact`), rating submitted (`selectionClick`). Add offer-arrival
  (`heavyImpact`) on the captain side per F-13-07.
  Wrap in a shared helper so intensity choices stay consistent and can be
  centrally muted:

```dart
// packages/flutter_shared/lib/theme/motion.dart
enum GoHaptic { select, confirm, alert }
void goHaptic(GoHaptic h) => switch (h) {
  GoHaptic.select  => HapticFeedback.selectionClick(),
  GoHaptic.confirm => HapticFeedback.mediumImpact(),
  GoHaptic.alert   => HapticFeedback.heavyImpact(),
};
```

  Platform parity: `selectionClick` is a no-op on many Android builds — use
  `lightImpact` there for arrival ticks so Android riders are not left with
  nothing. Verify on a physical mid-range Android before sign-off
  (`needs-check`: I could not test hardware from here).
- **Files to change** — new helper in `flutter_shared`;
  `captain_bids_sheet.dart` (arrival, accept); `trip_screen.dart` (assigned,
  arrived, complete); `rating_sheet.dart`; `offer_card.dart` /
  `offer_card_entrance.dart` (captain arrival alert).
- **DB / API** — none.
- **Effort** — S.
- **Risk** — over-buzzing. The 2 s coalescing window and reserving
  `heavyImpact` for arrival-class events only are the guards.
- **Acceptance criteria** — every moment marked "yes" in the §6.1 haptic column
  fires exactly one haptic; a burst of five bids in one second produces one.
- **Tests** — widget tests asserting `HapticFeedback` platform channel calls.

### P1.1 — Choreograph the nine moments

- **Goal** — the product's emotional beats are marked.
- **Design** — implement §6.1 in full.
- **Files to change** — `captain_bids_sheet.dart`, `trip_screen.dart`,
  `fare_estimate_sheet.dart`, `offer_card.dart`, `active_trip_panel.dart`,
  `go_online_button.dart`, `status_chip.dart`, plus new shared transition
  widgets.
- **DB / API** — none.
- **Effort** — L.
- **Risk** — scope creep into visual redesign. Constrain to motion; T12 owns
  looks.
- **Acceptance criteria** — every row of §6.1 is implemented with its stated
  duration, curve and haptic, all drawn from tokens.
- **Tests** — golden tests at animation midpoint for the four highest-value
  moments; widget tests for haptics and durations.

### P1.2 — Fix the frame budget on the two screens that matter

- **Goal** — no dropped frames on the offer card or the live map.
- **Design**
  - `offer_card.dart:286` — hoist the static card body into the
    `AnimatedBuilder`'s `child` parameter so only the ring and the seconds
    rebuild; wrap the ring in a `RepaintBoundary`. If the blur still costs, drop
    `BackdropFilter` for a solid token colour while the countdown runs — a
    driver at speed will not miss a blur.
  - Add `RepaintBoundary` around `SkeletonList` rows
    (`skeleton_loader.dart:207`–`222`), the `_LivePulse` dot
    (`go_online_button.dart:80`–`186`), and `MainBottomNav`
    (`main_bottom_nav.dart:173`–`265`).
  - Narrow `main_shell.dart:400` from `context.watch<CaptainState>()` to
    `Selector`s so a GPS tick does not rebuild a five-tab `IndexedStack`.
  - Scope `trip_screen.dart`'s socket updates: hold `_captainLoc` in a
    `ValueNotifier` and rebuild only the marker layer, not the screen.
  - Pass the invariant inner dot as `AnimatedBuilder.child` at
    `home_screen.dart:847`–`882`.
- **Files to change** — as listed.
- **DB / API** — none.
- **Effort** — M.
- **Risk** — `Selector` refactors can drop rebuilds that were incidentally
  needed. Do `main_shell` last and separately.
- **Acceptance criteria** — with the performance overlay on, an active offer
  card holds 60 fps on a mid-range Android; a GPS tick during a trip does not
  rebuild the tab stack.
- **Tests** — manual profile-mode pass on a physical device, recorded in the PR;
  `debugProfileBuildsEnabled` spot check.

### P1.3 — Narrate the waits

- **Goal** — no unexplained indefinite spinner.
- **Design**
  - **Dispatch** (`trip_screen.dart:460`–`471`): replace the bare spinner with
    staged, honest copy driven by real elapsed time — 0–8 s "جارٍ إرسال طلبك
    للكباتن القريبين", 8–25 s "الكباتن بيشوفوا طلبك" plus a live bid count
    (already available at `captain_bids_sheet.dart:105`), 25 s+ "لسه بندور —
    ممكن تستنى أو تعدّل السعر" with an explicit action. Add a radar sweep on
    `durationAmbient`. Add a soft timeout at 90 s offering a re-price or cancel.
  - **Fare estimate** (`fare_estimate_sheet.dart:514`–`539`): show the journey
    card immediately — the route is already in hand from the home screen — and
    skeleton only the price. Never blank content the app already has.
  - **`LoadingOverlay`**: add a 120 ms fade-in, a 400 ms minimum display time to
    stop the flash, `go.scrim` instead of hardcoded black, and
    `AppTokens.font()` for the label.
- **Files to change** — `trip_screen.dart`, `fare_estimate_sheet.dart`,
  `loading_overlay.dart`; new shared `StagedWaitIndicator`.
- **DB** — none.
- **API contract** — none required. A future `GET /trips/{id}/dispatch-status`
  returning `{ notified: int, viewing: int, eta_hint_seconds: int }` would let
  the copy be true rather than time-based; that is **T06**'s call, flagged in §9.
- **Effort** — M.
- **Risk** — narration must not lie. Only state what the client can prove; the
  bid count is real, "5 captains are looking" is not until the API says so.
- **Acceptance criteria** — the dispatch screen changes state at least twice in
  30 s; the fare sheet never hides the journey card; `LoadingOverlay` never
  appears for under 400 ms.
- **Tests** — widget tests pumping the clock through each stage boundary.

### P1.4 — Make sheets behave like sheets

- **Goal** — native-feeling, interruptible, keyboard-correct sheets.
- **Design** — move the three modal sheets to `DraggableScrollableSheet` with a
  real handle and snap points; add `viewInsets` padding to
  `fare_estimate_sheet.dart` (F-13-10); give the bids panel an enter/exit
  transition (`durationNormal`, `curveDecelerate` in, `curveAccelerate` out)
  instead of appearing between frames.
- **Files to change** — `home_screen.dart:407`,`:460`; `trip_screen.dart:205`,
  `:296`–`307`; `fare_estimate_sheet.dart`; `location_search_sheet.dart`.
- **DB / API** — none.
- **Effort** — M.
- **Risk** — drag conflicts with inner scrollables; use the sheet's own
  controller as the list's `ScrollController`.
- **Acceptance criteria** — every sheet can be dragged and dismissed by fling,
  is interruptible mid-animation, and no sheet lets the keyboard cover its own
  input.
- **Tests** — widget drag tests; a keyboard-metrics test on the fare sheet.

### P2.1 — Signature moments

- **Goal** — two or three moments people remember.
- **Design** — trip complete: fare counts up over `durationSlow` with
  `curveEmphasised`, receipt card settles, one `mediumImpact`. Captain assigned:
  the card rises as the map camera eases to frame both points. Going online: the
  pill fills from the leading edge and the live dot begins to breathe. Keep each
  under 600 ms; a captain tapping through twelve trips a day must never wait on
  an animation.
- **Files to change** — `trip_screen.dart`, `go_online_button.dart`,
  `active_trip_panel.dart`.
- **Effort** — M. **Risk** — low. **DB / API** — none.
- **Acceptance criteria** — each is skippable, respects reduce-motion, and adds
  no blocking delay to any action.
- **Tests** — golden at midpoint; a test asserting the underlying action
  completes independently of the animation.

### P2.2 — Content-shaped skeletons everywhere

- **Goal** — no full-screen spinner on a list or detail screen.
- **Design** — extend `skeleton_loader.dart` with `SkeletonBidCard`,
  `SkeletonTripRow`, `SkeletonEarningsRow`, `SkeletonOfferCard`, each matching
  its real counterpart's height, radius and column structure. Replace the
  full-screen spinners at `trip_screen.dart:227`, `trip_detail_screen.dart:54`
  and the fare sheet.
- **Effort** — M. **Risk** — skeletons drifting from real layouts; build each
  from the same constants as the real widget. **DB / API** — none.
- **Acceptance criteria** — no `CircularProgressIndicator` remains as the sole
  content of a list or detail screen.
- **Tests** — golden tests pairing each skeleton against its real widget at the
  same width.

### P2.3 — Keep it from drifting back

- **Goal** — the token system stays true.
- **Design** — a CI grep step failing the build on new animation duration
  literals, plus a reduce-motion widget test suite. The workflow YAML is
  included below rather than committed, because this phase must not touch
  `.github/workflows/**`.

```yaml
# PROPOSED — do not commit in this phase.
# Suggested path: .github/workflows/motion-lint.yml
name: motion-lint
on: [pull_request]
jobs:
  no-magic-durations:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Fail on hardcoded animation durations
        run: |
          # Animation call sites only. Timers/polls/timeouts are exempt.
          if grep -rnE "(duration|curve):\s*(const\s+)?Duration\(milliseconds:" \
               apps packages --include=*.dart \
             | grep -vE "Timer|periodic|timeout|debounce"; then
            echo "::error::Use AppTokens.duration* / AppTokens.curve* instead."
            exit 1
          fi
      - name: Fail on ungated infinite animations
        run: |
          if grep -rnE "\.repeat\(|onPlay:\s*\(c\)\s*=>\s*c\.repeat" \
               apps packages --include=*.dart \
             | grep -v "reduceMotion"; then
            echo "::error::Looping animations must be gated on reduceMotion()."
            exit 1
          fi
```

- **Effort** — S. **Risk** — false positives on legitimate timers; the
  exclusions above cover the current tree. **DB / API** — none.
- **Acceptance criteria** — a PR adding `Duration(milliseconds: 250)` to an
  animation fails CI.
- **Tests** — the workflow is its own test; verify against a deliberate
  violation PR.

---

### 6.1 Motion specification

This is the implementable artefact the brief asks for. A Flutter developer
should be able to build from this table without further design input. All
durations and curves are the tokens defined in P0.4.

| # | Moment | Trigger | Animation | Duration | Curve | Haptic |
|---|---|---|---|---|---|---|
| 1 | **Request sent** | Rider taps "اطلب رحلة" (`fare_estimate_sheet.dart:371`) | Button label → inline spinner; sheet slides down; map recentres to pickup; radar begins | `durationNormal` (sheet `durationSheet`) | `curveAccelerate` out | `confirm` |
| 2 | **Searching** | Trip enters `searching` | Radar sweep from the pickup pin, looping; staged copy changes at 8 s and 25 s (P1.3) | `durationAmbient` loop | `curveLinear` | none |
| 3 | **First bid arrives** | First item into `_bids` (`captain_bids_sheet.dart:105`) | Panel enters (fade + 8 px rise); row inserts via `AnimatedList` size+fade; count badge ticks | Panel `durationNormal`; row `durationNormal` | `curveDecelerate` | `select` — the *first* bid only |
| 4 | **Subsequent bids** | Later items | Row inserts, appended below; **no reorder**; list frozen while touched (P0.1) | `durationNormal` | `curveDecelerate` | `select`, coalesced ≤1 per 2 s |
| 5 | **Bid accepted** | Rider taps accept | Chosen row lifts and scales to 1.02, siblings dim to 40% and collapse, panel exits | 400 ms hold, exit `durationNormal` | `curveEmphasised` in, `curveAccelerate` out | `confirm` |
| 6 | **Captain assigned** | `trip.updated` → assigned (`trip_screen.dart:144`) | Captain card rises from the bottom; avatar scales 0.9→1.0; map eases to frame captain + pickup | `durationSlow` | `curveEmphasised` | `confirm` |
| 7 | **Captain moving** | `location.captain` (`trip_screen.dart:145`) | Position tween + shortest-arc bearing tween (P0.2) | matched to interval, clamp 1200–4000 ms; bearing `durationSlow` | `curveLinear` pos / `curveDecelerate` bearing | none |
| 8 | **Captain arriving** | Status → `arrived` | Card pulses once; ETA row crossfades to "الكابتن وصل"; marker pulses twice | `durationNormal`, ×2 | `curveDecelerate` | `alert` |
| 9 | **Trip start** | Status → `in_progress` | Pickup pin fades out; route redraws to dropoff; panel crossfades to in-trip | `durationSlow` | `curveStandard` | `confirm` |
| 10 | **Trip complete** | Status → `completed` | Map dims; receipt rises; fare counts up from 0 | `durationSlow` | `curveEmphasised` | `confirm` |
| 11 | **Payment success** | Payment confirmed (future — cash-only today) | Amount → check mark morph; single green sweep | `durationSlow` | `curveEmphasised` | `confirm` |
| 12 | **Offer arrives (captain)** | New offer (`available_trips_tab.dart:113`) | Existing staggered entrance, retimed to `staggerStep`; countdown ring starts | `durationNormal`, stagger `staggerStep` × min(i, `staggerMax`) | `curveDecelerate` | **`alert`** — the F-13-07 fix |
| 13 | **Offer expiring** | ≤5 s left (`offer_card.dart:112`) | Existing colour flip to `danger`; ring continues | ring 15 s linear | `curveLinear` | `select` per second (exists) |
| 14 | **Offer accepted (captain)** | Tap accept (`offer_card.dart:141`) | Card scales to 1.02 then exits upward; others collapse | `durationNormal` | `curveStandard` | `confirm` (exists) |
| 15 | **Going online** | Toggle (`go_online_button.dart`) | Pill fills from leading edge; live dot begins breathing | fill `durationNormal`; dot `durationAmbient` | `curveDecelerate` / `curveLinear` | `confirm` (exists) |
| 16 | **Status change** | `StatusChip` variant changes (`status_chip.dart`) | Crossfade label + colour instead of hard swap | `durationFast` | `curveStandard` | none |
| 17 | **Tab change** | Nav tap (`main_bottom_nav.dart`) | Tick slides (not width-pops); icon crossfades; colour tweens | `durationFast` | `curveStandard` | `select` |
| 18 | **Press feedback** | Any primary control | Scale to 0.96 — one constant everywhere (F-13-17) | `durationInstant` | `curveStandard` | none |
| 19 | **Sheet open / close** | Any bottom sheet | Draggable, interruptible, gesture-driven (P1.4) | `durationSheet` | `curveDecelerate` / `curveAccelerate` | none |
| 20 | **Skeleton sweep** | Any loading list | Existing shared-phase sweep — retime to `durationAmbient` | `durationAmbient` | `curveLinear` | none |

**Reduce-motion fallbacks.** Rows 1–20 all collapse to `Duration.zero` via
`motionOf`, except rows 2, 7 and 20: the radar and skeleton sweep stop entirely
and render their still state, and marker movement becomes a direct position set
(which is today's behaviour — the current implementation is, precisely, the
reduce-motion fallback for row 7).

---

## 7. Phasing

### P0 — before any production traffic

| Item | Phase | Effort | Owner type |
|---|---|---|---|
| P0.1 — Bid list safety: freeze on touch, stable keys, animated insertion, commit confirmation | P0 | M | Flutter |
| P0.2 — Marker interpolation + bearing (shared widget, 3 adoption sites) | P0 | M | Flutter |
| P0.3 — Delete dead `splash.mp4` ×3 and both `assets/videos/` declarations | P0 | S | Flutter |
| P0.4 — Motion tokens + `motionOf` / reduce-motion contract + substitution sweep | P0 | M | Flutter |
| P0.5 — Rider haptics (6 events) + captain offer-arrival alert | P0 | S | Flutter |

P0.1 is here because it can cost a rider money. P0.3 is here because it is
free. P0.4 is here because every later item depends on the tokens existing —
doing it after P1 means touching all the same files twice. P0.2 and P0.5 are
here because they are the difference between a demo and a product, and both are
days rather than weeks.

**P0 total: roughly 6–9 developer-days, one Flutter engineer.**

### P1 — first 30 days

| Item | Phase | Effort | Owner type |
|---|---|---|---|
| P1.1 — Choreograph the 20 moments in §6.1 | P1 | L | Flutter |
| P1.2 — Frame budget: `AnimatedBuilder.child` hoisting, `RepaintBoundary`s, `Selector` narrowing | P1 | M | Flutter |
| P1.3 — Narrate the waits: staged dispatch, skeleton fare, `LoadingOverlay` repair | P1 | M | Flutter |
| P1.4 — Draggable interruptible sheets + fare-sheet keyboard fix | P1 | M | Flutter |

### P2 — next 90 days

| Item | Phase | Effort | Owner type |
|---|---|---|---|
| P2.1 — Signature moments (complete, assigned, going online) | P2 | M | Flutter |
| P2.2 — Content-shaped skeleton library | P2 | M | Flutter |
| P2.3 — CI motion lint + reduce-motion test suite | P2 | S | ops |

---

## 8. Metrics

Motion is measurable. Instrument these before P0 lands so the change is provable
rather than asserted.

| Metric | How | Current | Target |
|---|---|---|---|
| **Wrong-bid acceptance rate** | Client event on accept carrying `(bid_id, time_since_last_list_mutation_ms)`. Any accept within 500 ms of a list mutation is a suspected mis-tap | unknown — untracked, and the mechanism exists (F-13-01) | < 0.1% of accepts, and zero within 300 ms of a mutation |
| **Bid-accept cancellation within 30 s** | Existing cancellation data, filtered to cancels within 30 s of accept | unknown | halve after P0.1 — a mis-tap usually shows up as an immediate cancel |
| **App download size** | `flutter build apk --analyze-size`, both apps | includes ~855 KB dead video each | −855 KB each after P0.3 |
| **Cold start to first frame** | `flutter run --trace-startup`, mid-range Android | unmeasured | establish a baseline, then hold p90 < 2.0 s |
| **Marker frame continuity** | Frames in which the marker's rendered position changed, during an active trip | ~1 frame per GPS fix (teleport) | > 55 of 60 frames/s |
| **Jank on the offer card** | `flutter run --profile` frame timings across a full 15 s countdown | unmeasured; per-frame `BackdropFilter` rebuild (F-13-09) | zero frames > 16 ms on a mid-range device |
| **Offer acceptance rate, and time-to-first-interaction** | Captain-side analytics on offer shown → first touch | unknown | measurable rise after the P0.5 arrival haptic; time-to-touch down |
| **Offer expiry rate** | Offers reaching 0 s with no interaction | unknown — likely material given no arrival signal | reduce by a third after P0.5 |
| **Dispatch-screen abandonment** | Rider cancels while `searching`, bucketed by elapsed time | unknown | reduce after P1.3; the 25 s+ bucket is the one to watch |
| **Reduce-motion sessions** | Sessions with `disableAnimations == true` | unknown — never queried | report it; it sizes the F-13-08 audience |
| **Animation duration literals** | The CI grep in P2.3 | 30 distinct values | 0 outside `AppTokens` |

The first two are the important ones. Everything else is craft; those two are
whether a rider paid a price they chose.

---

## 9. Cross-cutting notes

Findings outside this axis, addressed to their owners. Not fixed here.

**→ T27 (Cross-App Parity)** — this track's own cross-app observations, which
are systematic rather than incidental:

- **Duplicated splash, divergent quality.** `apps/rider/lib/screens/splash_screen.dart`
  (16,963 b) and `apps/captain/lib/screens/splash_screen.dart` (15,559 b) render
  the same brand moment from two separate implementations. The rider's handles
  reduce-motion throughout; the captain's has no such check anywhere
  (`captain/splash_screen.dart:45`, `:232`). One shared `BrandSplash` in
  `flutter_shared` would delete ~15 KB of duplication and close the
  accessibility gap in one move.
- **Duplicated trip chat, badly diverged.**
  `apps/rider/lib/screens/trip/trip_chat_screen.dart` is 5,016 bytes;
  `apps/captain/lib/screens/home/trip_chat_screen.dart` is 16,240 bytes. Two
  implementations of the two ends of one conversation, differing by 3× in size.
  (Noting explicitly: both files exist — an earlier analysis pass of mine
  wrongly flagged the rider import at `trip_screen.dart:10` as dangling. It is
  valid. The problem is divergence, not absence.)
- **Two entrance-animation implementations for the same card.**
  `offer_card_entrance.dart` (460 ms, `easeOut`/`easeOutCubic`, 70 ms stagger) is
  used only at `available_trips_tab.dart:113`, while
  `nearby_requests_screen.dart:287`–`292` applies its own inline
  `.fadeIn().slideY()` with a 50 ms stagger and flutter_animate's 300 ms default.
  Same card, two motions.
- **`AvailableTripsTab` appears to be dead.** It is the only consumer of
  `OfferCardEntrance`, but `main_shell.dart:443` mounts `NearbyRequestsScreen`
  at that slot. If confirmed dead, deleting it also deletes the only use of the
  better entrance animation — adopt the animation first, then delete
  (`likely`, not confirmed: I did not exhaustively trace every route).
- **Motion vocabulary is diverging with the code.** The captain app has haptics
  and the rider app has none; the rider app has reduce-motion and the captain
  app has none. Each app got the polish pass the other missed. The shared
  package is the fix, and P0.4/P0.5 put the primitives there.

**→ T15 (Accessibility)** — reduce-motion is entirely absent from the captain
app (F-13-08), including in shared code that leaks into both
(`go_online_button.dart:57`). The `motionOf` contract in P0.4 is the mechanism;
T15 should own verifying coverage and deciding whether `accessibleNavigation`
should also suppress non-essential motion. Note that `disableAnimations` is
currently read in exactly three places repo-wide.

**→ T12 (Design System)** — motion tokens are specified in P0.4 to sit inside
`AppTokens` beside the radius scale (`app_theme.dart:161`) and spacing scale
(`:171`), reachable via the existing `GoTheme.of(context)` extension
(`:373`). T12 owns whether that is the right home and how it is documented.
Also for T12: `LoadingOverlay` bypasses the token system entirely — hardcoded
`Colors.black.withOpacity(0.4)` at `loading_overlay.dart:13` where `go.scrim`
exists at `app_theme.dart:392`, hardcoded white at `:23` and `:30`, and a bare
`TextStyle` that skips `AppTokens.font()` so the label is not Cairo.

**→ T07 (Realtime)** — two things. First, the `location.captain` websocket
payload (consumed at `trip_screen.dart:145`–`150`) should carry a `heading`
field; P0.2 derives bearing client-side from consecutive fixes, which works but
is strictly worse than the device's own compass reading. Second, the marker
interpolation in P0.2 assumes a roughly regular update cadence — if `TripRoom`
emits irregularly, the tween clamp will visibly lag. The 10 s poll fallback at
`trip_screen.dart:172` is documented as existing because `TripRoom` has failed
closed before (`:163`–`:169`); motion quality on that screen is downstream of
that reliability.

**→ T06 (Dispatch)** — P1.3 wants to narrate the dispatch wait honestly. Today
the client can only tell the rider the elapsed time and the bid count. A
lightweight `GET /trips/{id}/dispatch-status` returning
`{ notified, viewing, eta_hint_seconds }` would let the copy be true. T06 owns
whether that is cheap.

**→ T03 (Money Integrity) and T05 (Bidding Economics)** — F-13-01 means the
client can commit to a bid the rider did not choose, regardless of server-side
correctness. Two questions for those tracks: is `accept-bid` idempotent per
trip, and is there any server-side window in which an accept for a
just-superseded bid is rejected rather than honoured? A server-side guard would
be defence in depth behind the client fix; it does not replace it, because the
accepted bid is valid — just not the one the human picked.

**→ T09 (Rider Journey)** — the fare estimate sheet does not offset for the
keyboard (F-13-10) even though it hosts the price input at
`fare_estimate_sheet.dart:699`–`735`. That is a journey defect as much as a
motion one.

**→ T26 (Mobile Release)** — P0.3 removes ~855 KB from each app binary. Worth
folding into whatever size budget T26 sets.

**→ T24 (Performance)** — `main_shell.dart:400` calls
`context.watch<CaptainState>()` at the root of `build`, so every GPS tick
rebuilds a five-tab `IndexedStack` plus the map and all chrome. P1.2 narrows it
for frame-rate reasons; the battery and CPU implications on a device that runs
this app for eight-hour shifts are T24's.

---

## 10. Open questions

Decisions for the product owner. Each with options and my recommendation.

**Q1 — Should accepting an expensive bid require confirmation?**
P0.1 proposes that a bid ≥15% above the cheapest available needs a second
deliberate action.
*Options:* (a) no confirmation, rely on the freeze-on-touch mechanism alone;
(b) confirm only on the ≥15% outlier; (c) confirm on every accept.
*Recommendation:* **(b).** (a) leaves a real money path protected only by
timing. (c) taxes the common case and slows the product's core loop, which in a
bidding marketplace is the thing that must stay fast. The threshold should be
configurable server-side so it can be tuned without a release.

**Q2 — How honest should the dispatch wait be?**
Staged copy driven by elapsed time is implementable today. Copy driven by real
dispatch state needs an endpoint from T06.
*Options:* (a) time-based staging now; (b) wait for the endpoint and do it once;
(c) time-based now, swap the data source later.
*Recommendation:* **(c).** The UI work is identical; only the data source
changes. Ship the perceived-performance win now, make it true later. Never show
a count the client cannot prove — a fabricated "7 captains notified" is worse
than a spinner.

**Q3 — Keep `BackdropFilter` on the offer card?**
The blur is re-evaluated every frame for 15 seconds (F-13-09). Hoisting the
static subtree fixes most of it; dropping the blur entirely fixes all of it.
*Options:* (a) hoist and keep the blur; (b) drop the blur for a solid token
surface; (c) keep on high-end, drop on low-end by device tier.
*Recommendation:* **(a) first, measure, then (b) if it still janks.** A driver
glancing at a card for a few seconds while moving gains nothing from a blur, and
(c) buys a device-tier system this codebase does not have and should not grow
for one card.

**Q4 — Who owns the shared motion library, T13 or T28?**
This document specifies; T28 is scoped as the build.
*Options:* (a) T28 builds everything in §6; (b) T13's P0 ships with the token
set and the safety fixes, T28 takes P1.1 onward; (c) merge the tracks.
*Recommendation:* **(b).** P0.1 through P0.5 are safety, money and
free-win items that should not queue behind a library project. Tokens (P0.4) are
the natural handoff artefact: once they exist, T28 has a foundation to build the
signature moments on.

**Q5 — Adopt Material 3's motion scale or keep the bespoke one in P0.4?**
*Options:* (a) adopt M3 `short1`–`extraLong4` verbatim; (b) the six bespoke
tokens in P0.4; (c) bespoke names aliased onto M3 values.
*Recommendation:* **(b).** M3's scale is thirteen values, which reintroduces the
choice paralysis that produced 30 literals. Six named-by-intent tokens
(`durationFast` reads as a decision; `short3` does not) are easier to review and
harder to misuse. The rule table in P0.4 is what makes them enforceable.

**Q6 — Is `AvailableTripsTab` dead, and if so what happens to `OfferCardEntrance`?**
`main_shell.dart:443` mounts `NearbyRequestsScreen`, and `AvailableTripsTab` is
the only consumer of the better entrance animation.
*Options:* (a) delete both; (b) delete the tab, promote `OfferCardEntrance` to
the live screen; (c) leave it.
*Recommendation:* **(b).** `OfferCardEntrance` is the better implementation —
tokenised stagger, RTL-aware direction (`offer_card_entrance.dart:54`), a
sensible cap. It should replace the inline animation at
`nearby_requests_screen.dart:287`–`292` before the dead tab is removed.
Confirm the tab is genuinely unreachable first; I marked that `likely`, not
`confirmed`.

**Q7 — Should the rider app get a distinct haptic vocabulary, or mirror the captain's?**
*Options:* (a) mirror the captain's intensities exactly; (b) a softer rider
vocabulary, since a rider holds the phone and a captain has it mounted.
*Recommendation:* **(a), via the shared `goHaptic` helper in P0.5.** Two
vocabularies is how the apps drifted apart in the first place. The one
justified exception is captain offer arrival, which needs `alert` precisely
because the device is mounted and out of hand — and that is a per-moment choice
inside a shared vocabulary, not a second vocabulary.
