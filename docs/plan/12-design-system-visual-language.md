# 12 — Design System & Visual Language

> Track: B — Product surface & experience · Reviewer: chat-20260801-1344-33ce · Date: 2026-08-01
> Base commit reviewed: `84c1ce927fe82dc75dd3b4ba4cf2216b792dc304`

## 1. Scope

This document covers the design system as an artefact and, more importantly, as a
practice: what tokens exist across the three front-ends, whether they agree, whether
screens actually consume them, what the shared component library provides versus what
a ride-hailing product needs, and what Synaptic Go looks like as a brand.

Specifically in scope: token inventory and the Flutter↔admin diff; adoption metrics for
colour, spacing and type; dark-mode correctness; the shared widget library and
cross-app duplication of presentational code; Arabic typography, numerals and RTL
mirroring; iconography; brand identity, wordmark and splash; map styling as a design
surface; elevation and glass; visual hierarchy on the three highest-traffic screens.

Explicitly **not** in scope, with the track that owns it:

| Not covered here | Owner |
|---|---|
| Screen-by-screen rider flow correctness and state handling | T09 |
| Screen-by-screen captain flow correctness and shift durability | T10 |
| Admin console functionality, data tables, missing pages | T11 |
| Localisation completeness, string coverage, translation quality | T14 (l10n track) |
| Accessibility conformance as a programme (contrast audit, screen readers, tap targets) | T16 |
| The systematic rider/captain duplication problem as an architectural programme | T27 |
| Map provider cost, tile billing, quota | T22 (cost track) |

Where this document names a duplication or a cross-app mismatch, it does so because
the *visual* consequence is mine to report. The remediation programme belongs to T27
and I have addressed those notes to it in section 9.

One deliberate correction to the brief before anything else. The brief states the map
is "currently default OSM tiles" and asks whether typography is IBM Plex Sans Arabic.
Neither premise holds on current `main`: the map is CARTO Positron / Dark Matter
(`app_theme.dart:238-242`), and the Flutter design system is Cairo
(`app_theme.dart:265`). Both questions are still worth answering, but the answers are
different from the ones the brief anticipated, and section 3 sets out what is actually
there.

## 2. What I actually read

I pulled the entire repository at the pinned commit as a tarball rather than fetching
file by file, because a quantitative adoption audit needs the whole tree — every count
in this document is computed over all 84 Dart files and 37 admin TypeScript files, not
a sample.

**Design system core — read in full, personally:**

| File | Lines | Note |
|---|---|---|
| `packages/flutter_shared/lib/theme/app_theme.dart` | 1055 | The system. Tokens, `GoTheme` extension, both `ThemeData` builders, `MapTiles`. |
| `apps/admin/src/design/tokens.ts` | 248 | The admin's *nominal* token file. See F-12-05. |
| `apps/admin/src/design/globals.css` | 212 | The admin's *actual* token file. |
| `apps/admin/src/design/ThemeContext.tsx` | 103 | Admin dark-mode mechanism. |
| `apps/admin/src/styles.css` | 174 | Light/dark CSS custom property blocks. |
| `apps/admin/tailwind.config.js` | — | The layer that actually resolves colour for components. |

**All 15 shared widgets** in `packages/flutter_shared/lib/widgets/` were read:
`counter_offer_sheet.dart` (335), `empty_state.dart` (87), `error_state.dart` (76),
`go_date_field.dart` (341), `go_online_button.dart` (234), `godrive_wordmark.dart` (67),
`loading_overlay.dart` (37), `main_bottom_nav.dart` (680), `map_controls.dart` (232),
`navigation_button.dart` (64), `offline_gate.dart` (232), `offline_guard_banner.dart` (126),
`skeleton_loader.dart` (228), `status_chip.dart` (62), `vehicle_map_marker.dart` (194).

**All 9 admin UI components** in `apps/admin/src/components/ui/`: `Badge.tsx` (77),
`Button.tsx` (55), `Card.tsx` (37), `DataTable.tsx` (348), `ErrorBoundary.tsx` (111),
`Input.tsx` (282), `Pagination.tsx` (124), `QuickSearchModal.tsx` (167), `Toast.tsx` (161).

**Screens read for hierarchy, dark mode and duplication:** rider `home_screen.dart`,
`vehicle_selector.dart`, `fare_estimate_sheet.dart`, `travel_mode_bottom_bar.dart`,
`trip_screen.dart`, `trip_chat_screen.dart`, `profile_screen.dart`, `wallet_screen.dart`,
`login_screen.dart`, `splash_screen.dart`, `safety/sos_screen.dart`, `help_screen.dart`,
`invite_screen.dart`, `saved_places_screen.dart`; captain `offer_card.dart`,
`active_trip_panel.dart`, `main_shell.dart`, `trip_chat_screen.dart`,
`earnings/wallet_screen.dart`, `earnings_screen.dart`, `profile/settings_screen.dart`,
`documents/documents_onboarding_screen.dart`, `onboarding/onboarding_screen.dart`,
`safety/sos_screen.dart`, `splash_screen.dart`, `login_screen.dart`.

**Also read:** both `main.dart` files, both `pubspec.yaml` files plus
`flutter_shared/pubspec.yaml`, both `AndroidManifest.xml` files, both
`services/trip_ws.dart`, `services/fcm_service.dart`, `app_state.dart` and
`captain_state.dart` (theme-mode persistence only), `apps/admin/index.html`,
`docs/ROADMAP.md` (typography claim only), and the repo root inventory.

**Skimmed rather than read:** `l10n/app_strings.dart` (5664 lines) — I searched it for
brand-name literals and numeral formatting rather than reading it; string coverage
belongs to T14. `DataTable.tsx` I read for token consumption, not for table logic.

Every count in section 3 and every `path:line` in section 4 was produced by reading or
grepping the file at the pinned commit. Where I could not verify something I have
marked it `needs-check` and said why.

## 3. How it works today

### 3.1 The Flutter system

`app_theme.dart` is a genuinely well-built design system, and it is important to say so
before the findings, because the failures in this document are failures of *adoption
and coherence*, not of craft. The file defines:

**Colour.** A brand ramp (`primary` `#4E842D`, `primaryLight` `#69A83D`, `primaryDark`
`#38631E`, `primaryDeep` `#22400F`, `primarySoft` `#EAF5E3`, `headerAccent` `#DDF2D1`),
a semantic set with contrast ratios documented in comments (`success` `#178841` at
4.53:1, `warning` `#947105` at 4.54:1, `danger` `#D92D20` at 4.53:1, `accent` `#A56A07`
at 4.50:1, `info` `#1D6DBE`, `star` `#F5B301`, `sos` `#DC2626`), eight badge pairs plus
eight night variants (`app_theme.dart:74-96`), a light neutral ramp, and **two** dark
ramps — a blue-tinted `dark*` set (`#0B1220`…`#334155`, lines 113-119) and a neutral
near-black `night*` set (`#0E0E10`…`#34343B`, lines 127-133). Plus `lime` `#C1F11D` as
the dark-mode action colour, splash tokens, and map/route tokens.

The fact that contrast ratios are written into the source as comments is a real signal
of intent. Someone checked.

**Radii** (`app_theme.dart:161-166`): 6 / 10 / 14 / 18 / 26 / 999.
**Spacing** (`171-177`): a clean 4dp grid — 4 / 8 / 12 / 16 / 24 / 32 / 48, plus
`tapTarget` 48 and `primaryActionHeight` 56.
**Elevation** (`187-230`): four named `BoxShadow` presets — `shadowCard` (0.06α, blur 10),
`shadowFloating` (0.14α, blur 16), `shadowSheet` (0.13α, blur 24, upward), `shadowOffer`
(0.18α, blur 28) — plus a `glow(color, opacity)` helper.
**Motion**: none. Zero `Duration` or `Curve` constants in the file.
**Type**: `AppTokens.font()` wraps `GoogleFonts.cairo` (line 265) and `AppTokens.money()`
provides oversized numerals at w900, height 1.1, tracking -0.5 (line 283). A full
Material `TextTheme` with all 15 roles is built at lines 1029-1052.

**`GoTheme`** (line 303 onward) is a `ThemeExtension` exposing brightness-aware semantic
colours — `bg`, `panel`, `surface`, `elevated`, `text`, `muted`, `border`, `action`,
`onAction`, `actionPressed`, `routeLine`, `routeCasing`, `pinPickup`, `pinDropoff`,
`scrim`, and an `isDark` flag. Screens call `GoTheme.of(context)` instead of branching on
brightness. In light mode `action` is `primary`; in dark mode it becomes `lime` with
`onAction` = `onLime` `#101010` (lines 385, 404).

This design is correct, and it worked: across 60 screen files in the two apps, exactly
**one** still derives brightness by hand (`rider/splash_screen.dart:130`, and it
immediately feeds `GoTheme.forBrightness`). The pattern `GoTheme` was built to eliminate
is effectively gone.

