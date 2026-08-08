# Tempo Rebrand — Execution Plan

> GoDrive → **Tempo**, brand green → **brand blue**, plus a rebuilt animated
> launch screen. This document is pushed **before** the work lands, and
> updated at the end of the run with the outcome of each step.

## Scope, in one paragraph

Every colour in both Flutter apps already resolved through `AppTokens`, with
**zero** brand hex literals anywhere else in the Dart tree. That made the
recolour a surgical edit to one file rather than a 251-site find-and-replace.
The neutrals — every white, black and grey in both themes — are untouched by
construction, because they live in separate token blocks that this change
never opens. Semantic greens (success, approved, completed, pickup pin) are
also deliberately preserved: a completed trip turning blue would break a
convention users read without thinking.

## The palette

The blue ramp is a **hue rotation, not a re-tune**. Each step was derived by
solving for the lightness that reproduces the corresponding green step's
measured contrast on white at hue 214°, so every contrast promise the old
code comments made still holds to two decimal places.

| Token | Before | After | Contrast on white |
|---|---|---|---|
| `primary` / `primaryFill` | `#4E842D` | **`#1472ED`** | 4.50:1 — identical |
| `primaryLight` | `#69A83D` | **`#619AE5`** | 2.89:1 — identical |
| `primaryDark` | `#38631E` | **`#0C55B5`** | 7.07:1 — identical |
| `primaryDeep` | `#22400F` | **`#063776`** | 11.61:1 — identical |
| `primarySoft` | `#EAF5E3` | **`#ECF2FA`** | 1.12:1 — identical |
| `headerAccent` | `#DDF2D1` | **`#E3EDFA`** | 1.19:1 — identical |
| `routeLine` | `#4E842D` | **`#1472ED`** | 4.50:1 — identical |
| `splashBg` | `#0C1A08` | **`#0A1729`** | 18.00:1 — identical |
| `splashGlowStart` | `#2C5518` | **`#124A93`** | 8.68:1 — identical |
| `splashGlowTint` | `0x333E7A22` | **`0x331869D4`** | 5.23:1 — identical |
| `splashFade` | `0x000C1A08` | **`0x000A1729`** | transparent `splashBg` |

Dark mode's action colour was a **lime `#C1F11D`** — a green-family accent that
would have kept the entire night theme reading green long after daylight had
turned blue. It becomes **`#4CC2FF`** (ink on it 9.49:1, on `nightPanel` 8.66:1).
The `lime*` names survive as `@Deprecated` aliases so all ~31 call sites keep
compiling without touching twenty files.

## Commit sequence

One commit per file, in dependency order — tokens first, then the widgets that
read them, then the screens, then names, then the console.

### 1. Design tokens

1. `packages/flutter_shared/lib/theme/app_theme.dart` — modify

### 2. Shared brand widgets

2. `packages/flutter_shared/lib/flutter_shared.dart` — modify
3. `packages/flutter_shared/lib/l10n/app_strings.dart` — modify
4. `packages/flutter_shared/lib/widgets/go_date_field.dart` — modify
5. `packages/flutter_shared/lib/widgets/godrive_wordmark.dart` — delete
6. `packages/flutter_shared/lib/widgets/main_bottom_nav.dart` — modify
7. `packages/flutter_shared/lib/widgets/tempo_splash.dart` — add
8. `packages/flutter_shared/lib/widgets/tempo_wordmark.dart` — add
9. `packages/flutter_shared/lib/widgets/vehicle_map_marker.dart` — modify

### 3. Splash screens

10. `apps/captain/lib/screens/splash_screen.dart` — modify
11. `apps/rider/lib/screens/splash_screen.dart` — modify

### 4. Localised app titles

