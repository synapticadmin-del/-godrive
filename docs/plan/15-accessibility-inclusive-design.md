# 15 — Accessibility & Inclusive Design

> Track: B — Product surface & experience · Reviewer: `chat-20260801-1331-3e86` · Date: 2026-08-01 (UTC)
> Base commit reviewed: `697f4347045e67bc488a9c91631d6497ab6511d7` (`main`)

---

## 1. Scope

This document covers whether Synaptic Go can be operated by people with low vision, colour-vision deficiency, motor difficulty, vestibular sensitivity, or low literacy — and by a captain who can only look at the screen for one second. It covers the three surfaces that render to users: `packages/flutter_shared`, `apps/rider`, `apps/captain`, and `apps/admin`.

Concretely it covers: measured colour contrast across both themes in all three apps; touch-target geometry; screen-reader support (Flutter `Semantics` and admin ARIA); dynamic type and layout survival at 130% and 200% OS font scale; colour as a sole information carrier; keyboard and focus management in the admin console; motion sensitivity; driver glanceability; one-handed reach; form semantics; low-literacy affordances; and a repeatable assistive-technology test plan.

**What this document does not cover, and who owns it instead:**

| Out of scope here | Owner |
|---|---|
| Arabic copy quality, RTL mirroring correctness, string externalisation | **T14** — Localisation, RTL & Content Design |
| Animation *craft*, timing curves, perceived-performance strategy | **T13** — Motion & Micro-interactions (I cover only the reduced-motion *guard*, and hand the inventory over) |
| Building the shared animation library | **T28** — Motion Development |
| Design-token architecture and the design system itself | **T12** — Design System & Visual Language (I hand over the dead-token finding) |
| Systematically reconciling rider vs captain divergence | **T27** — Cross-App Parity (I log every divergence I hit) |
| Admin IA, ops workflow design | **T11** — Admin Console & Operations Tooling |
| Rider / captain journey completeness | **T09** / **T10** |

Accessibility here is not compliance theatre. Every finding below is also a plain usability defect under Egyptian conditions: a 3-year-old Android in direct Cairo sunlight, a captain glancing at a mounted phone in traffic, a 60-year-old with reading glasses who set their phone font to 200%.

---

## 2. What I actually read

65 files, 21,102 lines, downloaded at commit `697f4347` and read from disk with real line numbers. Every `path:line` in this document was resolved against that snapshot.

**Theme & tokens (read in full, and computed against):**

| File | Note |
|---|---|
| `packages/flutter_shared/lib/theme/app_theme.dart` (1,055 lines) | The Flutter palette. Carries inline contrast *claims* in comments (`// 4.50:1 on white`) which I verified numerically. |
| `apps/admin/src/design/tokens.ts` (249 lines) | Read in full. **Never imported by anything.** |
| `apps/admin/src/design/globals.css` (5.9 KB) | Read. **Never imported by anything.** |
| `apps/admin/src/styles.css` | The CSS variables that actually render. Contains the global focus ring at :135–138 and a `prefers-reduced-motion` block at :140. |
| `apps/admin/tailwind.config.js` | The live colour source for semantic/brand classes. |

**Flutter shared widgets (all 16 read):** `status_chip.dart`, `main_bottom_nav.dart`, `map_controls.dart`, `go_online_button.dart`, `navigation_button.dart`, `counter_offer_sheet.dart`, `vehicle_map_marker.dart`, `skeleton_loader.dart`, `go_date_field.dart`, `godrive_wordmark.dart`, `loading_overlay.dart`, `empty_state.dart`, `error_state.dart`, `offline_gate.dart`, `offline_guard_banner.dart`, `flutter_shared.dart`. These are where `Semantics` coverage should live; five of the seven `Semantics(` nodes in the entire product are here.

**Rider app:** `main.dart` (text-scale and reduced-motion behaviour), `screens/home/home_screen.dart` (1,400+ lines — primary surface), `home/vehicle_selector.dart`, `home/fare_estimate_sheet.dart`, `home/location_search_sheet.dart`, `home/travel_mode_bottom_bar.dart`, `trip/trip_screen.dart`, `trip/trip_chat_screen.dart`, `safety/sos_screen.dart`, `ride/captain_bids_sheet.dart`, `ride/rating_sheet.dart`, `login_screen.dart`, `splash_screen.dart`.

**Captain app:** `main.dart` (the text-scale clamp), `screens/home/offer_card.dart` (the safety-critical surface — read closely), `home/offer_card_entrance.dart`, `home/main_shell.dart`, `home/home_tab.dart`, `home/active_trip_panel.dart`, `home/available_trips_tab.dart`, `safety/sos_screen.dart`, `login_screen.dart`, `splash_screen.dart`.

**Admin console:** `main.tsx`, `App.tsx`, all 9 `components/ui/*`, `components/RejectionReasonModal.tsx`, all 4 `components/layout/*`, `pages/LoginPage.tsx`, `pages/CaptainVerificationPage.tsx` (1,000+ lines — the core ops workflow), `pages/TripsPage.tsx`, `pages/DashboardPage.tsx`, `design/ThemeContext.tsx`.

**Skimmed rather than read:** `packages/flutter_shared/lib/l10n/app_strings.dart` (184 KB) — grepped for accessibility-relevant strings only; it belongs to T14. `pages/AnalyticsPage.tsx`, `PricingPage.tsx`, `SettingsPage.tsx` — grepped for the mouse-only-control and focus patterns, not read line by line.

**Method note.** The contrast numbers in §4 are not eyeballed. I extracted every token from the files above and computed WCAG 2.x relative luminance and contrast ratios in a script, including alpha compositing for the night badge tokens whose backgrounds are 18% alpha over a dark panel. 84 foreground/background pairs measured; 38 fail. The replacement hex values in §6 were solved numerically against the same formula, not chosen by eye.

**Could not verify statically** (marked `needs-check` throughout): anything requiring a physical device — actual rendered text height in Cairo Arabic at 200%, TalkBack/VoiceOver announcement order, `BackdropFilter` effect on effective contrast, and whether Flutter's default 48dp `IconButton` tap target survives the app's theme overrides.

---

## 3. How it works today

### 3.1 There are four colour sources in the admin, and only two of them render

This is the single most consequential structural fact I found, so it goes first.

```
apps/admin/src/design/tokens.ts     ← 249 lines of tokens.  IMPORTED BY NOTHING.
apps/admin/src/design/globals.css   ← CSS variables.        IMPORTED BY NOTHING.
apps/admin/src/styles.css           ← CSS variables.        imported at main.tsx:8  ✅ renders
apps/admin/tailwind.config.js       ← brand/semantic hexes.  ✅ renders
```

`apps/admin/src/main.tsx:8` reads `import "./styles.css";` and nothing else. A grep across every `.ts`/`.tsx`/`.js` file for `design/tokens`, `designTokens`, or `globals.css` returns only `tokens.ts`'s own export statements.

This matters because **`tokens.ts` contains the WCAG-compliant palette and `tailwind.config.js` contains the failing one.** Someone did the accessibility remediation work — `tokens.ts:32` even documents it: `500: '#4e842d', // WCAG AA compliant GoDrive green (4.53:1 on white)`. I verified that value: it measures 4.50:1, essentially as claimed. But `tailwind.config.js:50` sets `primary.500` to `#6bb522`, which measures **2.54:1**, and that is the one that reaches the screen.

The same split runs through every semantic colour:

| Token | `tokens.ts` (dead) | measured | `tailwind.config.js` (live) | measured |
|---|---|---|---|---|
| success | `#4e842d` :57 | 4.50:1 ✅ | `#6bb522` :72 | 2.54:1 ❌ |
| warning | `#b45309` :63 | 5.02:1 ✅ | `#f59e0b` :77 | 2.15:1 ❌ |
| error | `#dc2626` :69 | 4.83:1 ✅ | `#ef4444` :82 | 3.76:1 ❌ |
| info | `#1d4ed8` :75 | 6.70:1 ✅ | `#6bb522` :87 | 2.54:1 ❌ |