**Dark mode is real and reachable.** Both apps pass `theme:`/`darkTheme:`/`themeMode:`
into `MaterialApp` (`rider/main.dart:89`, `captain/main.dart:81`); `themeMode` is
persisted to `SharedPreferences` (`app_state.dart:547-558`,
`captain_state.dart:209-216`); the rider exposes a three-way System/Light/Dark dropdown
(`rider/settings_screen.dart:63-75`) and the captain a two-way switch
(`captain/settings_screen.dart:467-473`). This is not a theoretical dark mode.

### 3.2 The admin system

The admin has **three** layers that all claim to define tokens, and they disagree.

1. `design/tokens.ts` — 248 lines of structured TypeScript: an 11-stop brand ramp, a
   charcoal ramp, semantic colours, spacing, radii, 7 shadow levels, 3 transition
   durations, z-index layers, breakpoints, layout constants.
2. `design/globals.css` — CSS custom properties.
3. `tailwind.config.js` — what components actually resolve against.

`tokens.ts` sets `brand.primary.500` to `#4e842d`, matching Flutter exactly
(`tokens.ts:32`, with the comment "WCAG AA compliant GoDrive green (4.53:1 on white)").
`globals.css:26` sets `--color-brand-primary-500` to `#6bb522`. Tailwind resolves
`primary.500` to `#6bb522`. Components consume Tailwind. **`#6bb522` is what ships.**

And `tokens.ts` is imported by **nothing** — zero import statements referencing
`design/tokens` anywhere in `apps/admin/src`. It is inert.

Admin dark mode is a React context persisting `light|dark|system` to `localStorage`
under `synaptic-admin-theme`, toggling a `.dark` class on `<html>`
(`ThemeContext.tsx:20, 41-44`), which activates the `.dark` block in `styles.css:48`.
Conceptually the same shape as `GoTheme` — one switch, whole palette — but entirely
siloed. There is no shared token source, no codegen, no schema bridging Dart and CSS. A
token change must be made twice, by hand, in two languages. The drift that theory
predicts has already happened.

### 3.3 Adoption — what the numbers actually say

The brief asks how many hardcoded colours, magic spacing numbers and inline text styles
remain after PRs #12, #15, #18, #35 and #36. The honest answer is more interesting than
"a lot".

| Measure | rider | captain | shared | admin |
|---|---|---|---|---|
| `Color(0x…)` hex literals | 31 | **0** | 77 (the token definitions) | 0 |
| — distinct values | 10 | 0 | — | — |
| `Colors.white` | \| combined 134 | | | |
| `Colors.black` | \| combined 32 | | | |
| `Colors.transparent` | \| combined 50 | | | |
| Files using `GoTheme.of` | \| combined 39 of 60 | | | |
| Raw `fontSize:` call sites | 199 | ~193 | — | — |
| — distinct size values | 23 | 25 | — | — |
| Hardcoded hex in admin `ui/` | — | — | — | 8 (all `Badge.tsx:13-16`) |

**The colour migration essentially succeeded.** All 31 hex literals in the rider app are
10 distinct values living in one place: `trip_screen.dart:592-601`, an Arabic→`Color`
lookup mapping vehicle colour names (`'أسود'`, `'فضي'`, `'أحمر'`…) to swatches. That is
domain data describing a physical car, not a theme violation. It should arguably move to
a named map, but painting a red car red is not a token failure. The captain app has zero
hex literals. Any report that counts these as "219 violations remaining" is measuring
the wrong thing.

**The real residue is `Colors.white`/`Colors.black`, and most of it is legitimate.** Of
the 25 files that use both `GoTheme` and literal white/black, the overwhelming majority
are: white text on the brand-green gradient header, white icons on semantic-coloured
chips, black shadows at low opacity, and `Colors.transparent`. Those are correct in both
brightnesses. Section 4 lists the genuine breaks — there are seven, and they cluster in
predictable places: screens that were built before `GoTheme` landed and screens that use
a non-adaptive gradient constant.

**The type scale is the real adoption failure.** A complete 15-role `TextTheme` exists
at `app_theme.dart:1029-1052` and screens do not use it. Instead they call
`AppTokens.font(fontSize: <raw int>)` — 199 times in the rider app across 23 distinct
sizes (13 appears 37 times, 14 appears 33, 16 appears 23, 12 appears 21, and then a long
tail through 14.5, 12.5, 11.5, 17, 19, 21, 25, 42, 48). A 23-value type scale is not a
scale. This is the axis where the design system exists on paper and not in the product.

**Spacing is in good shape.** The 4dp grid in `AppTokens` matches the admin's scale step
for step, and screens broadly use it.

## 4. Findings

