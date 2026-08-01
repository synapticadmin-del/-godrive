# 14 — Localisation, RTL & Content Design

> Track: B — Product surface & experience · Reviewer: chat-20260801-1329-a653 · Date: 2026-08-01 (UTC)
> Base commit reviewed: `697f4347045e67bc488a9c91631d6497ab6511d7`

## 1. Scope

This document covers the localisation axis of Synaptic Go: the string catalogues and how they are wired, RTL layout correctness in both Flutter apps, numeral and format policy, the quality and consistency of the Arabic copy itself, server-side language handling for notifications and error messages, and the cost of adding localisation to the admin console.

**What it does not cover, and who owns it instead:**

- Visual design tokens, typography scale and colour — **T12**. This document only touches fonts where the font choice affects Arabic legibility and APK weight.
- Animation and perceived performance — **T13** / **T28**.
- Screen-reader labels and contrast — **T15**. Where an `aria-label`/`semanticsLabel` is missing *and* untranslated, it is counted here as a string, but the accessibility verdict belongs to T15.
- The systematic rider↔captain duplication problem — **T27**. This document reports every parity gap it found under §9, but does not propose the unification programme.
- Notification delivery mechanics, queue and DLQ behaviour — **T19**. Only the *language* of the payload is assessed here.
- Whether the ARB→`AppStrings` architectural choice should be revisited at all is a decision recorded in §10; the migration cost is estimated here because no other track owns it.

A structural note that shapes everything below: **there is no `docs/` planning document on this axis to write on top of.** `docs/ROADMAP.md`, `docs/IMPROVEMENTS.md` and `docs/CHECKLIST.md` were checked for localisation content; the axis is unowned. This is the first document on it.

## 2. What I actually read

Every file below was downloaded at the pinned commit and read from disk with real line numbers. Where I skimmed rather than read in full, it says so.

**String catalogues**

| File | Note |
|---|---|
| `packages/flutter_shared/lib/l10n/app_strings.dart` | 5,664 lines. Read in full: the doc comment (1–45), the abstract class (46–1776), `AppStringsAr` (1777–3720), and `AppStringsEn` (3721–5664). This is the live catalogue. |
| `apps/rider/lib/l10n/app_ar.arb` | 58 lines, 56 keys. Read in full. |
| `apps/rider/lib/l10n/app_en.arb` | 58 lines, 56 keys. Read in full. |
| `apps/captain/lib/l10n/app_ar.arb` | 50 lines, 48 keys. Read in full. |
| `apps/captain/lib/l10n/app_en.arb` | 50 lines, 48 keys. Read in full. |
| `apps/rider/lib/l10n/generated/app_localizations*.dart` | Header and delegate contract read (1–40); the per-locale bodies skimmed — they are machine output and, as §3 establishes, unreachable. |
| `apps/captain/lib/l10n/generated/app_localizations*.dart` | Same treatment. |

**Wiring and state**

| File | Note |
|---|---|
| `apps/rider/lib/main.dart` | Read in full (173 lines). Locale, delegates, `Directionality`. |
| `apps/captain/lib/main.dart` | Read in full (92 lines). Same surface, plus the `textScaler` clamp. |
| `apps/rider/lib/services/app_state.dart` | Read the locale, bootstrap and persistence regions; grepped all `SharedPreferences` keys. |
| `apps/captain/lib/services/captain_state.dart` | Same treatment. |
| `apps/rider/pubspec.yaml`, `apps/captain/pubspec.yaml`, `packages/flutter_shared/pubspec.yaml` | Read the dependency and `flutter:` blocks. |
| `apps/rider/l10n.yaml`, `apps/captain/l10n.yaml` | Existence and content confirmed. |
| `scripts/check_l10n_parity.py` | Read in full (227 lines) **and executed** against the tree. Output quoted in §3. |

**Theme, format and RTL primitives**