So the answer to the brief's question — *"PR #? claimed WCAG AAA on admin — verify the claim numerically"* — is: **the claim is false, and it is false in an unusually specific way.** The compliant values exist in the repository. They are simply in a file that the build never reads. The admin light theme does not reach AAA; it does not reach AA; its primary button does not reach the 3:1 floor for a non-text UI element.

### 3.2 The Flutter light theme was actually fixed. The night theme was not.

`app_theme.dart` annotates several tokens with their measured ratio, and those annotations are honest:

| Token | Line | Comment claims | I measured | Verdict |
|---|---|---|---|---|
| `accent` `#A56A07` | :49 | 4.50:1 | 4.50:1 | accurate |
| `success` `#178841` | :59 | 4.53:1 | 4.53:1 | accurate |
| `warning` `#947105` | :60 | 4.54:1 | 4.54:1 | accurate |
| `danger` `#D92D20` | :61 | 4.53:1 | **4.83:1** | comment is wrong, but conservative |
| `sos` `#DC2626` | :62 | 4.83:1 | 4.83:1 | accurate |

That is a design system doing the right thing. The problem is that this care stopped at the light theme. The same tokens rendered on the night surfaces fail across the board, because a colour tuned for 4.5:1 against white cannot also clear 4.5:1 against `#1A1A1D`:

| Token on `nightPanel #1A1A1D` | Measured | Required |
|---|---|---|
| `primary` `#4E842D` | 3.86:1 | 4.5:1 |
| `success` `#178841` | 3.83:1 | 4.5:1 |
| `warning` `#947105` | 3.82:1 | 4.5:1 |
| `danger` `#D92D20` | 3.59:1 | 4.5:1 |
| `accent` `#A56A07` | 3.86:1 | 4.5:1 |
| `info` `#1D6DBE` | 3.29:1 | 4.5:1 |
| `sos` `#DC2626` on `nightBg` | 3.99:1 | 4.5:1 |

The night badge tokens are worse, and they are worse for a structural reason. `app_theme.dart:89–96` defines their backgrounds with an 18% alpha (`0x2E`) over the panel, then puts a light tint on top:

```dart
static const badgePendingTextNight = Color(0xFFFCD34D);
static const badgePendingBgNight  = Color(0x2EF59E0B);   // 18% alpha
```

Composited, that is light-on-light: **1.49:1**. The four night badges measure 1.49, 1.62, 1.98 and 1.62 — the worst contrast anywhere in the product, on the chips that carry document-verification and trip status.

### 3.3 Screen-reader support is close to absent in Flutter

Across roughly 16,500 lines of Dart there are **7** occurrences of `Semantics(` and **5** of `semanticLabel`. There are **zero** occurrences of `MergeSemantics`, `ExcludeSemantics`, `liveRegion`, `SemanticsService.announce`, `Semantics(sortKey:)`, and `IndexedSemantics`.

The seven that exist are decent work, and all but one are on navigation chrome:

| `path:line` | What it labels | Verdict |
|---|---|---|
| `main_bottom_nav.dart:478` | Rider crest button | useful |
| `main_bottom_nav.dart:514` | Captain crest destination, merges badge count | useful |
| `main_bottom_nav.dart:607` | The four nav tabs, with selected state | useful |
| `map_controls.dart:44` | `MapCircleButton`, `label: tooltip` | useful *when the caller passes a tooltip* |
| `go_online_button.dart:117` | Online toggle — `button`/`enabled`/`toggled`/label | the single most complete node in the product |
| `fare_estimate_sheet.dart:808` | Price stepper − / + | useful |
| `travel_mode_bottom_bar.dart:150` | Intercity mode tab | useful |

The five `semanticLabel` values all live inside that one price stepper.

What this leaves uncovered is the entire booking flow and the entire live-trip screen. The consequence is developed in §4 under F-15-05 and F-15-06.

### 3.4 The admin console is genuinely better — unevenly

The admin has 56 `aria-*` attributes and some real craftsmanship. `Input.tsx:31–37` is the best accessibility code in the repository, and it carries its own reasoning:

```tsx
// useId, not Math.random(): a random id is regenerated on every render, so
// the label's htmlFor and the aria-describedby targets pointed at a
// different element after each re-render — clicking a label stopped focusing
// its input and screen readers lost the error/hint association.
const generatedId = useId();
```

That is a real fix to a real bug, correctly explained. `Toast.tsx:63–65` has a proper `aria-live="polite"` region. `DataTable.tsx:251–266` gives clickable rows `tabIndex={0}` and Enter/Space handling. `styles.css:140` honours `prefers-reduced-motion`. `index.html` sets `lang="ar" dir="rtl"` at the document level.

But the quality is inconsistent per-component, and the components that handle the most consequential actions are the weakest. `LoginPage.tsx:57,60` uses raw `<input>` with an unassociated `<label>` — it does not use the good `Input` component sitting next to it. `RejectionReasonModal.tsx`, which performs an irreversible rejection of a captain's documents, contains **no `useEffect`, no `useRef`, no Escape handler, no `role="dialog"`, and no `aria-modal`** — a grep for all of those returns nothing.

### 3.5 Text scale is clamped in one app and not the other

`apps/captain/lib/main.dart:68–76` wraps the app in a `MediaQuery` that clamps the OS text scale, with an honest comment about why:

```dart
// A driver glances at this screen in traffic. Honour the
// system text scale so captains who need larger type get it,
// but clamp the top end so the map chrome and the offer card
// cannot blow their layouts apart.
textScaler: media.textScaler.clamp(minScaleFactor: 0.9, maxScaleFactor: 1.3),
```

The rider app has no such clamp — `apps/rider/lib/main.dart:64` has a `builder`, but it only sets status-bar icon brightness. So a user who sets 200% gets 130% in the captain app and 200% in the rider app. Neither is right: the captain app overrides the user's stated accessibility need, and the rider app honours it into layouts that were never built for it.

---

## 4. Findings

Severity: **S1** blocker (cannot go live) · **S2** major · **S3** moderate · **S4** polish.