12. `apps/captain/lib/l10n/app_ar.arb` — modify
13. `apps/captain/lib/l10n/app_en.arb` — modify
14. `apps/captain/lib/l10n/generated/app_localizations.dart` — modify
15. `apps/captain/lib/l10n/generated/app_localizations_ar.dart` — modify
16. `apps/captain/lib/l10n/generated/app_localizations_en.dart` — modify
17. `apps/rider/lib/l10n/app_ar.arb` — modify
18. `apps/rider/lib/l10n/app_en.arb` — modify
19. `apps/rider/lib/l10n/generated/app_localizations.dart` — modify
20. `apps/rider/lib/l10n/generated/app_localizations_ar.dart` — modify
21. `apps/rider/lib/l10n/generated/app_localizations_en.dart` — modify

### 5. Names & identifiers

22. `apps/captain/android/app/build.gradle` — modify
23. `apps/captain/android/app/src/main/AndroidManifest.xml` — modify
24. `apps/captain/android/app/src/main/kotlin/tech/synapticstudio/tempo_captain/MainActivity.kt` — rename+modify
25. `apps/captain/ios/Runner.xcodeproj/project.pbxproj` — modify
26. `apps/captain/ios/Runner/Info.plist` — modify
27. `apps/captain/pubspec.yaml` — modify
28. `apps/captain/web/index.html` — modify
29. `apps/captain/web/manifest.json` — modify
30. `apps/rider/android/app/build.gradle` — modify
31. `apps/rider/android/app/src/main/AndroidManifest.xml` — modify
32. `apps/rider/android/app/src/main/kotlin/tech/synapticstudio/tempo_rider/MainActivity.kt` — rename+modify
33. `apps/rider/ios/Runner.xcodeproj/project.pbxproj` — modify
34. `apps/rider/ios/Runner/Info.plist` — modify
35. `apps/rider/pubspec.yaml` — modify
36. `apps/rider/web/index.html` — modify
37. `apps/rider/web/manifest.json` — modify

### 6. App screens & copy

38. `apps/captain/lib/main.dart` — modify
39. `apps/captain/lib/models/ride_request_model.dart` — modify
40. `apps/captain/lib/screens/documents/document_status_screen.dart` — modify
41. `apps/captain/lib/screens/documents/document_upload_screen.dart` — modify
42. `apps/captain/lib/screens/documents/documents_onboarding_screen.dart` — modify
43. `apps/captain/lib/screens/earnings/earnings_screen.dart` — modify
44. `apps/captain/lib/screens/earnings/wallet_screen.dart` — modify
45. `apps/captain/lib/screens/home/active_trip_panel.dart` — modify
46. `apps/captain/lib/screens/home/available_trips_tab.dart` — modify
47. `apps/captain/lib/screens/home/home_tab.dart` — modify
48. `apps/captain/lib/screens/home/main_shell.dart` — modify
49. `apps/captain/lib/screens/home/offer_card.dart` — modify
50. `apps/captain/lib/screens/home/trip_chat_screen.dart` — modify
51. `apps/captain/lib/screens/home/trips_tab.dart` — modify
52. `apps/captain/lib/screens/onboarding/onboarding_screen.dart` — modify
53. `apps/captain/lib/screens/profile/settings_screen.dart` — modify
54. `apps/captain/lib/screens/safety/sos_screen.dart` — modify
55. `apps/captain/lib/services/captain_state.dart` — modify
56. `apps/captain/test/widget_test.dart` — modify
57. `apps/rider/lib/main.dart` — modify
58. `apps/rider/lib/screens/home/home_screen.dart` — modify
59. `apps/rider/lib/screens/home/location_search_sheet.dart` — modify
60. `apps/rider/lib/screens/places/saved_places_screen.dart` — modify
61. `apps/rider/lib/screens/profile/invite_screen.dart` — modify
62. `apps/rider/lib/screens/profile/settings_screen.dart` — modify
63. `apps/rider/lib/screens/ride/captain_bids_sheet.dart` — modify
64. `apps/rider/lib/screens/safety/sos_screen.dart` — modify
65. `apps/rider/lib/screens/trip/trip_screen.dart` — modify
66. `apps/rider/lib/screens/wallet/wallet_screen.dart` — modify
67. `apps/rider/lib/services/location_service.dart` — modify
68. `apps/rider/test/widget_test.dart` — modify
69. `pps/admin/index.html` — modify