| ID | Sev | Finding | Evidence (`path:line`) | Impact | Confidence |
|---|---|---|---|---|---|
| F-12-01 | S1 | The product ships under two different names. Every user-visible surface says "GoDrive"; every push notification says "Synaptic Go". | `packages/flutter_shared/lib/services/fcm_service.dart:17,80` vs `apps/rider/lib/main.dart:55`, `apps/rider/android/app/src/main/AndroidManifest.xml:11` | A rider who installed "GoDrive" receives a notification from "Synaptic Go" and does not recognise it. Directly suppresses notification open-rate — the channel that drives trip acceptance. | confirmed |
| F-12-02 | S1 | The dark-mode primary action colour is `lime #C1F11D` — the signature colour of inDrive, the direct competitor whose pricing model this product copies. | `app_theme.dart:137`, bound as `action` at `:404` | Every primary CTA in dark mode renders in a competitor's brand colour. Undermines differentiation in the one market where both apps compete, and is a trademark/trade-dress question, not just an aesthetic one. | confirmed (code) / assumed (inDrive's exact brand hex not independently verified) |
| F-12-03 | S1 | The rider SOS screen hardcodes light-mode tokens and renders a white panel in dark mode. | `apps/rider/lib/screens/safety/sos_screen.dart:31,116` (`AppTokens.lightPanel`); contrast with `apps/captain/lib/screens/safety/sos_screen.dart:118` (`AppTokens.sosBackdrop`) | A rider in danger at night gets a full-brightness white screen. Destroys night vision, announces the screen to anyone nearby, and it is the one screen that must not fail. The correct token (`sosBackdrop #1A0000`) already exists and is used by the captain app. | confirmed |
| F-12-04 | S1 | Admin and mobile ship different brand greens. Mobile is `#4E842D`; the admin console renders `#6BB522`. | `app_theme.dart:36` vs `apps/admin/src/design/globals.css:26,167`, `apps/admin/tailwind.config.js:50`, `apps/admin/src/components/common/GoDriveLogo.tsx:44` | The logo in the admin console is a visibly different green from the logo in the apps. Screenshots, investor decks and support material built from the console are off-brand. | confirmed |
| F-12-05 | S2 | `apps/admin/src/design/tokens.ts` is 248 lines of authoritative-looking dead code. It is imported by nothing. | `apps/admin/src/design/tokens.ts` (whole file); zero matches for `from '…design/tokens'` across `apps/admin/src` | Its `brand.primary.500` is *correct* (`#4e842d`, `:32`) while the live value is wrong. Any engineer who opens the token file to check a value gets the right answer and the wrong product. This is how F-12-04 survives review. | confirmed |
| F-12-06 | S2 | The admin collapses four distinct semantic roles onto one hex: brand primary, success, info and focus-ring are all `#6bb522`. | `globals.css:26` (primary), `:45` (success), `:60` (info), `:79` (border-focus) | An operations console cannot signal state by colour: "informational" and "succeeded" are indistinguishable, and both match the brand chrome. Partially rescued by `Badge.tsx` hardcoding its own distinct palette — which is itself F-12-16. | confirmed |
| F-12-07 | S2 | No typeface is bundled. Both apps fetch Cairo over the network at runtime via `google_fonts`. | `apps/rider/pubspec.yaml:50`, `apps/captain/pubspec.yaml:45`, `packages/flutter_shared/pubspec.yaml:20`; zero `.ttf`/`.otf` files in the repository | First launch on a weak Egyptian mobile connection renders the entire product in the platform fallback sans — which for Arabic is a different skeleton, different weight, different metrics. Every layout tuned to Cairo reflows. The first impression of the product is a font it was not designed in. | confirmed |
| F-12-08 | S2 | The design system has no shared Button, no shared Card, no shared TextField and no shared Toast. | `packages/flutter_shared/lib/widgets/` — 15 widgets, all domain-specific; `go_online_button.dart:12` is an online/offline toggle, not a button primitive | Every screen hand-rolls `ElevatedButton`/`OutlinedButton` with inline styling; every error is a raw `ScaffoldMessenger.showSnackBar`. These are the four highest-frequency primitives in any app. Their absence is why the type scale is bypassed 199 times — there is nothing to bypass it *through*. | confirmed |
| F-12-09 | S2 | The typeface is split three ways across one product. | Cairo system-wide (`app_theme.dart:265`); IBM Plex Sans Arabic at 19 rider call sites (`home_screen.dart:782,1072,1210,1254,1276,1290,1300,1360,1437,1473`; `saved_places_screen.dart:197,198,258,293,470,564,569,582,618`); IBM Plex in admin (`tokens.ts:116`, `apps/admin/index.html:9`) | The rider's home screen — the most-viewed screen in the product — is set in a different typeface from the rest of the rider app. `docs/ROADMAP.md:21` specifies IBM Plex; the system chose Cairo; nobody reconciled them. | confirmed |
| F-12-10 | S2 | Rider chat bubbles use physical `Alignment`, inverting them in RTL. Own messages appear on the left in Arabic. | `apps/rider/lib/screens/trip/trip_chat_screen.dart:97`; correct implementation at `apps/captain/lib/screens/home/trip_chat_screen.dart:248-251` | In an Arabic-first product, the rider's own messages sit on the wrong side of the conversation. The captain app already fixed this; the fix was never carried across. | confirmed |
| F-12-11 | S2 | Captain document tiles use `Colors.black54`/`Colors.black87` chrome that disappears against the dark-mode tile background. | `documents_onboarding_screen.dart:531,576`; duplicated verbatim at `onboarding_screen.dart:1148,1191` | The "×" remove button on an uploaded document photo is `black87` on `nightSurface #26262B` — effectively invisible. A captain who uploads the wrong licence photo in dark mode has no discoverable way to delete it. Blocks onboarding. | confirmed |
| F-12-12 | S2 | A complete 15-role type scale exists and is bypassed. 199 raw `fontSize:` call sites across 23 distinct values in the rider app alone. | Scale at `app_theme.dart:1029-1052`; call sites throughout `apps/rider/lib/screens/**` and `apps/captain/lib/screens/**` | There is no typographic hierarchy in practice — 13, 14, 14.5, 15, 16, 17, 18 all appear, so "body" means seven different things. Changing the scale changes nothing. | confirmed |
| F-12-13 | S2 | The rider login screen forces `Colors.white` as its action foreground and `AppTokens.primary` as its action fill, ignoring `GoTheme` in dark mode. | `apps/rider/lib/screens/login_screen.dart:68` (`_onAction => Colors.white`), `:959` | In dark mode the first screen a new user sees renders a green button with white text where the design system specifies lime with near-black text. The product's first impression contradicts its own dark theme. | confirmed |
| F-12-14 | S2 | Presentational code is copy-pasted between the two apps at scale. | `login_screen.dart` 57.1% identical (rider 1044 / captain 830 lines); `services/trip_ws.dart` 57.0% (117/132); wallet screens 50.0% (497/810) with `_formatStamp`, `_money` and `_iconFor` byte-identical (`rider/wallet_screen.dart:279-322` ≡ `captain/earnings/wallet_screen.dart:476-528`) | Every visual fix must be made twice and in practice is made once. F-12-10 and F-12-03 are both instances of a fix that landed in one app only. | confirmed |
| F-12-15 | S2 | Every named radius tier disagrees between admin and mobile. | `app_theme.dart:161-166` (6/10/14/18/26) vs `tokens.ts:169-173` (4/8/12/16/20) | `sm` is 10dp on mobile and 4px in the console. The two surfaces have different physical softness — the console reads sharper and more clinical than the product it administers. No single change reconciles them because the ramps have different shapes. | confirmed |
| F-12-16 | S2 | `Badge.tsx` hardcodes all four status palettes as arbitrary Tailwind hex values, bypassing tokens entirely. | `apps/admin/src/components/ui/Badge.tsx:13-16` — 8 literals (`#EAF5E3`/`#14532D`, `#FEF3C7`/`#78350F`, `#FEE2E2`/`#7F1D1D`, `#EFF6FF`/`#1E40AF`) | Status badges — the densest information surface in the console — do not respond to dark mode at all. Light-mode pastel fills render against dark table rows. Ironically these values *match Flutter's* badge tokens, so the one component that agrees with mobile does so by accident. | confirmed |
| F-12-17 | S2 | Roughly seven directional icons are not mirrored for RTL. | `trip_screen.dart:282` (`Icons.arrow_back`), `schedule_screen.dart:98,118` (`chevron_right`), `location_search_sheet.dart:544`, `captain/settings_screen.dart:931`, `captain/earnings/wallet_screen.dart:579`, both chat send icons (`rider/trip_chat_screen.dart:140`, `captain/trip_chat_screen.dart:356`) | Flutter does not auto-mirror `Icon`. Back arrows and trailing chevrons point the wrong way in Arabic. Some sites *are* handled (`home_screen.dart:766`, `profile_screen.dart:814`, `saved_destinations_sheet.dart:359-360`), which proves the team knows the pattern and applies it inconsistently. | confirmed |
| F-12-18 | S2 | Non-adaptive brand gradients on rider help and invite cards. | `apps/rider/lib/screens/profile/help_screen.dart:36-50`, `invite_screen.dart:64-72` — `LinearGradient([primary, primaryDark])` with no `isDark` branch | In dark mode a mid-green banner sits on a `#0E0E10` page looking like a light-mode component pasted in. `AppTokens.headerGradient(go.isDark)` exists and is used correctly by `profile_screen.dart:509`. | confirmed |
| F-12-19 | S3 | Zero motion tokens in the Flutter design system. | No `Duration`/`Curve` constants in `app_theme.dart` (grep count 0); admin defines three (`tokens.ts:190-192`) but they are dead with the rest of the file | Every animation duration in both apps is an inline magic number. There is no way to tune the product's overall pace, and no reduce-motion policy expressible at the token layer (the rider splash implements it by hand; the captain splash does not). | confirmed |
| F-12-20 | S3 | Map tile URLs are defined twice in the same file, and the two apps read different definitions. | `AppTokens.mapTilesLight/Dark` at `app_theme.dart:238-242` with resolver `:248`; `MapTiles._light/_dark` at `:487-490` with resolver `urlForContext`. Rider uses `MapTiles` (`home_screen.dart:567`, `trip_screen.dart:248`, `saved_places_screen.dart:491`); captain uses `AppTokens` (`main_shell.dart:526`) | Identical today. The moment a branded style URL lands in one, the two apps render different maps. | confirmed |
| F-12-21 | S3 | Thirteen raw `BoxShadow` instances bypass the four elevation presets, including two hand-rolled variants of `shadowSheet` at the wrong alpha. | `trip_screen.dart:338,362,405,436`; `home_screen.dart:830,870,966,1129,1404`; `saved_places_screen.dart:517,552`; `offer_card.dart:882`; `main_bottom_nav.dart:397`; `rider/sos_screen.dart:132` | `shadowSheet` is 0.13α; `trip_screen.dart:436` uses 0.20 and `home_screen.dart:1129` uses 0.16/0.55. Three bottom sheets, three different shadows. Every widget inside `flutter_shared/` uses the presets correctly — the drift is entirely in the app layer. | confirmed |
| F-12-22 | S3 | Two near-identical offline banners inside the shared package itself. | `offline_gate.dart:17` (`GoOnlineCtaBanner`) and `offline_guard_banner.dart:14` (`OfflineGuardBanner`) — same icon-box + title + body + `GoOnlineButton` layout; the latter hardcodes Arabic strings at `:39-44` while the former is localisation-aware at `:54-68` | The design system is duplicating itself. One of these is dead weight and the hardcoded-Arabic one is the worse implementation. | confirmed |
| F-12-23 | S3 | No icon-size tokens. 16 distinct icon sizes in each app. | rider: 12,13,14,16,17,18,19,20,21,22,23,24,25,32,38,40,48; captain: 11,12,13,14,15,17,18,19,20,21,22,24,26,30,32,40 | Icons are optically misaligned with the text they sit beside because nothing binds icon size to type size. | confirmed |
| F-12-24 | S3 | CARTO Positron is a data-visualisation basemap being used as the primary content surface of a mobile product in Cairo. | `app_theme.dart:238-242`; attribution correctly present at `:245` | Positron is engineered to recede behind data layers in a desktop browser. At ~70% of screen time, in July Cairo sunlight, it washes toward white and the `#4E842D` route line loses separation. Also: `cartodb-basemaps-{s}.global.ssl.fastly.net` is the free legacy CDN — production use above CARTO's traffic threshold is a terms question. `needs-check` on current commercial terms. | confirmed (code) / needs-check (licensing) |
| F-12-25 | S3 | Dead ternary branch in the vehicle selector's glass treatment. | `apps/rider/lib/screens/home/vehicle_selector.dart:163` — `go.isDark ? Colors.white : Colors.white` | Both branches return white. The dark-mode resting chip gets an unintended white veil. Harmless visually, but it is a fossil of an intent that was lost. | confirmed |
| F-12-26 | S3 | The rider in-progress trip panel shows no ETA and no elapsed time. | `apps/rider/lib/screens/trip/trip_screen.dart:530-548` — driver card, status row, chat button, nothing else | The single question a rider has during a trip is "when do I arrive". The captain's `ActiveTripPanel` has a running clock (`active_trip_panel.dart:239`); the rider has nothing. A design-hierarchy failure with a support-ticket cost. | confirmed |
| F-12-27 | S3 | Rider home inverts its own hierarchy. | `home_screen.dart` — vehicle category strip renders above the location fields; the Continue button is conditional and `Size.fromHeight(54)` (`:1202`) against the system's `primaryActionHeight` of 56 (`app_theme.dart:181`); two utility toggles float over the map at `:679-697` | The largest, most visually active element is a secondary decision (vehicle class); the primary action is the smallest and appears last. Theme and language toggles occupy prime map real estate. | confirmed |
| F-12-28 | S4 | `splash.mp4` is an orphan asset. | Repo root; referenced only in a `.gitignore:116` comment; no Dart file loads it. Both splash screens are code-drawn and correctly use `splashBg`/`splashGlowStart`/`splashGlowTint` | Dead weight in the repository and a misleading signal about how the splash works. | confirmed |
| F-12-29 | S4 | The captain settings screen offers no "System" theme option; the rider's does. | `captain/settings_screen.dart:467-473` (two-way `Switch`) vs `rider/settings_screen.dart:63-75` (three-way dropdown) | A captain cannot follow the device theme, so their app will not go dark at dusk with the rest of the phone. | confirmed |
| F-12-30 | S4 | All numerals render as Western digits with no explicit decision recorded. | `location_service.dart:54` (`'$durationMin دقيقة'`), `fare_estimate_sheet.dart:115`, `wallet_screen.dart:412`; no `NumberFormat`, no `Intl.defaultLocale` anywhere | Defensible for Egypt — Western digits are the digital norm — but the comment at `location_service.dart:51` documents the example as `"١٦ دقيقة"` in Arabic-Indic, so the code and its own documentation disagree. Decide it, write it down. | confirmed |