| ID | Sev | Finding | Evidence (`path:line`) | Impact | Confidence |
|---|---|---|---|---|---|
| F-15-01 | S1 | Admin's AA-compliant palette is dead code; the failing palette renders. White label on primary button = 2.54:1 | `main.tsx:8`, `tokens.ts:32/57/63/69/75`, `tailwind.config.js:50/72/77/82/87` | Every primary action in the ops console is below the AA floor and below even the 3:1 UI floor | confirmed |
| F-15-02 | S1 | Keyboard-only ops user cannot open any captain's document group — the accordion header is a bare `<div onClick>` | `CaptainVerificationPage.tsx:752–754` | The console's core workflow is unreachable without a mouse. Verification cannot be completed | confirmed |
| F-15-03 | S1 | Flutter night theme fails AA on every semantic colour (3.29–3.99:1); night badges measure 1.49–1.98:1 | `app_theme.dart:36,49,59–63,89–96` vs `:127–128` | Night mode is the default in-car condition. Status and money text is unreadable for low-vision users | confirmed |
| F-15-04 | S1 | A blind rider cannot request a trip. Vehicle selection exposes no role and no selected state | `vehicle_selector.dart:344`, `:93` | The rider cannot tell what they selected or whether selection happened. Flow is not completable | confirmed |
| F-15-05 | S1 | Zero live-region announcements anywhere. Every realtime transition is silent — including *captain cancelled* | no `liveRegion`/`SemanticsService.announce` in repo; `trip_screen.dart:144,184`, `captain_bids_sheet.dart:104–106` | A blind rider is not told their captain arrived, or that they have been stranded | confirmed |
| F-15-06 | S1 | Rider's in-trip back and SOS buttons are unlabelled `GestureDetector`s at 44dp | `trip_screen.dart:282,286` → def at `:396–409` | The emergency control is invisible to screen readers and undersized for motor difficulty | confirmed |
| F-15-07 | S1 | `RejectionReasonModal` has no dialog role, no Escape, no focus management, no live error | `RejectionReasonModal.tsx:92–97,125–128,183–191` (no `useEffect`/`useRef`/`role=`/`aria-modal` in file) | An irreversible destructive decision is taken in a modal that AT cannot perceive and keyboard users cannot escape | confirmed |
| F-15-08 | S1 | Captain app caps text scale at 1.3×; a captain who set 200% gets 130% | `apps/captain/lib/main.dart:70–73` | The app overrides a declared accessibility need — WCAG 1.4.4 failure by construction | confirmed |
| F-15-09 | S1 | Captain splash runs five simultaneous looping animations with no reduced-motion guard | `captain/splash_screen.dart:43–47,231,371–411,417–445,450–487` | Vestibular-sensitive captains get radar sweep + scrolling road + drifting gradients + shimmer on every cold start | confirmed |
| F-15-10 | S1 | The map is a total screen-reader dead zone in both apps | `trip_screen.dart:254–274,327–393`; `home_screen.dart:590–641`; `vehicle_map_marker.dart:46–56` | No text alternative for captain position, route, ETA, or pickup/dropoff. WCAG 1.1.1 | confirmed |
| F-15-11 | S2 | Admin focus ring `#6bb522` = 2.54:1, below the 3:1 UI floor; `Button.tsx` then suppresses it and specifies no ring colour | `styles.css:135–138`; `Button.tsx:34` | Keyboard users cannot see where focus is on the app's most common control | confirmed |
| F-15-12 | S2 | Captain's three decision buttons are all sub-48dp: accept 46dp, counter 42dp, decline 42dp | `offer_card.dart:609,656,705,790,830` | A moving driver mis-taps the highest-stakes controls in the product | confirmed |
| F-15-13 | S2 | Meaning-critical addresses are `maxLines: 1` inside fixed-height boxes; they truncate at 1× and worsen with scale | `home_screen.dart:1343`; `fare_estimate_sheet.dart:499–505`; `offer_card.dart:572–581` | Riders confirm trips without being able to read the destination | confirmed |
| F-15-14 | S2 | `IndexedStack` keeps four inactive screens in the semantics tree with no `ExcludeSemantics` | `home_screen.dart:503–506` | A screen-reader user swipes through hundreds of off-screen nodes before reaching the pickup field | confirmed |
| F-15-15 | S2 | `QuickSearchModal` puts `role="dialog"`/`aria-modal`/`aria-label` on the backdrop, not the panel; no focus trap; no focus restore | `QuickSearchModal.tsx:63–68,79–86` | `aria-modal="true"` is asserted while Tab escapes freely — the app lies to assistive tech | confirmed |
| F-15-16 | S2 | Admin search results are non-interactive `<div>`s — no `tabIndex`, no `role`, no key handler | `QuickSearchModal.tsx:108,130,145` | Quick search is mouse-only | confirmed |
| F-15-17 | S2 | `LoginPage` uses raw inputs with unassociated labels and a silent error region | `LoginPage.tsx:47–52,57,60,73,76` | The first screen of the console is the least accessible one; failures are not announced | confirmed |
| F-15-18 | S2 | Rider home's location dot pulses continuously with no reduced-motion guard | `home_screen.dart:97–101,844–882` | Persistent looping motion on the app's landing surface | confirmed |
| F-15-19 | S2 | No skip link anywhere; every page load requires tabbing past 10+ nav items | grep across `apps/admin/src` returns nothing | Keyboard ops users pay a 10-tab tax on every navigation | confirmed |
| F-15-20 | S2 | Rider-side 44dp glass buttons and 46dp default map buttons | `home_screen.dart:1010–1032,1050–1083`; `map_controls.dart:20` | Below the 48dp target across both apps' map chrome | confirmed |
| F-15-21 | S2 | `star` `#F5B301` = 1.85:1 and `lightFaint` `#9CA3AF` = 2.54:1 on white | `app_theme.dart:50,107` | Ratings and secondary text are effectively invisible in sunlight | confirmed |
| F-15-22 | S2 | Captain's "call rider" control is an unlabelled `InkWell` + icon | `active_trip_panel.dart:384–392` | Mid-trip contact is unreachable by screen reader | confirmed |
| F-15-23 | S3 | Pickup/dropoff distinguished by colour-only dots in the fare journey card | `fare_estimate_sheet.dart:488–509`; tokens `app_theme.dart:155–156` | ~8% of Egyptian men cannot distinguish origin from destination there | confirmed |
| F-15-24 | S3 | `aria-sort` is on the sort `<button>`, not the `<th>` | `DataTable.tsx:221–222` | Sort state is misreported or ignored by AT | confirmed |
| F-15-25 | S3 | `TopBar` dropdowns have no Escape and no arrow-key handling | `TopBar.tsx:112–131,153–170` | Menus trap mouse-free users | confirmed |
| F-15-26 | S3 | No voice input for destination entry; no TTS anywhere | `location_search_sheet.dart:176` (keyboard-only `TextField`) | Low-literacy riders must type an address to book | confirmed |
| F-15-27 | S3 | Pagination `<select>` has no programmatic label | `Pagination.tsx:73–84` | Page-size control is unlabelled for AT | confirmed |
| F-15-28 | S3 | `text-tertiary` on `surface-tertiary` = 4.34:1; `pinPickup` = 2.62:1 as a UI element | `styles.css:34/23`; `app_theme.dart:155` | Narrow misses that fail on real panels | confirmed |
| F-15-29 | S3 | Empty state after filtering is not announced | `DataTable.tsx:191–199` | Silent "no results" for AT users | confirmed |
| F-15-30 | S4 | `role="navigation"` on `<aside>` overrides the native `complementary` role | `Sidebar.tsx:77–78` | Semantically incorrect, functionally survivable | confirmed |
| F-15-31 | S4 | `role="alert"` on inline validation re-announces on every keystroke | `Input.tsx:104` | Chatty; `aria-live="polite"` would be calmer | confirmed |
| F-15-32 | S4 | `letterSpacing: -0.5` and `height: 1.1` on the money style at 12.5sp | `app_theme.dart:287–288`; used at `vehicle_selector.dart:396` | Possible Arabic numeral crowding at small sizes | needs-check |

### The S1 findings, in prose

**F-15-01 — The admin's accessibility fix exists and is not plugged in.**
This is the cheapest S1 in the document to close and the most embarrassing to leave open. `main.tsx:8` imports only `styles.css`. `design/tokens.ts` and `design/globals.css` are unreferenced. The consequence is that `tokens.ts:32`'s carefully-derived `#4e842d` — annotated in-file as "WCAG AA compliant … (4.53:1 on white)", and which I measure at 4.50:1 — never renders, while `tailwind.config.js:50`'s `#6bb522` at **2.54:1** does. Every `bg-primary-500` button with a white label in the console sits at 2.54:1 against a required 4.5:1. `warning-main #f59e0b` is worse at 2.15:1. Someone has already done this work; the build simply does not consume it. Note the direction of the irony: the admin's **dark** theme passes nearly every pair I measured (`text-link` 5.21:1, `success` 7.44:1, `warning` 8.81:1). It is the default light theme that is broken.

**F-15-02 — A keyboard-only operator cannot verify a single captain.**
`CaptainVerificationPage.tsx:752–754`:

```tsx
<div
  onClick={() => toggleCaptainAccordion(group.captainId)}
  className="p-5 flex ... cursor-pointer select-none ..."
>
```

No `tabIndex`, no `role="button"`, no `onKeyDown`. This element is not in the tab order at all, and it is the only way to reveal a captain's documents. The chevron `<button>` nested inside at `:848` is focusable but relies on the parent `div`'s handler, which keyboard events never reach. So the walkthrough is: log in (works, with unassociated labels), navigate the sidebar (works — real `NavLink`s), then stop. The user cannot open any group, cannot see any document, cannot approve or reject anything. Everything downstream — the approve/reject buttons at `:982–994`, which are real `<button>`s — is correct and unreachable. This is one attribute away from working, and it currently blocks the console's entire reason for existing.

**F-15-03 — Night mode is where the app is actually used, and it is the untested theme.**
The light palette was tuned with real rigour (§3.2). The night palette was not tuned at all — the same hexes are simply rendered on `#0E0E10`/`#1A1A1D`. Every semantic colour lands between 3.29:1 and 3.99:1. `sos #DC2626` on `nightBg` is 3.99:1: the emergency colour misses the floor. The night badges are the worst artefact in the product at 1.49–1.98:1, and they fail for a fixable structural reason — `app_theme.dart:90/92/94/96` build the chip background from an 18% alpha wash (`0x2E`) over a dark panel, then place a light tint on top of it, which is light-on-light by construction. Solid dark backgrounds fix this completely (§6, P0.2).