| File | Note |
|---|---|
| `packages/flutter_shared/lib/theme/app_theme.dart` | Read the `AppTokens.font`/`money` definitions (255–290) and the theme blocks that set text styles; the colour token sections skimmed (T12's territory). |
| `packages/flutter_shared/lib/widgets/go_date_field.dart` | Read the formatting helpers and the numeral-policy comment (40–75) in full. |
| `packages/flutter_shared/lib/widgets/map_controls.dart`, `main_bottom_nav.dart`, `skeleton_loader.dart`, `godrive_wordmark.dart`, `counter_offer_sheet.dart`, `vehicle_map_marker.dart` | Read the direction-sensitive regions. |

**Screens** — all 30 rider and 24 captain Dart files were scanned programmatically for Arabic literals, `isAr` ternaries and RTL primitives; the following were additionally read around the cited lines: `rider/trip/trip_chat_screen.dart`, `captain/home/trip_chat_screen.dart`, `rider/trip/trip_screen.dart`, `rider/home/home_screen.dart`, `rider/home/fare_estimate_sheet.dart`, `rider/home/location_search_sheet.dart`, `rider/ride/captain_bids_sheet.dart`, `rider/profile/profile_screen.dart`, `rider/profile/settings_screen.dart`, `rider/safety/sos_screen.dart`, `captain/safety/sos_screen.dart`, `captain/profile/settings_screen.dart`, `captain/documents/*`, `captain/onboarding/onboarding_screen.dart`, both `login_screen.dart`.

**API**

| File | Note |
|---|---|
| `apps/api/src/lib/utils.ts`, `middleware/rateLimit.ts`, `middleware/auth.ts` | Read in full — the error envelope and its codes. |
| `apps/api/src/lib/notifications.ts` | Read in full — transports, WhatsApp template, OTP email. |
| `apps/api/src/routes/` — `auth.ts`, `trips.ts`, `wallet.ts`, `promo.ts`, `payments.ts`, `intercity.ts`, `safety.ts`, `companies.ts`, `devices.ts`, `geocode.ts`, `user.ts`, `captain.ts`, `admin.ts`, `search.ts` | Read for every error return and every notification payload. `admin.ts` skimmed outside its error paths. |
| `apps/api/src/lib/schemas.ts`, `types.ts` | Read for any locale field. |
| `migrations/0001_init.sql` … `0019_trips_captain_status_index.sql` | All 19 grepped for `locale`/`language`/`lang`/`preferred`; `0001` and `0015` read directly for the user/captain column lists. |
| `packages/flutter_shared/lib/services/api_client.dart` | Read the `_decode` error path. |

**Admin console** — all 39 files under `apps/admin/src` inventoried with line counts; `Layout.tsx`, `Sidebar.tsx`, `TopBar.tsx`, `Badge.tsx`, `ErrorBoundary.tsx`, `RejectionReasonModal.tsx`, `PricingPage.tsx`, `SettingsPage.tsx`, `CaptainVerificationPage.tsx`, `AnalyticsPage.tsx` read for string extraction; `package.json` and `tailwind.config.js` read in full.

Four analysis subagents were used for parallel reading (RTL sweep, API tracing, admin sizing, Arabic copy criticism). Every line number they returned that appears in this document was spot-checked against the files on disk.

## 3. How it works today

### 3.1 There are two string catalogues, and the one the team documents is not the one that runs

The repository contains a complete, conventional Flutter `gen-l10n` setup: `l10n.yaml` in both apps, four ARB files, and generated `AppLocalizations` classes under `lib/l10n/generated/`.

It is not connected to anything.

```dart
// apps/rider/lib/main.dart:59-63
localizationsDelegates: const [
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
],
```

`AppLocalizations.delegate` is absent. The captain app is identical (`apps/captain/lib/main.dart:53-57`). A repository-wide search for `AppLocalizations` outside the generated directory returns exactly one hit, and it is a comment (`packages/flutter_shared/lib/l10n/app_strings.dart:19`). **All 208 ARB entries — 104 keys × 2 locales — are unreachable code.**

What actually runs is a hand-written catalogue:

```dart
// packages/flutter_shared/lib/l10n/app_strings.dart:52-55
static AppStrings of(BuildContext context) {
  final code = Localizations.localeOf(context).languageCode;
  return code == 'en' ? const AppStringsEn() : const AppStringsAr();
}
```

`AppStrings` is 5,664 lines: an abstract class with **545 members** (495 getters, 50 methods) and two concrete locale classes. Its own doc comment (`app_strings.dart:5-23`) is candid that this is a deliberate stopgap — "the long-term home for copy is the ARB + `gen-l10n` pipeline (the scaffolding already exists under `lib/l10n/`)" — chosen because migrating 400+ literals without a Flutter SDK on CI was judged unsafe.

That reasoning is sound. The problem is what grew around it.

### 3.2 The parity guard covers the catalogue that cannot break, and not the one that can

`scripts/check_l10n_parity.py` exists precisely to prevent locale drift. Executed against the pinned tree:

```
$ python3 scripts/check_l10n_parity.py
checked packages/flutter_shared/lib/l10n/app_strings.dart
  AppStrings (abstract): 544 member(s)  AppStringsAr: 545  AppStringsEn: 545
  note  AppStringsAr: 1 member(s) not declared on AppStrings (legal Dart): confirmAction
  note  AppStringsEn: 1 member(s) not declared on AppStrings (legal Dart): confirmAction
check_l10n_parity: OK
exit 0
```

It passes. It is also, by construction, checking a catalogue where drift is *already impossible* — `AppStringsAr` and `AppStringsEn` both `extends AppStrings`, so a missing translation is a Dart compile error before the script ever runs. The script's own header says as much (`check_l10n_parity.py:26-27`).

Meanwhile `CATALOG` is hardcoded to one path (`check_l10n_parity.py:42`) and the ARB files — where drift is silent and possible — are never opened.

Measured directly against the ARB files: rider `ar`/`en` both hold 56 keys with zero drift; captain both hold 48 with zero drift; two keys per app are intentionally identical across locales (`appTitle`, `phoneNumberHint`). So there is no drift *today*. There is simply no mechanism that would catch it, and no mechanism that notices the files are dead.

### 3.3 Coverage: what the live catalogue actually reaches

| Measure | Rider | Captain | Shared package |
|---|---|---|---|
| Inline Arabic string literals still in Dart | **359** across 23 files | **53** across 14 files | 32 across 7 files |
| `isAr` / locale-ternary occurrences | **187** | 11 | 16 |
| Dart files carrying Arabic literals | 23 of 30 | 14 of 24 | 7 |

Of the 545 members declared on `AppStrings`, **343 are referenced** anywhere in app code and **201 are never referenced at all**. (Method: regex for `.<member>` across every non-generated Dart file excluding the catalogue itself; a small number of dynamic call sites could be missed, so treat 201 as a floor. Confidence: `likely`.)

The asymmetry is the story. The catalogue's doc comment names the reference migration explicitly: "Every Captain screen is now a reference migration — `earnings_screen`, `settings_screen`, `trips_tab`, `offer_card`, `home_tab`, `active_trip_panel`, `wallet_screen`, `document_upload_screen`, `document_status_screen`, and `trip_chat_screen`. Copy their pattern" (`app_strings.dart:41-45`). The captain app did the work. The rider app did not, and carries 6.8× the inline literals and 17× the locale ternaries.

The 201 orphans are largely rider-shaped strings that were written into the catalogue in anticipation of a migration that never landed — `bidsChooseCaptainTitle`, `bidsAllCaptainsVerified`, `bidsEtaMinutes`, `availableBalanceLabel` and so on all exist, translated, unused, while the rider screens that should consume them keep their own literals.

### 3.4 What the language switch actually does

Both apps default to Arabic:

```dart
// apps/rider/lib/services/app_state.dart:61
Locale locale = const Locale('ar', 'EG');
// apps/captain/lib/services/captain_state.dart:122
Locale locale = const Locale('ar', 'EG');
```

The switch is reachable from six places: rider settings dropdown (`apps/rider/lib/screens/profile/settings_screen.dart:44-49`), rider profile (`profile_screen.dart:407`, `:552`), rider home (`home_screen.dart:694`), rider login (`login_screen.dart:252`), captain settings (`captain/screens/profile/settings_screen.dart:497`) and captain login (`captain/screens/login_screen.dart:186`).

It takes effect immediately — `setLocale` calls `notifyListeners()` and `MaterialApp.locale` rebuilds, so no restart is needed. Two things it does not do:

```dart
// apps/rider/lib/services/app_state.dart:532-535
void setLocale(Locale newLocale) {
  locale = newLocale;
  notifyListeners();
}
```

**It is never persisted.** The same class persists `themeMode` (`app_state.dart:586`) and the captain persists both theme and search radius (`captain_state.dart:1138`, `:713`). Language alone is dropped on restart. **And it is never sent to the server** — no call site pushes the locale to any endpoint.

### 3.5 The server has no idea what language anyone reads

Definitive, with evidence:

- No `locale` / `language` / `lang` / `preferred_language` column exists on `users` (`migrations/0001_init.sql:3-13`), on `captains` (`0001_init.sql:27-44`), or anywhere across all 19 migrations. The only textual hit is a comment about "the future en locale" in `0017_fix_document_type_titles.sql:30`.
- No such field in `apps/api/src/lib/types.ts` (`DbUser`, `DbCaptain`).
- `Accept-Language` is never read. The only occurrences in the API are *outbound*, requesting `ar,en` place names from Nominatim (`apps/api/src/lib/geocode.ts:40`, `:102`).

The consequences are mechanical. All 23 notification types are hardcoded Arabic — trip offer (`apps/api/src/routes/trips.ts:580-581`), acceptance (`:883-884`), completion (`:1067-1068`), bid received (`:1203-1204`), wallet top-up (`apps/api/src/routes/payments.ts:193-194`), SOS (`apps/api/src/routes/safety.ts:35-36`), intercity (`apps/api/src/routes/intercity.ts:179-180`, `:302-303`, `:458-459`) and the rest. The OTP email is hardcoded Arabic (`apps/api/src/lib/notifications.ts:184-185`). The WhatsApp OTP template language is a single global environment variable, `WHATSAPP_TEMPLATE_LANG`, defaulting to `"ar"` (`notifications.ts:93`) — one language for the entire user base.

### 3.6 The error surface is English

The API returns a structured envelope with a machine `code` and a human `error` string. Across the routes there are roughly **71 distinct codes**. Nine ship Arabic text; the rest ship English.

The Arabic nine are ad hoc rather than policy — `TURNSTILE_FAILED` (`auth.ts:77`), `OFFLINE` (`trips.ts:843`, `:1166`), `INSUFFICIENT_BALANCE` (`wallet.ts:110`, `:120`; `intercity.ts:110`, `:163`), `ALREADY_BOARDED` / `ALREADY_DEPARTED` (`intercity.ts:252`, `:255`), `SPEND_LIMIT` and `NO_COMPANY` (`companies.ts:50`, `:225`), and one un-coded admin guard (`search.ts:11`). Everything else — `INVALID_CREDENTIALS`, `TRIP_TAKEN`, `FILE_TOO_LARGE`, `RATE_LIMITED`, `VALIDATION_ERROR` — is English.

The client does not map codes to Arabic. It extracts the server's `error` string verbatim:

```dart
// packages/flutter_shared/lib/services/api_client.dart:32
// data['error'] is thrown as an Exception message
```

…and screens render that message directly. Confirmed call sites where an English server string reaches an Arabic-speaking user:

| Where | Line | What the user sees |
|---|---|---|
| Rider login | `apps/rider/lib/screens/login_screen.dart:165-169` | `Invalid credentials` / `Account suspended` in a snackbar |
| Rider fare sheet | `apps/rider/lib/screens/home/fare_estimate_sheet.dart:165`, `:220`, `:247` | `Pricing not configured` inline and in a snackbar |
| Rider saved places | `apps/rider/lib/screens/places/saved_places_screen.dart:79`, `:90`, `:106` | Bare `e.toString()` — literally `Exception: file required` |
| Rider bids sheet | `apps/rider/lib/screens/ride/captain_bids_sheet.dart:150-157` | Reads `body['error']` directly — `Trip already assigned or completed` |
| Captain active trip | `apps/captain/lib/screens/home/active_trip_panel.dart:114-116` | `Trip is already completed or state changed` |
| Captain document upload | `apps/captain/lib/screens/documents/document_upload_screen.dart:782-784`, `:815` | `خطأ: File too large (max 10MB)` — Arabic wrapper, English payload |
| Captain onboarding | `documents_onboarding_screen.dart:258-259`, `:282-284`; `onboarding/onboarding_screen.dart:338-341`, `:358` | Same hybrid |
| Captain settings avatar | `captain/screens/profile/settings_screen.dart:79`, `:97` | Same hybrid |
| Captain payout | `captain/screens/earnings/wallet_screen.dart:257` | `فشل طلب السحب: Validation failed` |
| Captain earnings | `captain/screens/earnings/earnings_screen.dart:54`, `:94` | English error replaces the Arabic fallback |

The `خطأ: <English>` pattern is the tell: someone wrapped the error in Arabic chrome without noticing the payload never was.

### 3.7 Numerals and formatting

**Numerals are Western (0123) everywhere, deliberately.** A repository-wide search for Arabic-Indic digits in Dart returns zero hits. The decision is documented at the one place it was likely to break:

```dart
// packages/flutter_shared/lib/widgets/go_date_field.dart:50-52
/// Deliberately not `DateFormat`: `intl`'s Arabic locale renders Arabic-Indic
/// numerals, and nothing else in this product does. A payload must never
/// depend on the display locale in any case.

// go_date_field.dart:60-61
/// Western digits in both languages, matching every other number in the app
/// (fares, distances, plate numbers).
```

There is exactly one violation, and it is a mixed-script line:

```dart
// packages/flutter_shared/lib/l10n/app_strings.dart:1978
String tripsLast7Days(int count) => '$count رحلة • آخر ٧ أيام';
```

At `count = 3` this renders `3 رحلة • آخر ٧ أيام` — Western and Eastern digits in one nine-character span.

**Formatting is hand-rolled.** `intl` is a declared dependency in both apps but appears at only 7 sites outside generated code, and only ever as `DateFormat` with a fixed pattern (`captain/screens/earnings/wallet_screen.dart:26`, `rider/screens/wallet/wallet_screen.dart:50`, `rider/screens/history/history_screen.dart:64`). There is **no `NumberFormat` anywhere.** Money is built by concatenation: 44 `toStringAsFixed` calls and 36 sites appending `ج.م` by hand, e.g. `'${balance.toStringAsFixed(2)} ${isAr ? 'ج.م' : 'EGP'}'` (`rider/screens/profile/profile_screen.dart:703`), `'${price.round()} ج.م'` (`captain_bids_sheet.dart:459`).

Because the currency symbol is glued on per-call-site, spacing and decimal precision vary by screen: two decimals in profile, zero in payment methods (`payment_methods_screen.dart:66`), rounded in the bids sheet.

Relative time is not computed at all. It is three fixed strings:

```dart
// app_strings.dart:2092, 2095, 2098
String get notifTimeMinutesAgo => 'منذ 5 دقائق';
String get notifTimeHourAgo    => 'منذ ساعة';
String get notifTimeHoursAgo   => 'منذ 3 ساعات';
```

The notification screen will always say five minutes. The same mock-data-as-copy pattern shipped the fare and the captain's name: `'وصلت بسلامة. الأجرة 45 ج.م.'` (`:2071`), `'تم إضافة 100 ج.م إلى محفظتك.'` (`:2083`), `'كيف كانت رحلتك مع الكابتن أحمد؟'` (`:2089`). These are parameterless getters — no code path can substitute real values.

### 3.8 Fonts

Type is `GoogleFonts.cairo`, resolved through one helper (`packages/flutter_shared/lib/theme/app_theme.dart:265`, and `:283` for the money style). No `fonts:` asset block exists in any of the three pubspecs, and there is not a single `.ttf` or `.otf` in the repository.

That means the `google_fonts` package fetches Cairo over HTTP on first use and caches it. On a cold install with no connectivity the app renders Arabic in the platform fallback; the first launch of an Egyptian ride-hailing app is therefore network-dependent for its typeface. Cairo itself is a good Arabic face with full Arabic coverage, so the *choice* is right — the *delivery* is the problem.

### 3.9 RTL

Both apps drive direction from a manual `Directionality` wrapper rather than letting `MaterialApp` derive it (`apps/rider/lib/main.dart:81-84`, `apps/captain/lib/main.dart:60-63`). With Arabic as the default locale, every layout is RTL by default and must be direction-agnostic.

Much of it is. `PositionedDirectional`, `AlignmentDirectional`, `EdgeInsetsDirectional` and `TextAlign.start` are used correctly across the captain app and the shared widgets — `captain/home/trip_chat_screen.dart:249-251`, `captain/home/main_shell.dart:674`, `:733`, `shared/main_bottom_nav.dart:534`, `:634`, `captain/home/offer_card.dart:369`, `:521`, `captain/profile/settings_screen.dart:454`, `:477`, and the skeleton loader even flips its sheen direction (`shared/skeleton_loader.dart:99-100`). The offer-card entrance animation flips its slide axis for RTL (`captain/home/offer_card_entrance.dart:48-54`).

The defects are concentrated in the rider app and in icon choice. Full catalogue in §4.

## 4. Findings

Severity per `board/TEMPLATE.md`. Confidence: `confirmed` = I read the code at the cited line; `likely` = strong inference from measurement; `needs-check` = could not verify.

| ID | Sev | Finding | Evidence (`path:line`) | Impact | Confidence |
|---|---|---|---|---|---|
| F-14-01 | S1 | The ARB / `gen-l10n` pipeline is dead code: `AppLocalizations.delegate` is registered in neither app, so all 208 ARB entries are unreachable | `apps/rider/lib/main.dart:59-63`; `apps/captain/lib/main.dart:53-57`; zero non-generated call sites | A developer adding a string to the ARB files ships nothing. Two catalogues, one of them a decoy | confirmed |
| F-14-02 | S1 | Selecting English leaves most of the rider UI in Arabic — 359 inline Arabic literals and 201 orphaned catalogue members | `apps/rider/lib/screens/profile/settings_screen.dart:44-49` (the switch); measured across 23 rider files | The language switch is a visible feature that does not work. Ships a half-translated UI | confirmed |
| F-14-03 | S1 | English API error text reaches Arabic users on every failure path; ~62 of ~71 codes carry English messages and the client has no code→Arabic map | `packages/flutter_shared/lib/services/api_client.dart:32`; `apps/rider/lib/screens/login_screen.dart:165-169`; `apps/rider/lib/screens/places/saved_places_screen.dart:79` | Every error in an Arabic-first product is an English error. `Exception: file required` is shown verbatim | confirmed |
| F-14-04 | S2 | The parity guard checks only `app_strings.dart`, where drift is a compile error anyway; the ARB files have no guard | `scripts/check_l10n_parity.py:42`; script output `exit 0` | False assurance. The check that passes is the one that cannot fail | confirmed |
| F-14-05 | S2 | Locale is never persisted — theme and search radius are | `apps/rider/lib/services/app_state.dart:532-535` vs `:586`; `captain_state.dart:1117-1120` vs `:1138` | Every restart reverts an English user to Arabic | confirmed |
| F-14-06 | S2 | No server-side locale storage anywhere; all 23 notification types are hardcoded Arabic and the WhatsApp OTP language is one global env var | `migrations/0001_init.sql:3-13`; `apps/api/src/lib/notifications.ts:93`, `:184-185`; `apps/api/src/routes/trips.ts:580-581` | Push, OTP and email cannot ever match the user's chosen language | confirmed |
| F-14-07 | S2 | `goOnline` is mistranslated as an internet-connectivity instruction in the shared catalogue | `app_strings.dart:3554` (`'اتصل بالإنترنت لعرض الرحلات المتاحة'`) vs correct `apps/captain/lib/l10n/app_ar.arb:14` (`'ابدأ العمل'`) | A captain with working data is told to fix his internet. Directly suppresses supply and generates support load | confirmed |
| F-14-08 | S2 | Six competing Arabic terms for the pickup point, one of which means the opposite | `apps/rider/lib/l10n/app_ar.arb:19` (`'موقف النزول'` = drop-off); `app_strings.dart:1835`, `:1931`, `:2129`, `:2939`; `apps/captain/lib/l10n/app_ar.arb:25-26` | Rider and captain read different words for the same street corner | confirmed |
| F-14-09 | S2 | Arabic pluralisation is broken in 9 count-interpolating methods; the migration to `AppStrings` *regressed* two that were previously correct | `app_strings.dart:1832`, `:1978`, `:2119-2120`, `:2319`, `:2566`, `:2722`, `:2726`, `:3378`; regression vs `apps/rider/lib/screens/ride/captain_bids_sheet.dart:428-434` | `2 دقيقة`, `11 رحلات`, `404 رحلات` — visibly wrong Arabic on high-traffic surfaces | confirmed |
| F-14-10 | S2 | Mock data shipped as production copy in notifications | `app_strings.dart:2071`, `:2083`, `:2089`, `:2092`, `:2098` | Every notification says 45 EGP, 100 EGP, Captain Ahmed, five minutes ago. Parameterless getters — unfixable without signature changes | confirmed |
| F-14-11 | S2 | Rider chat bubbles use physical `Alignment`; the captain app already uses `AlignmentDirectional` | `apps/rider/lib/screens/trip/trip_chat_screen.dart:97` vs `apps/captain/lib/screens/home/trip_chat_screen.dart:249-251` | Bubble sides are correct only by accident and invert in any LTR subtree | confirmed |
| F-14-12 | S2 | The rider bids sheet hardcodes `Directionality.rtl` for its whole subtree | `apps/rider/lib/screens/ride/captain_bids_sheet.dart:222-223` | English users get an RTL bids sheet. A layout bug papered over with a direction override | confirmed |
| F-14-13 | S2 | 18 directional icons render unmirrored in Arabic | `rider/trip/trip_chat_screen.dart:140`; `rider/trip/trip_screen.dart:282`; `rider/home/travel_mode_bottom_bar.dart:115`; `rider/home/location_search_sheet.dart:544`; `rider/ride/schedule_screen.dart:98`, `:118`; `captain/earnings/wallet_screen.dart:579`; `shared/counter_offer_sheet.dart:255` | Back arrows point "forward", send arrows point off-screen, drill-in chevrons point backwards | confirmed |
| F-14-14 | S2 | Captain onboarding Next/Back chevrons are assigned inverted icons | `captain/documents/documents_onboarding_screen.dart:621`, `:652`; `captain/onboarding/onboarding_screen.dart:1269`, `:1312` | In the wizard that gates supply onboarding, "Back" points forward | confirmed |
| F-14-15 | S2 | Cairo is fetched at runtime from the Google Fonts CDN; no font is bundled | `packages/flutter_shared/lib/theme/app_theme.dart:265`; no `fonts:` block in any pubspec; no font file in the tree | First launch on poor connectivity renders Arabic in a fallback face. Also an external dependency at startup | confirmed |
| F-14-16 | S2 | All gendered copy is masculine and gender is not stored anywhere | `app_strings.dart:1866`, `:1884`, `:2499`, `:2588`, `:3591`, `:3135`; `captain_state.dart:1006`; zero `gender` matches in schema | Female captains and riders are addressed as male throughout, including in the SOS flow | confirmed |
| F-14-17 | S2 | The rider SOS screen bypasses the catalogue entirely with hardcoded Arabic, while equivalent keys exist unused | `apps/rider/lib/screens/safety/sos_screen.dart:32`, `:33`, `:35`, `:39`, `:115` vs unused `app_strings.dart:2584`, `:2588`, `:2592` | An English-locale rider gets an all-Arabic emergency dialog. The captain app does this correctly | confirmed |
| F-14-18 | S3 | No `NumberFormat` anywhere; currency is concatenated at 36 sites with inconsistent precision | `rider/profile/profile_screen.dart:703` (2dp); `rider/ride/payment_methods_screen.dart:66` (0dp); `rider/ride/captain_bids_sheet.dart:459` (rounded) | The same balance renders three ways across three screens | confirmed |
| F-14-19 | S3 | One mixed-numeral string violates the otherwise-consistent Western-digit policy | `app_strings.dart:1978` | `3 رحلة • آخر ٧ أيام` — two digit scripts in one line | confirmed |
| F-14-20 | S3 | Zero ICU syntax in the ARB files — no `plural`, no `select`, no `placeholders` blocks | measured across all four ARB files | If the ARB pipeline is ever revived it will inherit the same plural bugs | confirmed |
| F-14-21 | S3 | 187 `isAr` ternaries in the rider app derive direction/language by string comparison instead of reading `Directionality` | `rider/home/home_screen.dart:703-704`, `:765-766`; `rider/places/saved_places_screen.dart:215-216` | Brittle: correct today, silently wrong if locale and direction ever diverge | confirmed |
| F-14-22 | S3 | Orthography is split across the catalogue: `جاري`/`جارٍ`, `ملغية`/`ملغاة`, `ـاً`/`ـًا`, ASCII `...` vs `…` | `app_strings.dart:1878` vs `:2344`; `:2413` vs `:2546`; `:1884` vs `:2985`; `:2182` vs `:1940` | Reads as several authors with no style guide, because it is | confirmed |
| F-14-23 | S3 | Terminology drift on the core nouns: `سائق` vs `كابتن`, `العميل` vs `الراكب`, `التكلفة`/`الأجرة`/`السعر`, six variants of "estimated fare" | `app_strings.dart:2706`, `:2710`, `:3391` (`سائق`); `:1820`, `:1851`, `:1855` (`العميل`); `:1823`, `:1916`, `:3165` | Vocabulary inconsistency reads as an unfinished product | confirmed |
| F-14-24 | S3 | The admin console has no i18n library and 103 physical-direction Tailwind utilities, though it is already Arabic/RTL-first | `apps/admin/src/components/layout/Layout.tsx:10`; `apps/admin/package.json`; zero logical-property usages | ~305 hardcoded Arabic strings. Adding English later is a real project, not a config change | confirmed |
| F-14-25 | S3 | `bidsEtaMinutes` takes a `String`, making a plural fix impossible without a signature change | `app_strings.dart:2722` | A type choice has locked in a copy bug | confirmed |
| F-14-26 | S3 | Rider `pubspec.yaml` has no `generate: true`; the captain's does | `apps/captain/pubspec.yaml:54`; absent in `apps/rider/pubspec.yaml` | The rider's generated localizations are stale committed artifacts; the captain's regenerate at build. Two build behaviours for one pipeline | confirmed |
| F-14-27 | S4 | Four near-identical phrasings of "move the map to set the location" | `app_strings.dart:2672`, `:2971`; `rider/home/home_screen.dart:1432`; `rider/home/location_search_sheet.dart:321` | Same sentence, four endings | confirmed |
| F-14-28 | S4 | Six names for the SOS feature | `apps/rider/lib/l10n/app_ar.arb:37`; `app_strings.dart:2466`, `:2584`, `:3619`, `:3627`; `rider/safety/sos_screen.dart:115` | The one feature a user must recognise instantly has no fixed name | confirmed |
| F-14-29 | S4 | Duplicate identical methods `onbStepCounter` and `stepOfTotal` | `app_strings.dart:3434`, `:3667` | Catalogue bloat; two keys, one string | confirmed |
| F-14-30 | S4 | `'عنوان الدفع (IPA) أو رقم الحساب'` ships untranslated fintech jargon | `app_strings.dart:2019` | No InstaPay user recognises "payment address"; `IPA` is unexplained | confirmed |

### Expanding the blockers

**F-14-01 — the localisation system is a decoy.** The repository looks like it has a conventional Flutter localisation setup. It has all the artefacts: `l10n.yaml`, four ARB files, generated `AppLocalizations` classes with the standard doc comment telling you to register the delegate. Nobody registered it. The delegate list in both apps stops at the three `Global*` delegates, so `AppLocalizations.of(context)` would return `null` if anything called it — and nothing does, because the team writes against `AppStrings` instead.

This is worse than having no ARB files. A new engineer follows the obvious convention, adds a key to `app_ar.arb` and `app_en.arb`, sees the generated class update, and ships a string that can never render. Nothing fails. `flutter analyze` is clean. `check_l10n_parity.py` passes. The 104 keys already sitting there — including a `pickup` key whose Arabic says "drop-off" — look maintained.

The fix is a one-line decision, not a one-line change: either register the delegate and migrate onto ARB, or delete the ARB tree and the generated output and make `AppStrings` the only catalogue. What cannot continue is both.

**F-14-02 — the language switch does not switch the language.** The rider app exposes a language control in four places, including a proper dropdown in settings (`apps/rider/lib/screens/profile/settings_screen.dart:44-49`). Flip it to English and you get: the app bar in English (Material's own delegates), the captain screens in English (they migrated), and 359 Arabic string literals still on screen across 23 rider files — `trip_screen.dart` alone holds 46, `profile_screen.dart` 34, `captain_bids_sheet.dart` 22.

Meanwhile 201 members of the shared catalogue sit translated and unused, many of them exactly the strings those screens need: `bidsChooseCaptainTitle`, `bidsAllCaptainsVerified`, `bidsCaptainFallback`, `availableBalanceLabel`. The work is half-done in the most expensive way — the translations exist, the call sites were never rewired.

For an Egyptian product this is not a launch blocker because Arabic is the default and the overwhelming majority of users will never touch the switch. It is a blocker on *shipping the switch*. Either finish the rider migration or remove the control until it is finished; a visible toggle that produces a bilingual mess is worse than no toggle.

**F-14-03 — every error path speaks English.** This is the finding with the widest blast radius, because it is not scoped to a screen: it is the failure mode of every API call in the product.

The API's error envelope carries a machine `code` and a human `error`. Nine codes carry Arabic. Roughly sixty-two carry English. The Flutter client reads `data['error']` and throws it (`packages/flutter_shared/lib/services/api_client.dart:32`), and eleven confirmed call sites render that string straight into a snackbar or an inline error slot.

So an Egyptian rider whose card is declined, whose promo code expired, whose trip was taken by another captain, or who simply lost signal, is shown English. In three places — `apps/rider/lib/screens/places/saved_places_screen.dart:79`, `:90`, `:106` — they are shown the Dart exception wrapper too: `Exception: file required`.

The hybrid cases are the most revealing. `apps/captain/lib/screens/documents/document_upload_screen.dart:815` renders `strings.docErrorPrefix(...)`, producing `خطأ: File too large (max 10MB)`. Someone localised the *frame* around the message and never noticed the message itself never was. The same pattern is at `captain/screens/earnings/wallet_screen.dart:257` — `فشل طلب السحب: Validation failed`.

The mapping table in §6 (P0.3) is the deliverable that closes this. It is a client-side concern: the API should keep returning stable English codes and stable English `error` strings for logs, and the client should translate the `code`, never display the `error`.

### Expanding the majors worth reading before the plan

**F-14-07 — "go online" became "connect to the internet".** `app_strings.dart:3554` renders `'اتصل بالإنترنت لعرض الرحلات المتاحة'` for the English source `'Go online to see available trips'` (`:5504`). In ride-hailing, "go online" means *start your shift*. The Arabic instructs a captain sitting in his car with full 4G to fix his internet connection.

The captain app's own ARB file already has this right — `apps/captain/lib/l10n/app_ar.arb:14` says `"goOnline": "ابدأ العمل"` — but that file is dead (F-14-01), so the wrong string is the one that ships. This is a supply-side revenue bug wearing a copy bug's clothes: the empty state a captain sees when he has no trips tells him the wrong reason and the wrong remedy.

**F-14-09 — Arabic plurals, and a migration that went backwards.** Arabic needs four count forms: singular, dual, paucal (3–10, broken plural), and 11+ (singular accusative). Nine methods in the catalogue interpolate a count into Arabic text. One handles it correctly, and it is a model of how to do it:

```dart
// app_strings.dart:3570-3575
String requestsNearbyCount(int count) {
  if (count == 1) return 'رحلة واحدة متاحة بالقرب منك';
  if (count == 2) return 'رحلتان متاحتان بالقرب منك';
  if (count <= 10) return '$count رحلات متاحة بالقرب منك';
  return '$count رحلة متاحة بالقرب منك';
}
```

The others do not. `aboutMinutes` (`:1832`) renders `~2 دقيقة` and `~3 دقيقة`. `tripsRecorded` (`:2119-2120`) uses an English-shaped binary ternary — `count == 1 ? 'رحلة' : 'رحلات'` — which produces `2 رحلات` (should be dual `رحلتين`) and `404 رحلات` (should be `404 رحلة`). `docRequiredMissing` (`:2319`) renders `ارفع 1 مستندات مطلوبة أولاً` in the most common case a document wizard hits.

The part that should worry a reviewer is the direction of travel. Two rider screens already solved this, with comments explaining the rule:

```dart
// apps/rider/lib/screens/ride/captain_bids_sheet.dart:428-431
/// Arabic plural for the trip counter: 3–10 takes the broken plural
/// (رحلات), everything else the singular (رحلة). "404 رحلة" is correct;
/// "404 رحلات" is not.
static String _tripsLabel(int n) => (n >= 3 && n <= 10) ? 'رحلات' : 'رحلة';
```

Their catalogue replacements — `bidsTripCount` (`:2726`) and `bidsEtaMinutes` (`:2722`) — discard the rule. `bidsEtaMinutes` additionally takes a `String`, so no call site can branch on the number even if someone wanted to fix it (F-14-25). The shared catalogue is currently a regression against the screens it exists to replace, which means the migration needs a plural policy before it continues, not after.

**F-14-10 — mock data is production copy.** Five notification strings ship hardcoded sample values: `'وصلت بسلامة. الأجرة 45 ج.م.'` (`:2071`), `'تم إضافة 100 ج.م إلى محفظتك.'` (`:2083`), `'كيف كانت رحلتك مع الكابتن أحمد؟'` (`:2089`), `'منذ 5 دقائق'` (`:2092`), `'منذ 3 ساعات'` (`:2098`).

These are getters with no parameters. There is no code path that could substitute a real fare, a real name, or a real elapsed time. Every rider's notification list will say the trip cost 45 EGP and the captain was called Ahmed. `'تم إضافة 100 ج.م'` also carries a grammar error — `إضافة` is feminine, so `تم` should be `تمت`, which the same file gets right four hundred lines earlier at `:2247`.

**F-14-16 — everyone is male.** There is no `gender` column anywhere in the schema — confirmed across all 19 migrations, `0001_init.sql:3-13` for users and `0015_captain_onboarding_fields.sql:10-17` for captains. Roughly forty imperatives and a dozen adjective agreements are masculine: `'متصل ومستعد للرحلات'` (`:1866`), `'أنت غير متصل حالياً'` (`:1884`), `'هل أنت متأكد أنك تريد تسجيل الخروج؟'` (`:2499`), `'أنت صاحب القرار'` (`:3135`), and — in the safety flow, which is the worst place for it — `'هل أنت متأكد من تفعيل حالة الطوارئ؟'` (`:2588`).

The right response is not to add a gender column and two variants of every string. It is to rewrite to gender-free constructions, which Arabic supports well and which the file occasionally already achieves by accident: `'هل أنت في حالة طوارئ؟'` (`:3643`) and `'لست في خطر'` (`:3650`) both read either way unvocalised. §6/P1.4 makes this a copy rule rather than a schema change.

**F-14-17 — the rider's emergency dialog cannot be translated.** `apps/rider/lib/screens/safety/sos_screen.dart` never calls `AppStrings`. Its confirmation dialog is hardcoded Arabic at lines 32, 33, 35 and 39, and its screen title at line 115 (`'الطوارئ والسلامة'`) has no key anywhere in the catalogue. Keys for exactly this dialog exist and are unused: `sosWarningTitle` (`:2584`), `sosConfirmMessage` (`:2588`), `sosConfirmAction` (`:2592`).

The captain's SOS screen does it correctly (`apps/captain/lib/screens/safety/sos_screen.dart:124`, `:134`, `:160`, `:170`, `:192`). Two implementations of the same safety-critical surface, one of which cannot render in the user's chosen language. This one belongs to T17 as well as here.

**F-14-15 — the typeface is a network call.** `AppTokens.font` resolves to `GoogleFonts.cairo` (`app_theme.dart:265`). The `google_fonts` package downloads the face at runtime and caches it; no font file is bundled and no `fonts:` block exists in any pubspec. On a cold install with weak or no connectivity — a realistic first-launch condition in much of the Egyptian market — Arabic renders in the platform fallback until the download succeeds.

Cairo is the right choice: full Arabic coverage, good at small sizes, designed for screen. Bundling the two or three weights actually used costs roughly 300–500 KB in the APK and removes a startup network dependency. That trade is obviously worth taking for an Arabic-first product, and it also removes a third-party request at launch, which T25 will want to know about.

## 5. Benchmark gap

**Careem** is the reference for this market and the fairest comparison. Its Egyptian product is Arabic-first in the same sense Synaptic Go intends: Arabic is the default, the copy is written in Arabic rather than translated into it, and the register is deliberately warm Egyptian rather than MSA. Careem also uses Western digits throughout its Egyptian apps, which corroborates the policy this codebase already chose. *(Confident on the Arabic-first default and the warm register; the digit policy I have observed but mark as* `likely` *rather than verified at a specific build.)*

Where Synaptic Go actually sits against it: the *ambition* is right and partly realised — the captain app's migrated screens read well, and two strings (`app_strings.dart:2356`, `:2742`) are genuinely excellent Egyptian. But 95% of the catalogue is MSA, and the gap between `'جارٍ البحث عن كباتن قريبين'` and its own subtitle `'هتوصلك عروض الأسعار هنا أول ما يردّوا'` — two lines of the same empty state, two registers — is the kind of seam Careem does not have.

**inDrive** is the closer functional analogue given the bidding model, and it is genuinely multilingual with solid RTL. Its relevant lesson is not tooling but discipline: the price-negotiation surface is where numbers, currency and counts collide, and inDrive keeps that surface terse and numerically unambiguous. Synaptic Go's equivalent surface is the weakest part of its copy — `'سعر معدّل'` on an action button (`:1844`), `'الوصول $km كم'` for what is actually the distance to the rider (`:1826`), and three offer-hint methods that accept the price as a parameter and then never interpolate it (`:3201`, `:3205`, `:3209`), silently deleting the amounts the inline originals used to show (`rider/home/fare_estimate_sheet.dart:775`, `:781`).

**Uber** is the process benchmark rather than the product one. What matters from Uber is not their string service but three habits this repo lacks: ICU pluralisation as the default authoring format so plural bugs are structurally impossible; a per-user locale attribute that server-side messaging reads, so push and SMS match the app; and a CI gate that fails a build on an untranslated or unreachable key. Synaptic Go has none of the three. It has a CI gate, but pointed at the catalogue that cannot break (F-14-04).

**The honest summary of the gap.** On *coverage* the product is closer than it looks — 545 catalogue members with both locales complete is real work, and the captain app is genuinely migrated. On *correctness* it is further behind than it looks: plurals are wrong, gender is uniformly masculine, six terms compete for "pickup", and the error surface is English. On *infrastructure* it is behind in a way that will not fix itself: no server-side locale, no ICU, no guard on the files that can drift, and a dead pipeline sitting next to a live one.

The single structural difference between Synaptic Go and all three benchmarks is that none of them have two string catalogues.

## 6. Improvement plan

Ordered by dependency, then by value. P0 items are the S1 set plus the two S2s that block them.

### P0.1 — Choose one catalogue and delete the other

- **Goal** — a developer adding a user-visible string has exactly one place to put it, and no way to add one that never renders.
- **Design** — keep `AppStrings` as the source of truth and **delete the ARB pipeline**. Rationale: `AppStrings` holds 545 members against the ARB's 104, it is compile-safe by construction (a missing translation is a build error, which is a stronger guarantee than any ARB linter), and it is what 343 live call sites already use. Reviving the ARB path would mean migrating 545 members, re-solving compile-safety with tooling, and running both during the transition. That is a large project whose only prize is convention. Recommend instead: delete `apps/{rider,captain}/lib/l10n/` entirely (ARB, generated output, `l10n.yaml`), drop `generate: true` from `apps/captain/pubspec.yaml:54`, and move the two ARB-only strings worth keeping (`appSlogan`, `phoneNumberHint`) into `AppStrings`. Record the decision in `packages/flutter_shared/lib/l10n/README.md` so the next engineer does not re-add the scaffolding. Before deleting, diff the 104 ARB keys against `AppStrings` and port anything missing — `pickup` must be ported as **`مكان الركوب`**, not as the existing wrong value.
- **Files to change** — delete `apps/rider/lib/l10n/**`, `apps/captain/lib/l10n/**`, `apps/rider/l10n.yaml`, `apps/captain/l10n.yaml`; edit `apps/captain/pubspec.yaml:54`; add `packages/flutter_shared/lib/l10n/README.md`.
- **DB** — none.
- **API contract** — none.
- **Effort** — S.
- **Risk** — low; the deleted code is provably unreferenced. Rollback is a revert. The one real risk is deleting a key that a future ARB revival would have wanted, which the pre-delete diff mitigates.
- **Acceptance criteria** — `grep -r AppLocalizations apps/ packages/` returns nothing; no `.arb` file remains; both apps build; the string count in `AppStrings` is ≥ 545 + ported keys.
- **Tests** — a CI grep step that fails if `.arb` or `AppLocalizations` reappears (folded into P0.2).

### P0.2 — Make the parity guard guard something

- **Goal** — CI fails when a user-visible string is added outside the catalogue, when a catalogue member is orphaned, or when the deleted pipeline reappears.
- **Design** — extend `scripts/check_l10n_parity.py` with three new checks, keeping the existing duplicate/drift logic. (a) **Inline-literal budget**: scan every non-generated Dart file under `apps/*/lib` and `packages/flutter_shared/lib` for string literals containing Arabic script; compare against a checked-in baseline file of per-file counts; fail if any file's count *increases*. This ratchets the 359/53/32 downward without demanding a big-bang migration. (b) **Orphan report**: list abstract members never referenced by `.<member>`; warn, and fail above a threshold that starts at 201 and only decreases. (c) **Pipeline guard**: fail if any `.arb` file or `AppLocalizations` reference exists. Wire it into CI as a required check.
- **Files to change** — `scripts/check_l10n_parity.py`; new `scripts/l10n_baseline.json`; CI workflow — **note: `.github/workflows/**` is not writable by this review's tooling, so the YAML is supplied as `docs/plan/assets/14-l10n-ci.yml.txt` and must be applied by hand.**
- **DB** — none.
- **API contract** — none.
- **Effort** — M.
- **Risk** — low. A noisy ratchet annoys developers; mitigate by failing only on increase, never on absolute count.
- **Acceptance criteria** — adding a new Arabic literal to `rider/trip_screen.dart` fails CI; adding one to `AppStrings` does not; re-adding an `.arb` file fails CI.
- **Tests** — unit tests for the scanner against three fixture files (clean, added literal, re-added ARB).

### P0.3 — Map API error codes to Arabic on the client

- **Goal** — no user ever sees an English server string or a Dart exception wrapper.
- **Design** — add `AppStrings.errorForCode(String code, {String? fallback})` to the shared catalogue, implemented in both locale classes over the table below. Change `ApiClient` to surface the structured `code` alongside the message — today `_decode` (`packages/flutter_shared/lib/services/api_client.dart:32`) throws only the human string, so the code is discarded at the boundary and cannot be recovered downstream. Introduce a typed `ApiException { code, serverMessage, status }`, throw that, and change every `catch` site to render `strings.errorForCode(e.code)`. The server's English `error` string stays exactly as it is — it is useful in logs and in Sentry — it simply stops being displayed. Unknown codes fall back to `errorGeneric`.
- **Files to change** — `packages/flutter_shared/lib/services/api_client.dart`; `packages/flutter_shared/lib/l10n/app_strings.dart`; the eleven confirmed call sites: `rider/screens/login_screen.dart:165-169`, `rider/screens/home/fare_estimate_sheet.dart:165`, `:220`, `rider/screens/places/saved_places_screen.dart:79`, `:90`, `:106`, `rider/screens/ride/captain_bids_sheet.dart:150-157`, `captain/screens/home/active_trip_panel.dart:114-116`, `captain/screens/documents/document_upload_screen.dart:782-784`, `:815`, `captain/screens/documents/documents_onboarding_screen.dart:258-259`, `:282-284`, `captain/screens/onboarding/onboarding_screen.dart:338-341`, `:358`, `captain/screens/profile/settings_screen.dart:79`, `:97`, `captain/screens/earnings/wallet_screen.dart:257`, `captain/screens/earnings/earnings_screen.dart:54`.
- **DB** — none.
- **API contract** — no change required. Recommended hardening for a later phase: guarantee that every error response carries a `code` (a handful of admin/search paths return `error` with no `code` — `apps/api/src/routes/search.ts:11`, `apps/api/src/routes/admin.ts:498`), and freeze the code list as a shared constant.
- **Effort** — M.
- **Risk** — medium: touching every error path can swallow errors if a `catch` is rewritten carelessly. Mitigate by keeping `serverMessage` on the exception and logging it unconditionally, so nothing is lost from telemetry. Rollback is per-screen.
- **Acceptance criteria** — no screen renders `e.toString()`; every code in the table resolves to Arabic and English text; an unknown code renders `errorGeneric`; the raw server message still reaches logs.
- **Tests** — a table-driven unit test asserting every code in the table maps to non-empty text in both locales, and that the set of codes in the table matches a constant extracted from the API (a small script diffing the two prevents silent drift).

#### The mapping table

Arabic column is the proposed user-facing text. Terminology follows P1.3. Codes marked † already ship Arabic server-side and can be shown as-is if the client cannot resolve the code, but should still be mapped for consistency.

| Code | HTTP | Server message (stays, for logs) | Proposed Arabic | Source |
|---|---|---|---|---|
| `RATE_LIMITED` | 429 | Too many requests | حاول تاني بعد شوية | `middleware/rateLimit.ts:40` |
| `INVALID_JSON` | 400 | Invalid JSON body | في حاجة مانجحتش. جرّب تاني | `middleware/rateLimit.ts:71` |
| `VALIDATION_ERROR` | 400 | Validation failed | البيانات مش مكتملة أو فيها خطأ | `middleware/rateLimit.ts:79` |
| `UNAUTHORIZED` | 401 | Unauthorized | محتاج تسجّل دخول تاني | `middleware/auth.ts:46` |
| `WRONG_TOKEN_TYPE` | 401 | Use access token | انتهت الجلسة. سجّل دخول تاني | `middleware/auth.ts:53` |
| `INVALID_TOKEN` | 401 | Invalid or expired token | انتهت الجلسة. سجّل دخول تاني | `middleware/auth.ts:63` |
| `FORBIDDEN` | 403 | Forbidden | مالكش صلاحية للخطوة دي | `middleware/auth.ts:71` |
| `TURNSTILE_FAILED` † | 400 | تحقق الإنسانية فشل | التحقق مانجحش. جرّب تاني | `routes/auth.ts:77` |
| `INVALID_OTP` | 401 | Invalid or expired code | الرمز غلط أو انتهت صلاحيته | `routes/auth.ts:151`, `:174` |
| `OTP_EXPIRED` | 401 | Code expired | انتهت صلاحية الرمز. اطلب رمز جديد | `routes/auth.ts:153` |
| `TOO_MANY_ATTEMPTS` | 429 | Maximum verification attempts exceeded | حاولت كتير. استنى شوية وجرّب تاني | `routes/auth.ts:160` |
| `USER_CREATE_FAILED` | 500 | Failed to create user | ماقدرناش نعمل الحساب. جرّب تاني | `routes/auth.ts:221` |
| `SUSPENDED` | 403 | Account suspended | الحساب موقوف. كلّم الدعم | `routes/auth.ts:223`, `:398` |
| `INVALID_REFRESH` | 401 | Invalid refresh token | انتهت الجلسة. سجّل دخول تاني | `routes/auth.ts:271` |
| `REFRESH_REVOKED` | 401 | Refresh token revoked | تم إنهاء الجلسة. سجّل دخول تاني | `routes/auth.ts:286` |
| `REFRESH_EXPIRED` | 401 | Refresh token expired | انتهت الجلسة. سجّل دخول تاني | `routes/auth.ts:289` |
| `USER_INVALID` | 401 | User not found or suspended | الحساب مش متاح. كلّم الدعم | `routes/auth.ts:302` |
| `EMAIL_EXISTS` | 409 | Email already exists | الإيميل ده مستخدم قبل كده | `routes/auth.ts:364` |
| `CREATE_FAILED` | 500 | User creation failed | ماقدرناش نعمل الحساب. جرّب تاني | `routes/auth.ts:380` |
| `INVALID_CREDENTIALS` | 401 | Invalid credentials | بيانات الدخول غير صحيحة | `routes/auth.ts:394`, `:397` |
| `ADMIN_EXISTS` | 403 | Admin already exists | حساب الأدمن موجود بالفعل | `routes/auth.ts:429` |
| `NOT_FOUND` | 404 | Not found / User not found / Trip not found | مالقيناش المطلوب | `routes/auth.ts:466`, `trips.ts:652`, `:1156` |
| `NO_PROFILE` | 400 | Complete captain profile first | كمّل بيانات حسابك الأول | `routes/captain.ts:145`, `:322` |
| `LATLNG_REQUIRED` | 400 | lat/lng required when going online | مش قادرين نحدد موقعك. فعّل الموقع وجرّب تاني | `routes/captain.ts:158` |
| `INVALID_KEY` | 400 | Invalid document key | نوع المستند غير معروف | `routes/captain.ts:545` |
| `TYPE_INACTIVE` | 400 | Document type is not currently accepted | المستند ده مش مطلوب حاليًا | `routes/captain.ts:558` |
| `MISSING_FILE` | 400 | file required | اختار الملف الأول | `routes/captain.ts:629`, `user.ts:126` |
| `EMPTY_FILE` | 400 | File is empty | الملف فاضي. اختار صورة تانية | `routes/captain.ts:630`, `user.ts:127` |
| `FILE_TOO_LARGE` | 400 | File too large (max 10MB) | الملف كبير. الحد الأقصى ١٠ ميجا | `routes/captain.ts:631`, `user.ts:129` |
| `MISSING_KEY` | 400 | key required | في بيانات ناقصة | `routes/captain.ts:676` |
| `NO_PRICING` | 500 | Pricing not configured | التسعير مش متاح في منطقتك دلوقتي | `routes/trips.ts:324` |
| `INVALID_TRANSITION` | 400 | Cannot cancel from ${status} | مش ممكن الإلغاء في المرحلة دي | `routes/trips.ts:724` |
| `MISSING_ID` | 400 | trip id required | في بيانات ناقصة | `routes/trips.ts:832` |
| `NOT_APPROVED` | 403 | Captain not approved | حسابك لسه تحت المراجعة | `routes/trips.ts:838` |
| `OFFLINE` † | 403 | يجب أن تكون متصلاً… | لازم تكون أونلاين الأول | `routes/trips.ts:843`, `:1166` |
| `NOT_AVAILABLE` | 409 | Trip not available (${status}) | الرحلة دي مابقتش متاحة | `routes/trips.ts:851` |
| `BUSY` | 409 | You already have an active trip | عندك رحلة شغالة دلوقتي | `routes/trips.ts:859` |
| `TRIP_TAKEN` | 409 | Trip was already taken by another captain | كابتن تاني خد الرحلة | `routes/trips.ts:869` |
| `CONFLICT` | 409 | Trip is already completed or state changed | حالة الرحلة اتغيّرت. حدّث الصفحة | `routes/trips.ts:980`, `intercity.ts:267` |
| `NOT_COMPLETED` | 400 | Trip not completed | الرحلة لسه ماخلصتش | `routes/trips.ts:1100` |
| `ALREADY_RATED` | 409 | Already rated | قيّمت الرحلة دي قبل كده | `routes/trips.ts:1118` |
| `TRIP_CLOSED` | 400/409 | Trip is no longer accepting bids / open | الرحلة مابقتش بتستقبل عروض | `routes/trips.ts:1158`, `:1280` |
| `BID_NOT_FOUND` | 404 | Bid not found or no longer valid | العرض ده مابقاش متاح | `routes/trips.ts:1288` |
| `CAPTAIN_NOT_APPROVED` | 409 | Captain is not approved | الكابتن ده مش معتمد | `routes/trips.ts:1296` |
| `TRIP_CONFLICT` | 409 | Trip already assigned or completed | الرحلة اتاخدت بالفعل | `routes/trips.ts:1313` |
| `INSUFFICIENT_BALANCE` † | 400/409 | رصيد غير كافٍ… | رصيدك مش كفاية | `routes/wallet.ts:110`, `:120`, `intercity.ts:110`, `:163` |
| `PROMO_INVALID` | 404 | Invalid promo code | الكود ده مش صحيح | `routes/promo.ts:28` |
| `PROMO_EXPIRED` | 400 | Promo expired | الكود ده انتهت صلاحيته | `routes/promo.ts:31` |
| `PROMO_EXHAUSTED` | 400 | Promo fully used | الكود ده اتستخدم بالكامل | `routes/promo.ts:34` |
| `PROMO_EXISTS` | 409 | Promo code already exists | الكود ده موجود بالفعل | `routes/promo.ts:79` |
| `MISSING_CODE` | 400 | code required | اكتب الكود الأول | `routes/promo.ts:97` |
| `PAYMOB_INTENTION_FAILED` | 502 | (raw upstream Paymob message) | مانقدرش نكمل الدفع دلوقتي. جرّب تاني | `routes/payments.ts:91` |
| `SCHEDULE_CLOSED` | 400 | Schedule closed | الحجز على الرحلة دي اتقفل | `routes/intercity.ts:94` |
| `DEPARTED` | 400 | Schedule already departed | الرحلة قامت بالفعل | `routes/intercity.ts:96` |
| `NO_SEATS` | 409 | Not enough seats available | مافيش أماكن كفاية | `routes/intercity.ts:123` |
| `ALREADY_BOARDED` † | 409 | لا يمكن الإلغاء بعد صعود الراكب | مش ممكن الإلغاء بعد ما الراكب ركب | `routes/intercity.ts:252` |
| `ALREADY_DEPARTED` † | 409 | لا يمكن الإلغاء بعد موعد المغادرة | مش ممكن الإلغاء بعد ميعاد القيام | `routes/intercity.ts:255` |
| `QR_MISMATCH` | 400 | Invalid QR | الكود ده مش صحيح | `routes/intercity.ts:384` |
| `REVOKED` | 410 | Token revoked | الرابط ده مابقاش شغال | `routes/safety.ts:98` |
| `EXPIRED` | 410 | Token expired | انتهت صلاحية الرابط | `routes/safety.ts:100` |
| `MISSING_TOKEN` | 400 | token required | في بيانات ناقصة | `routes/devices.ts:37` |
| `LATLNG_RANGE` | 400 | lat/lng out of range | الموقع ده مش صحيح | `routes/geocode.ts:18` |
| `QUERY_TOO_SHORT` | 400 | q must be at least 2 chars | اكتب حرفين على الأقل | `routes/geocode.ts:32` |
| `NOT_EMPLOYEE` | 403 | Not a company employee | مش مسجّل ضمن موظفي الشركة | `routes/companies.ts:36` |
| `SPEND_LIMIT` † | 403 | تجاوزت الحد الشهري للإنفاق | وصلت للحد الشهري للإنفاق | `routes/companies.ts:50` |
| `NO_COMPANY` † | 403 | لا تملك صلاحية بوابة الشركة | مالكش صلاحية بوابة الشركة | `routes/companies.ts:225` |
| `INTERNAL` | 500 | Summary failed | في حاجة مانجحتش. جرّب تاني | `routes/companies.ts:180` |
| `MISSING_FIELDS` | 400 | id and titleAr are required | في بيانات ناقصة | `routes/admin.ts:705` |
| `DUPLICATE_ID` | 409 | Document type id already exists | المعرّف ده موجود بالفعل | `routes/admin.ts:719` |
| `FILE_NOT_FOUND` | 404 | File not found | مالقيناش الملف | `routes/admin.ts:901` |
| `BAD_KEY` | 400 | Invalid avatar path | مسار الصورة مش صحيح | `routes/user.ts:204` |

*(Note the file-size string uses Arabic-Indic `١٠` above only because it sits inside a sentence; per P1.5 it should ship as `10`. Flagged so the implementer does not copy it verbatim.)*

### P0.4 — Persist the locale, and stop shipping a switch that lies

- **Goal** — a language choice survives restart; the switch is either honest or hidden.
- **Design** — two parts. (a) Persist: add a `_kLocale` SharedPreferences key next to the existing `_kThemeMode`, write it in `setLocale`/`toggleLanguage` out-of-band exactly as `setThemeMode` already does (`app_state.dart:586`), and restore it in `bootstrap()`. Mirror in `captain_state.dart`. (b) Gate: until the rider migration in P1.1 lands, hide the English option in the rider app behind the same build flag used for internal builds, or remove the four rider entry points and keep only the settings dropdown. Shipping one honest control beats four dishonest ones.
- **Files to change** — `apps/rider/lib/services/app_state.dart:532-544`, `:139` (bootstrap); `apps/captain/lib/services/captain_state.dart:1117-1120`, `:212` (bootstrap); `apps/rider/lib/screens/profile/profile_screen.dart:407`, `:552`; `apps/rider/lib/screens/home/home_screen.dart:694`; `apps/rider/lib/screens/login_screen.dart:252`.
- **DB** — none.
- **API contract** — none yet; P1.6 adds the server side.
- **Effort** — S.
- **Risk** — low. A corrupt persisted value must fall back to `ar-EG`, matching the defensive pattern already used for `themeMode` (`app_state.dart:553-555`).
- **Acceptance criteria** — set English, force-quit, relaunch → still English; corrupt the pref → app opens in Arabic, no crash.
- **Tests** — widget test for restore-on-bootstrap; unit test for the corrupt-value fallback.

### P1.1 — Finish the rider migration onto `AppStrings`

- **Goal** — drive the rider app's 359 inline Arabic literals and 187 `isAr` ternaries to zero, consuming the 201 orphaned members that already exist.
- **Design** — screen-by-screen, highest count first, following the captain app's reference pattern named in `app_strings.dart:41-45`. Order by literal count: `trip_screen.dart` (46), `profile_screen.dart` (34), `captain_bids_sheet.dart` (22), `location_search_sheet.dart` (19), `saved_places_screen.dart` (18), `fare_estimate_sheet.dart` (17), `help_screen.dart` (16), `home_screen.dart` (16), then the tail. Each screen: replace literals with `strings.x`, delete the local `isAr` where it only selected copy, keep it only where it genuinely selects layout (and then replace it with `Directionality.of(context)` per P1.2). Where a needed member is already orphaned, use it rather than adding a new one — and where the orphan's text has drifted from the inline literal, take the *better* of the two and note the choice in the PR. Three known drifts to resolve: `'تعيين نقطة الانطلاق'` (`home_screen.dart:750`) vs `'تحديد نقطة الانطلاق'` (`app_strings.dart:2939`); `'موقعي الحالي (GPS)'` (`home_screen.dart:240`) vs `'الموقع الحالي (GPS)'` (`:2920`); `'جارٍ حساب المسار...'` (`home_screen.dart:1253`) vs `'جاري حساب المسار…'` (`:2963`). The baseline ratchet from P0.2 enforces monotone progress.
- **Files to change** — 23 rider screen files; `packages/flutter_shared/lib/l10n/app_strings.dart` for the residual gaps.
- **DB** — none.
- **API contract** — none.
- **Effort** — L (estimate 6–9 engineer-days at observed density; the captain app is the proof it is tractable).
- **Risk** — medium: mechanical edits across 23 files risk copy regressions. Mitigate with the ratchet, screen-by-screen PRs, and a golden-screenshot pass per screen in both locales.
- **Acceptance criteria** — rider inline-Arabic count is 0; orphan count drops below 40; English locale renders no Arabic outside user-generated content and brand marks.
- **Tests** — golden tests for the eight highest-traffic rider screens in `ar-EG` and `en-US`.

### P1.2 — Fix RTL: directional primitives, icons, and the two overrides

- **Goal** — no screen depends on physical direction; no navigation icon points the wrong way in Arabic.
- **Design** — four workstreams. (a) **Chat bubbles**: replace `Alignment.centerLeft/centerRight` with `AlignmentDirectional.centerStart/centerEnd` at `rider/screens/trip/trip_chat_screen.dart:97`, copying `captain/screens/home/trip_chat_screen.dart:249-251`. (b) **Remove the hardcoded override** at `rider/screens/ride/captain_bids_sheet.dart:222-223` and fix the sheet's internals with directional primitives — this override is currently masking whatever layout bug prompted it, so budget for the underlying fix. (c) **Icons**: introduce one shared helper in `flutter_shared` — `GoIcons.back(context)`, `.forward(context)`, `.drillIn(context)`, `.send(context)` — that reads `Directionality.of(context)` and returns the correct glyph, then replace the 18 unguarded sites (`rider/trip/trip_chat_screen.dart:140`, `rider/trip/trip_screen.dart:282`, `rider/home/travel_mode_bottom_bar.dart:115`, `rider/home/location_search_sheet.dart:544`, `rider/ride/schedule_screen.dart:98`, `:118`, `captain/earnings/wallet_screen.dart:579`, `captain/profile/settings_screen.dart:931`, `shared/counter_offer_sheet.dart:255`, `captain/home/trip_chat_screen.dart:356`, `captain/documents/document_upload_screen.dart:893`, `captain/profile/settings_screen.dart:540`, and the four inverted wizard chevrons at `captain/documents/documents_onboarding_screen.dart:621`, `:652`, `captain/onboarding/onboarding_screen.dart:1269`, `:1312`). The helper also retires the six *correct but brittle* manual `isAr` icon swaps (`rider/home/home_screen.dart:765-766`, `rider/places/saved_places_screen.dart:215-216`, `rider/profile/profile_screen.dart:814`, `rider/places/saved_destinations_sheet.dart:359-360`). (d) **Physical insets**: `shared/widgets/map_controls.dart:75` and `rider/home/travel_mode_bottom_bar.dart:168` badge corners to `PositionedDirectional`; `rider/ride/trip_detail_screen.dart:111` to `EdgeInsetsDirectional`; `rider/home/home_screen.dart:703-704` to `PositionedDirectional(end: 16)`; `rider/profile/profile_screen.dart:531` to `TextAlign.start`. Leave the six verified-correct `TextDirection.ltr` overrides alone (phone numbers, fares, the wordmark, the date-picker dialog) and add a comment at each explaining why.
- **Files to change** — as enumerated; new `packages/flutter_shared/lib/widgets/go_icons.dart`.
- **DB** — none.
- **API contract** — none.
- **Effort** — M.
- **Risk** — low individually; the bids-sheet override (b) is the only item that could surface a hidden layout bug. Do it in its own PR.
- **Acceptance criteria** — zero `Icons.arrow_back|arrow_forward|chevron_left|chevron_right|send` outside `go_icons.dart`; zero `Alignment.center(Left|Right)` and `EdgeInsets.only(left:|right:)` in widget trees; the bids sheet renders LTR under an English locale.
- **Tests** — golden tests of the chat screens, the bids sheet and both onboarding wizards in both directions; a lint rule (custom `analysis_options` or the CI grep) banning the raw icons.

### P1.3 — Ratify the lexicon and rewrite the twenty highest-traffic strings

- **Goal** — one word per concept across both apps, and copy that sounds like a person.
- **Design** — adopt the decisions below as a checked-in style guide, then apply. **Terminology:** `كابتن`/`كباتن` (never `سائق` — fix `app_strings.dart:2706`, `:2710`, `:3391`); `الراكب` in captain-facing copy and second person in rider-facing copy (never `العميل` — fix `:1820`, `:1851`, `:1855`); `رحلة` for an assigned trip and `طلب` only for an unassigned request; `الأجرة` for money owed and `السعر` only inside the bidding UI (retire `التكلفة` at `rider/home/home_screen.dart:1188`); **`مكان الركوب`** ↔ `الوجهة` for the two endpoints, retiring `موقف النزول`, `موقف الراكب`, `موقف غير محدد`, `نقطة الالتقاط` and `نقطة الوصول`; `المحفظة` / `رصيدك` / `اشحن`; `إلغاء` for the action and `ملغية` for the state (one spelling); `عرض` reserved exclusively for a captain's bid, with the promo notification at `:2074` renamed to `خصم جديد`. **Orthography:** `جارٍ` everywhere, tanwīn as `ـًا`, ellipsis as `…`. **Register:** warm Egyptian for anything the user reads under pressure — empty states, errors, trip states, safety — and neutral MSA only for legal and document copy. **Gender:** prefer constructions that read either way; never add `ة` variants.
- **Files to change** — `packages/flutter_shared/lib/l10n/app_strings.dart` (Arabic class, and English where the source was the problem); new `docs/COPY_STYLE_AR.md`; the inline duplicates in the rider app fall out of P1.1.
- **DB** — none.
- **API contract** — none.
- **Effort** — M for the twenty below plus the terminology sweep; L if the whole 545-member catalogue is re-voiced (recommend doing the sweep now and the full re-voice in P2).
- **Risk** — low technically; the risk is bikeshedding. Mitigate by making the style guide the decision record and reviewing copy changes as copy, not as code.
- **Acceptance criteria** — zero occurrences of `سائق`, `العميل`, `موقف النزول`, `موقف الراكب`, `التكلفة`, `ملغاة`, `جاري`; the twenty strings below are live.
- **Tests** — the P0.2 script gains a banned-term list; a copy reviewer signs off the twenty.

#### The twenty rewritten strings

| # | Key / location | Current Arabic | Problem | Proposed Arabic | Why better |
|---|---|---|---|---|---|
| 1 | `pickup` — `apps/rider/lib/l10n/app_ar.arb:19` | موقف النزول | Names the drop-off — the opposite end of the trip | **مكان الركوب** | Correct endpoint, and the phrase Egyptians actually use |
| 2 | `tripSearchingTitle` — `app_strings.dart:2344` | جارٍ البحث عن كابتن… | Passive MSA gerund; sounds like a form, not a helper | **بندوّر لك على كابتن…** | Active and first-person — someone is working for you |
| 3 | `tripSearchingSubtitle` — `app_strings.dart:2347` | سنبلغك فور قبول كابتن لرحلتك | Written-Arabic register on the most anxious screen | **هنبلّغك أول ما كابتن يقبل** | Same promise, spoken, shorter |
| 4 | `bidsChooseCaptainTitle` — `app_strings.dart:2706` | اختيار سائق | Wrong brand noun; verbal noun where a heading wants a verb | **اختار كابتنك** | Restores `كابتن`, adds ownership |
| 5 | `bidsAllCaptainsVerified` — `app_strings.dart:2710` | تم التحقق من جميع السائقين | Passive bureaucratic MSA, four lines from `كابتن GoDrive` | **كل الكباتن موثّقين** | Reassurance as a plain statement, not an audit finding |
| 6 | `acceptWithFare` — `app_strings.dart:1841` | قبول بـ $fare ج.م | Verbal noun on the captain's most-tapped button | **اقبل بـ $fare ج.م** | An imperative reads as a button |
| 7 | `counterOffer` — `app_strings.dart:1844` | سعر معدّل | "Adjusted price" — a label, not an action; nobody says it | **اعرض سعرك** | Names the action, and uses `عرض` in its one sanctioned sense |
| 8 | `skipLabel` — `app_strings.dart:1847` | تخطي | Reads as *surmounting*; also spelled `تخطّي` at `:2856` | **تجاهل** | Unambiguous dismissal; settles the two-spelling split |
| 9 | `riderOfferedPrice` — `app_strings.dart:1820` | سعر العميل المقترح | `العميل` is bank vocabulary; too long for the chip | **سعر الراكب** | Correct noun, fits under a countdown |
| 10 | `pickupDistanceKm` — `app_strings.dart:1826` | الوصول $km كم | "The arrival N km" — names neither rider nor pickup | **الراكب على بعد $km كم** | States the fact the captain is deciding on |
| 11 | `offerExpired` — `app_strings.dart:1817` | انتهت مهلة العرض | `مهلة` is legal-notice register for a 15-second timer | **خلص وقت العرض** | Plain, same length, no blame |
| 12 | `sosActiveTitle` — `app_strings.dart:3643` | هل أنت في حالة طوارئ؟ | Clinical; raises panic instead of lowering it | **محتاج مساعدة دلوقتي؟** | Calm, human, gender-safe; asks about help, not status |
| 13 | `sosActiveBody` — `app_strings.dart:3646-3647` | استخدم هذا الزر فقط في حالات الخطر الحقيقي (حوادث، سرقة، اعتداء). | Reads as a liability disclaimer scolding the user | **الزر ده لحالات الخطر الحقيقي — حادثة أو سرقة أو اعتداء.\nإحنا معاك.** | Same guardrail, then a promise; ends on reassurance |
| 14 | `sosConfirmMessage` — `app_strings.dart:2588` | هل أنت متأكد من تفعيل حالة الطوارئ؟ سيتم إرسال موقعك للسلطات وإدارة التطبيق. | "Are you sure?" introduces doubt at the worst moment; masculine | **هنبعت موقعك دلوقتي لفريق الأمان والجهات المختصة. تأكيدك بيبدأ المساعدة فورًا.** | Declarative not interrogative; gender-free; frames confirmation as help starting |
| 15 | `sosConfirmAction` — `app_strings.dart:2592` | تأكيد الطوارئ | Confirms a category, not an action | **ابعت طلب المساعدة** | The button says what it sends |
| 16 | `sosCancelAction` — `app_strings.dart:3650` | إلغاء — لست في خطر | Leads with the system word and a negation of danger | **أنا بخير، إلغاء** | Leads with reassurance in the user's own voice |
| 17 | `tripCaptainArrived` — `app_strings.dart:2365` | وصل الكابتن — تفضّل بالنزول | `النزول` is ambiguous (come down / get out); `تفضّل` is masculine | **الكابتن وصل ومستنيك** | Removes the ambiguity, gender-free, adds warmth |
| 18 | `tripCompletedTitle` — `app_strings.dart:2371` | وصلت بسلامة! | Unvocalised `وصلت` is four different words; defaults masculine | **حمد الله على السلامة!** | The phrase every Egyptian hears on arriving safely; gender-free |
| 19 | `tripCancelledTitle` — `app_strings.dart:2374` | تم إلغاء الرحلة | Agentless passive — a system log, not a message | **الرحلة اتلغت** | Two words, plainly spoken, no blame |
| 20 | `genericLoadError` — `app_strings.dart:1787` | حدث خطأ، حاول مرة أخرى | The most-shown string in the app is also the coldest | **في حاجة مانجحتش. جرّب تاني.** | Admits the app's fault, fits any snackbar, actionable |

Five more that deserve the same pass: `ratingTagPoliteCaptain` (`:2864`) `موجّه مهذب` → **كابتن محترم**; `ratingTagOnTime` (`:2872`) `في الوقت` → **جه في معاده**; `noTripsYet` (`:2123`) → **لسه مافيش رحلات**; `noTransactionsYet` (`:2059`) → **لسه مافيش معاملات على محفظتك**; `homeSearchingSubtitle` (`:1881`) → **فضل في منطقة زحمة، الطلبات بتزيد**.

### P1.4 — Correct Arabic plurals and de-gender the copy

- **Goal** — no count renders ungrammatically; no user is addressed as the wrong gender.
- **Design** — add one helper to the shared package, `arPlural(int n, {required String one, required String two, required String few, required String many})`, modelled exactly on the already-correct `requestsNearbyCount` (`app_strings.dart:3570-3575`). Rewrite the nine broken methods through it: `aboutMinutes` (`:1832`), `tripsLast7Days` (`:1978`), `tripsRecorded` (`:2119-2120`), `docApprovedOfTotal` (`:2247-2248`), `docRequiredMissing` (`:2319`), `tripDurationMinutes` (`:2566`), `bidsEtaMinutes` (`:2722` — **change the parameter from `String` to `int` first**), `bidsTripCount` (`:2726`), `docBirthDateAge` (`:3378`). Restore the amounts the offer hints silently dropped (`:3201`, `:3205`, `:3209` vs the originals at `rider/home/fare_estimate_sheet.dart:775`, `:781`). Separately, rewrite the ~50 masculine constructions to gender-free forms per the P1.3 rule; do **not** add a gender column.
- **Files to change** — `packages/flutter_shared/lib/l10n/app_strings.dart`; new `packages/flutter_shared/lib/l10n/ar_plural.dart`; the two rider screens whose local helpers become redundant (`rider/ride/captain_bids_sheet.dart:428-434`, `rider/trip/trip_screen.dart:585`).
- **DB** — none. Explicitly rejecting a `gender` column: it is a schema, onboarding, and privacy change to solve a problem that gender-free copy solves for free.
- **API contract** — none.
- **Effort** — M.
- **Risk** — low. `bidsEtaMinutes`' signature change is a breaking call-site change; the compiler finds every one.
- **Acceptance criteria** — a parameterised test renders every count-bearing method at n = 1, 2, 3, 10, 11, 100 and a native reviewer signs off each; zero masculine-only second-person constructions outside document/legal copy.
- **Tests** — the parameterised plural test above, checked into CI.

### P1.5 — Ratify Western numerals and centralise formatting

- **Goal** — one number policy, written down, enforced, and applied through one formatter instead of 80 call sites.
- **Design** — **Recommendation: Western digits (0123) everywhere, for prices, phone numbers, plate numbers, ETAs and dates.** Justification for this market: Egyptian digital and commercial contexts overwhelmingly use Western digits — prices, phone numbers and car plates are written that way in daily life — and the regional benchmarks (Careem, inDrive, Uber in Egypt) follow the same convention. Arabic-Indic numerals remain standard in Gulf print and in some formal Egyptian print, but in a phone UI they slow down exactly the users who scan a fare in half a second. The codebase already made this decision deliberately (`go_date_field.dart:50-52`, `:60-61`); this ratifies it rather than reversing it. Two consequences follow. First, fix the single violation at `app_strings.dart:1978` (`آخر ٧ أيام` → `آخر 7 أيام`). Second, stop avoiding `intl` — the reason it was avoided is that its `ar` locale substitutes Arabic-Indic digits, but that is a locale argument, not a reason to hand-roll. Introduce `GoFormat` in the shared package wrapping `NumberFormat`/`DateFormat` pinned to a Western-digit locale, exposing `money(num)`, `distanceKm(num)`, `durationMinutes(int)`, `dateShort`, `dateTime`, and a real `relativeTime(DateTime)`. Migrate the 36 `ج.م` concatenations and 44 `toStringAsFixed` calls onto it, fixing the precision inconsistency (`profile_screen.dart:703` 2dp vs `payment_methods_screen.dart:66` 0dp vs `captain_bids_sheet.dart:459` rounded) to a single rule: whole pounds in lists and chips, two decimals only on wallet ledger rows. Replace the three fixed relative-time getters (`:2092`, `:2095`, `:2098`) with `relativeTime`.
- **Files to change** — new `packages/flutter_shared/lib/l10n/go_format.dart`; `app_strings.dart:1978`, `:2092`, `:2095`, `:2098`; the 36 currency sites; `packages/flutter_shared/lib/widgets/go_date_field.dart` (keep the ISO wire helper as-is — it is correct that a payload must not depend on display locale).
- **DB** — none.
- **API contract** — none.
- **Effort** — M.
- **Risk** — medium: money rendering is high-visibility and a precision change is user-noticeable. Roll out behind the formatter with golden tests on the wallet, fare sheet and bids sheet.
- **Acceptance criteria** — zero Arabic-Indic digits in source; zero manual `' ج.م'` concatenation; the same balance renders identically on all three screens; notification timestamps are computed.
- **Tests** — golden tests for wallet/fare/bids; unit tests for `GoFormat` at boundary values; the P0.2 script gains an Arabic-Indic-digit check.

### P1.6 — Give the server a locale to speak

- **Goal** — push notifications, OTP and email match the language the user chose.
- **Design** — add a `locale` column to `users` (and `captains` if captain identity is separate for messaging), default `'ar'`, constrained to `('ar','en')`. Have the client send it on login and whenever `setLocale` runs, via a small `PATCH /user/preferences` (or by extending the existing `/user/device` call, which already fires on token refresh — cheaper, and it means locale travels with the device that will receive the push). Introduce a server-side message catalogue mirroring the client's, keyed by the same identifiers, and route all 23 notification payloads through it. For WhatsApp, register an `en` variant of the `synaptic_go_otp` template and select per-user instead of reading the global `WHATSAPP_TEMPLATE_LANG` (`notifications.ts:93`). Localise the OTP email (`notifications.ts:184-185`). Where locale is unknown, default to Arabic — the current behaviour, which stays correct for the overwhelming majority.
- **Files to change** — new migration `0020_user_locale.sql`; `apps/api/src/lib/types.ts`; `apps/api/src/lib/notifications.ts`; new `apps/api/src/lib/messages.ts`; the 23 notification call sites across `routes/trips.ts`, `routes/payments.ts`, `routes/safety.ts`, `routes/intercity.ts`, `apps/api/src/index.ts`; `routes/devices.ts` or `routes/user.ts` for the write path; client `app_state.dart` / `captain_state.dart`.
- **DB** — migration `0020`:
  ```sql
  ALTER TABLE users ADD COLUMN locale TEXT NOT NULL DEFAULT 'ar'
    CHECK (locale IN ('ar','en'));
  ```
  (Mirror on `captains` only if captain messaging resolves independently of `users`; verify before writing — marked `needs-check`.)
- **API contract** — extend the existing device registration:
  ```
  POST /user/device
  { "token": "...", "platform": "android", "locale": "ar" }   // locale added, optional
  → 200 { "ok": true }
  ```
  and read it on write. No response shape changes.
- **Effort** — L.
- **Risk** — medium: a message catalogue on the server is a second place copy can drift from the client. Mitigate by keying both off the same identifier list and adding a CI diff between the two key sets. WhatsApp template approval has external lead time — start it first.
- **Acceptance criteria** — a user set to English receives English push, OTP and email; an unset user receives Arabic; the key sets of client and server catalogues match in CI.
- **Tests** — integration test per notification type in both locales; a CI step diffing catalogue keys.

### P2.1 — Re-voice the full catalogue and settle orthography

- **Goal** — all 545 members read as one author, in the register the style guide defines.
- **Design** — a systematic pass over `AppStringsAr` applying `docs/COPY_STYLE_AR.md` from P1.3: register, the `جاري`/`جارٍ` and `ملغية`/`ملغاة` splits, tanwīn form, ellipsis character, and the four phrasings of "move the map" (`:2672`, `:2971`, `rider/home/home_screen.dart:1432`, `rider/home/location_search_sheet.dart:321`). Retire the duplicate `onbStepCounter`/`stepOfTotal` pair (`:3434`, `:3667`). Rewrite the untranslated fintech jargon at `:2019`. Fix `'سنة الانتاج'` → `'سنة الموديل'` (`:3470`, also missing its hamza) and `'إقرار'` → `'اعتماد'` (`:2244`). Best done by a native copywriter with the engineer reviewing, not the reverse.
- **Files to change** — `packages/flutter_shared/lib/l10n/app_strings.dart`.
- **DB** / **API contract** — none.
- **Effort** — L.
- **Risk** — low; pure copy. Ship behind the same golden tests P1.1 established.
- **Acceptance criteria** — banned-term and orthography checks pass; a native reviewer signs off the full catalogue.
- **Tests** — the P0.2 banned-term list extended to orthography variants.

### P2.2 — Bundle the font

- **Goal** — Arabic renders correctly on first launch with no network.
- **Design** — download the Cairo weights actually used (inspect `AppTokens.font` call sites for the weight set; `w400`, `w600`, `w700`, `w900` are all referenced), add them under `packages/flutter_shared/fonts/`, declare a `fonts:` block, and switch `AppTokens.font`/`money` from `GoogleFonts.cairo(...)` to `TextStyle(fontFamily: 'Cairo', ...)`. Keep `google_fonts` only if something else needs it; otherwise drop the dependency.
- **Files to change** — `packages/flutter_shared/pubspec.yaml`; `packages/flutter_shared/lib/theme/app_theme.dart:265`, `:283`; new font assets.
- **DB** / **API contract** — none.
- **Effort** — S.
- **Risk** — low. APK grows by roughly 300–500 KB depending on weights and whether the variable font is used; measure before and after and hand the number to T26. Subsetting is possible but not recommended for Arabic — glyph coverage for names and addresses is unpredictable.
- **Acceptance criteria** — airplane-mode cold launch renders Cairo; no runtime font request in a network trace; APK delta recorded.
- **Tests** — manual airplane-mode launch on a clean install; APK size assertion in the release job.

### P2.3 — Admin console: extract Arabic into a locale file, defer English

- **Goal** — the console's ~305 Arabic strings live in a catalogue, so adding English later is a translation job rather than a refactor.
- **Design** — the brief frames this as "add Arabic to the admin console", but the console is **already Arabic and already RTL**: `apps/admin/src/components/layout/Layout.tsx:10` sets `dir="rtl"` globally, every page re-declares it, and technical fields correctly force `ltr` (`CaptainsPage.tsx:398-399`, `AuditLogPage.tsx:90`, `:104`, `:116`, `:126`, `TripsPage.tsx:99`). The real gap is the inverse: **English does not exist, and Arabic is hardcoded.** Recommendation: adopt `react-i18next` (small, Vite-friendly, `Trans` handles the JSX interpolations at e.g. `AnalyticsPage.tsx:384`), extract the ~305 unique strings into `ar.json`, and stop there for launch. Do **not** build the English locale or migrate the 103 physical-direction Tailwind utilities to logical properties until English is actually required — Egyptian ops teams work comfortably in Arabic, and the flip-to-LTR work is only owed when someone needs LTR. Extraction alone is ~4.5 engineer-days; the full bilingual project including the RTL/LTR flip and QA is ~8.5.
- **Files to change** — `apps/admin/package.json`; new `apps/admin/src/i18n.ts`, `apps/admin/src/locales/ar.json`; `apps/admin/src/main.tsx`; the 16 files carrying user-visible text, notably the label maps in `components/ui/Badge.tsx` (15 status labels), `pages/PricingPage.tsx` (`VEHICLE_NAMES_AR`, `CITY_NAMES_AR`), and the Leaflet popup HTML in `pages/CaptainsPage.tsx:180`.
- **DB** / **API contract** — none.
- **Effort** — L (4.5 days for extraction; 8.5 for the full bilingual programme).
- **Risk** — low. The Leaflet popups are raw HTML strings and are the fiddliest part; do them last.
- **Acceptance criteria** — zero Arabic literals in `apps/admin/src` outside `locales/`; console renders identically to today; a stub `en.json` exists and is not wired to a switcher.
- **Tests** — a grep check mirroring P0.2's, scoped to `apps/admin/src`.

### P2.4 — Localise the intercity and B2B surfaces properly

- **Goal** — the newest vertical does not repeat the error-message and notification mistakes.
- **Design** — `routes/intercity.ts` and `routes/companies.ts` are the two routes with the highest ratio of ad-hoc Arabic error strings (`intercity.ts:110`, `:163`, `:252`, `:255`; `companies.ts:50`, `:225`). Once P0.3 lands, these should return codes and let the client translate, matching every other route. Separately, the monthly B2B invoice job (`apps/api/src/index.ts:333-370`) writes a `company_invoices` row and sends nothing — whether invoices are emailed at all is `needs-check`, and if they are added they must be localised and must respect P1.6's locale.
- **Files to change** — `apps/api/src/routes/intercity.ts`, `apps/api/src/routes/companies.ts`.
- **DB** / **API contract** — no shape change; the `error` string becomes English-for-logs like every other route.
- **Effort** — S.
- **Risk** — low, but it is a user-visible regression if done before P0.3 ships the client mapping. Sequence after P0.3.
- **Acceptance criteria** — no route returns Arabic in the `error` field; all nine current Arabic messages have client mappings.
- **Tests** — a route-level test asserting `error` is ASCII for every error response.

## 7. Phasing

| Item | Phase | Effort | Owner type |
|---|---|---|---|
| P0.1 — Delete the ARB pipeline, one catalogue | **P0** | S | Flutter |
| P0.2 — Parity guard: literal ratchet, orphan report, pipeline guard | **P0** | M | Flutter + ops (CI) |
| P0.3 — API error code → Arabic mapping on the client | **P0** | M | Flutter |
| P0.4 — Persist locale; hide the dishonest switch | **P0** | S | Flutter |
| P1.1 — Finish the rider migration onto `AppStrings` | P1 | L | Flutter |
| P1.2 — RTL: directional primitives, icon helper, remove overrides | P1 | M | Flutter |
| P1.3 — Ratify the lexicon; ship the twenty rewritten strings | P1 | M | Copy + Flutter |
| P1.4 — Arabic plurals; de-gender the copy | P1 | M | Flutter + copy |
| P1.5 — Ratify Western numerals; centralise formatting in `GoFormat` | P1 | M | Flutter |
| P1.6 — Server-side locale; localise notifications, OTP, email | P1 | L | Backend + Flutter |
| P2.1 — Re-voice the full catalogue; settle orthography | P2 | L | Copy |
| P2.2 — Bundle the Cairo font | P2 | S | Flutter |
| P2.3 — Admin: extract Arabic to `ar.json`, defer English | P2 | L | Admin |
| P2.4 — Intercity/B2B error surfaces onto codes | P2 | S | Backend |

**P0 — before any production traffic.** Four items, roughly 4–6 engineer-days together. The reasoning: P0.1 and P0.2 are cheap and they stop the bleeding — every day the dead pipeline stays, someone can add a string that never renders, and every day without the ratchet the 359 grows. P0.3 is the only P0 that is genuinely large, and it earns its place because it is the failure path of every API call in an Arabic-first product; shipping English errors to Egyptian users on launch day is the kind of thing that shows up in store reviews in week one. P0.4 is small and prevents shipping a visibly broken feature.

Note what is deliberately *not* P0: the rider migration (P1.1). It is the largest single piece of work on this axis and it does not block launch, because Arabic is the default and works. It blocks *English*, which is a feature that can wait — provided P0.4 stops advertising it.

**P1 — first 30 days.** The rider migration is the spine; P1.2 through P1.5 are best done *inside* it, screen by screen, rather than as separate sweeps — a screen being migrated is already open, already being golden-tested, and its `isAr` ternaries and physical insets are right there. Sequencing P1.3's lexicon decisions *before* P1.1 starts matters, so the migration writes the agreed vocabulary rather than migrating the wrong words and re-editing later. P1.6 is independent and backend-owned, so it can run in parallel; start the WhatsApp `en` template approval on day one because it has external lead time.

**P2 — next 90 days.** Everything here is either a large copy investment (P2.1), a small physical improvement (P2.2), or work that is only owed once someone actually needs English (P2.3). P2.4 is trivial but must follow P0.3.

**Sequencing constraints worth stating explicitly:**
- P1.3 (lexicon) → P1.1 (migration). Decide the words before writing them 359 times.
- P0.3 (client mapping) → P2.4 (server stops returning Arabic). Reversing this ships English to users.
- P0.2 (ratchet) → P1.1. The ratchet is what proves the migration is monotone.
- P1.6's WhatsApp template approval is externally gated; begin immediately regardless of phase.

## 8. Metrics

Nothing on this axis is currently instrumented, so most "current" values below are measurements taken from the tree rather than telemetry. That is itself the first finding: there is no dashboard that would tell anyone the rider app is 359 literals from being translatable.

**Build-time metrics — cheap, and the ones that actually drive the work.** Emit these from the P0.2 script on every CI run and chart them.

| Metric | Current | Target | When |
|---|---|---|---|
| Inline Arabic literals, rider | 359 | 0 | End of P1 |
| Inline Arabic literals, captain | 53 | 0 | End of P1 |
| Inline Arabic literals, `flutter_shared` | 32 | 0 | End of P1 |
| `isAr` locale ternaries, rider | 187 | 0 | End of P1 |
| Orphaned `AppStrings` members | 201 | < 20 | End of P1 |
| Reachable string catalogues | 2 (one dead) | 1 | P0 |
| API error codes with a client Arabic mapping | 0 of ~71 | 71 of 71 | P0 |
| Notification types with per-user locale | 0 of 23 | 23 of 23 | End of P1 |
| Count-bearing methods with correct Arabic plurals | 1 of 10 | 10 of 10 | End of P1 |
| Unguarded directional icons | 18 | 0 | End of P1 |
| Physical-direction primitives in widget trees | 5 confirmed defects | 0 | End of P1 |
| Arabic-Indic digits in source | 1 | 0 | P1 |
| Admin strings outside a locale file | ~305 | 0 | P2 |

**Runtime metrics — what proves the change worked for users.**

| Metric | How to instrument | Current | Target |
|---|---|---|---|
| Share of sessions in each locale | Log `locale` on session start (needs P1.6's column, or a client analytics property) | unknown — nothing records it | Baseline within 2 weeks of P0.4 |
| Locale-switch events, and switch-backs within one session | Client event on `setLocale` | unknown | Switch-back rate < 10% — a high rate means English is broken, which today it is |
| Error screens showing untranslated text | Client event when `errorForCode` falls through to `errorGeneric`, tagged with the unmapped code | unmeasurable today | < 1% of error renders; any recurring unmapped code is a bug |
| OTP delivery → verification success, split by locale | Existing auth funnel, split once locale exists | unknown | No gap between `ar` and `en` cohorts |
| Captain "go online" empty-state → goes online within 5 min | Client funnel on the empty state carrying F-14-07's mistranslation | unknown | Establish baseline before the copy fix, measure after — this is the one copy change with a directly attributable supply effect |
| Support tickets tagged language/wording | Support tooling tag | unknown | Downward trend post-P1.3 |
| First-launch time-to-first-Arabic-glyph on a cold, offline install | Manual/instrumented launch test | fallback font until download | Cairo on frame one after P2.2 |

The two worth arguing for specifically: **the `errorGeneric` fall-through counter**, because it turns "did we map every code" from an audit into a live signal that catches new codes the moment a backend PR adds one; and **the captain empty-state funnel**, because F-14-07 is the one finding in this document with a plausible direct revenue number attached, and measuring it before the fix is the only way anyone will believe it afterwards.

## 9. Cross-cutting notes

Findings outside this axis, addressed to their owners. Not fixed here.

**→ T27 (Cross-App Parity)** — this axis produced the sharpest quantitative evidence of the drift T27 owns:
- The rider app carries **359** inline Arabic literals across 23 files and **187** `isAr` ternaries; the captain app carries **53** and **11**. The catalogue's own doc comment names ten captain screens as the completed reference migration (`app_strings.dart:41-45`) and no rider screens. One app finished a migration the other never started.
- `apps/captain/pubspec.yaml:54` sets `generate: true`; `apps/rider/pubspec.yaml` does not. Two build behaviours for the same (dead) pipeline (F-14-26).
- Duplicated screens have diverged in correctness, not just in code: rider `trip_chat_screen.dart:97` uses physical `Alignment` while captain `trip_chat_screen.dart:249-251` uses `AlignmentDirectional`; rider `safety/sos_screen.dart` hardcodes Arabic and bypasses the catalogue entirely while captain `safety/sos_screen.dart:124-192` reads from it correctly.
- The rider app has **four** language-switch entry points (`profile_screen.dart:407`, `:552`, `home_screen.dart:694`, `login_screen.dart:252`) plus a settings dropdown; the captain has two. Same feature, different surface area.
- Rider `main.dart` clamps nothing; captain `main.dart:68-74` clamps `textScaler` to 0.9–1.3. A shared decision implemented in one app.
- Vocabulary diverges across the apps for the same objects: pickup is `موقف النزول` (rider ARB), `موقف الراكب` (captain ARB), `نقطة الالتقاط` and `نقطة الانطلاق` (shared catalogue). A rider and a captain on the same trip read four words for one street corner.

**→ T17 (Safety, Trust & Accountability)** — the rider's SOS confirmation dialog is hardcoded Arabic and unreachable by the catalogue (`apps/rider/lib/screens/safety/sos_screen.dart:32`, `:33`, `:35`, `:39`, `:115`), while `sosWarningTitle`/`sosConfirmMessage`/`sosConfirmAction` exist unused (`app_strings.dart:2584`, `:2588`, `:2592`). Separately, the SOS copy is interrogative and masculine at the worst possible moment (`:2588`), and the feature has six different names across the product (F-14-28). Safety copy under stress is a safety property, not a polish item — §6/P1.3 items 12–16 propose the rewrites but T17 should own whether the flow itself is right.

**→ T19 (Growth, Notifications & Lifecycle)** — all 23 notification payloads are hardcoded Arabic with no per-user locale (F-14-06), and five notification strings ship mock data that no code path can substitute: `'الأجرة 45 ج.م'`, `'تم إضافة 100 ج.م'`, `'الكابتن أحمد'`, `'منذ 5 دقائق'`, `'منذ 3 ساعات'` (`app_strings.dart:2071`, `:2083`, `:2089`, `:2092`, `:2098`). P1.6 proposes the locale plumbing; the *content* strategy for lifecycle messaging is T19's.

**→ T08 (Data Model & Migrations)** — there is no `locale` column anywhere across 19 migrations, and no `gender` column either. P1.6 proposes `0020_user_locale.sql`. Whether captain messaging resolves through `users` or needs its own column is `needs-check` and touches T08's ownership of the identity model.

**→ T22 (Observability)** — nothing on this axis is instrumented. The single highest-value addition is a counter on `errorForCode` falling through to the generic fallback, tagged with the unmapped code: it converts localisation coverage from a periodic audit into a live signal. §8 lists the rest.

**→ T23 (Testing & CI)** — `scripts/check_l10n_parity.py` passes (`exit 0`) while checking the one catalogue where drift is already a compile error, and never opens the ARB files (F-14-04). This is a worked example of a green check that guarantees nothing, and T23 should look for siblings — `check_migrations.py`, `check_migrations_apply.py` and `check_repo_hygiene.py` sit in the same directory and deserve the same scepticism. Also: the CI YAML for P0.2 could not be written by this review because the GitHub App lacks `workflows` permission; it is supplied at `docs/plan/assets/14-l10n-ci.yml.txt` for manual application.

**→ T25 (Privacy & Compliance)** — `google_fonts` fetches Cairo from a Google CDN at runtime on first launch (F-14-15), which is a third-party request at app start carrying the user's IP. P2.2 removes it by bundling, which is worth noting as a privacy improvement and not only a performance one.

**→ T26 (Mobile Release & Store Readiness)** — bundling Cairo (P2.2) adds roughly 300–500 KB to the APK; the current 0 KB is only achieved by deferring the cost to a runtime download. Store listings and screenshots are also localisation surfaces this document did not examine — `needs-check`, and T26's.

**→ T12 (Design System)** — `AppTokens.font` and `AppTokens.money` are the single choke point for all typography (`app_theme.dart:255-289`), which is good design-system hygiene and made P2.2 a two-line change. Noted as a strength, not a defect. T12 should also know that the `textScaler` clamp exists in the captain app only.

**→ T05 (Pricing & Bidding Economics)** — three offer-hint methods accept the suggested price as a parameter and never interpolate it (`app_strings.dart:3201`, `:3205`, `:3209`), silently deleting amounts that the inline originals displayed (`rider/home/fare_estimate_sheet.dart:775`, `:781`). The rider's most price-sensitive guidance currently renders without the numbers. Copy-shaped, but it lands on T05's surface.

## 10. Open questions

**Q1 — One catalogue: keep `AppStrings`, or revive ARB?**
Options: (a) delete the ARB pipeline and standardise on `AppStrings`; (b) migrate all 545 members onto ARB and delete `AppStrings`; (c) leave both.
**Recommendation: (a).** `AppStrings` is compile-safe by construction — a missing translation cannot build — which is a stronger guarantee than any ARB linter provides, and 343 call sites already depend on it. Option (b) is a large migration whose only prize is convention, and it would re-open the compile-safety problem that motivated `AppStrings` in the first place (`app_strings.dart:5-23`). Option (c) is the status quo and is actively harmful. The cost of (a) is giving up ARB-native tooling and translator handoff formats, which matters only if translation is ever outsourced — see Q4.

**Q2 — Do we ship English at all in v1?**
Options: (a) ship the switch as-is; (b) hide the switch until the rider migration completes; (c) drop English entirely and be Arabic-only.
**Recommendation: (b).** (a) ships a visibly broken feature — 359 Arabic literals remain on screen in English mode. (c) is tempting for focus and would be defensible for the rider app, but English has real value for the captain app (a non-trivial minority of Cairo captains are more comfortable reading English UI chrome than MSA) and the captain app is *already* migrated, so English there costs nothing. Hide it in rider, keep it in captain, finish P1.1, then re-enable.

**Q3 — Numerals: Western or Arabic-Indic?**
Options: (a) Western `0123` everywhere; (b) Arabic-Indic `٠١٢٣` in Arabic locale; (c) Arabic-Indic for prose, Western for identifiers.
**Recommendation: (a), ratifying what the code already does.** Egyptian digital commerce, phone numbers and plates run on Western digits; the regional benchmarks do the same; and mixed-script numbers are the actual defect (`app_strings.dart:1978`). (c) is the worst option — it guarantees both scripts appear on the same screen. This is presented as a decision to *confirm* rather than to make, but it should be confirmed explicitly and written into `docs/COPY_STYLE_AR.md`, because the current policy exists only as a comment in one widget file (`go_date_field.dart:50-52`) and will not survive the next contributor.

**Q4 — Who writes the Arabic?**
Options: (a) engineers, as today; (b) a native Egyptian copywriter owns the catalogue with engineers reviewing; (c) an agency, with ARB handoff.
**Recommendation: (b).** The evidence that (a) has reached its limit is concrete: `goOnline` became "connect to the internet" (`:3554`), `pickup` became "drop-off" (rider ARB `:19`), a rating tag reads `موجّه مهذب` (`:2864`), and ~95% of the catalogue is MSA while the two best strings in it (`:2356`, `:2742`) are Egyptian and were clearly written by someone with a different instinct. This is not a skills failure; writing product copy in a second register is a specialist job. (c) is premature at one language pair and would argue for keeping ARB (Q1) purely for handoff format.

**Q5 — Register: MSA or Egyptian colloquial?**
Options: (a) MSA throughout; (b) Egyptian throughout; (c) Egyptian for user-facing moments, MSA for legal/document copy.
**Recommendation: (c),** and it should be written down. Careem's Egyptian product demonstrates the warmth of (b) works commercially, but document, consent and legal copy in colloquial reads unserious and may create compliance ambiguity. The rule proposed in P1.3 — Egyptian for anything read under pressure, MSA for anything read for the record — draws the line where users actually feel it. What is not defensible is the current state, where the two registers sit in adjacent lines of the same card (`:2353` and `:2356`).

**Q6 — Gender: store it, or write around it?**
Options: (a) add a `gender` column and dual copy variants; (b) rewrite to gender-free constructions.
**Recommendation: (b).** (a) means a schema change, an onboarding question, a privacy consideration, and roughly doubling the gendered subset of the catalogue — to solve a problem Arabic grammar lets you sidestep. The file already sidesteps it by accident twice (`:3643`, `:3650`). Revisit only if the product later needs gender for a substantive reason such as women-only ride matching, which is a T17/T16 question, not a localisation one.

**Q7 — Admin console: English now, later, or never?**
Options: (a) full bilingual admin at launch (~8.5 days); (b) extract Arabic to a locale file now, English later (~4.5 days); (c) leave hardcoded.
**Recommendation: (b).** The console is already Arabic and already RTL (`apps/admin/src/components/layout/Layout.tsx:10`) and Egyptian ops teams work comfortably in Arabic, so English is not a launch requirement. But leaving ~305 strings hardcoded means the eventual English project starts with a refactor instead of a translation. Extraction now is the cheap half of the work and it makes the expensive half optional.

**Q8 — Should the API stop returning human-readable `error` strings entirely?**
Options: (a) keep English `error` for logs, client translates the `code` (P0.3's design); (b) drop `error`, return `code` only; (c) return a localised `error` using the server-side locale from P1.6.
**Recommendation: (a).** (b) makes debugging and log-reading worse for no user-visible gain. (c) sounds appealing once P1.6 exists, but it puts user-facing copy on the server where it drifts from the client catalogue and cannot be changed without a deploy — and it still fails for any client that has not sent a locale. Keep translation on the client, where the copy already lives. This does require the API to guarantee a `code` on every error response; two paths currently omit it (`apps/api/src/routes/search.ts:11`, `apps/api/src/routes/admin.ts:498`).