### The S1 set, in prose

**F-12-01 — the product does not know its own name.** This is the finding I would fix
first, because it costs nothing to fix and it is bleeding conversion right now. The
`MaterialApp` title is `'GoDrive'` (`rider/main.dart:55`), the Android launcher label is
`GoDrive`, the localised `appTitle` is `GoDrive` in both `ar` and `en`, the wordmark
draws the literal string `'GoDrive'` (`rider/splash_screen.dart:389`), the invite share
text says `حمّل تطبيق GoDrive`, and the invite link points at `https://godrive.app`
(`invite_screen.dart:37`). Meanwhile the FCM channel is `synaptic_go_default` and every
notification that arrives without an explicit title falls back to the string
`'Synaptic Go'` (`fcm_service.dart:17,80`). The package id is
`tech.synapticstudio.godrive` and the Dart packages are `synaptic_go_rider` /
`synaptic_go_captain`.

The internal names are fine — package ids and channel ids are plumbing. The defect is
that a *user-visible* string, on the highest-stakes surface the product owns, uses the
company name instead of the product name. A rider whose captain has arrived gets a
lock-screen notification from an app called "Synaptic Go" and has to think about
whether it is spam. Notification open-rate is the conversion funnel for a ride-hailing
app. One string.

**F-12-02 — the dark-mode action colour belongs to a competitor.** `AppTokens.lime` is
`Color(0xFFC1F11D)` and it is bound as `action` in the dark theme
(`app_theme.dart:137, 404`), which means it fills every primary CTA in dark mode: accept
the offer, confirm the trip, go online. inDrive's brand is built on a high-chroma
yellow-green lime over dark surfaces — that is the most recognisable colour signature in
this exact category, in this exact market. I am confident about inDrive's brand
character from ordinary market familiarity; I have *not* verified their exact registered
hex, so treat the "essentially identical" claim as `assumed` and get a designer or
counsel to confirm before launch.

Set that aside and a design problem remains regardless: `#4E842D` forest green and
`#C1F11D` acid lime are not one brand in two brightnesses. They are two different
personalities. The light theme is calm, institutional, agricultural. The dark theme is
loud, sporty, energetic. A user who toggles the theme does not experience "the same
product at night" — they experience a different company. A brand's dark mode should be
the *same hue* rendered for a dark substrate, not a different hue chosen because it
happens to glow.

**F-12-03 — the SOS screen fails in the dark.** `apps/rider/lib/screens/safety/sos_screen.dart`
sets `backgroundColor: AppTokens.lightPanel` on both the confirmation dialog (`:31`) and
the screen scaffold (`:116`), and uses `lightText`/`lightMuted` for its copy. Those are
light-ramp constants, not `GoTheme` reads, so they do not change in dark mode. A rider
who hits SOS at 11pm gets a full-screen white panel.

Three things make this worse than a normal theming bug. It is a safety screen, so the
failure mode is a rider who has lost their night vision and is holding a lit beacon in a
situation where they may not want to be conspicuous. The correct token already exists —
`AppTokens.sosBackdrop` `#1A0000`, documented at `app_theme.dart:65-67` as "a near-black
red that keeps the SOS screen unmistakable even in peripheral vision, day or night". And
the captain app already does it correctly (`captain/safety/sos_screen.dart:118`). The
design system anticipated this screen, provided for it, and the rider app did not pick
it up. This is a one-line fix and it should not wait for a phase.

**F-12-04 — two greens.** Mobile renders `#4E842D`. The admin console renders `#6BB522`
— a lighter, more saturated, more yellow green — as its brand primary
(`globals.css:26`), and the console's own logo component hardcodes it
(`GoDriveLogo.tsx:44`). Put a phone next to the console and the wordmarks do not match.

The reason this survived review is F-12-05: the file an engineer would open to check the
brand colour, `design/tokens.ts`, contains the *correct* value `#4e842d` at line 32,
annotated "WCAG AA compliant GoDrive green (4.53:1 on white)". It is right, it is
well-commented, and it is imported by nothing. The live value comes from CSS custom
properties and Tailwind. So the token file tells the truth about the brand and lies
about the product, and every audit that reads it concludes the admin is fine.

Worth noting the contrast consequence: `#6BB522` on white is roughly 3.0:1 by
computation — it does **not** meet WCAG AA for body text, whereas the `#4E842D` it
replaced does at 4.53:1. Whoever changed it made the console lighter and, incidentally,
less accessible. Flagged to T16 in section 9.

## 5. Benchmark gap

Competitor mechanics below are marked **confident** where they are observable in the
shipped products, **assumed** where I am reasoning from category norms. No competitor
source code was read.

| Axis | Uber | inDrive | Careem | Synaptic Go today |
|---|---|---|---|---|
| Brand colour strategy | Monochrome discipline: black/white with a single accent. Dark mode is the same brand rendered darker (confident) | One unmistakable lime, applied at maximum chroma on dark. The colour *is* the brand (confident) | Warm regional green with confident Arabic type; culturally rooted rather than globally neutral (confident) | Two unrelated hues by brightness (`#4E842D` / `#C1F11D`), the second borrowed from inDrive |
| Typography | Custom typeface (Uber Move) — proprietary, bundled, a real asset (confident) | System-adjacent grotesk, high legibility prioritised over distinction (assumed) | Custom Arabic-first family with genuine Arabic type design, not a Latin face with Arabic bolted on (confident) | Cairo, unbundled, fetched at runtime, contradicted in 19 rider call sites by IBM Plex |
| Map | Custom-styled vector basemap; road hierarchy and label density tuned per market; distinctive night style (confident) | Utilitarian basemap, extreme contrast for sunlight legibility (assumed) | Custom style with Arabic-first labelling (assumed) | CARTO Positron/Dark Matter off the free CDN, unmodified |
| Component system | Base Design System — public, versioned, one source across web and native (confident) | Not public (needs-check) | Not public (needs-check) | 15 domain widgets, no Button/Card/Field/Toast primitive; admin and mobile fully siloed |
| Numerals | Locale-aware formatting (confident) | Locale-aware (assumed) | Locale-aware with Arabic-Indic where regionally appropriate (assumed) | Western digits everywhere, by default rather than by decision |
| Dark mode | Complete, treated as a first-class surface (confident) | Dark-primary product (confident) | Complete (assumed) | Genuinely built and reachable, with seven real breaks and a safety screen that fails |

Where Synaptic Go actually sits: **the system is better than the product.** The token
layer, the `GoTheme` extension, the documented contrast ratios, the four-preset elevation
scale, the custom-painted vehicle marker, the casing-plus-line route rendering — that is
work of a standard the category respects. What is missing is the connective tissue that
turns a token file into a look: primitives that force consumption, one name, one
typeface, one green, and a map that belongs to the product.

The single largest visual gap against all three benchmarks is the **map**. It is 70% of
the pixels and it is the one surface that is entirely un-branded. Uber's map is instantly
recognisable as Uber's. This map is recognisable as CARTO's.