**F-15-04 / F-15-05 / F-15-10 — A blind rider cannot book a ride, and would not be told if they were stranded.**
Walking the flow in source order: destination entry (`location_search_sheet.dart`) is *partially* usable — the `TextField` hint is exposed and result rows read their visible text, though the clear button at `:193` has no `tooltip` or `semanticLabel`. Then it breaks. `vehicle_selector.dart:344` builds each vehicle class as a raw `GestureDetector` wrapping an `AnimatedContainer`; the accessible node is just the concatenated text ("اقتصادي 45 ج.م") with **no button role and no selected state**. The rider cannot tell which class is active, cannot confirm a tap registered, and cannot distinguish the disabled Freight/Tuktuk chips (`Opacity(0.42)` with no `ExcludeSemantics`) from live ones. The fare sheet that follows is the *best*-instrumented screen in the app — the price stepper at `:808` is properly labelled — but the flow has already failed a step earlier.

Then it compounds. With no `liveRegion` and no `SemanticsService.announce` anywhere, every realtime transition renders silently through `setState`: bid arrives (`captain_bids_sheet.dart:104–106`), captain assigned, **captain arrived**, trip started, trip completed, and **captain cancelled** (`trip_screen.dart:144,184`). The last one is the one to hold in mind: a blind rider stands at the kerb, the captain cancels, the screen updates, and the phone says nothing. They have been stranded and the app knows and does not tell them.

And the map — where "where is my captain" actually lives — produces no semantic nodes at all. `flutter_map`'s `Marker` and `PolylineLayer` emit nothing, and the app adds nothing: not for the captain's position (`trip_screen.dart:383–393`), the route (`:254–274`), pickup (`:327–343`), dropoff (`:346–376`), or nearby vehicles (`home_screen.dart:620–634`). There is no ETA text alternative either; `_assignedContent` shows a static "الكابتن في الطريق إليك" with no number.

**F-15-06 — The emergency control is the least accessible control.**
`trip_screen.dart:396–409`:

```dart
Widget _circleButton(IconData icon, VoidCallback onTap, {Color? color}) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      width: 44, height: 44,
      ...
      child: Icon(icon, color: ..., size: 22),
```

No `Semantics`, no `tooltip`, no text. This one helper renders both the back button (`:282`) and the in-trip SOS button (`:286`). So the SOS control announces as nothing, is 44dp against a 48dp floor, and — per §3 and the reach analysis — sits in the **top-right corner**, the hardest point on a 6.7-inch screen for a one-handed user to reach, precisely when the user is panicking. Note the contrast with the captain's map SOS, which goes through `MapCircleButton` and therefore *does* get `Semantics(button: true, label: tooltip)` at `map_controls.dart:44` and is explicitly sized to 50dp. The rider side simply did not get the same treatment.

**F-15-07 — The destructive modal is the unguarded one.**
A grep of `RejectionReasonModal.tsx` for `useEffect|useRef|Escape|role=|aria-modal` returns nothing at all. Focus is never moved in (except an `autoFocus` on the textarea, and only when the custom preset is chosen at `:189`), never trapped, never restored. There is no Escape handler — a keyboard user who opens it must Tab past six preset buttons to reach Cancel. The error at `:125–128` renders without `role="alert"`, so a failed submit is silent. Compare `QuickSearchModal`, which at least *attempts* ARIA (albeit on the wrong node, F-15-15), and `ZoomablePreviewModal` at `CaptainVerificationPage.tsx:256–262`, which is a third pattern with none. Three modals, three different levels of support, and the one performing an irreversible action against a captain's livelihood has the least.

**F-15-08 — The captain app overrides the user's declared need.**
`main.dart:70–73` clamps to `maxScaleFactor: 1.3`. The intent is defensible and documented — a blown-out offer card in traffic is its own safety problem. But the mechanism is a WCAG 1.4.4 failure: a captain who set 200% receives 130%, i.e. 65% of what they asked for, with no way to opt out. The right fix is not to raise the clamp blindly but to make the layouts survive so the clamp can be removed (§6, P1.2). Meanwhile the rider app clamps nothing, which is the correct *policy* attached to layouts that cannot honour it — `_LocationField` at `home_screen.dart:1343` is a fixed `height: 56` holding `maxLines: 1` address text, and `fare_estimate_sheet.dart:499–505` truncates pickup and dropoff in the confirmation card. So at 200% the rider is asked to confirm a trip whose addresses they cannot read (F-15-13).

**F-15-09 — Five looping animations, no guard.**
The product does know how to do this: `skeleton_loader.dart:58`, `rider/splash_screen.dart:73–82`, `rider/login_screen.dart:100–104`, and `rider/main.dart:141–144` all check `MediaQuery.disableAnimations` correctly, and the admin honours `prefers-reduced-motion` at `styles.css:140`. The captain splash simply never got the treatment: a single `_motion` controller at `:43–47` is started with `.repeat()` and drives radar rings (`:417–445`), scrolling road dashes (`:450–487`), a drifting gradient backdrop (`:371–411`) and a logo glow, plus an independently repeating `.shimmer()` on the wordmark at `:231`. None consult `disableAnimations`. The rider's home-screen location dot (`home_screen.dart:97–101`) is the second offender and arguably the more chronic one, since it loops for the entire session rather than a few seconds.

---

## 5. Benchmark gap

**WCAG 2.2 AA — the specific criteria currently failing:**

| SC | Name | Where it fails |
|---|---|---|
| 1.1.1 | Non-text Content | Map layers, icon-only controls (F-15-06, F-15-10, F-15-22) |
| 1.3.1 | Info and Relationships | `LoginPage` labels, Pagination select, `RejectionReasonModal` textarea (F-15-17, F-15-27) |
| 1.4.1 | Use of Colour | Journey card endpoint dots (F-15-23) |
| 1.4.3 | Contrast (Minimum) | 38 measured pairs (F-15-01, F-15-03, F-15-21, F-15-28) |
| 1.4.4 | Resize Text | Captain 1.3× clamp (F-15-08) |
| 1.4.10 | Reflow | Fixed-height boxes clipping scaled text (F-15-13) |
| 1.4.11 | Non-text Contrast | Focus ring 2.54:1, borders 1.23:1, `pinPickup` 2.62:1 (F-15-11, F-15-28) |
| 2.1.1 | Keyboard | Accordion, search results, dropdowns (F-15-02, F-15-16, F-15-25) |
| 2.1.2 | No Keyboard Trap | `RejectionReasonModal` has no escape route (F-15-07) |
| 2.3.3 | Animation from Interactions | Captain splash, rider pulse (F-15-09, F-15-18) |
| 2.4.1 | Bypass Blocks | No skip link (F-15-19) |
| 2.4.3 | Focus Order | No focus restore in any modal (F-15-07, F-15-15) |
| 2.4.7 | Focus Visible | `Button.tsx:34` suppresses the outline (F-15-11) |
| 2.5.8 | Target Size (Minimum) | 42–46dp decision buttons (F-15-12, F-15-20) |
| 4.1.2 | Name, Role, Value | Vehicle selector, SOS, modals (F-15-04, F-15-06, F-15-07) |
| 4.1.3 | Status Messages | No live regions anywhere in Flutter (F-15-05) |

**Against Uber** *(confident — publicly documented accessibility programme, VoiceOver/TalkBack-complete booking, and a published commitment to screen-reader support)*: Uber's ride request flow is operable end to end with a screen reader, vehicle options are exposed as labelled selectable options with state, and trip status changes are announced. Synaptic Go fails at vehicle selection and announces nothing thereafter. Uber also ships driver-side large-target design; Synaptic Go's captain decision buttons are 42–46dp.