### 7. Admin console

70. `apps/admin/public/tempo-logo.png` — rename
71. `apps/admin/src/components/common/TempoLogo.tsx` — rename+modify
72. `apps/admin/src/components/layout/Sidebar.tsx` — modify
73. `apps/admin/src/design/globals.css` — modify
74. `apps/admin/src/design/tokens.ts` — modify
75. `apps/admin/src/pages/AnalyticsPage.tsx` — modify
76. `apps/admin/src/pages/LiveMapPage.tsx` — modify
77. `apps/admin/src/pages/LoginPage.tsx` — modify
78. `apps/admin/src/styles.css` — modify
79. `apps/admin/tailwind.config.js` — modify

### 8. API strings

80. `apps/api/deploy.sh` — modify
81. `apps/api/src/routes/captain.ts` — modify
82. `apps/api/src/routes/user.ts` — modify

### 9. Docs

83. `apps/captain/FLUTTER_SETUP.md` — modify
84. `apps/captain/README.md` — modify
85. `apps/rider/FLUTTER_SETUP.md` — modify
86. `apps/rider/README.md` — modify
87. `docs/plan/assets/E17-android-release-runbook.md` — modify

**Total: 87 commits.**

## Verification run before pushing

| Check | Result |
|---|---|
| `check_l10n_parity.py` | OK — ar/en stay key-for-key aligned |
| `check_repo_hygiene.py` | OK — 365 text files scanned |
| `check_migrations.py` | OK — 23 migrations |
| `check_migrations_apply.py` | OK — 23/23 applied to a fresh DB, 40 tables |
| Neutral tokens | all 21 verified present and byte-identical |
| Brand green literals remaining | none outside the semantic greens |

`flutter analyze` and the Node typechecks could not be run here — neither the
Flutter SDK nor the workspace `node_modules` exist in this sandbox. CI is the
gate for those.

## Deliberately NOT done

**The npm workspaces keep the `@synaptic-go/*` scope.** The name appears 60
times, and `.github/workflows/ci.yml` is one of the places it appears. The
GitHub App authoring these commits holds no `workflows` permission, so a push
touching that file is rejected — renaming the scope would leave `main` red
with no way for the agent to repair it. The proposed workflow diff is filed
under `docs/` instead; applying it is a human step.

**`info #1D6DBE` is unchanged.** It now sits 3.8° from the brand hue, which is
a genuine collision, but it is a semantic that was not in scope. Flagged for a
separate decision rather than moved unilaterally.

**Bundle identifiers changed.** `tech.synapticstudio.tempo_*` is a new store
identity: existing installs will not upgrade in place. This was explicitly
requested.

---

# Outcome

**Status: shipped.** `main` moved `3c9641b → da8424f7` — 88 commits, one per file,
the plan itself first.

## What landed

| | |
|---|---|
| Commits | 88 (one per file, dependency-ordered) |
| Files changed | 88 · +979 / −539 |
| Base at push | `3c9641b` — re-checked immediately before pushing, unmoved |

## Verification after the push

Read back through the **contents API**, never `raw.githubusercontent.com`,
which is CDN-cached and will happily serve pre-write content:

| Path | Result |
|---|---|
| `packages/flutter_shared/lib/theme/app_theme.dart` | PASS — byte-for-byte |
| `packages/flutter_shared/lib/widgets/tempo_splash.dart` | PASS — byte-for-byte |
| `packages/flutter_shared/lib/widgets/tempo_wordmark.dart` | PASS — byte-for-byte |
| `apps/rider/lib/screens/splash_screen.dart` | PASS — byte-for-byte |
| `apps/captain/lib/screens/splash_screen.dart` | PASS — byte-for-byte |
| `apps/admin/src/design/tokens.ts` | PASS — byte-for-byte |
| `docs/TEMPO-REBRAND-PLAN.md` | PASS — byte-for-byte |