The second largest is **typographic hierarchy**. Uber and Careem both drive hierarchy
almost entirely through type — size, weight and spacing carry the design. Synaptic Go has
the tokens to do this (`money()` at w900, a display scale up to 44) and instead has 23
arbitrary font sizes in one app, which produces a flat, undifferentiated surface where
everything is 13-16px and nothing leads.

## 6. Improvement plan

### P0.1 — One product name

- **Goal** — every surface a user sees says the same thing, so notifications are
  recognised and opened.
- **Design** — decide the user-facing name (recommendation: **GoDrive**, because it is
  already in the store listing, the launcher label, both localisations, the wordmark, the
  share copy and the `godrive.app` domain; "Synaptic Go" is the studio's name for the
  project). Then remove the product name from notification code entirely: the FCM
  fallback title should read from the localised `appTitle`, not a hardcoded literal.
- **Files to change** — `packages/flutter_shared/lib/services/fcm_service.dart:17,80`
  (channel display name and fallback title); audit `l10n/app_strings.dart` for any
  remaining "Synaptic Go" user-visible literal.
- **DB** — none. **API contract** — none.
- **Effort** — S (under an hour).
- **Risk** — changing the FCM *channel id* (`synaptic_go_default`) would orphan existing
  users' notification preferences. Change the channel's display *name* only; leave the id
  alone. Rollback is a one-line revert.
- **Acceptance criteria** — grep for `Synaptic Go` returns zero hits in code paths that
  render to a user; a push with no explicit title displays "GoDrive"; existing users'
  notification settings survive the upgrade.
- **Tests** — widget test asserting the notification fallback title equals
  `strings.appTitle`; manual push on a device upgraded from the prior build.

### P0.2 — Fix the SOS screen in dark mode

- **Goal** — the emergency screen is legible and non-blinding at night in both apps.
- **Design** — the rider SOS screen adopts the same fixed-dark treatment the captain
  already uses. `sosBackdrop` is a fixed emergency canvas by design: it does not follow
  brightness, it is always the near-black red, because an emergency screen should look
  identical every time it appears.
- **Files to change** — `apps/rider/lib/screens/safety/sos_screen.dart:31,116` →
  `AppTokens.sosBackdrop`; body copy from `lightText`/`lightMuted` → white / `white70`,
  matching `apps/captain/lib/screens/safety/sos_screen.dart` as the reference.
- **DB** — none. **API contract** — none.
- **Effort** — S (under an hour).
- **Risk** — none meaningful; contrast improves in both brightnesses.
- **Acceptance criteria** — rider SOS screenshot in dark mode is visually identical in
  treatment to captain SOS; no `lightPanel`/`lightText` reference remains in either
  safety screen.
- **Tests** — golden test for both SOS screens in both brightnesses. These two screens
  are worth golden coverage even if nothing else gets it.

### P0.3 — Resolve the brand colour, and stop shipping a competitor's

- **Goal** — one brand hue, expressed correctly in both brightnesses, that is not
  inDrive's.
- **Design** — this is the one decision in this document that needs the product owner
  (section 10, Q1). Two defensible routes:

  **Route A — keep the green, fix the dark mode.** Lowest cost, lowest risk. Retain
  `#4E842D` and replace the lime with a light-register version of the *same hue* so dark
  mode is the same brand at night.

  | Token | Today | Proposed | Note |
  |---|---|---|---|
  | `primary` (light action) | `#4E842D` | `#4E842D` unchanged | 4.53:1 on white, AA |
  | `lime` → rename `actionDark` | `#C1F11D` | `#7CC142` | same green family, ~8.9:1 against `nightBg`, reads as the brand at night |
  | `onLime` → `onActionDark` | `#101010` | `#0B1A05` | near-black with a green cast |
  | `limePressed` → `actionDarkPressed` | `#A9D617` | `#6BAB37` | |

  **Route B — reposition on a Cairo-rooted palette.** Higher cost, genuinely
  differentiated. Nile blue as primary, desert amber as accent, warm limestone surface —
  a palette that is recognisably *of Egypt* rather than generically "modern", and that no
  competitor in the market occupies.

  | Token | Proposed | Rationale |
  |---|---|---|
  | `primary` | `#1F6F8B` | Deep Nile blue-teal. ~5.1:1 on white. Unoccupied in this market — Uber is black, inDrive lime, Careem green |
  | `actionDark` | `#4FA8C7` | Same hue, light register for dark surfaces |
  | `accent` | `#C07A2A` | Desert amber; the complement. Carries rating, fare emphasis, warning |
  | `bg` (light) | `#F6F2EC` | Warm limestone rather than clinical grey-white |
  | `success` / `danger` | `#178841` / `#D92D20` unchanged | Already AA-verified; keep |

  Route B is the stronger answer to the brief's question ("does this look like a product
  someone chose"). Route A is the right answer if launch is near. Either way the lime
  must go.
- **Files to change** — `app_theme.dart:36-44,137-139,385,404` and the `GoTheme` light/dark
  instances; `apps/admin/src/design/globals.css:26,45,60,79,167,171`;
  `apps/admin/tailwind.config.js:45-88`; `apps/admin/src/components/common/GoDriveLogo.tsx:44`.
- **DB** — none. **API contract** — none.
- **Effort** — S for Route A, M for Route B (Route B needs the marketing surfaces and the
  store listing to follow).
- **Risk** — Route B invalidates existing screenshots and store assets. Do it before
  launch or not for a year.
- **Acceptance criteria** — one `primary` hex appears in both `app_theme.dart` and the
  admin's live CSS; no token in the product is within a perceptible distance of
  `#C1F11D`; the dark action colour is the same hue family as the light one.
- **Tests** — a CI check (P1.1) that fails if the two values diverge.

### P0.4 — Make the admin's live tokens match, and delete the file that lies

- **Goal** — the console and the apps are the same brand, and there is exactly one place
  to read a token value.
- **Design** — `globals.css` becomes the admin's single source and is *generated*, not
  hand-written (see P1.1). Immediately, before the generator exists: correct the live
  values and delete `tokens.ts`. Restore semantic separation — `success`, `info` and
  `primary` must be three different colours.

  | CSS variable | Today | Proposed |
  |---|---|---|
  | `--color-brand-primary-500` | `#6bb522` | `#4e842d` (or Route B primary) |
  | `--color-success-main` | `#6bb522` | `#178841` — matches Flutter `success` |
  | `--color-info-main` | `#6bb522` | `#1d6dbe` — matches Flutter `info` |
  | `--color-warning-main` | `#f59e0b` | `#947105` — matches Flutter `warning` |
  | `--color-error-main` | `#ef4444` | `#d92d20` — matches Flutter `danger` |
  | `--color-border-focus` | `#6bb522` | `#4e842d` |

- **Files to change** — `apps/admin/src/design/globals.css:26,45,50,55,60,79,167,171`;
  `apps/admin/tailwind.config.js:33,43,50,72-88`; delete
  `apps/admin/src/design/tokens.ts`; `Badge.tsx:13-16` → semantic Tailwind classes.
- **DB** — none. **API contract** — none.
- **Effort** — S.
- **Risk** — `Badge.tsx`'s hardcoded pastels currently render acceptably in light mode;
  moving them to tokens will change their appearance. Review the badge set visually after
  the change. Note the accessibility improvement: `#4e842d` restores AA on white where
  `#6bb522` (~3.0:1) does not.
- **Acceptance criteria** — `tokens.ts` no longer exists; grep for `#6bb522` returns zero;
  grep for `bg-[#` in `components/ui/` returns zero; success, info and primary are three
  distinct hexes.
- **Tests** — visual regression on the badge set in both brightnesses.

### P1.1 — One token source, generated into both platforms

- **Goal** — a token change is made once and cannot drift.
- **Design** — a single `design/tokens.json` at the repo root as the source of truth. A
  small Node script generates `packages/flutter_shared/lib/theme/tokens.g.dart` (a
  `const` class consumed by `AppTokens`) and `apps/admin/src/design/tokens.g.css` (the
  custom properties consumed by Tailwind). Both generated files are committed and CI
  fails if regenerating produces a diff. This is the mechanism that makes F-12-04 and
  F-12-15 permanently impossible; without it they will come back.
- **Files to change** — new `design/tokens.json`, new `scripts/gen-tokens.mjs`, new
  `.github/workflows` check (**proposed CI YAML goes in
  `docs/plan/assets/12-token-drift.yml.txt`, not in `.github/workflows` — the GitHub App
  has no `workflows` permission**); `app_theme.dart` refactored to read generated
  constants; `globals.css` replaced by the generated file.
- **DB** — none. **API contract** — none.
- **Effort** — M.
- **Risk** — a generator that nobody runs is worse than no generator. The CI drift check
  is the load-bearing part, not the script.