**Against Careem** *(confident on the regional point — Careem operates across MENA with Arabic-first RTL products and documents accessibility support)*: the relevant benchmark is that Arabic-first does not excuse weaker semantics. Synaptic Go's RTL setup is sound at the document level (`index.html` `lang="ar" dir="rtl"`), which is a real strength; the gap is semantic, not directional.

**Against inDrive** *(assumed — I have not verified inDrive's accessibility implementation)*: the price-negotiation model makes announcements *more* important than for a fixed-fare competitor, because offers arrive asynchronously and expire. Synaptic Go's `offer_card.dart:69` gives the captain a 15-second window and the rider's bid list polls every 5s (`captain_bids_sheet.dart:75`) — both are time-limited interactions delivered with no announcement, which is a harder problem than Uber's flow, not an easier one.

**The practical benchmark from the brief — can a 60-year-old with reading glasses and a 3-year-old Android book a ride without help?**

Partially, and worse than the code intends. They can complete the flow if they can read the screen. At 130% they will find the vehicle-class price labels tight inside `vehicle_selector.dart:326–328`'s fixed 112dp and the category chips clipped inside `:183–188`'s 62dp. At 200% the addresses truncate in both the home field and the fare confirmation, so they will tap "request" without having read their destination. If they use night mode — likely, given evening travel — status and fare text sits at 3.3–4.0:1. Rating stars at 1.85:1 are invisible to them. So: they will probably get a car, and they will not be confident about where it is taking them or what it costs. That is the honest answer.

---

## 6. Improvement plan

### P0.1 — Wire the admin to its own compliant palette

- **Goal.** Every admin surface meets AA without a redesign, using values already written and reviewed in this repository.
- **Design.** Make `tailwind.config.js` and `styles.css` the single source of truth and correct their values; then either delete `design/tokens.ts` + `design/globals.css` or convert `tokens.ts` into the generator that emits the CSS variables. Do not leave three files. The exact substitutions, each solved numerically against white and verified after substitution:

  | Token | `path:line` | Current | Measured | Replace with | Achieves |
  |---|---|---|---|---|---|
  | `primary.500` | `tailwind.config.js:50` | `#6bb522` | 2.54:1 | **`#4E8419`** | 4.51:1 |
  | `success.main` | `tailwind.config.js:72` | `#6bb522` | 2.54:1 | **`#4E8419`** | 4.51:1 |
  | `warning.main` | `tailwind.config.js:77` | `#f59e0b` | 2.15:1 | **`#A56A07`** | 4.50:1 |
  | `error.main` | `tailwind.config.js:82` | `#ef4444` | 3.76:1 | **`#D83D3D`** | 4.51:1 |
  | `info.main` | `tailwind.config.js:87` | `#6bb522` | 2.54:1 | **`#4E8419`** | 4.51:1 |
  | `text.link` | `tailwind.config.js:42` | `#579619` | 3.63:1 | **`#4D8516`** | 4.51:1 |
  | `border.focus` | `tailwind.config.js:33`, `styles.css:136` | `#6bb522` | 2.54:1 | **`#62A61F`** | 3.00:1 (UI floor) |
  | `--border-primary` | `styles.css:28` | `#e2e8f0` | 1.23:1 | **`#91959A`** | 3.00:1 (UI floor) |
  | `--text-tertiary` | `styles.css:34` | `#64748b` | 4.34:1 on `#F1F5F9` | **`#627188`** | 4.51:1 |
  | `--text-disabled` | `styles.css:37` | `#94a3b8` | 2.56:1 | **`#6D7887`** | 4.50:1 |

  Note that `#4E8419` is within rounding distance of Flutter's `primary #4E842D`. Adopting it converges the admin and the apps on one brand green that is AA-safe in both — worth flagging to **T12**.
  Keep the dark theme as-is; it already passes. Verify the light-theme *disabled* state separately: `#6D7887` is a real colour change and disabled controls must still read as disabled by more than contrast alone.
- **Files to change.** `apps/admin/tailwind.config.js`, `apps/admin/src/styles.css`, delete-or-rewire `apps/admin/src/design/tokens.ts` and `apps/admin/src/design/globals.css`.
- **DB.** none. **API contract.** none.
- **Effort.** S. **Risk.** Purely visual; the brand green darkens perceptibly. Rollback is a one-commit revert. Get design sign-off on `#4E8419` before merge.
- **Acceptance criteria.** Automated contrast check over the rendered token set reports zero AA failures in light and dark. No component references `design/tokens.ts`.
- **Tests.** A unit test that walks the exported token map and asserts ratios (the script used for this audit can be committed as `apps/admin/scripts/contrast-check.mjs`); axe-core in CI on five representative pages.

### P0.2 — Re-derive the Flutter night palette; make the night badges solid

- **Goal.** Night mode meets AA on text and UI, including the status badges.
- **Design.** Night tokens need their own values rather than the light values reused. Solved substitutions, measured on `nightPanel #1A1A1D` (or `nightBg #0E0E10` where noted):

  | Token | `path:line` | Current | Measured | Night value | Achieves |
  |---|---|---|---|---|---|
  | `primary` | `app_theme.dart:36` | `#4E842D` | 3.86:1 | **`#5D8F3F`** | 4.50:1 |
  | `success` | `:59` | `#178841` | 3.83:1 | **`#2E9453`** | 4.50:1 |
  | `warning` | `:60` | `#947105` | 3.82:1 | **`#9E7E1C`** | 4.50:1 |
  | `danger` | `:61` | `#D92D20` | 3.59:1 | **`#E05247`** | 4.51:1 |
  | `accent` | `:49` | `#A56A07` | 3.86:1 | **`#AD771D`** | 4.50:1 |
  | `info` | `:63` | `#1D6DBE` | 3.29:1 | **`#4385C9`** | 4.50:1 |
  | `sos` (on `nightBg`) | `:62` | `#DC2626` | 3.99:1 | **`#E03D3D`** | 4.50:1 |
  | `nightBorder` | `:133` | `#34343B` | 1.56:1 | **`#5E5E64`** | 3.00:1 |
  | `darkFaint` | `:118` | `#6B7280` | 3.87:1 | **`#767D8A`** | 4.50:1 |
  | `darkBorder` | `:119` | `#334155` | 1.81:1 | **`#566172`** | 3.00:1 |

  For the badges, drop the alpha wash entirely and use solid dark backgrounds — this is the change that moves 1.49:1 to 9.62:1:

  | Badge | Text (keep) | Current bg | Replace bg | Achieves |
  |---|---|---|---|---|
  | pending | `#FCD34D` `:89` | `0x2EF59E0B` `:90` | **`#3A2A05`** | 9.62:1 |
  | approved | `#86EFAC` `:91` | `0x2E22C55E` `:92` | **`#0C2E18`** | 10.54:1 |
  | stopped | `#FCA5A5` `:93` | `0x2EEF4444` `:94` | **`#3A1212`** | 8.68:1 |
  | completed | `#86EFAC` `:95` | `0x2422C55E` `:96` | **`#0C2E18`** | 10.54:1 |

  Also fix in light theme: `star #F5B301` → **`#997001`** (1.85 → 4.51:1); `lightFaint #9CA3AF` → **`#727780`** (2.54 → 4.50:1); `lightMuted` on `lightBg` → **`#6B727F`** (4.48 → 4.51:1); `lightBorder #E6E8EB` → **`#949597`** for UI use (1.23 → 3.00:1); `pinPickup #12B76A` → **`#11AB63`** (2.62 → 3.00:1).
- **Files to change.** `packages/flutter_shared/lib/theme/app_theme.dart` only.
- **DB.** none. **API contract.** none.
- **Effort.** S. **Risk.** `star` and `lightFaint` change visibly; `lightBorder` at 3:1 will read much heavier and should be applied only where the border is a *meaningful* UI boundary, not to decorative hairlines. Split the token if needed.
- **Acceptance criteria.** A Dart test iterates the token pairs and asserts ≥4.5:1 (text) / ≥3:1 (UI) in both themes. Zero night pairs below floor.
- **Tests.** `packages/flutter_shared/test/theme_contrast_test.dart`, run in CI.

### P0.3 — Make the captain-verification accordion keyboard-operable

- **Goal.** A keyboard-only operator can complete a full verification.
- **Design.** Convert `CaptainVerificationPage.tsx:752` from `<div onClick>` to a real `<button type="button">` (or add `role="button"`, `tabIndex={0}`, and an Enter/Space `onKeyDown`), add `aria-expanded={isOpen}` and `aria-controls` pointing at the panel id, and remove the now-redundant inner chevron button from the tab order with `aria-hidden`/`tabIndex={-1}`. While here, sweep the other mouse-only controls: `QuickSearchModal.tsx:108,130,145` and `Toast.tsx:147`.
- **Files to change.** `apps/admin/src/pages/CaptainVerificationPage.tsx`, `components/ui/QuickSearchModal.tsx`, `components/ui/Toast.tsx`.
- **DB.** none. **API contract.** none.
- **Effort.** S. **Risk.** Low; button default styling must be reset to preserve the current layout.
- **Acceptance criteria.** With the mouse physically unplugged, an operator can log in, open a captain group, preview a document, approve one and reject another with a reason.
- **Tests.** Playwright keyboard-only journey; axe-core assertion of zero `nested-interactive`/`interactive-supports-focus` violations on the page.

### P0.4 — Fix the focus indicator, then make it universal

- **Goal.** Focus is always visible and always meets 3:1.
- **Design.** Set the global ring to `#62A61F` at `styles.css:136` (3.00:1 — or go darker for headroom). Then fix `Button.tsx:34`, which currently sets `focus:outline-none focus-visible:ring-2` **with no ring colour**, so it both suppresses the global outline and falls back to Tailwind's default translucent blue. Add an explicit `focus-visible:ring-[#62A61F]`. Audit every other `focus:outline-none` in the codebase for the same pattern, notably `QuickSearchModal.tsx:85`.
- **Files to change.** `apps/admin/src/styles.css`, `components/ui/Button.tsx`, `components/ui/QuickSearchModal.tsx`, plus any component the audit turns up.
- **Effort.** S. **Risk.** none meaningful.
- **Acceptance criteria.** Tabbing through every page shows a continuously visible indicator; no element relies on the browser default.
- **Tests.** Playwright walks the tab order per page and asserts a computed outline/ring on each stop.

### P0.5 — Give the rider's SOS and back buttons names and legal targets

- **Goal.** The emergency control is perceivable, reachable, and correctly sized.
- **Design.** Rewrite the `_circleButton` helper at `trip_screen.dart:396` to accept a required `semanticLabel`, wrap its child in `Semantics(button: true, label: ...)`, and raise the box from 44dp to 48dp. Better: replace the bespoke helper with the shared `MapCircleButton`, which already does the right thing at `map_controls.dart:44` and is what the captain app uses. This closes F-15-06 and part of F-15-20 with one change, and removes a duplicated widget — relevant to **T27**.
- **Files to change.** `apps/rider/lib/screens/trip/trip_screen.dart`; possibly `packages/flutter_shared/lib/widgets/map_controls.dart` to accept the needed variants.
- **Effort.** S. **Risk.** Minor visual shift in the trip header.
- **Acceptance criteria.** TalkBack announces "استغاثة طارئة، زر" on the SOS control; both buttons measure ≥48dp.
- **Tests.** Flutter `semantics` widget test asserting the labels exist; golden test for the header.

### P0.6 — Announce trip state changes

- **Goal.** A rider who cannot see the screen learns that their captain arrived, and learns if they were abandoned.
- **Design.** Add a small `announce(BuildContext, String)` helper in `flutter_shared` wrapping `SemanticsService.announce` with the correct `TextDirection`. Call it from the single place each transition lands — `trip_screen.dart:144` and `:184` for status, `captain_bids_sheet.dart:104` for new bids. Mark the status badge `Semantics(liveRegion: true)` at `trip_screen.dart:412` so passive exploration also picks it up. Prioritise, in order: **cancelled**, **arrived**, new bid, assigned, started, completed. Strings go through the existing localisation layer (coordinate with **T14**).
- **Files to change.** new `packages/flutter_shared/lib/a11y/announce.dart`; `apps/rider/lib/screens/trip/trip_screen.dart`; `apps/rider/lib/screens/ride/captain_bids_sheet.dart`; the captain equivalents in `active_trip_panel.dart`.
- **DB.** none. **API contract.** none — this consumes existing WS/poll events.
- **Effort.** M. **Risk.** Over-announcing is a real failure mode; debounce and never announce captain-location ticks.
- **Acceptance criteria.** With TalkBack on, each of the six transitions produces exactly one spoken announcement.
- **Tests.** Widget tests driving a fake trip stream and asserting on `SemanticsService` calls.

### P0.7 — Guard the captain splash and the rider pulse

- **Goal.** No unavoidable looping motion for a user who asked for less.
- **Design.** The pattern already exists at `rider/splash_screen.dart:73–82`; copy it. In `captain/splash_screen.dart`, read `MediaQuery.disableAnimations` in `didChangeDependencies`, and when true do not `.repeat()` the `_motion` controller (`:47`), drop the `.shimmer()` at `:231`, and render the final frame statically. In `home_screen.dart:97–101`, do not start `_pulseController` when reduced motion is set. Then hand the full unguarded-animation inventory to **T13**/**T28**.
- **Files to change.** `apps/captain/lib/screens/splash_screen.dart`, `apps/rider/lib/screens/home/home_screen.dart`.
- **Effort.** S. **Risk.** none.
- **Acceptance criteria.** With "Remove animations" enabled in Android developer settings, the captain splash is static and the rider location dot does not pulse.
- **Tests.** Widget test with `MediaQueryData(disableAnimations: true)` asserting controllers are not animating.

### P0.8 — Make `RejectionReasonModal` a real dialog

- **Goal.** An irreversible decision is taken in a modal that AT can perceive and keyboard users can leave.
- **Design.** Build one `<Modal>` primitive and adopt it in all three places rather than fixing this file alone. It must: render `role="dialog" aria-modal="true"` on the **panel**, take an `aria-labelledby` pointing at the title, move focus to the first control on open, trap Tab, restore focus to the trigger on close, and close on Escape. Then migrate `RejectionReasonModal.tsx:92`, `QuickSearchModal.tsx:63` (moving its ARIA off the backdrop — F-15-15), and `ZoomablePreviewModal` at `CaptainVerificationPage.tsx:256`. Add `role="alert"` to the rejection error at `:125` and bind the textarea at `:183–191` to its label.
- **Files to change.** new `apps/admin/src/components/ui/Modal.tsx`; the three modal sites.
- **Effort.** M. **Risk.** Focus-trap regressions; ship behind a per-modal migration rather than all at once.
- **Acceptance criteria.** For each modal: Escape closes, Tab cycles inside, focus returns to the trigger, and a screen reader announces the dialog by name.
- **Tests.** Playwright per modal; axe-core zero violations.

### P1.1 — Raise every decision target to 48dp

- **Goal.** No safety-relevant control below the Material floor.
- **Design.** `offer_card.dart` — accept `:609` 46→48, counter `:656` and decline `:705` 42→48, and the same in the bid-sent state at `:790,830`. `map_controls.dart:20` — default `size` 46→48. `home_screen.dart:1010,1050` — glass buttons 44→48. Introduce `AppTokens.tapTarget` (already used correctly at `active_trip_panel.dart:571`) as the only permitted source for these values and lint against literals.
- **Files to change.** `apps/captain/lib/screens/home/offer_card.dart`, `packages/flutter_shared/lib/widgets/map_controls.dart`, `apps/rider/lib/screens/home/home_screen.dart`.
- **Effort.** S. **Risk.** The offer card is dense; +6dp on two buttons may force a reflow. Verify on a 360dp-wide device.
- **Acceptance criteria.** No interactive box below 48dp on home, trip, offer, or SOS screens.
- **Tests.** A widget test walking the tree and asserting rendered sizes of tappable nodes.

### P1.2 — Survive 200%, then remove the captain clamp

- **Goal.** Honour the user's OS setting instead of overriding it.
- **Design.** Two steps, in order. First make layouts elastic: replace fixed heights with `min`-constraints on `home_screen.dart:1343` (56dp field), `vehicle_selector.dart:183–188` (62dp strip) and `:326–328` (112dp cards); wrap bare `Text` in `Row`s with `Expanded` (`trip_screen.dart:665–682`, `:734–739`); and allow addresses two lines before ellipsising at `home_screen.dart:1343`, `fare_estimate_sheet.dart:499–505`, `offer_card.dart:572–581`. Only then raise `main.dart:70–73` from 1.3 to at least 2.0. Keep the scoped exceptions — `go_date_field.dart:175` and `godrive_wordmark.dart:63` are both justified and documented.
- **Files to change.** as listed, plus `apps/captain/lib/main.dart`.
- **Effort.** L. **Risk.** The highest-risk item here; the offer card must stay glanceable at 200%, which may mean a distinct large-text layout rather than pure reflow.
- **Acceptance criteria.** At 200% on a 360×640 device, no `RenderFlex` overflow on splash, login, home, fare, trip, offer, SOS — and full pickup/dropoff addresses remain readable.
- **Tests.** Golden tests at 1.0/1.3/2.0 for the seven screens.

### P1.3 — Add redundant cues wherever colour carries meaning

- **Goal.** No information conveyed by hue alone.
- **Design.** `fare_estimate_sheet.dart:488–509` — give the origin/destination dots distinct glyphs (`trip_origin` vs `place`), matching what `home_screen.dart:1169–1190` already does correctly. Make `StatusChip`'s `icon` parameter required at `status_chip.dart:49` so no caller can ship a colour-only chip. In `offer_card.dart:509–540`, raise the 10.5sp from/to labels — they are currently the only non-colour cue and they are the smallest text on the card.
- **Files to change.** `apps/rider/lib/screens/home/fare_estimate_sheet.dart`, `packages/flutter_shared/lib/widgets/status_chip.dart`, `apps/captain/lib/screens/home/offer_card.dart`.
- **Effort.** S. **Risk.** Making `icon` required is a breaking signature change; sweep call sites.
- **Acceptance criteria.** A greyscale screenshot of every status surface remains unambiguous.
- **Tests.** Golden tests rendered through a greyscale filter.

### P1.4 — Name the booking flow for screen readers

- **Goal.** A blind rider can complete a booking.
- **Design.** `vehicle_selector.dart:344` and `:93` — wrap each option in `Semantics(button: true, inMutuallyExclusiveGroup: true, selected: isSelected, label: '<class>، <price>')` and wrap disabled chips in `ExcludeSemantics`. `home_screen.dart:503` — wrap inactive `IndexedStack` children in `ExcludeSemantics` (F-15-14). `home_screen.dart:1336` — give `_LocationField` a `button: true` role and a hint. `location_search_sheet.dart:193` — label the clear button. `active_trip_panel.dart:384` — label "call rider". Then add minimum map alternatives: a `Semantics` summary node over the map exposing captain distance/ETA and route length, updated with the same data that drives the visuals.
- **Files to change.** `vehicle_selector.dart`, `home_screen.dart`, `location_search_sheet.dart`, `active_trip_panel.dart`, `trip_screen.dart`.
- **Effort.** M. **Risk.** Low. Over-labelling the map could get chatty — one summary node, not one per marker.
- **Acceptance criteria.** The full booking flow is completable with TalkBack and with VoiceOver, verified by a human.
- **Tests.** Semantics widget tests per screen; the manual pass in P2.2.

### P1.5 — Admin structure: skip link, form bindings, table semantics

- **Goal.** Close the remaining S2/S3 admin items as one sweep.
- **Design.** Add a skip link as the first focusable element in `Layout.tsx` targeting the existing `<main>` at `:14`. Migrate `LoginPage.tsx:57–76` onto the accessible `Input` component and give the error at `:47` a `role="alert"`. Move `aria-sort` from the button to the `<th>` in `DataTable.tsx:221`. Add `role="status"` to the empty state at `:191`. Label the Pagination `<select>` at `:73`. Add Escape and arrow-key handling to the `TopBar` dropdowns at `:112,153`. Change `Sidebar.tsx:77` from `<aside role="navigation">` to `<nav>`. Soften `Input.tsx:104` from `role="alert"` to `aria-live="polite"` for inline validation.
- **Effort.** M. **Risk.** Low.
- **Acceptance criteria.** axe-core reports zero serious/critical violations across all admin pages.
- **Tests.** axe-core in CI on every route.

### P2.1 — Voice destination entry and a low-literacy path

- **Goal.** A rider who reads slowly can still book.
- **Design.** Add `speech_to_text` behind a microphone button in `location_search_sheet.dart:176`, with Egyptian Arabic as the primary locale. Pair every icon-only control on the primary surfaces with a visible text label. Promote saved places (`saved_destinations_sheet.dart`) so repeat trips need no reading at all — this is the highest-leverage low-literacy affordance and it mostly exists already.
- **Effort.** M. **Risk.** Arabic dialect STT accuracy varies; keep typing as a first-class path, never a fallback-only.
- **Acceptance criteria.** A destination can be set end to end without typing.
- **Tests.** Manual, with Egyptian Arabic speakers.

### P2.2 — Standing assistive-technology test plan

- **Goal.** A repeatable checklist, not a one-off audit.
- **Design.**
  - **Every PR (automated, CI):** axe-core on all admin routes; the contrast unit tests from P0.1/P0.2; a golden-test suite at text scales 1.0/1.3/2.0; a lint rule rejecting interactive widgets with no accessible name.
  - **Every release (manual, 45 min):** TalkBack on a low-end Android (Samsung A-series, Android 12) — complete a rider booking and a captain accept; VoiceOver on the oldest supported iPhone — same two flows; keyboard-only pass through admin captain-verification; 200% font scale on the seven core screens; greyscale-mode pass for colour-only meaning; "remove animations" pass on both splashes.
  - **Quarterly:** an outdoor sunlight legibility session with a mounted phone; a session with at least one low-vision and one older user; re-run the full contrast sweep after any brand change.
  - **Device matrix:** low-end Android 12 (the realistic floor), mid-range Android 14, oldest supported iPhone. Test in Arabic RTL as the default, not as a variant.
- **Effort.** M to set up, S per release. **Risk.** Manual passes get skipped under deadline; make the 45-minute release pass a named release-checklist item with an owner.
- **Acceptance criteria.** The checklist runs for two consecutive releases without being waived.

---

## 7. Phasing

| Item | Phase | Effort | Owner type |
|---|---|---|---|
| P0.1 Wire admin to compliant palette | P0 | S | admin |
| P0.2 Night palette + solid badges | P0 | S | Flutter |
| P0.3 Keyboard-operable accordion | P0 | S | admin |
| P0.4 Focus indicator | P0 | S | admin |
| P0.5 SOS/back label + 48dp | P0 | S | Flutter |
| P0.6 Announce trip state changes | P0 | M | Flutter |
| P0.7 Guard splash + pulse animations | P0 | S | Flutter |
| P0.8 Real modal primitive | P0 | M | admin |
| P1.1 48dp decision targets | P1 | S | Flutter |
| P1.2 Survive 200%, drop the clamp | P1 | L | Flutter |
| P1.3 Redundant non-colour cues | P1 | S | Flutter |
| P1.4 Name the booking flow | P1 | M | Flutter |
| P1.5 Admin structure sweep | P1 | M | admin |
| P2.1 Voice entry / low-literacy | P2 | M | Flutter + backend |
| P2.2 Standing AT test plan | P2 | M | ops + QA |

**P0 — before any production traffic.** The ten S1s. Seven of the eight P0 items are S-effort; the whole P0 block is roughly one focused engineer-week across Flutter and admin, and it converts the product from "cannot be used by a blind rider and cannot be operated without a mouse" to "usable, with rough edges". There is no good argument for shipping without it.

**P1 — first 30 days.** Target size, dynamic type, colour redundancy, the semantic pass over booking, and the admin structural sweep. P1.2 is the only L and should start early because it may force a distinct large-text layout for the offer card.

**P2 — next 90 days.** Voice entry, low-literacy work, and institutionalising the test plan so this document does not need writing again.

---

## 8. Metrics

| Metric | How measured | Current | Target |
|---|---|---|---|
| Token pairs failing WCAG AA | committed contrast test over both themes, all three apps | **38 of 84** | 0 |
| axe-core serious/critical violations, admin | CI on every route | not instrumented (`needs-check`; ≥12 expected from findings) | 0 |
| Interactive Flutter widgets with an accessible name | lint rule counting named vs total tappables | 7 `Semantics` + 5 `semanticLabel` across ~16.5k lines | 100% on the booking + trip + offer + SOS paths |
| Screen-reader booking completion | manual TalkBack + VoiceOver, per release | **fails at vehicle selection** | completes on both |
| Keyboard-only admin verification | manual, per release | **fails at the accordion** | completes |
| Interactive targets below 48dp on core screens | widget test | ≥9 confirmed | 0 |
| Screens with `RenderFlex` overflow at 200% | golden tests at 1.0/1.3/2.0 | `needs-check` (≥4 predicted) | 0 |
| Unguarded looping animations | grep + review | 2 major (captain splash, rider pulse) | 0 |
| Text-scale honoured | `maxScaleFactor` in each app | captain 1.3×, rider unclamped | ≥2.0× both, layouts intact |
| Realtime transitions announced | count of announce calls vs transitions | 0 of 6 | 6 of 6 |
| Sunlight legibility of offer-card decision text | quarterly outdoor session, pass/fail per element | `needs-check` | all decision text passes |

Two of these deserve to be release gates rather than dashboards: screen-reader booking completion and keyboard-only admin verification. They are binary, they are cheap to check, and they are the two that currently fail.

---

## 9. Cross-cutting notes

**To T27 — Cross-App Parity.** The rider and captain apps have diverged on accessibility in ways that look like drift, not decisions:

- **SOS is a different feature in each app.** Rider (`rider/sos_screen.dart:28–45`) shows a confirm `AlertDialog` and requires a second tap; captain (`captain/sos_screen.dart:59–61`) fires immediately on one tap with `HapticFeedback.heavyImpact()`. Rider's screen is on the normal white `lightPanel`; captain's uses `sosBackdrop #1A0000` so it is unmistakably an emergency surface. Rider pops the screen on success with no confirmation; captain shows a success state with a check icon. Rider has no haptics; captain has two. Rider requires a `tripId` constructor param, so **a rider who needs SOS before a captain is assigned has no path to it at all**; captain's screen needs no trip. These should be one shared widget.
- **Text-scale clamp exists only in the captain app** (`captain/main.dart:70–73`); rider has none.
- **Map circle buttons are implemented twice.** The captain side uses shared `MapCircleButton`, which carries `Semantics` (`map_controls.dart:44`); the rider trip screen has a private `_circleButton` (`trip_screen.dart:396`) which carries none and is 44dp instead of 46/50dp.
- **Reduced-motion handling is honoured in the rider splash/login and ignored in the captain splash.**

**To T12 — Design System.** `apps/admin/src/design/tokens.ts` and `design/globals.css` are dead code — nothing imports them, and they contain the *correct* AA values while the live `tailwind.config.js` contains failing ones. Four sources of colour truth for one console is the root cause of F-15-01, and it will regenerate the bug after any fix unless the architecture is collapsed to one. Also: the proposed admin `#4E8419` converges on Flutter's `#4E842D`, so a single cross-platform brand green is available if you want it.

**To T13 — Motion & Micro-interactions.** Full inventory of animations with no reduced-motion guard: `captain/splash_screen.dart:43–47` (the `_motion` controller driving `:371–411`, `:417–445`, `:450–487`), `:231` (repeating shimmer), `home_screen.dart:97–101` + `:844–882` (looping location pulse), `offer_card_entrance.dart:56–74` (one-shot slide+scale per offer, fires on every WS push), `main_bottom_nav.dart:453–460,619–628` and `active_trip_panel.dart:664–667` (brief, tap-triggered, low risk). The correct pattern already exists at `skeleton_loader.dart:58` and `rider/main.dart:141`.

**To T14 — Localisation & Content.** Announcement strings from P0.6 need Arabic copy and must route through the existing localisation layer. Also relevant: `app_theme.dart:287–288` sets `letterSpacing: -0.5` and `height: 1.1` on the money style, used at 12.5sp in `vehicle_selector.dart:396` — negative tracking on Arabic numerals at small sizes needs a device check. And `packages/flutter_shared/lib/l10n/app_strings.dart` is 184 KB in a single file, which is a maintainability problem I did not otherwise assess.

**To T11 — Admin Console.** Beyond accessibility, `CaptainVerificationPage.tsx` has three different modal patterns in one page (`RejectionReasonModal`, `QuickSearchModal`, inline `ZoomablePreviewModal`), none consistent. The P0.8 modal primitive is worth doing for maintainability regardless of accessibility.

**To T09 / T10 — Rider & Captain Journeys.** The rider cannot reach SOS before a captain is assigned (`rider/sos_screen.dart` requires `tripId`). That is a journey gap as much as an accessibility one.

**To T23 — Testing & CI.** P2.2 proposes axe-core, contrast unit tests, and text-scale golden tests as CI gates. I could not add CI YAML here — the review protocol forbids touching `.github/workflows/**` — so the config belongs in your track.

---

## 10. Open questions

**Q1 — Is WCAG 2.2 AA a commitment or an aspiration?**
It changes the phasing. If Synaptic Go intends to contract with Egyptian government or corporate B2B customers (the `companies` routes and monthly-invoice cron suggest B2B is real), accessibility conformance is likely to appear in procurement. *Options:* (a) commit to AA and gate releases on it; (b) target AA on the rider/captain critical paths only, best-effort in admin; (c) treat it as backlog. **Recommendation: (a).** The P0 block is about a week of work, and the alternative is re-auditing later with more surface area.

**Q2 — Does the brand green change, or does the brand green get a text variant?**
P0.1 darkens the admin's `#6bb522` to `#4E8419`. *Options:* (a) change the brand colour everywhere and gain one AA-safe green across all three apps; (b) keep `#6bb522` for large graphics and fills only, add a darker text-and-focus variant. **Recommendation: (a)** — the Flutter apps already ship `#4E842D`, so the admin is the outlier, and a single green is simpler than a two-token discipline nobody will follow.

**Q3 — Should the captain's text-scale clamp be removed, or made an explicit in-app setting?**
Removing it (P1.2) is the WCAG-correct answer but risks a blown-out offer card in traffic, which is its own safety problem. *Options:* (a) remove after making layouts elastic; (b) keep a clamp but raise it to 1.6× and add an in-app "large text" mode with a purpose-built layout; (c) leave at 1.3×. **Recommendation: (a), with (b) as the fallback if the offer card cannot be made to survive 200% while staying glanceable.** Not (c) — overriding a declared accessibility setting is indefensible.

**Q4 — What is the minimum viable map alternative for a blind rider?**
Full map accessibility is a large project. *Options:* (a) a single live `Semantics` summary ("captain 3 minutes away, 1.2 km") updated from existing data; (b) that plus a "describe my trip" button producing a spoken summary on demand; (c) full per-marker semantics. **Recommendation: (a) in P1.4, (b) in P2.** Option (c) is chatty and low-value.

**Q5 — Should SOS require confirmation?**
The two apps disagree today (§9), so a decision is owed regardless. *Options:* (a) both confirm — fewer false alarms, slower in a real emergency; (b) neither confirms — fastest, more false alarms; (c) hold-to-activate for ~1.5s with haptic feedback — no extra tap, resistant to pocket taps, and works for users who cannot make precise taps. **Recommendation: (c) in both apps,** built once in `flutter_shared`, with the captain's `sosBackdrop` treatment and success state adopted on the rider side. Note this also resolves the accessibility problem that a confirm dialog adds a second unlabelled control to an emergency path.

**Q6 — Who owns the 45-minute manual AT pass?**
Automated checks cannot answer "can a blind rider book a ride". *Options:* (a) a named engineer per release on rotation; (b) QA; (c) an external accessibility vendor quarterly. **Recommendation: (a) per release plus (c) annually.** The rotation matters more than the vendor — engineers who have used their own product with TalkBack write different code afterwards.