Deletions and renames confirmed by status code: `godrive_wordmark.dart`,
`GoDriveLogo.tsx` and the old Kotlin `MainActivity.kt` path all return 404;
`TempoLogo.tsx` and the new Kotlin path both return 200.

## Still open

1. **CI is the real gate.** `flutter analyze` and the Node typechecks could not
   run in the authoring sandbox — no Flutter SDK, no `node_modules`. The four
   Python check scripts (l10n parity, repo hygiene, migrations, migrations
   apply) all passed locally. Watch the CI run on this commit.
2. ~~**`info #1D6DBE`** collision~~ — **RESOLVED**, see the addendum below.
3. **`@synaptic-go/*` npm scope unchanged** — see above; renaming it needs a
   human to edit `.github/workflows/ci.yml`.
4. ~~**Stale comments.**~~ — **RESOLVED.** Every present-tense green/lime
   reference in Dart, TSX and CSS prose now reads blue/cyan. The deliberately
   historical passages (the rebrand narrative in `app_theme.dart`, the
   `@Deprecated` lime aliases, "old/previous revision" stories) stay as
   written, because they describe the green era accurately.
5. ~~**Orphaned binaries.**~~ — **RESOLVED.** `GODRIVE.png`, root `splash.mp4`,
   both apps' `assets/videos/splash.mp4` (and their `assets/videos/` pubspec
   entries), plus `godrive_logo.png` / `splash_brand.png` in both apps are
   deleted; `generate_tempo_assets.py` no longer recreates the last two.

---

# Addendum — the `info` collision, resolved

`AppTokens.info` moved from **`#1D6DBE` to `#0E818E`**, a cyan-teal at hue 186.

## Why contrast was the wrong instrument

The obvious check — WCAG contrast between `info` and the brand — is misleading
here. Contrast is a pure luminance ratio, so two colours of equal lightness
score ~1.0 no matter how far apart their hues are. Measured that way the new
teal scores **1.02:1** against the brand, *worse* than the 1.17:1 it replaced,
while being obviously more distinguishable to the eye.

The right instrument for side-by-side distinguishability is **CIEDE2000**:

| Pair | dE2000 | Reading |
|---|---|---|
| old `#1D6DBE` vs brand | **5.9** | a related shade — the collision |
| new `#0E818E` vs brand | **25.4** | clearly a different colour |
| new `#0E818E` vs `success` | 27.8 | no second collision introduced |

## Why not violet

Violet scored well on paper (dE 17–23) and was rejected on a colour-vision
check. Simulated under deuteranopia it collapses back into the brand blue:

| Candidate | dE normal | dE protan | dE deutan |
|---|---|---|---|
| violet hue 258 | 17.0 | 3.3 | **1.6** — invisible |
| violet hue 274 | 23.3 | 5.1 | **3.0** — invisible |
| cyan hue 186 | 25.4 | 19.0 | **15.1** — holds |

Blue-versus-cyan is a distinction on the blue-yellow axis, which red-green
deficiency leaves intact. Blue-versus-violet is not.

## Contrast, for completeness

| Surface | old `#1D6DBE` | new `#0E818E` |
|---|---|---|
| on white | 5.27:1 | 4.62:1 — AA |
| on `nightPanel` | 3.29:1 | **3.76:1** |

Dark mode improves on the way past: the old value sat under the 3:1 floor for
graphical objects by a hair in some pairings.

No `infoNight` token was added. It would need a brightness-aware accessor and
edits at all eight call sites, and an unwired token is exactly the dead weight
the splash tokens once carried before anything referenced them.

## The admin had a worse version of the same bug

`--color-info-*` and `--color-success-*` were **byte-identical** (`#6bb522`), so
an info state and a success state were indistinguishable — and `tokens.ts`
carried a third value, `#1d4ed8`, a blue that collided with the new brand
directly. All three files now point `info` at the same teal ramp
(`#e8f7f8` / `#0e818e` / `#09636d`) while `success` stays green.