- **Acceptance criteria** — changing a hex in `tokens.json` and regenerating updates both
  platforms; CI fails on a hand-edit to either generated file.
- **Tests** — CI job proves the drift check catches a deliberate hand-edit.

### P1.2 — Ship the four missing primitives

- **Goal** — screens stop hand-rolling buttons and text, and the type scale becomes
  unavoidable rather than optional.
- **Design** — four widgets in `packages/flutter_shared/lib/widgets/`, each consuming
  `GoTheme` and the type scale internally so a caller *cannot* pass a raw `fontSize`:

  ```dart
  // go_button.dart
  enum GoButtonVariant { primary, secondary, ghost, danger }
  enum GoButtonSize { regular, large }   // 48dp tapTarget / 56dp primaryActionHeight
  class GoButton extends StatelessWidget {
    const GoButton({ required String label, required VoidCallback? onPressed,
      GoButtonVariant variant = GoButtonVariant.primary,
      GoButtonSize size = GoButtonSize.large,
      IconData? icon, bool busy = false });
  }

  // go_card.dart      — panel colour, radiusLg, shadowCard, GoTheme-aware
  // go_text_field.dart — inputFill, radiusMd, error state, RTL-correct affixes
  // go_toast.dart     — showGoToast(context, message, GoToastKind.{info,success,error})
  ```
- **Files to change** — four new widgets, exported from `flutter_shared.dart`. Then
  migrate: the highest-value first pass is every `ElevatedButton` in the rider booking
  flow and the captain offer/trip flow.
- **DB** — none. **API contract** — none.
- **Effort** — M for the primitives; L for full migration across 60 screens.
- **Risk** — a half-migration is the worst state (three button styles instead of two).
  Migrate by flow, not by file, and finish each flow.
- **Acceptance criteria** — `GoButton` exists and is used by every primary action in both
  apps' core flows; `showGoToast` replaces every raw `ScaffoldMessenger` call in those
  flows; new raw `ElevatedButton` in a migrated flow fails review.
- **Tests** — golden tests for all four primitives across both brightnesses and both text
  directions.

### P1.3 — Bundle the typeface and collapse to one family

- **Goal** — the product always renders in its own type, offline and on first launch.
- **Design** — vendor Cairo's variable font into
  `packages/flutter_shared/assets/fonts/`, declare it in the package `pubspec.yaml`, and
  switch `AppTokens.font()` from `GoogleFonts.cairo(...)` to a plain `TextStyle(fontFamily:
  'Cairo')`. Delete the 19 IBM Plex call sites in the rider app. Point the admin at the
  same bundled family — self-host the woff2 rather than the Google CDN link.
- **Files to change** — `packages/flutter_shared/pubspec.yaml` (fonts declaration + drop
  `google_fonts`), `app_theme.dart:260-290`, `apps/rider/lib/screens/home/home_screen.dart`
  (10 sites), `apps/rider/lib/screens/places/saved_places_screen.dart` (9 sites),
  `apps/admin/index.html:9`, `apps/admin/src/design/globals.css:90`.
- **DB** — none. **API contract** — none.
- **Effort** — M.
- **Risk** — bundling adds roughly 300-500KB per app depending on the subset; ship a
  Latin+Arabic subset, not the full family. Layout will shift slightly on the 19 screens
  that were rendering IBM Plex — review them.
- **Acceptance criteria** — the app renders in Cairo with the device in airplane mode on
  first launch after install; zero `GoogleFonts.` references remain; one family name
  across Flutter and admin.
- **Tests** — an integration test that launches with the network disabled and asserts the
  resolved font family.

### P1.4 — Make the type scale the only way to set type

- **Goal** — typographic hierarchy that actually reads, and one place to tune it.
- **Design** — the `TextTheme` already exists (`app_theme.dart:1029-1052`). Add named
  accessors on `AppTokens` mirroring the roles, migrate call sites in priority order, and
  ban raw sizes in review. Proposed Arabic-tuned adjustments to the existing scale:

  | Role | Today | Proposed | Reason |
  |---|---|---|---|
  | `bodyLarge` | 15 / w500 / h1.55 | 15 / w500 / **h1.6** | Arabic needs more leading than Latin at the same size |
  | `bodyMedium` | 14 / w400 / h1.55 | 15 / w400 / **h1.6** | 14 is small for Arabic body copy; 13 and 14 together account for 70 of 199 rider call sites and both are too small |
  | `bodySmall` | 13 / w400 / h1.5 | 13 / w400 / **h1.55** | |
  | `labelSmall` | 11 / w500 | **12** / w500 | 11px Arabic with diacritics is not reliably legible |
  | `money` helper | h1.1 | unchanged | correct for numerals; must never be used for Arabic prose |

- **Files to change** — `app_theme.dart:1029-1052`; then call sites, flow by flow.
- **DB** — none. **API contract** — none.
- **Effort** — L (199 rider + ~193 captain call sites), but incrementally shippable.
- **Risk** — raising `bodyMedium` from 14 to 15 will reflow dense screens. Do it with the
  P1.2 primitives so the change lands in one place per component.
- **Acceptance criteria** — distinct raw `fontSize:` values in the rider app drop from 23
  to under 5 (charts, the money helper and genuine one-offs); `bodyMedium` renders at 15/1.6.
- **Tests** — a lint or CI grep capping raw `fontSize:` occurrences, ratcheting downward.

### P1.5 — RTL correctness pass

- **Goal** — the Arabic build is not a mirrored afterthought.
- **Design** — fix the known breaks, then prevent recurrence with a lint. The pattern is
  already understood by the team — `home_screen.dart:766` and `profile_screen.dart:814`
  do it correctly — so this is consistency, not education.
- **Files to change** — `rider/trip_chat_screen.dart:97` → `AlignmentDirectional.centerEnd`
  / `centerStart` (copy `captain/trip_chat_screen.dart:248-251` exactly);
  `trip_screen.dart:282` back arrow; `schedule_screen.dart:98,118`,
  `location_search_sheet.dart:544`, `captain/settings_screen.dart:931`,
  `captain/earnings/wallet_screen.dart:579` chevrons; both chat send icons; and
  `trip_detail_screen.dart:111` `EdgeInsets.only(right: 8)` → `EdgeInsetsDirectional`.
  For icons, prefer a small `DirectionalIcon` helper in `flutter_shared` over per-site
  ternaries.
- **DB** — none. **API contract** — none.
- **Effort** — S.
- **Risk** — none; all changes are locale-conditional or directional equivalents.
- **Acceptance criteria** — zero physical `Alignment.centerLeft/Right` in message or list
  layouts; every directional icon routed through the helper; screenshots of the chat,
  trip and settings screens in `ar` show correct sidedness.
- **Tests** — golden tests in both directions for the chat bubble, the trip header and one
  settings list row.

### P2.1 — A branded map style

- **Goal** — the surface that is 70% of the product stops belonging to a tile vendor.
- **Design** — a custom vector style delivered by MapTiler (or self-hosted
  OpenMapTiles), specified for Cairo rather than for generic data-viz:
  - **Road hierarchy** — the Ring Road, Corniche el-Nil, Salah Salem and the 6th October
    corridor rendered a full weight step above ordinary arterials. Cairo navigation is
    organised around these; Positron renders them at near-grid weight.
  - **Labels** — Arabic primary at a heavier weight than the Latin transliteration;
    aggressive POI suppression below z14.
  - **Surface** — warm limestone `#F2EDE6` rather than Positron's cool grey, so the
    basemap reads as *place* and the route line separates cleanly.
  - **Night** — true near-black `#0E0E10` matching `nightBg`, roads at low-luminance grey,
    the route line in white as today.
  - **Route line** — reads against both: keep the casing-plus-line technique already
    implemented, which is correct.
- **Files to change** — resolve F-12-20 first (one tile definition, not two): delete the
  `MapTiles` class at `app_theme.dart:484-501` and point the rider's three call sites at
  `AppTokens.mapTilesFor`. Then swap the URL and add the API key to per-app config.
- **DB** — none. **API contract** — none, unless the key is served from the backend.
- **Effort** — L (style authoring is design work, not just a URL change).
- **Risk** — vendor cost and quota; hand cost modelling to T22. The free CARTO CDN in
  production is a terms exposure (F-12-24) that this also resolves.
- **Acceptance criteria** — one tile-URL definition in the codebase; both apps render the
  branded style; the style is legible at 800 nits and at night.
- **Tests** — manual outdoor legibility check at midday; screenshot set at z12/z14/z16 in
  both modes.

### P2.2 — Extract the duplicated presentational code

- **Goal** — a visual fix lands once. Scoped here to *presentational* extraction; the
  architectural programme is T27's.
- **Design** — in priority order by (duplication × visual risk):
  1. `WalletBalanceCard` → shared. `_BalanceCard` + `_Bloom` are byte-identical between
     `rider/wallet_screen.dart:332-477` and `captain/earnings/wallet_screen.dart:600-750`;
     only the CTA differs. API: `{ balance, actionLabel, actionIcon, onAction }`.
  2. `TripChatScreen` → shared, using the captain's implementation as the reference (it
     has WebSocket, correct RTL, auto-scroll, typing indicator; the rider's has none of
     these). API: `{ tripId, selfRole, fetchMessages, sendMessage, wsMessages? }`. This
     fixes F-12-10 by deletion.
  3. `SosScreen` → shared, captain's version as reference. Fixes F-12-03 by deletion.
     API: `{ onSendSos, tripId?, includeShareTrip }`.
  4. Auth screen shell → shared. 57.1% identical; the captain lacks the rider's entrance
     choreography and reduce-motion handling. API takes `{ heroSlides, callbacks,
     actionColor, fixedDarkCanvas }`.
  5. Delete `offline_guard_banner.dart`; parameterise `GoOnlineCtaBanner` (it is the
     localisation-aware one).
- **Files to change** — as above, plus call-site updates in both apps.
- **DB** — none. **API contract** — none.
- **Effort** — L.
- **Risk** — over-parameterising produces a widget with 15 flags that is worse than two
  copies. If a shared version needs more than ~5 parameters, leave it duplicated and say
  so.
- **Acceptance criteria** — the five items above exist once; `diff` similarity between the
  two apps' screen directories drops materially.
- **Tests** — golden tests for each extracted widget in both apps' configurations.

### P2.3 — Motion, icon and surface tokens

- **Goal** — close the three remaining token-layer gaps.
- **Design** — add to `AppTokens`:
  ```dart
  // Motion
  static const durInstant  = Duration(milliseconds: 100);
  static const durFast     = Duration(milliseconds: 160);
  static const durNormal   = Duration(milliseconds: 240);
  static const durSlow     = Duration(milliseconds: 360);
  static const curveStandard  = Curves.easeOutCubic;
  static const curveEmphasis  = Curves.easeOutBack;
  // Icons — bound to the type scale
  static const double iconSm = 16, iconMd = 20, iconLg = 24, iconXl = 32;
  ```
  Plus a `reduceMotion(context)` helper wrapping `MediaQuery.disableAnimationsOf` so the
  policy the rider splash implements by hand becomes systemic.
- **Files to change** — `app_theme.dart`; then the 13 raw `BoxShadow` sites (F-12-21),
  routing the three bottom-sheet variants to `shadowSheet` and promoting
  `home_screen.dart:830`'s `_softShadow` into the token layer as a brightness-aware preset
  (it is a legitimate variant and should be shared, not local).
- **DB** — none. **API contract** — none.
- **Effort** — M.
- **Risk** — low.
- **Acceptance criteria** — zero raw `Duration(milliseconds:` in screen files; raw
  `BoxShadow` outside `app_theme.dart` reduced to zero; four icon sizes replace 16.
- **Tests** — CI grep ratchet on raw `BoxShadow` and `Duration` in `apps/*/lib/screens/`.

### P2.4 — Hierarchy fixes on the three screens that matter

- **Goal** — the primary action dominates on the product's highest-traffic surfaces.
- **Design** —
  - **Rider home** — move the vehicle category strip *below* the location fields; a
    secondary decision must not visually precede the primary inputs. Raise the Continue
    button from 54 to `primaryActionHeight` 56 and to w900. Move the theme and language
    toggles out of the map overlay into profile settings — they are settings, not actions,
    and they currently occupy the spot the eye lands on first.
  - **Captain offer** — the card is the best-designed surface in the product; the fare at
    30dp `money()` is correctly the hero and the accept button correctly spans full width.
    One change: raise accept from 46dp to 56dp for consistency and for tapping while
    moving.
  - **Rider trip in progress** — the real gap is content, not layout. Add elapsed time
    (mirroring `active_trip_panel.dart:239`) and promote the fare to ~32dp with a label.
    The chat button becomes secondary. See F-12-26.
- **Files to change** — `rider/home_screen.dart` (panel order, `:1202`, `:679-697`);
  `captain/offer_card.dart:608-648`; `rider/trip_screen.dart:530-548`.
- **DB** — none. **API contract** — the rider ETA needs an ETA on the trip payload if one
  is not already exposed; `needs-check` against T09's findings before assuming a backend
  change is required.
- **Effort** — M.
- **Risk** — reordering the rider home panel changes a flow users may have learned; ship
  behind a flag if there is any live traffic.
- **Acceptance criteria** — on each of the three screens, the primary action is the
  largest interactive element and sits at 56dp.
- **Tests** — golden tests for the three screens at two device sizes.

## 7. Phasing

**P0 — before any production traffic.** The S1 set. Four items, roughly one engineer-day
in total apart from the brand decision, which is a meeting rather than a task.

| Item | Findings closed | Effort | Owner-type |
|---|---|---|---|
| P0.1 One product name | F-12-01 | S | Flutter |
| P0.2 SOS dark mode | F-12-03 | S | Flutter |
| P0.3 Brand colour decision + lime removal | F-12-02, part of F-12-04 | S (Route A) / M (Route B) | Design + Flutter + admin |
| P0.4 Admin live tokens corrected, `tokens.ts` deleted | F-12-04, F-12-05, F-12-06, F-12-16 | S | Admin |

**P1 — first 30 days.** The structural work that makes the system self-enforcing.

| Item | Findings closed | Effort | Owner-type |
|---|---|---|---|
| P1.1 Generated single token source + CI drift check | prevents F-12-04, F-12-15 recurring | M | Backend/tooling |
| P1.2 `GoButton` / `GoCard` / `GoTextField` / `GoToast` | F-12-08, enables F-12-12 | M + L migration | Flutter |
| P1.3 Bundle Cairo, delete IBM Plex call sites | F-12-07, F-12-09 | M | Flutter + admin |
| P1.4 Type scale enforced, Arabic leading tuned | F-12-12 | L, incremental | Flutter |
| P1.5 RTL correctness pass | F-12-10, F-12-17, part of F-12-14 | S | Flutter |
| — Radius reconciliation (falls out of P1.1) | F-12-15 | S | Admin |
| — Captain "System" theme option | F-12-29 | S | Flutter |
| — Delete `splash.mp4`, fix dead ternary | F-12-28, F-12-25 | S | Flutter |

**P2 — next 90 days.** The work that turns a coherent system into a distinctive product.

| Item | Findings closed | Effort | Owner-type |
|---|---|---|---|
| P2.1 Branded map style, one tile definition | F-12-20, F-12-24 | L | Design + Flutter + ops |
| P2.2 Extract duplicated presentational code | F-12-14, F-12-22 | L | Flutter (with T27) |
| P2.3 Motion / icon / surface tokens | F-12-19, F-12-21, F-12-23 | M | Flutter |
| P2.4 Hierarchy fixes on the three key screens | F-12-26, F-12-27 | M | Design + Flutter |
| — Non-adaptive gradients, captain document tiles | F-12-11, F-12-18 | S | Flutter |
| — Numeral policy decided and documented | F-12-30 | S | Product |

Note on sequencing: **P1.1 should land before P1.2 and P1.3.** Building primitives and
bundling fonts against two divergent token sources bakes the divergence into the
components. Fix the source, then build on it.

## 8. Metrics

Design work is measurable here because most of the failures are countable. Every current
value below was computed at base commit `84c1ce92` and can be re-run as a CI ratchet.

| Metric | How measured | Current | Target | Phase |
|---|---|---|---|---|
| User-visible "Synaptic Go" literals | grep of rendered strings | 2 (`fcm_service.dart:17,80`) | 0 | P0 |
| Token hexes differing between Flutter and admin | diff of the two token sets | 6 families disagree (primary, success, warning, danger, info, all 5 radii) | 0 | P0/P1 |
| Live occurrences of `#6bb522` | grep `apps/admin/src` | 8 | 0 | P0 |
| Distinct hexes serving primary/success/info in admin | grep `globals.css` | 1 (all `#6bb522`) | 3 | P0 |
| Screens rendering light surfaces in dark mode | manual audit, this document | 7 (F-12-03, 11×2, 13, 18×2) | 0 | P0/P1 |
| Bundled font files | `find -name '*.ttf' -o -name '*.otf'` | 0 | ≥1 | P1 |
| Typefaces referenced product-wide | grep `GoogleFonts.`/`font-family` | 2 (Cairo, IBM Plex) | 1 | P1 |
| Distinct raw `fontSize:` values, rider | grep + uniq | 23 | ≤5 | P1/P2 |
| Raw `fontSize:` call sites, rider | grep count | 199 | ≤40 | P2 |
| Shared UI primitives (button/card/field/toast) | count in `flutter_shared/widgets` | 0 of 4 | 4 of 4 | P1 |
| Physical `Alignment.centerLeft/Right` in content layout | grep | 1 real bug (+3 cosmetic gradients) | 0 | P1 |
| Unmirrored directional icons | manual audit | ~7 | 0 | P1 |
| Raw `BoxShadow` outside `app_theme.dart` | grep | 13 | 0 | P2 |
| Motion tokens defined | grep `Duration` in `app_theme.dart` | 0 | ≥4 | P2 |
| Distinct icon sizes per app | grep + uniq | 16 | 4 | P2 |
| Tile-URL definitions | grep `urlTemplate`/tile constants | 2 | 1 | P2 |
| Cross-app duplication, login screens | `diff` similarity | 57.1% | <15% | P2 |

Two product metrics worth instrumenting alongside the code metrics, because they are the
ones that pay for this work:

- **Notification open rate**, segmented before/after P0.1. This is the direct commercial
  test of the naming fix and I would expect it to move measurably.
- **Dark-mode adoption** — the share of sessions with `themeMode` resolving to dark.
  Currently unknown and not instrumented (`needs-check`). If it is material, the seven
  dark-mode breaks in F-12-03/11/13/18 are affecting a large share of sessions and
  should move up in priority. If it is near zero, the SOS fix still ships in P0 on safety
  grounds alone.

## 9. Cross-cutting notes

**To T27 — cross-app duplication (owns the systematic problem).**
Measured similarity at base commit `84c1ce92`: `login_screen.dart` 57.1% (rider 1044 /
captain 830 lines), `services/trip_ws.dart` 57.0% (117/132), wallet screens 50.0%
(497/810), `trip_chat_screen.dart` 22.4% (150/421), `splash_screen.dart` 21.0%, rider vs
captain `sos_screen.dart` 17.7%. The low percentages on the last three are *not* good
news — they are cases where the two apps diverged into different feature sets for the
same screen, which is worse than a clean copy. Specifics you will want:
`_formatStamp`, `_money` and `_iconFor` are byte-identical between the two wallet screens
(`rider/wallet_screen.dart:279-322` ≡ `captain/earnings/wallet_screen.dart:476-528`);
`trip_ws.dart` diverged into a callback API in the rider and a broadcast-stream API in the
captain, and the rider silently drops the reconnect status notification the captain
emits. Two of my findings (F-12-03 rider SOS, F-12-10 rider chat RTL) are fixes that
landed in the captain app and were never carried across — that is the duplication tax
showing up as user-visible defects, and it is your strongest argument. My P2.2 proposes
presentational extraction only; the architecture is yours.

**To T16 — accessibility.** Two things from this track. First, the admin's live primary
`#6bb522` computes to roughly 3.0:1 on white, below AA for body text; the `#4e842d` it
diverged from is 4.53:1 and is documented as such at `tokens.ts:32`. Someone lightened
the console and lost AA. Second, `labelSmall` at 11px (`app_theme.dart:1052`) is
questionable for Arabic with diacritics; I propose 12 in P1.4 but you own the threshold.
Also note the reduce-motion policy is implemented by hand in
`rider/splash_screen.dart:73-78,83` and absent from `captain/splash_screen.dart:46` — my
P2.3 adds a systemic helper, but the audit of what respects it is yours.

**To T14 — localisation.** `docs/ROADMAP.md:21` specifies IBM Plex Sans Arabic; the
implementation uses Cairo. Whichever wins, the roadmap line should be corrected so the
next reviewer does not re-litigate it. Separately, `l10n/app_strings.dart` contains
user-visible brand literals — `'حمّل تطبيق GoDrive'` (`:3357`), `'Download the GoDrive
app'` (`:5306`), `'تتبع رحلتي على GoDrive'` (`:2616`) — which need to change with the
naming decision in P0.1. And the numeral question (F-12-30) is jointly yours: no
`NumberFormat`, no `Intl.defaultLocale`, so all output is Western digits regardless of
locale.

**To T09 — rider flow.** F-12-26: the in-progress panel (`trip_screen.dart:530-548`) has
no ETA and no elapsed time, while the captain's equivalent does. I have treated it as a
hierarchy failure; if the trip payload does not expose an ETA, it is a backend gap and
yours. Also `rider/trip_chat_screen.dart` polls only — incoming captain messages are
invisible until the rider sends something. I found it while comparing chat
implementations; the functional fix is yours, the RTL fix is mine.

**To T10 — captain flow.** F-12-11: the "×" remove control on document tiles is
`Colors.black87` on `nightSurface` and is invisible in dark mode
(`documents_onboarding_screen.dart:576`, `onboarding_screen.dart:1191`). A captain who
uploads a wrong document in dark mode cannot delete it. I have it as a theming bug; it
manifests as an onboarding blocker, which is your axis.

**To T11 — admin console.** `apps/admin/src/design/tokens.ts` is 248 lines imported by
nothing. I propose deleting it in P0.4. If any of your work references it, coordinate
before it goes.

**To T22 — cost.** The map tiles come from `cartodb-basemaps-{s}.global.ssl.fastly.net`,
CARTO's free legacy CDN (`app_theme.dart:238-242`). Production traffic on the free tier
is a terms-of-service exposure, and my P2.1 proposes MapTiler or self-hosted
OpenMapTiles. Both have real per-tile economics at ride-hailing volumes. `needs-check` on
CARTO's current commercial terms — I did not verify them.

## 10. Open questions

**Q1 — What is the brand?** *(blocks P0.3; the only decision here that cannot be made by
an engineer)*
The dark-mode action colour is `#C1F11D`, which is inDrive's signature lime, in the one
market where you compete with inDrive directly.
- **Option A** — keep `#4E842D`, replace the lime with `#7CC142` (same hue, light
  register). Cost: hours. Result: one coherent brand, still a green ride-hailing app in a
  category with a green ride-hailing app.
- **Option B** — reposition on Nile blue `#1F6F8B` with desert amber `#C07A2A` and a warm
  limestone canvas. Cost: days plus store assets and marketing. Result: a palette no
  competitor in Egypt occupies, rooted in the city rather than in category convention.
- **Recommendation: B, if the launch date allows it; A otherwise, immediately.** The
  brief asks whether this looks like a product someone chose. Today the honest answer is
  no — the light theme is a safe green and the dark theme is a competitor's colour. A is
  a correction; B is a decision. But A shipped this week beats B debated for a month, and
  either is better than launching in inDrive's lime.

**Q2 — What is the product called?** *(blocks P0.1)*
The apps say GoDrive; notifications say Synaptic Go; the domain is `godrive.app`; the
studio is Synaptic.
- **Recommendation: GoDrive as the product, Synaptic as the studio.** Everything
  user-facing already says GoDrive, so this is the zero-cost direction. If the intent is
  genuinely to launch as "Synaptic Go", the change is much larger than
  `fcm_service.dart` — it is the launcher label, both localisations, the wordmark, the
  share copy and the domain — and it should be scoped deliberately rather than discovered
  at launch.

**Q3 — Arabic-Indic or Western numerals?** *(F-12-30)*
Currently Western everywhere, by default rather than decision. The code comment at
`location_service.dart:51` documents the example in Arabic-Indic while the implementation
at `:54` emits Western.
- **Recommendation: Western digits, and write it down.** Egyptian digital convention
  favours Western numerals, and fares and distances are scanned rather than read. But the
  decision should be explicit in the design system with a one-line rationale, so the next
  engineer does not "fix" it. If it changes, `money()` and every fare/distance/time
  surface change together — this is not a per-screen choice.

**Q4 — Should the admin console look like the apps?** *(shapes P1.1)*
- **Recommendation: shared spine, licensed divergence.** Identical brand colour, semantic
  colours, typeface and spacing grid — those are the brand and must be generated from one
  source. Licensed to diverge: radius (a data-dense console legitimately reads tighter
  than a touch product — but pick the two ramps deliberately rather than inheriting
  today's accident), density and type sizes, elevation (a console needs less), and
  component inventory. The current state is not divergence, it is drift: nobody chose
  `#6bb522` over `#4E842D` for the console: it happened.

**Q5 — Is dark mode a supported surface or a courtesy?** *(shapes priority of F-12-11/13/18)*
It is fully built, reachable and persisted in both apps, but seven screens break in it and
one of them is the SOS screen. Adoption is not instrumented, so nobody knows the cost.
- **Recommendation: instrument it first, then decide.** Add the `themeMode` resolution to
  session analytics before P1 planning. If dark is a meaningful share of sessions, the
  remaining breaks are P1, not P2. The SOS fix ships in P0 regardless — that one is not
  an adoption question.

**Q6 — Who owns the map style?** *(blocks P2.1)*
A branded map is design work, not a URL swap: road hierarchy, label language priority, POI
density thresholds and a night palette all have to be authored. There is no design owner
named anywhere in the repository.
- **Recommendation: treat the map as a design deliverable with a named owner and a
  budget.** It is 70% of the pixels in the product and currently the only major surface
  that is entirely un-designed. If no owner exists, P2.1 will not happen, and this is the
  single highest-leverage visual change available.
