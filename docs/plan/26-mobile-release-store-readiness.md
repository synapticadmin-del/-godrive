# 26 — Mobile Release Engineering & Store Readiness

> Track: D — Engineering excellence & production readiness · Reviewer: `chat-20260801-1420-39cc` · Date: 2026-08-01 UTC
> Base commit reviewed: `913718bafb1c8a10f6d8c6a387abca952d72289f`

Every `path:line` in this document was read at that commit. Where a claim rests on
an external policy rather than the code, the source is named and the claim is
marked `confirmed` or `assumed`.

---

## 1. Scope

This document covers everything between a green CI run and an app installed on a
real phone in Egypt:

- Android and iOS build configuration, signing, and the artefact each produces.
- Versioning, and the absence of any server-side control over which client
  versions are allowed to talk to the API.
- Permissions actually declared in both apps on both platforms, and whether the
  code behind them exists.
- Store readiness: Play and App Store policy blockers, listing content, data
  declarations, and the review risks specific to ride-hailing.
- Artefact size, and what it costs a user on a constrained Egyptian connection.
- Release mechanics: staged rollout, kill switch, rollback, and remote config.

**Explicitly not covered here** (owned elsewhere):

| Out of scope | Owner |
|---|---|
| Backend CI gates, test strategy, Worker deploy pipeline, migration testing | **T23** |
| Runtime observability, alerting, incident response for the API | **T22** |
| Privacy policy text, GDPR/Egyptian data law, retention schedule | **T25** |
| Arabic copy quality, l10n catalogue mechanics, RTL correctness | **T14** |
| Rider↔captain screen-level parity and shared-widget consolidation | **T27** |
| Push notification content, delivery, and lifecycle messaging | **T19** |
| Perceived performance, animation, splash choreography | **T13** / **T28** |

The one place I cross the line into T23's territory is CI, because CI is where a
signed mobile artefact has to come from and none exists today. The proposed
workflow in §6 is mobile-only and stands alongside T23's backend pipeline.

---

## 2. What I actually read

Read in full, at the pinned commit:

| File | Note |
|---|---|
| `apps/rider/android/app/build.gradle` (90 L) | Signing config, SDK levels, Firebase deps |
| `apps/captain/android/app/build.gradle` (90 L) | Byte-identical to rider except `applicationId`/`namespace` |
| `apps/rider/android/app/src/main/AndroidManifest.xml` (47 L) | Permission set, FCM channel, no `allowBackup` |
| `apps/captain/android/app/src/main/AndroidManifest.xml` (46 L) | Same permissions as rider — including the same omissions |
| `apps/rider/android/gradle.properties`, `apps/captain/android/gradle.properties` (5 L each) | No signing or version material |
| `apps/rider/android/app/proguard-rules.pro` (9 L) | Keeps all Flutter + Firebase classes |
| `apps/rider/ios/Runner/Info.plist` (62 L) | Usage strings, `UIBackgroundModes` |
| `apps/captain/ios/Runner/Info.plist` (63 L) | Same plus `fetch` |
| `apps/rider/ios/Runner.xcodeproj/project.pbxproj` (616 L) | Read the build-settings blocks; skimmed the object graph |
| `apps/captain/ios/Runner.xcodeproj/project.pbxproj` (616 L) | Same, compared identity keys only |
| `apps/rider/pubspec.yaml` (63 L), `apps/captain/pubspec.yaml` (59 L) | Version, deps, asset declarations |
| `packages/flutter_shared/pubspec.yaml` (27 L) | Shared package deps |
| `packages/flutter_shared/lib/services/api_client.dart` (36 L) | `baseUrl` is constructor-injected; no version header |
| `apps/rider/lib/main.dart` (173 L) | Entry point, Firebase init, no error handler |
| `apps/captain/lib/main.dart` (92 L) | Same shape, no error handler |
| `.github/workflows/ci.yml` (246 L) | The only workflow installed |
| `apps/api/wrangler.toml` (180 L) | `APP_VERSION`, dev/prod/staging envs |
| `.gitignore` (117 L) | Signing and Firebase secrets correctly excluded |
| `scripts/install-apks.bat`, `run-rider.bat`, `run-captain.bat` (5 L each) | The actual build process today |
| `docs/DEPLOYMENT.md` (85 L) | Deploy history and the uninstalled workflow |
| `docs/CHECKLIST.md` (54 L) | Owner's own outstanding list |
| `package.json` (26 L), `README.md` (91 L), `docs/STACK.md` (70 L) | Context |

Verified absent by direct fetch returning 404 at the pinned commit:
`apps/rider/android/key.properties`, `apps/captain/android/key.properties`,
`apps/*/android/local.properties`, `apps/*/ios/Podfile`,
`apps/*/ios/Runner/Runner.entitlements`.

Directory listings taken through the Contents API (byte sizes below come from
its `size` field, so they are exact): `apps/*/android/app`, `apps/*/ios`,
`apps/*/assets/**`, `apps/*/android/app/src/main/res/**`, `migrations/`.

Read by delegated analysis, with `path:line` returned and spot-checked by me:
`apps/rider/lib/services/app_state.dart`, `apps/captain/lib/services/captain_state.dart`,
`apps/captain/lib/services/offers_ws.dart`, `apps/api/src/index.ts`,
`apps/api/src/routes/user.ts`, `apps/api/src/routes/devices.ts`,
`apps/api/src/routes/admin.ts`, `apps/api/src/lib/schemas.ts`,
`migrations/0003_global_transport.sql`, `migrations/0016_system_config.sql`,
both `splash_screen.dart`, both profile/settings screens,
`apps/captain/lib/screens/onboarding/onboarding_screen.dart`.

**Not read**: the Dart UI tree beyond the screens named above, the admin console,
and the API's business logic. Asset byte counts come from API metadata, not from
downloading the binaries. Play Console and App Store Connect state could not be
inspected at all — no credentials — so every claim about *configured* store
state is `needs-check` and marked as such.

---

## 3. How it works today

### 3.1 The build process is one Windows laptop

There is no automated production of a mobile artefact anywhere in this
repository. The build process is three `.bat` files:

```
scripts/run-rider.bat:2    set PATH=C:\Users\kayf\flutter-sdk\flutter\bin;%PATH%
scripts/run-rider.bat:3    cd /d C:\Users\kayf\synaptic-go\rider\rider
scripts/install-apks.bat:3 adb install -r "%USERPROFILE%\Desktop\SynapticGo-APKs\synaptic-go-rider-debug.apk"
```

Three things to notice. The Flutter SDK path is a specific user's home directory.
The project path `C:\Users\kayf\synaptic-go\rider\rider` does not correspond to
this monorepo's layout (`apps/rider`), so these scripts are stale — they describe
a pre-monorepo checkout. And the artefacts installed are `-debug.apk`.
`docs/CHECKLIST.md:52-54` confirms the state: "Rider APK debug built / Captain APK
debug built / APKs folder: `Desktop/SynapticGo-APKs`". Debug APKs, on a desktop,
on one machine.

### 3.2 What CI does — and what it deliberately does not

`.github/workflows/ci.yml` is better than the repo's reputation. Three jobs run
on every PR: `node` (typecheck api/admin/shared, build admin, run the shared test
suite), `flutter` (`pub get` + `flutter analyze` for `flutter_shared`, captain and
rider), and `checks` (four Python scripts covering migration naming/ordering,
migration apply-to-fresh-DB, l10n parity, repo hygiene). Each step is
`continue-on-error: true` and a final `Result` step aggregates and fails the job,
so one run shows every failure rather than stopping at the first.

Two limits matter for this track.

**Nothing is built for mobile.** `ci.yml:100-192` runs `flutter analyze` only.
There is no `flutter test`, no `flutter build apk`, no `flutter build appbundle`,
no iOS job, and `permissions: contents: read` (`ci.yml:22-23`) with no artefact
upload step. CI cannot produce an installable file, signed or otherwise.

**`flutter test` would find nothing anyway.** Neither app has a `test/`
directory — `apps/rider` and `apps/captain` each contain only `android`, `ios`,
`lib`, `pubspec.yaml`; `packages/flutter_shared` contains only `lib` and
`pubspec.yaml`. There are zero Flutter tests in the repository. (Test strategy
belongs to T23; I note it here only because it bears on release confidence.)

The workflow's own header is honest about the third limit
(`ci.yml:6-9`): "this workflow makes failures VISIBLE, it does not make them
BLOCKING. To actually stop a broken merge, all three jobs below must be added as
required status checks". Whether branch protection is actually configured cannot
be read from the repository — `needs-check`.

### 3.3 Android build configuration

Both apps are configured identically (`apps/rider/android/app/build.gradle` and
`apps/captain/android/app/build.gradle` differ only in `namespace`/`applicationId`):

| Setting | Value | Line |
|---|---|---|
| `namespace` / `applicationId` | `tech.synapticstudio.synaptic_go_rider` (captain: `…_captain`) | :34, :49 |
| `compileSdk` | 35 | :35 |
| `minSdk` | 23 (Android 6.0) | :50 |
| `targetSdk` | **34** | :51 |
| `versionCode` / `versionName` | from `local.properties`, else `"1"` / `"1.0"` | :23-31, :52-53 |
| `minifyEnabled` / `shrinkResources` | true / true | :67-68 |
| Release signing | conditional — see below | :56-71 |

Version numbers flow from `local.properties`, which is gitignored
(`.gitignore:57`) and generated by the Flutter tool from the pubspec at build
time. Both pubspecs declare `version: 1.0.0+1`
(`apps/rider/pubspec.yaml:4`, `apps/captain/pubspec.yaml:4`), so both apps build
as versionName `1.0.0`, versionCode `1`. The API meanwhile reports
`APP_VERSION = "0.4.0"` in all three Worker environments
(`apps/api/wrangler.toml:76`, `:144`, `:172`).

The signing block is the important one:

```gradle
apps/rider/android/app/build.gradle:56-63
    signingConfigs {
        release {
            keyAlias keystoreProperties['keyAlias']
            …
            storeFile keystoreProperties['storeFile'] ? file(keystoreProperties['storeFile']) : null
        }
    }
apps/rider/android/app/build.gradle:70-71
            // Falls back to debug signing for local dev; CI/release builds must provide key.properties (gitignored)
            signingConfig = keystorePropertiesFile.exists() ? signingConfigs.release : signingConfigs.debug
```

`key.properties` returns 404 at the pinned commit for both apps, and
`.gitignore:77-79` excludes `*.keystore`, `*.jks` and `key.properties`. Excluding
them is correct. The consequence is not: on any machine without those files —
which is every machine except one laptop, including any CI runner —
`flutter build apk --release` **succeeds** and emits a debug-signed release
build. §4 covers why that is the most dangerous line in the mobile codebase.

Firebase is wired at the native layer: `apply plugin: "com.google.gms.google-services"`
(`build.gradle:7`) with `firebase-messaging` and `firebase-analytics` from BoM
33.0.0 (`build.gradle:87-89`). `google-services*.json` and
`GoogleService-Info.plist` are gitignored (`.gitignore:75-76`) and absent.
`docs/CHECKLIST.md:21` lists "Firebase project (FCM push)" as an unchecked item
under "قريبًا (مش يوم 1)" — soon, not day one. So the Firebase project may not
exist yet, while both apps call `Firebase.initializeApp()` unconditionally at
startup (`apps/rider/lib/main.dart:20`).

### 3.4 Permissions: what is declared, on which platform

This is where the two apps and the two platforms disagree with each other and
with the code.

| Permission / capability | Rider Android | Captain Android | Rider iOS | Captain iOS |
|---|---|---|---|---|
| Fine + coarse location | ✅ `:3-4` | ✅ `:3-4` | ✅ `:48` | ✅ `:48` |
| Background / Always location | ❌ removed `:8` | ❌ removed `:6` | ✅ `UIBackgroundModes: location` `:56-60` | ✅ `:56-61` |
| `NSLocationAlwaysAndWhenInUse…` | — | — | ✅ `:50` | ✅ `:50` |
| Foreground service (+ type) | ❌ absent | ❌ absent | n/a | n/a |
| Notifications | ✅ `:6` | ✅ `:7` | ✅ `remote-notification` | ✅ `remote-notification` |
| Background fetch | n/a | n/a | ❌ | ✅ `:60` |
| `android:allowBackup` | not set (defaults true) `:10-14` | not set (defaults true) `:10-14` | n/a | n/a |
| Cleartext traffic | disabled `:14` | disabled `:14` | — | — |

Both Android manifests carry the same comment where background location used to
be: *"Background location removed: no foreground service is implemented yet.
Re-add with a real foreground service when background tracking ships."*
(`apps/rider/…/AndroidManifest.xml:8`, `apps/captain/…/AndroidManifest.xml:6`).
That is a defensible interim decision, honestly documented.

The iOS side never got the same treatment. Both `Info.plist` files still declare
`UIBackgroundModes` including `location`, and both declare
`NSLocationAlwaysAndWhenInUseUsageDescription` — the rider app included, whose
Arabic string reads "تحديد موقعك لتحديث رحلاتك ومتابعة السائق"
(`apps/rider/ios/Runner/Info.plist:51`). A passenger app does not need Always
location to watch a driver approach while the app is open.

And no code implements background location on either platform. The captain's
location stream stops when the app is backgrounded
(`apps/captain/lib/services/captain_state.dart:639`), and `LocationPermission.always`
is never requested — only `checkPermission()`/`requestPermission()` at
`captain_state.dart:490-492` and `:530-532`, with `deniedForever` handled at
`:539`. There is also no prominent-disclosure screen before the OS prompt; the
captain's onboarding is a four-step document upload wizard
(`apps/captain/lib/screens/onboarding/onboarding_screen.dart`).

The net position: **iOS claims a capability it does not implement, Android
implements none and claims none, and the product needs it on both.** A captain
whose phone screen locks stops receiving offers.

### 3.5 iOS: configured by the Flutter template, never by a human

`apps/rider/ios/Runner.xcodeproj/project.pbxproj` and the captain equivalent are
essentially untouched Flutter templates:

- No `DEVELOPMENT_TEAM` key exists in either file — grep across all 616 lines
  returns nothing. No Apple account has ever been attached.
- `CODE_SIGN_IDENTITY[sdk=iphoneos*] = "iPhone Developer"` (`:335`, `:455`, `:512`)
  — the legacy identity string, superseded by "Apple Development".
- `CODE_SIGN_STYLE = Automatic` appears only on the `RunnerTests` targets
  (`:383`, `:400`, `:415`), never on `Runner`.
- `IPHONEOS_DEPLOYMENT_TARGET = 12.0` (`:349`, `:475`, `:526`).
- Bundle IDs are `tech.synapticstudio.synapticGoRider` / `…synapticGoCaptain`
  (`:371`, `:550`, `:572`) — camelCase, versus the snake_case Android
  `applicationId`. Two identifier conventions for one product.
- No `Runner.entitlements` (404) — so no push-notification entitlement is
  declared, which APNs requires.
- No `Podfile` (404). CocoaPods has never been initialised, so no plugin's iOS
  side has ever been linked.

`docs/CHECKLIST.md:26` confirms the intent: "Apple Developer عند iOS" — an Apple
account when we get to iOS. **The honest state is Android-first with an
untouched iOS folder.** iOS is not "nearly ready"; it has never been built.

### 3.6 How each app finds the API

`ApiClient` takes `baseUrl` through its constructor and adds no version header
(`packages/flutter_shared/lib/services/api_client.dart:5-13`). The value comes
from a compile-time constant with a production default:

```dart
apps/rider/lib/services/app_state.dart:69-71
apps/captain/lib/services/captain_state.dart:131-133
  const String.fromEnvironment('API_BASE_URL',
      defaultValue: 'https://api.synapticstudio.tech')
```

WebSocket URLs are derived from the same base by swapping the scheme
(`apps/captain/lib/services/offers_ws.dart:31-34`). There are no build flavours
and no environment config class. Any build produced without an explicit
`--dart-define=API_BASE_URL=…` — which includes every `flutter run`, every debug
APK on a tester's phone, and every build the three `.bat` scripts produce —
talks to **production**, against the production D1 database.

### 3.7 Version signalling: informational only

`/health` returns `APP_VERSION: "0.4.0"` (`apps/api/src/index.ts:99-105`) as a
string. No route exposes a minimum supported client version; no client sends its
own version. `device_tokens` stores `id, user_id, token, platform, app_role,
last_seen_at, created_at` (`migrations/0003_global_transport.sql:12-22`) and
`deviceTokenSchema` accepts only `token`, `platform`, `appRole`
(`apps/api/src/lib/schemas.ts:84-88`) — there is no `app_version` column, which
would have been the cheapest possible upgrade signal. Both clients hardcode the
platform string:

```dart
apps/captain/lib/services/captain_state.dart:1113
apps/rider/lib/services/app_state.dart:526
  _post('/user/device', {'token': fcm, 'platform': 'android'})
```

So even the platform field is wrong the day an iOS build ships.

A `system_config` table does exist (`migrations/0016_system_config.sql:20`,
seeded with seven operational knobs at `:33-40`) with admin read/write routes
(`apps/api/src/routes/admin.ts:463`, `:488`). **No Flutter code reads it.** The
mechanism for remote control exists on the server and is unused by the clients.

### 3.8 What ships inside the APK

Byte counts from the Contents API at the pinned commit:

| Bundle | Bytes | Note |
|---|---|---|
| `apps/rider/assets/**` | 5,735,967 | 5.47 MB |
| `apps/captain/assets/**` | 4,589,824 | 4.38 MB |
| — of which `assets/videos/splash.mp4` | 875,855 each | **bundled but dead** |
| — of which `assets/images/icons/ios/` | 669,133 each | App Store icons in the app bundle |
| — of which `playstore_icon.png` | 153,779 each | Play Console graphic in the app bundle |
| Identical in both apps | 2,750,499 | same Git SHAs — 2.62 MB duplicated |
| `GODRIVE.png` (repo root) | 4,031,597 | **not bundled** — clone bloat only |
| `splash.mp4` (repo root) | 875,855 | **not bundled** — clone bloat only |
| `apps/*/android/app/src/main/res/**` | 5,053 | all five density buckets |

The splash video is the clearest waste. Both pubspecs declare the directory
(`apps/rider/pubspec.yaml:63`, `apps/captain/pubspec.yaml:59` — the
`- assets/videos/` entry), so the file is packed into both APKs, but
`video_player` is in neither pubspec and neither `splash_screen.dart` references
`mp4`, `VideoPlayer` or `assets/videos`. The rider splash's own comment says the
video splash was replaced with a static brand image — while
`apps/rider/lib/main.dart:41-45` still describes waiting "until it reports that
the video has played in full". 856 KB per app, shipped to every user, decoded by
nobody.

Fonts go the other way: `google_fonts: ^6.2.1` is in all three pubspecs with no
`fonts:` section and no font files anywhere, so Cairo is fetched from
`fonts.gstatic.com` at first use and cached. First launch on a slow connection
renders in Roboto until the download lands; an offline first launch renders in
Roboto for the whole session.

Estimated artefact sizes (ESTIMATED — no build was run): universal release APK
45–50 MB rider / 43–48 MB captain; per-ABI arm64 APK 18–22 / 16–20 MB; AAB
delivered download 13–17 / 12–15 MB.

### 3.9 Release mechanics that do not exist

No staged rollout process, no kill switch, no remote config consumed by the
clients, no crash reporting, no analytics beyond the `firebase-analytics`
artefact being on the Android classpath, and no global Dart error handler —
neither `main.dart` installs `FlutterError.onError`, `runZonedGuarded`, or
`PlatformDispatcher.onError`. A crash on a user's phone in Cairo produces no
signal anywhere.

---

## 4. Findings

| ID | Sev | Finding | Evidence (`path:line`) | Impact | Confidence |
|---|---|---|---|---|---|
| F-26-01 | S1 | `targetSdk 34` is below Google Play's current minimum (API 35); API 36 becomes mandatory 31 Aug 2026 | `apps/rider/android/app/build.gradle:51`, `apps/captain/…:51` | Play rejects the upload outright. Submission is impossible today | confirmed |
| F-26-02 | S1 | Release builds silently fall back to **debug signing** when `key.properties` is missing | `apps/rider/android/app/build.gradle:71`; `key.properties` 404; `.gitignore:77-79` | A debug-signed APK installs and looks shippable but can never be uploaded, and can never be upgraded to a real key | confirmed |
| F-26-03 | S1 | No account-deletion endpoint or UI on either app | `apps/api/src/routes/user.ts` (no `DELETE /user`); rider/captain profile screens | Mandatory on both stores. Automatic rejection | confirmed |
| F-26-04 | S1 | No force-upgrade / minimum-version gate anywhere | `apps/api/src/index.ts:99-105`; `migrations/0003_global_transport.sql:12-22`; `apps/api/src/lib/schemas.ts:84-88` | A broken build in users' hands cannot be recalled or blocked. Old clients keep calling changed endpoints forever | confirmed |
| F-26-05 | S1 | Background location declared on iOS, removed on Android, implemented on neither | `apps/rider/ios/Runner/Info.plist:56-60`, `apps/captain/…:56-61`, both manifests `:6`/`:8`, `captain_state.dart:639` | Captain stops receiving offers when backgrounded — core function absent. Simultaneously an Apple 2.5.4 rejection risk for an undeclared-use capability | confirmed |
| F-26-06 | S1 | Firebase config files absent and the Firebase project may not exist, while the google-services plugin is applied and `Firebase.initializeApp()` is unconditional | `build.gradle:7`, `main.dart:20`, `.gitignore:75-76`, `docs/CHECKLIST.md:21` | Android build fails on any machine but one; iOS cannot be configured at all | confirmed |
| F-26-07 | S1 | No CI produces a mobile artefact; builds come from one Windows laptop via stale scripts | `.github/workflows/ci.yml:100-192`, `:22-23`; `scripts/run-rider.bat:2-3`; `docs/CHECKLIST.md:52-54` | Bus factor 1. No reproducible build, no artefact provenance, no way for anyone else to ship | confirmed |
| F-26-08 | S1 | Every build defaults to the production API; tester and debug builds write to production D1 | `apps/rider/lib/services/app_state.dart:69-71`, `apps/captain/…:131-133`, `offers_ws.dart:31-34` | Test trips, test wallet rows and test captains land in production data | confirmed |
| F-26-09 | S2 | Version numbers are unmanaged and mutually inconsistent: both apps `1.0.0+1`, API `APP_VERSION 0.4.0` | `apps/rider/pubspec.yaml:4`, `apps/captain/pubspec.yaml:4`, `apps/api/wrangler.toml:76` | Second Play upload is rejected for duplicate `versionCode`. No build is traceable to a commit | confirmed |
| F-26-10 | S2 | No crash reporting and no global Dart error handler in either app | `apps/rider/lib/main.dart:18-31`, `apps/captain/lib/main.dart` | Production crashes are invisible. Store vitals degrade with no diagnosis path | confirmed |
| F-26-11 | S2 | iOS has no signing identity, no entitlements file and no Podfile | `project.pbxproj` (no `DEVELOPMENT_TEAM`), `:335`, `Runner.entitlements` 404, `Podfile` 404 | iOS is months of setup from submission, not days. Push cannot work without the entitlement | confirmed |
| F-26-12 | S2 | No prominent-disclosure screen before the location prompt | `apps/captain/lib/screens/onboarding/onboarding_screen.dart`, `captain_state.dart:490-492` | Play policy violation for location-collecting apps; enforcement risk after launch | confirmed |
| F-26-13 | S2 | No obfuscation (`--obfuscate --split-debug-info`) and no integrity checks on the captain app | Build commands in `scripts/*.bat`; no `--obfuscate` anywhere in the repo | Earnings and wallet logic ship as readable Dart symbols; no tamper resistance | confirmed |
| F-26-14 | S2 | 856 KB of dead splash video shipped in both APKs, plus store graphics inside the app bundle | `apps/rider/pubspec.yaml:63`, `apps/captain/pubspec.yaml:59`; `assets/images/icons/ios/` 669,133 B; `playstore_icon.png` 153,779 B | ~1.6 MB per app of pure waste in a storage- and data-constrained market | confirmed |
| F-26-15 | S2 | Fonts are fetched at runtime; no bundled fallback | all three pubspecs (`google_fonts: ^6.2.1`, no `fonts:` section) | Wrong typography on first launch over a slow connection, and for the whole session offline | confirmed |
| F-26-16 | S2 | Neither store account exists yet; Apple organisational enrolment needs a D-U-N-S number | `docs/CHECKLIST.md:25-26` | Weeks of lead time on the critical path, invisible in any engineering plan | confirmed |
| F-26-17 | S2 | No staged rollout, kill switch, or client-side remote config; `system_config` exists but no client reads it | `migrations/0016_system_config.sql:20`, `apps/api/src/routes/admin.ts:463`, `:488` | A bad release can only be fixed by another store release — 1 to 7 days | confirmed |
| F-26-18 | S2 | Push platform is hardcoded to `'android'` | `apps/captain/lib/services/captain_state.dart:1113`, `apps/rider/lib/services/app_state.dart:526` | iOS devices are registered as Android; APNs routing breaks the day iOS ships | confirmed |
| F-26-19 | S3 | `android:allowBackup` is not set, so it defaults to `true` | both `AndroidManifest.xml:10-14` | App-private data is copied to the user's cloud backup. Impact depends on what is in `SharedPreferences` versus secure storage | needs-check |
| F-26-20 | S3 | No `ITSAppUsesNonExemptEncryption` key in either `Info.plist` | `apps/rider/ios/Runner/Info.plist`, `apps/captain/…` | Every TestFlight/App Store upload stops for a manual export-compliance answer; blocks unattended publishing | confirmed |
| F-26-21 | S3 | Two identifier conventions: snake_case Android `applicationId`, camelCase iOS bundle ID | `build.gradle:49` vs `project.pbxproj:371` | Cosmetic now, but deep links, Firebase app registration and analytics joins get messy | confirmed |
| F-26-22 | S3 | Captain iOS declares a `fetch` background mode the rider does not, with no code behind it | `apps/captain/ios/Runner/Info.plist:60` | Another undeclared-use capability in front of App Review | confirmed |
| F-26-23 | S3 | Stale build scripts and a stale splash comment describe a layout and a video that no longer exist | `scripts/run-rider.bat:3`, `apps/rider/lib/main.dart:41-45` | A new developer follows them and fails on day one | confirmed |
| F-26-24 | S4 | Rider camera usage string mentions uploading "documents" — copied from the captain app | `apps/rider/ios/Runner/Info.plist:53` | Riders upload an avatar, not documents. Apple reads these strings | confirmed |
| F-26-25 | S4 | `apps/captain` sets `generate: true`, `apps/rider` does not | `apps/captain/pubspec.yaml:54` vs rider pubspec | Two different l10n mechanisms across two halves of one product (→ T14/T27) | confirmed |

---

### S1 expansions

**F-26-01 — The app cannot legally be uploaded today.**
Google Play's target API requirement is not a warning, it is an upload-time
rejection. As of August 2025 new apps and updates must target API 35; from
31 August 2026 the floor rises to API 36, with an extension path to
1 November 2026 requestable in Play Console. This app targets 34. It already
compiles against SDK 35 (`build.gradle:35`), so the change is one line plus a
behaviour-change review — Android 15 enforces edge-to-edge display by default,
non-dismissable foreground-service types, and stricter `targetSdk`-gated
background restrictions. The one-line change is trivial; not having tested the
Android 15 behaviour changes is the actual work.

**F-26-02 — The most dangerous line in the mobile codebase.**
```gradle
signingConfig = keystorePropertiesFile.exists() ? signingConfigs.release : signingConfigs.debug
```
The intent — let a developer build release locally without the production key —
is reasonable. The implementation fails open. A CI runner, a new laptop, or a
contractor's machine runs `flutter build apk --release`, gets exit code 0, and
produces an APK that installs, runs, and is signed with the universally-known
Android debug key. Nothing in the output says "this is not a real release".

Three consequences compound. Play refuses debug-signed uploads, so the failure
surfaces at the worst possible moment. Any Google service keyed to a certificate
fingerprint (Maps SDK, Firebase phone auth) silently behaves differently between
this build and a real one. And once users have installed a debug-signed build
sideloaded from a link — which is exactly how an Egyptian beta gets distributed —
they cannot be upgraded to the Play build, because Android refuses an update
signed by a different key. Those users must uninstall and lose their local state.

The fix is to fail closed: if a release build is requested and no keystore is
configured, stop the build with a clear message. The debug-signing path should
require an explicit opt-in flag.

**F-26-03 — Account deletion is a hard gate on both stores.**
`apps/api/src/routes/user.ts` deletes an avatar (`:220`) and a saved place
(`:319`); there is no route that deletes a user. No profile screen in either app
offers it. Google Play has required in-app deletion **plus** a
publicly-reachable web deletion URL since 31 May 2024, and blocks updates when
the Data-safety deletion questions are unanswered. Apple has enforced Guideline
5.1.1(v) since 30 June 2022 and rejects email-a-request flows and
"deactivate" as substitutes.

The ride-hailing wrinkle is real but solved: the platform must retain trip and
financial records for tax and dispute purposes, and Egypt's telecoms/data rules
point at a 180-day retention floor (assumed — worth legal confirmation, → T25).
The accepted pattern is deletion of the *account and personal identifiers* with
anonymised retention of the transaction ledger: null the phone, name, email and
avatar, replace the user row's identifiers with a tombstone, keep `trips` and
`wallet_transactions` rows pointing at the tombstone. That must be described in
the privacy policy and in the Data-safety form.

**F-26-04 — There is no way to stop a bad build.**
Today the platform cannot tell a client to update, cannot refuse to serve an
obsolete client, and does not even know what version is calling. `/health`
returning `"0.4.0"` (`index.ts:99-105`) is a server build string, not a client
policy. This is the single highest-leverage missing mechanism in this document,
because it is what makes every *other* mobile risk survivable: with a version
gate, a bad release is a two-hour incident; without one, it is a two-week
migration of the installed base. §6 P0.4 specifies it.

**F-26-05 — Background location: broken twice, in opposite directions.**
On Android the permission was deliberately removed pending a foreground service.
That is honest, and it is also a product hole: the captain's location stream
stops when the app is backgrounded (`captain_state.dart:639`), so a captain who
locks their phone disappears from dispatch. Under Android 14+ the fix is not just
re-adding `ACCESS_BACKGROUND_LOCATION` — it requires a foreground service with
`android:foregroundServiceType="location"`, the `FOREGROUND_SERVICE` and
`FOREGROUND_SERVICE_LOCATION` permissions, and a persistent notification. Missing
the type attribute throws at runtime on API 34+.

On iOS the opposite: `UIBackgroundModes: location` is declared for **both** apps,
including the rider, with an Always usage string, and no code uses it. App Review
routinely asks why a capability is declared and rejects apps that cannot
demonstrate it (Guideline 2.5.4).

Then there is Play's approval process, which is the schedule risk nobody has
booked: `ACCESS_BACKGROUND_LOCATION` requires a Permissions Declaration Form and
a demo video of no more than 30 seconds showing the feature triggering in the
background, the prominent-disclosure dialog, and the runtime prompt — reviewed
over "up to several weeks", during which the app sits pending. Only one location
feature may be declared per app; declaring several is a rejection.

Recommended sequencing: **strip the iOS declarations now** (they buy nothing and
risk rejection), ship v1 as a foreground-only product, and treat background
tracking as a deliberate, separately-scheduled release whose long pole is Play
review, not code.

**F-26-06 — The build depends on files nobody has.**
`apply plugin: "com.google.gms.google-services"` at `build.gradle:7` makes
`google-services.json` a build-time requirement; the Gradle plugin fails the
build when it is missing. It is correctly gitignored (`.gitignore:75-76`) and
correctly absent from the repo. What is missing is the other half: no CI secret,
no documented provisioning step, no `.example` file, and per
`docs/CHECKLIST.md:21` possibly no Firebase project at all. On iOS the equivalent
`GoogleService-Info.plist` is also absent, and since `Firebase.initializeApp()`
runs unconditionally at `main.dart:20`, an iOS build without it crashes at
launch.

**F-26-07 — One laptop is the release infrastructure.**
CI analyses the Dart but builds nothing (`ci.yml:100-192`), uploads nothing
(`permissions: contents: read`, `:22-23`), and the actual artefacts come from
`scripts/*.bat` hardcoded to `C:\Users\kayf\…` against a directory layout this
repo no longer has. There is no artefact provenance: no way to say which commit
produced the APK on a tester's phone. §6 P0.8 contains a complete workflow.

**F-26-08 — Testers are writing to production.**
`String.fromEnvironment('API_BASE_URL', defaultValue: 'https://api.synapticstudio.tech')`
means the *absence* of a build flag selects production. Every `flutter run`,
every debug APK from the `.bat` scripts, and every artefact a future CI job
builds without remembering the flag points at production D1 — creating trips,
moving wallet rows, registering captains. A staging Worker with its own database
already exists (`apps/api/wrangler.toml:157-172`, `synaptic-go-staging`), so the
backend half of the fix is done; the client half is not. The default should be
staging, with production requiring an explicit flag.

### S2 expansions

**F-26-09 — Versioning.** Both apps ship `1.0.0+1`; Play accepts a given
`versionCode` exactly once per package, so the second upload of either app fails
until someone remembers to bump. `APP_VERSION 0.4.0` on the API is a third,
unrelated number. Nothing derives a version from a git tag, so no installed build
can be traced to a commit — which makes a crash report, once crash reporting
exists, much less useful.

**F-26-10 — Blindness.** No Crashlytics, no Sentry, and no
`FlutterError.onError` / `runZonedGuarded` / `PlatformDispatcher.onError` in
either entry point. Android vitals in Play Console will eventually show a crash
*rate*, with no stack traces. For an app handling money on a captain's phone,
that is not enough to operate.

**F-26-11 — iOS is not a port, it is a project.** No `DEVELOPMENT_TEAM`, the
legacy `"iPhone Developer"` identity string, no entitlements file (so no
`aps-environment`, so no push), and no `Podfile` (so no plugin has ever linked
its iOS side). Combined with F-26-16's D-U-N-S lead time, an honest iOS estimate
is 6–10 weeks from a standing start, most of it not code.

**F-26-16 — The paperwork is on the critical path.** `docs/CHECKLIST.md:25-26`
lists the Play Console fee and Apple Developer enrolment as future items. Apple
organisational enrolment requires a D-U-N-S number for the legal entity, which
for an Egyptian company is itself a multi-week request, and Play's developer
verification adds identity checks. None of this is engineering work and all of it
blocks launch.

**F-26-17 — No lever between "fine" and "ship a new build".** `system_config`
(`migrations/0016_system_config.sql:20`) is admin-editable through
`apps/api/src/routes/admin.ts:463`/`:488` and read by nobody on the client. Adding
a client read of that table is the cheapest kill switch available and reuses
infrastructure that already exists.

---

## 5. Benchmark gap

Confidence labels below refer to my confidence about the competitor's behaviour,
independent of the Synaptic Go findings above.

| Capability | Uber / inDrive / Careem | Synaptic Go | Gap |
|---|---|---|---|
| Signed CI builds | Every artefact from CI, signed with keys in a secret manager; no laptop builds (confirmed as industry standard) | One Windows laptop, debug-signed fallback | Total |
| Force upgrade | All three refuse to operate below a minimum version and show a blocking update screen (confirmed — observable behaviour) | None | Total |
| Staged rollout | Play staged rollout at 1→5→20→50→100% with halt on crash-rate regression (confirmed) | No rollout control | Total |
| Remote config / kill switch | Firebase Remote Config or equivalent gating features per-city (confirmed for Uber; assumed for inDrive) | `system_config` exists, unread by clients | Near-total |
| Crash reporting | Crashlytics/Sentry with release-tagged symbol upload (confirmed) | None | Total |
| Background location | Foreground service + Play declaration + demo video approved; driver tracking is the core loop (confirmed) | Declared on iOS, absent on Android, implemented nowhere | Total |
| Account deletion | In-app deletion flow plus web URL (confirmed — required of them too) | None | Total |
| App size | inDrive is deliberately light for emerging markets, roughly 30–50 MB download; Uber is substantially larger (assumed — store-listing figures vary by device and change often) | 45–50 MB universal APK estimated, with ~1.6 MB of dead weight | Moderate |
| Bilingual listing | Separate Arabic and English store listings with localised screenshots (confirmed for the Egyptian Play listings) | No listing at all | Total |
| Obfuscation | Release builds obfuscated with symbol files retained for de-symbolication (confirmed as standard) | None | Total |

The honest summary: on the release-engineering axis this project is not behind
its competitors by a version or two, it is at zero. Every mechanism in the table
is absent, and most are absent because the project has never shipped to a store
at all. That is normal for pre-production — but it means the gap is measured in
weeks of setup work, not in features.

The one place Synaptic Go is *not* behind is the backend: CI runs typechecks,
migration checks, l10n parity and hygiene on every PR (`ci.yml:194-246`), and a
staging Worker with its own D1 already exists (`wrangler.toml:157-172`). The
mobile side simply never received the same attention.

---

## 6. Improvement plan

Ordered by what unblocks what. P0 items are prerequisites for submitting
anything to either store.

### P0.1 — Make release signing fail closed, and adopt Play App Signing

- **Goal** — it is impossible to produce something that looks like a release
  build but is not one, and losing the laptop does not lose the app.
- **Design** — invert the conditional at `build.gradle:71`. If the build type is
  `release` and no keystore is configured, throw a `GradleException` naming the
  three ways to supply one (local `key.properties`, `ANDROID_KEYSTORE_BASE64`
  env in CI, or an explicit `-PallowDebugSigning=true` opt-in for local smoke
  builds). Generate one upload keystore per app, store it base64 in GitHub
  Actions secrets, and enrol both apps in Play App Signing so Google holds the
  distribution key — an upload key can then be reset through Play Console if it
  is lost, which is the whole point. Register the Google-held **app signing**
  SHA-256 with Firebase and any Maps/PSP console, not the upload key.
- **Files to change** — `apps/rider/android/app/build.gradle:56-71`,
  `apps/captain/android/app/build.gradle:56-71`; new
  `docs/mobile/SIGNING.md`; new `apps/*/android/key.properties.example`.
- **DB** — none. **API contract** — none.
- **Effort** — S. **Risk** — a developer who relied on the silent fallback gets a
  build failure; mitigated by the explicit opt-in flag and the error message.
- **Acceptance criteria** — `flutter build apk --release` with no keystore fails
  with a readable message; with `key.properties` present it produces an APK whose
  `apksigner verify --print-certs` shows the upload certificate, not the Android
  debug certificate; both apps are enrolled in Play App Signing.
- **Tests** — a CI job that asserts the no-keystore release build exits non-zero.

### P0.2 — Raise `targetSdk` to 35 and schedule 36

- **Goal** — the upload is accepted.
- **Design** — set `targetSdk = 35` in both apps and work the Android 15
  behaviour changes: edge-to-edge is enforced by default (audit every
  `Scaffold`/`SafeArea` for content under the system bars), foreground service
  types are mandatory, and `ACCESS_BACKGROUND_LOCATION` prompting changes. Plan
  the move to 36 before 31 August 2026; if that date is at risk, file the Play
  Console extension to 1 November 2026 rather than discovering the block on
  submission day.
- **Files to change** — `apps/rider/android/app/build.gradle:51`,
  `apps/captain/android/app/build.gradle:51`, plus whatever the edge-to-edge
  audit turns up in `apps/*/lib/screens/**`.
- **DB / API contract** — none.
- **Effort** — M (one line, then a real device pass on Android 15).
- **Risk** — visual regressions under the status/navigation bars. Rollback is the
  one-line revert.
- **Acceptance criteria** — both apps build at `targetSdk 35`; a manual pass on
  an Android 15 device shows no content clipped by system bars; the internal-test
  upload is accepted by Play.
- **Tests** — golden tests for the main scaffolds once T23's Flutter test harness
  exists; until then, a documented manual device checklist.

### P0.3 — Account deletion, end to end

- **Goal** — both stores' deletion requirements are satisfied without destroying
  the financial record.
- **Design** — soft-delete with identifier tombstoning. `DELETE /user/account`
  requires a fresh OTP re-authentication, refuses while a trip is active or the
  wallet balance is non-zero (returning a specific error the UI explains), then
  nulls `phone`, `name`, `email`, `avatar_url`, sets `deleted_at`, writes an
  audit row, revokes all sessions in KV and deletes the user's `device_tokens`.
  Trips and wallet ledger rows keep pointing at the tombstoned user id. A public
  web form at `https://synapticstudio.tech/delete-account` performs the same
  operation via OTP for users who have uninstalled — Play requires this second
  path.
- **Files to change** — `apps/api/src/routes/user.ts` (new handler),
  `apps/api/src/lib/schemas.ts`, `apps/api/src/lib/audit.ts`;
  `apps/rider/lib/screens/profile/profile_screen.dart`,
  `apps/captain/lib/screens/profile/settings_screen.dart` (both need the same
  flow — see T27); a static page in `apps/admin` or a public Pages route.
- **DB** — one migration (next free number; the repo had 19 migration files with
  17 applied as of `docs/DEPLOYMENT.md:76-79`, so confirm at merge time):
  ```sql
  ALTER TABLE users ADD COLUMN deleted_at TEXT;
  CREATE INDEX idx_users_deleted_at ON users(deleted_at);
  ```
- **API contract** —
  ```
  DELETE /user/account
  Headers: Authorization: Bearer <jwt>
  Body:    { "otp": "123456", "reason": "optional string" }
  200:     { "ok": true, "deleted_at": "2026-08-01T14:20:36Z" }
  409:     { "error": "active_trip" | "wallet_balance_nonzero", "balance": 4250 }
  401:     { "error": "otp_invalid" }
  ```
- **Effort** — M. **Risk** — accidental deletion; mitigated by OTP
  re-authentication, the active-trip guard, and a 30-day tombstone window before
  hard anonymisation.
- **Acceptance criteria** — a user can delete from inside both apps in under four
  taps from the profile screen; sessions die immediately; the trip ledger still
  balances; the web form works without the app installed.
- **Tests** — integration test that deletion revokes sessions and preserves
  `wallet_transactions` row count; a test that deletion is refused mid-trip.

### P0.4 — Force-upgrade gate (the keystone)

- **Goal** — the platform can refuse to serve a client version, and can tell any
  client to update, without a store release.
- **Design** — three parts.
  1. **Clients identify themselves.** `ApiClient` adds `X-App-Version` (the
     pubspec `version`, injected at build time via `--dart-define=APP_VERSION`)
     and `X-App-Platform` (`android` | `ios`, from `Platform.isIOS`, replacing
     the hardcoded `'android'` of F-26-18) to every request.
  2. **The server publishes policy.** A new public `GET /config/app` reads
     `system_config` — no new table needed — and returns the minimum and latest
     versions per platform plus a maintenance flag. The splash screen calls it
     before anything else and blocks on `action: "force"`.
  3. **The server enforces.** A middleware compares `X-App-Version` against
     `min_supported_<platform>` and returns `426 Upgrade Required` for anything
     below it, so an old client that skips the check still cannot transact. Absent
     header ⇒ treated as legacy ⇒ 426 once a floor is set (this is why the header
     must ship in the *first* store build, before any floor is raised).
- **Files to change** — `packages/flutter_shared/lib/services/api_client.dart:10-13`
  (headers), both `splash_screen.dart` (gate), new
  `packages/flutter_shared/lib/widgets/force_upgrade_screen.dart` (shared by both
  apps — do not duplicate it, see T27), new `apps/api/src/routes/config.ts`,
  `apps/api/src/middleware/` (new `versionGate.ts`), `apps/api/src/index.ts`
  (mount both).
- **DB** — one migration adding a version column to device registrations and
  seeding the config keys:
  ```sql
  ALTER TABLE device_tokens ADD COLUMN app_version TEXT;
  INSERT INTO system_config (key, value) VALUES
    ('min_supported_android', '1.0.0+1'),
    ('min_supported_ios',     '1.0.0+1'),
    ('latest_android',        '1.0.0+1'),
    ('latest_ios',            '1.0.0+1'),
    ('maintenance_mode',      'false'),
    ('maintenance_message_ar',''),
    ('maintenance_message_en','');
  ```
- **API contract** —
  ```
  GET /config/app?platform=android&version=1.0.0%2B12      (public, cacheable 60 s)
  200 {
    "min_supported": "1.2.0+40",
    "latest":        "1.3.0+52",
    "action":        "none" | "recommend" | "force",
    "store_url":     "https://play.google.com/store/apps/details?id=tech.synapticstudio.synaptic_go_rider",
    "message":       { "ar": "يلزم تحديث التطبيق للمتابعة", "en": "An update is required to continue" },
    "maintenance":   { "active": false, "message": { "ar": "", "en": "" } }
  }

  Any authenticated request from a client below the floor:
  426 { "error": "upgrade_required", "min_supported": "1.2.0+40", "store_url": "…" }
  ```
  Version comparison is on the integer build number after `+`, not the semver
  string — it is the only monotonic part and it maps 1:1 to Android
  `versionCode` and iOS `CFBundleVersion`.
- **Effort** — M. **Risk** — a mis-set floor locks out the entire installed base.
  Mitigations: the admin UI must show the count of `device_tokens` below a
  proposed floor before saving; the floor can only ever be raised through the
  admin route, never by a deploy; and `426` is never returned for
  `GET /config/app` itself.
- **Acceptance criteria** — raising `min_supported_android` in the admin console
  causes a running old client to show the blocking update screen within 60
  seconds and to receive 426 on its next authenticated call; the update screen
  offers exactly one action, opening the store.
- **Tests** — unit tests on build-number comparison across `1.0.0+9` vs
  `1.0.0+10` (the classic string-compare bug); an integration test asserting 426
  for a stale header and 200 for a current one.

### P0.5 — Resolve background location deliberately

- **Goal** — the two platforms agree, the declarations match the code, and App
  Review has nothing to ask about.
- **Design** — two steps, in this order. **Now:** delete `UIBackgroundModes` and
  `NSLocationAlwaysAndWhenInUseUsageDescription` from the rider `Info.plist`
  entirely, and remove `fetch` from the captain's; ship v1 foreground-only on
  both platforms and say so in the store listing. **Then, as a scheduled
  release:** implement a real Android foreground service
  (`foregroundServiceType="location"`, `FOREGROUND_SERVICE` +
  `FOREGROUND_SERVICE_LOCATION` permissions, persistent notification showing
  "online — receiving offers"), add the iOS `location` background mode back on
  the captain only with `allowsBackgroundLocationUpdates` and the blue-bar
  indicator, add a prominent-disclosure screen before the OS prompt (P1.4), and
  budget several weeks for Play's declaration review including the 30-second demo
  video.
- **Files to change** — `apps/rider/ios/Runner/Info.plist:50-51,56-60`,
  `apps/captain/ios/Runner/Info.plist:56-61`; later
  `apps/captain/android/app/src/main/AndroidManifest.xml`, a new Kotlin
  foreground service, `apps/captain/lib/services/captain_state.dart:639`.
- **DB / API contract** — none.
- **Effort** — S for the strip, L for the real implementation.
- **Risk** — shipping v1 foreground-only means captains must keep the app open;
  that is a real product cost and must be a conscious decision (§10 Q1).
- **Acceptance criteria** — no declared capability lacks an implementation; the
  captain's online state and the OS notification agree.
- **Tests** — a manual device matrix (screen off, app backgrounded, battery
  saver on) for the later release.

### P0.6 — Build flavours so no build accidentally points at production

- **Goal** — production is opt-in, not the default.
- **Design** — invert the default in both state classes to the staging URL, and
  drive the value from `--dart-define-from-file` with three checked-in configs
  (`config/dev.json`, `config/staging.json`, `config/prod.json`). Add Android
  `productFlavors` with an `applicationIdSuffix` of `.dev`/`.staging` so a tester
  can hold a staging build and a production build on one phone, and give the
  non-production flavours a different app label and launcher icon so nobody
  demos the wrong one.
- **Files to change** — `apps/rider/lib/services/app_state.dart:69-71`,
  `apps/captain/lib/services/captain_state.dart:131-133`,
  both `android/app/build.gradle`, new `config/*.json`.
- **DB / API contract** — none.
- **Effort** — M. **Risk** — a release built without the prod config now points at
  staging; mitigated by the CI release job hardcoding `config/prod.json` and by
  an in-app debug banner on non-production flavours.
- **Acceptance criteria** — a build with no flags talks to staging; the release
  workflow produces a build that talks to production; both flavours install side
  by side.
- **Tests** — CI asserts the built AAB's `applicationId` matches the expected
  flavour.

### P0.7 — Provision Firebase and inject its config in CI

- **Goal** — anyone, and any runner, can build.
- **Design** — create the Firebase project if `docs/CHECKLIST.md:21` is still
  accurate, register four apps (rider/captain × Android/iOS), store
  `google-services.json` and `GoogleService-Info.plist` base64 in GitHub secrets,
  and have the release workflow decode them into place before building. Commit
  `.example` files with the structure and no keys so a new developer knows what
  is required.
- **Files to change** — new `apps/*/android/app/google-services.json.example`,
  new `docs/mobile/FIREBASE.md`, the release workflow in P0.8.
- **DB / API contract** — none.
- **Effort** — S once the Firebase project exists.
- **Risk** — none beyond secret handling.
- **Acceptance criteria** — a clean clone plus repository secrets produces a
  working build with push notifications registered.

### P0.8 — A release workflow that produces signed artefacts

- **Goal** — every artefact comes from CI, from a tagged commit, reproducibly.
- **Design** — a `workflow_dispatch` + tag-triggered workflow that derives the
  version from the git tag, decodes the keystore and Firebase config from
  secrets, builds an obfuscated AAB per app, uploads the AAB and the debug-symbol
  bundle as run artefacts, and (once the Play account exists) promotes to the
  internal test track. The iOS job is included but will not pass until P1.6
  supplies a signing identity.
- **Files to change** — cannot be committed here: the integration opening this PR
  has no `workflows` permission (the same constraint `docs/DEPLOYMENT.md:11-13`
  hit). The YAML is below and is also written to
  `docs/plan/assets/26-release-mobile.yml.txt` in this PR. Installing it is
  `git mv docs/plan/assets/26-release-mobile.yml.txt .github/workflows/release-mobile.yml`.
- **DB / API contract** — none.
- **Effort** — M.
- **Risk** — secrets misconfigured; the workflow fails loudly rather than
  producing an unsigned artefact, which is the desired failure mode.
- **Acceptance criteria** — pushing tag `rider-v1.1.0+14` produces a signed AAB
  whose `versionCode` is 14, downloadable from the run, verifiable with
  `apksigner`.
- **Tests** — the workflow's own verify step (below) asserts the signing
  certificate is not the debug certificate.

```yaml
# docs/plan/assets/26-release-mobile.yml.txt
# Install as .github/workflows/release-mobile.yml
name: release-mobile

on:
  push:
    tags: ['rider-v*', 'captain-v*']
  workflow_dispatch:
    inputs:
      app:     { description: 'rider | captain', required: true, default: 'rider' }
      track:   { description: 'internal | alpha | beta | production', required: true, default: 'internal' }

permissions:
  contents: read

jobs:
  android:
    name: android (signed aab)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      # Tag format: <app>-v<semver>+<build>, e.g. rider-v1.1.0+14
      # The build number after '+' becomes versionCode and must be monotonic.
      - name: derive app and version
        id: v
        run: |
          if [ "${{ github.event_name }}" = "workflow_dispatch" ]; then
            APP="${{ inputs.app }}"; TAG="$(git describe --tags --abbrev=0 || echo "${APP}-v0.0.1+1")"
          else
            TAG="${GITHUB_REF_NAME}"; APP="${TAG%%-v*}"
          fi
          REST="${TAG#*-v}"; NAME="${REST%%+*}"; CODE="${REST##*+}"
          case "$APP" in rider|captain) ;; *) echo "bad app: $APP"; exit 1 ;; esac
          case "$CODE" in ''|*[!0-9]*) echo "bad build number: $CODE"; exit 1 ;; esac
          echo "app=$APP"   >> "$GITHUB_OUTPUT"
          echo "name=$NAME" >> "$GITHUB_OUTPUT"
          echo "code=$CODE" >> "$GITHUB_OUTPUT"

      - uses: actions/setup-java@v4
        with: { distribution: 'temurin', java-version: '17' }

      - uses: subosito/flutter-action@v2
        with: { flutter-version: '3.24.5', channel: stable, cache: true }

      - name: decode signing material
        env:
          KEYSTORE_B64:   ${{ secrets.ANDROID_KEYSTORE_BASE64 }}
          STORE_PASSWORD: ${{ secrets.ANDROID_STORE_PASSWORD }}
          KEY_PASSWORD:   ${{ secrets.ANDROID_KEY_PASSWORD }}
          KEY_ALIAS:      ${{ secrets.ANDROID_KEY_ALIAS }}
        run: |
          test -n "$KEYSTORE_B64" || { echo "::error::ANDROID_KEYSTORE_BASE64 is not set — refusing to build"; exit 1; }
          APP=${{ steps.v.outputs.app }}
          echo "$KEYSTORE_B64" | base64 -d > "apps/$APP/android/upload.jks"
          cat > "apps/$APP/android/key.properties" <<EOF
          storeFile=upload.jks
          storePassword=$STORE_PASSWORD
          keyAlias=$KEY_ALIAS
          keyPassword=$KEY_PASSWORD
          EOF

      - name: decode firebase config
        env:
          GS_JSON: ${{ secrets.GOOGLE_SERVICES_JSON_RIDER }}
          GS_JSON_CAPTAIN: ${{ secrets.GOOGLE_SERVICES_JSON_CAPTAIN }}
        run: |
          APP=${{ steps.v.outputs.app }}
          if [ "$APP" = "rider" ]; then V="$GS_JSON"; else V="$GS_JSON_CAPTAIN"; fi
          test -n "$V" || { echo "::error::google-services.json secret missing for $APP"; exit 1; }
          echo "$V" | base64 -d > "apps/$APP/android/app/google-services.json"

      - name: pub get
        working-directory: apps/${{ steps.v.outputs.app }}
        run: flutter pub get

      # --obfuscate needs --split-debug-info; the symbols are the only way to
      # read a stack trace afterwards, so they are uploaded as an artefact and
      # must be kept for as long as the release is live.
      - name: build appbundle
        working-directory: apps/${{ steps.v.outputs.app }}
        run: |
          flutter build appbundle --release \
            --build-name=${{ steps.v.outputs.name }} \
            --build-number=${{ steps.v.outputs.code }} \
            --dart-define-from-file=../../config/prod.json \
            --obfuscate --split-debug-info=build/symbols

      # Fail closed: if the debug certificate somehow signed this, stop here
      # rather than shipping it. CN=Android Debug is the tell.
      - name: verify signature is not the debug key
        working-directory: apps/${{ steps.v.outputs.app }}
        run: |
          AAB=build/app/outputs/bundle/release/app-release.aab
          test -f "$AAB" || { echo "::error::no aab produced"; exit 1; }
          unzip -p "$AAB" META-INF/*.RSA 2>/dev/null | keytool -printcert 2>/dev/null | tee cert.txt || true
          if grep -qi "CN=Android Debug" cert.txt; then
            echo "::error::artefact is debug-signed — refusing to publish"; exit 1
          fi

      - uses: actions/upload-artifact@v4
        with:
          name: ${{ steps.v.outputs.app }}-${{ steps.v.outputs.name }}-${{ steps.v.outputs.code }}-aab
          path: apps/${{ steps.v.outputs.app }}/build/app/outputs/bundle/release/app-release.aab
          retention-days: 90

      - uses: actions/upload-artifact@v4
        with:
          name: ${{ steps.v.outputs.app }}-${{ steps.v.outputs.code }}-symbols
          path: apps/${{ steps.v.outputs.app }}/build/symbols
          retention-days: 365

      # Enable once the Play account exists and a service account JSON is stored.
      # Staged rollout starts at 10%; promote by hand after watching vitals.
      # - uses: r0adkll/upload-google-play@v1
      #   with:
      #     serviceAccountJsonPlainText: ${{ secrets.PLAY_SERVICE_ACCOUNT_JSON }}
      #     packageName: tech.synapticstudio.synaptic_go_${{ steps.v.outputs.app }}
      #     releaseFiles: apps/${{ steps.v.outputs.app }}/build/app/outputs/bundle/release/app-release.aab
      #     track: ${{ inputs.track || 'internal' }}
      #     status: inProgress
      #     userFraction: 0.10

  ios:
    name: ios (archive)
    runs-on: macos-14
    # Remove this guard once DEVELOPMENT_TEAM and the signing certificates exist.
    if: ${{ vars.IOS_SIGNING_READY == 'true' }}
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with: { flutter-version: '3.24.5', channel: stable, cache: true }
      - name: import certificates
        uses: apple-actions/import-codesign-certs@v3
        with:
          p12-file-base64: ${{ secrets.IOS_DIST_CERT_P12 }}
          p12-password:    ${{ secrets.IOS_DIST_CERT_PASSWORD }}
      - name: install provisioning profile
        run: |
          mkdir -p ~/Library/MobileDevice/Provisioning\ Profiles
          echo "${{ secrets.IOS_PROVISIONING_PROFILE }}" | base64 -d \
            > ~/Library/MobileDevice/Provisioning\ Profiles/app.mobileprovision
      - name: build ipa
        working-directory: apps/rider
        run: |
          echo "${{ secrets.GOOGLE_SERVICE_INFO_PLIST }}" | base64 -d > ios/Runner/GoogleService-Info.plist
          flutter pub get
          flutter build ipa --release \
            --dart-define-from-file=../../config/prod.json \
            --obfuscate --split-debug-info=build/symbols \
            --export-options-plist=ios/ExportOptions.plist
      - uses: actions/upload-artifact@v4
        with:
          name: rider-ipa
          path: apps/rider/build/ios/ipa/*.ipa
```

### P0.9 — Crash reporting and global error handlers

- **Goal** — a crash in Cairo produces a stack trace someone can read, attributed
  to a build number.
- **Design** — Firebase Crashlytics (the Firebase dependency already exists, so
  it costs roughly 1 MB and no new vendor). In both `main.dart`, wrap `runApp` in
  `runZonedGuarded`, set `FlutterError.onError` and
  `PlatformDispatcher.onError` to forward to Crashlytics, and tag every report
  with the build number and the flavour. Upload the `--split-debug-info` symbols
  from the release workflow so traces de-obfuscate. Coordinate the data-safety
  declaration with T25.
- **Files to change** — `apps/rider/lib/main.dart:18-31`,
  `apps/captain/lib/main.dart`, both `pubspec.yaml`, both
  `android/app/build.gradle`.
- **DB / API contract** — none. **Effort** — S.
- **Risk** — Crashlytics collects device identifiers; it must appear in the Play
  Data-safety form and the Apple privacy label before release, or the mismatch is
  itself a violation.
- **Acceptance criteria** — a deliberate test crash appears in the console within
  five minutes with a readable Dart stack trace and the correct build number.
- **Tests** — a debug-only "force crash" action behind a developer menu.

### P0.10 — One version number, derived from the tag

- **Goal** — every artefact is traceable to a commit, and `versionCode` never
  repeats.
- **Design** — the git tag is the source of truth (P0.8 parses it); the pubspec
  `version:` line is updated by the release workflow rather than by hand, and the
  same build number is passed to `--build-number`, sent as `X-App-Version`, and
  stored in `device_tokens.app_version`. The API's `APP_VERSION` stays a separate
  server version and should be renamed `API_VERSION` in `wrangler.toml` to stop
  the confusion.
- **Files to change** — both `pubspec.yaml:4`, `apps/api/wrangler.toml:76,144,172`.
- **Effort** — S. **Risk** — renaming `APP_VERSION` touches whatever reads it
  (`apps/api/src/index.ts:99-105`); trivial but must be done in one commit.
- **Acceptance criteria** — the version shown in the app's settings screen, the
  `versionCode` in Play, and the tag all agree.

### P1 — first 30 days

**P1.1 — Kill switch and remote config on the client.** Have the splash's
`GET /config/app` call also return the `system_config` keys the client needs, and
honour `maintenance_mode` with a blocking screen. Effort S; this reuses P0.4's
endpoint and the table at `migrations/0016_system_config.sql:20`, and it is the
difference between a bad hour and a bad week.

**P1.2 — App size.** Delete `assets/videos/` from both pubspecs (856 KB each,
measured, zero functional impact — F-26-14), move `assets/images/icons/ios/`
(669 KB) and `playstore_icon.png` (154 KB) out of the app bundle into a
non-bundled `store-assets/` directory, convert the large PNGs to WebP
(~1.5–2 MB estimated), and ship AABs so Play delivers per-ABI. Move
`GODRIVE.png` (3.84 MB) and the root `splash.mp4` out of the repository into the
design store — they are clone bloat, not APK bloat. Target: under 20 MB delivered
download per app.

**P1.3 — Bundle the fonts.** Add Cairo Regular/Medium/Bold to
`packages/flutter_shared/assets/fonts/` and declare them, so typography is
correct offline and on first launch. Roughly 300–600 KB, spent deliberately
rather than gambled on `fonts.gstatic.com` over an Egyptian mobile connection.

**P1.4 — Prominent disclosure screen.** Before the first location prompt in both
apps, a screen that states in Arabic and English what location is collected, why,
and whether it continues in the background — the wording Play's policy requires,
shown before the OS dialog, with an explicit continue action. Required now for
foreground use, mandatory before any background-location declaration.

**P1.5 — Obfuscation everywhere and a symbol archive.** Already in the P0.8
workflow; extend it to iOS and document where symbols live for each release.

**P1.6 — iOS from zero.** Apple Developer Program enrolment (start the D-U-N-S
request on day one — it is the long pole), `DEVELOPMENT_TEAM` in both projects,
replace the legacy `"iPhone Developer"` identity, add
`Runner.entitlements` with `aps-environment`, run `pod init`, add
`ITSAppUsesNonExemptEncryption: false` to both `Info.plist` files, and get one
TestFlight build out. Effort L, mostly waiting.

**P1.7 — Store listings.** See §6.1 below.

### P2 — next 90 days

**P2.1 — Background location, properly.** The Android foreground service, the iOS
background mode restored on the captain only, the Play declaration form and the
30-second demo video, budgeted for several weeks of review.

**P2.2 — Certificate pinning and integrity signals** on the captain app, which
displays earnings and requests payouts — pin the API certificate with a backup
pin and a remote kill switch, and add basic root/emulator signals feeding the
fraud engine (→ T18). Proportionate for a money-handling driver app; not worth
it on the rider app.

**P2.3 — Automated store publishing** with a staged-rollout runbook: 10% for 24
hours watching crash-free rate, then 50%, then 100%, with a documented halt
threshold.

**P2.4 — Flutter widget and golden tests** for the release-critical screens, once
T23's harness exists.

### 6.1 Store listing content plan

Both stores need Arabic (primary, `ar-EG`) and English (`en-US`) listings.

| Asset | Play requirement | Apple requirement | Status |
|---|---|---|---|
| App name | 30 chars | 30 chars | "جو درايف — GoDrive" / "GoDrive" |
| Short description / subtitle | 80 chars | 30 chars | to write |
| Full description | 4000 chars | 4000 chars | to write, both languages |
| Screenshots | ≥2 phone, 16:9 or 9:16 | 6.7" and 5.5" sets | none exist — must be captured post-P0.2 |
| Feature graphic | 1024×500 | n/a | none |
| App icon | 512×512 | 1024×1024 | `godrive_1024.png` exists (627,808 B) |
| Privacy policy URL | required | required | **missing → T25** |
| Data safety / nutrition labels | required | required | must declare precise location, phone, financial info, device IDs |
| Content rating questionnaire | required | age rating | not started |
| Account deletion URL | required | n/a | delivered by P0.3 |

Draft positioning, Arabic primary:

> **جو درايف — رحلتك بسعرك**
> اطلب رحلتك في مصر واتفق على السعر مع الكابتن قبل ما تركب. أسعار واضحة من
> الأول، كباتن موثّقين، ودفع كاش أو بمحفظتك.

> **GoDrive — your ride, your price**
> Book a ride anywhere in Egypt and agree the fare with your captain before you
> get in. Clear prices up front, verified captains, cash or wallet.

The captain listing leads on earnings transparency and no-commission-surprises
rather than on price negotiation. Screenshots must show real Arabic UI with RTL
layout — a screenshot set in English on an RTL product is a common and avoidable
review flag (→ T14).

---

## 7. Phasing

| Item | Phase | Effort | Owner type |
|---|---|---|---|
| P0.1 Signing fails closed + Play App Signing | P0 | S | Flutter/ops |
| P0.2 `targetSdk` 35 (+36 plan) | P0 | M | Flutter |
| P0.3 Account deletion end to end | P0 | M | backend + Flutter |
| P0.4 Force-upgrade gate | P0 | M | backend + Flutter |
| P0.5 Strip unimplemented iOS capabilities | P0 | S | Flutter |
| P0.6 Build flavours, staging by default | P0 | M | Flutter |
| P0.7 Firebase provisioning + CI secrets | P0 | S | ops |
| P0.8 Signed release workflow | P0 | M | ops |
| P0.9 Crashlytics + error handlers | P0 | S | Flutter |
| P0.10 Version from tag | P0 | S | ops |
| P1.1 Kill switch / remote config client | P1 | S | backend + Flutter |
| P1.2 App size reduction | P1 | M | Flutter |
| P1.3 Bundle Cairo | P1 | S | Flutter |
| P1.4 Prominent disclosure screen | P1 | S | Flutter |
| P1.5 Obfuscation + symbol archive | P1 | S | ops |
| P1.6 iOS from zero | P1 | L | Flutter + admin/legal |
| P1.7 Store listings, both languages | P1 | M | product + design |
| P2.1 Background location + Play declaration | P2 | L | Flutter + product |
| P2.2 Cert pinning + integrity (captain) | P2 | M | Flutter + backend |
| P2.3 Automated publishing + rollout runbook | P2 | M | ops |
| P2.4 Widget/golden tests | P2 | M | Flutter |

**Release checklist — every line must be true before the first submission:**

1. `targetSdk ≥ 35`, built and manually verified on an Android 15 device.
2. Release build fails without a keystore; `apksigner` shows the upload cert.
3. Both apps enrolled in Play App Signing; the Google-held SHA-256 registered
   with Firebase.
4. Account deletion works in-app and from the public web URL.
5. `X-App-Version` ships in the first store build; `GET /config/app` live; the
   426 middleware deployed with the floor set to the launch build.
6. No declared capability lacks an implementation on either platform.
7. Production is reachable only from a build made with `config/prod.json`.
8. Crashlytics reporting verified with a test crash, symbols uploaded.
9. Version derived from the git tag; `versionCode` unique and monotonic.
10. Privacy policy published; Data-safety and nutrition labels match the SDKs
    actually shipped.
11. Content rating completed; store listings live in `ar-EG` and `en-US` with
    RTL screenshots.
12. Staged rollout plan agreed with a written halt threshold.

---

## 8. Metrics

Nothing on this axis is currently instrumented, because no release has happened
and no crash reporter exists. Current values below are "none" wherever there is
no measurement path today — that itself is the finding.

| Metric | Source | Current | Target |
|---|---|---|---|
| Crash-free user rate | Crashlytics (P0.9) | unknown — no reporter | ≥ 99.5% before widening any rollout |
| Crash-free session rate | Crashlytics | unknown | ≥ 99.8% |
| ANR rate (Android) | Play Console vitals | unknown — no Play account | < 0.47% (Play's bad-behaviour threshold) |
| Delivered download size, rider | Play Console | ~45–50 MB universal APK (estimated) | < 20 MB via AAB |
| Delivered download size, captain | Play Console | ~43–48 MB (estimated) | < 18 MB via AAB |
| Cold start to first frame, mid-range Android | manual trace, then Play vitals | unmeasured | < 2.5 s |
| Share of installs on the current minimum version | `device_tokens.app_version` (P0.4) | not collected — no column | ≥ 95% within 14 days of a forced floor |
| Time from merge to artefact in a tester's hands | release workflow run time | manual, hours to days | < 20 minutes, automated |
| Time to halt a bad release | none | ∞ — requires a new store release | < 15 minutes via kill switch |
| Store review turnaround | Play Console / App Store Connect | no baseline | track per submission; expect weeks for the background-location declaration |
| Build reproducibility | CI | 0% — one laptop | 100% of shipped artefacts from CI |

The two that matter most in the first month are **share of installs on the
current minimum version** — it proves the force-upgrade gate actually works
before you ever need it — and **time to halt a bad release**, which is the
number that converts a mobile incident from a week into an hour.

---

## 9. Cross-cutting notes

**→ T23 (Testing, CI/CD & Release Safety).** We overlap at CI and should not both
write it. My proposal is that T23 owns the backend pipeline and the test pyramid;
this track owns the mobile release workflow in §6 P0.8. Three things I found that
are yours: (a) `docs/DEPLOYMENT.md:1-13` says the API deploy workflow is sitting
uninstalled at `docs/ci/deploy-api.yml` because of the missing `workflows`
permission — the same wall I hit, so someone with repo admin needs to do one
`git mv` for both of us; (b) `ci.yml:6-9` states plainly that the checks are
visible but not blocking unless branch protection lists them as required — I
could not verify whether it is configured, and if it is not, everything both of
us build is advisory; (c) there are zero Flutter tests and no `test/` directory
in either app, so `flutter test` in any pipeline is a no-op today.

**→ T25 (Privacy, Compliance & Legal).** The store forms are legal artefacts and
I cannot fill them without you. Specifically: the privacy policy URL is required
by both stores and does not exist; the Play Data-safety form and Apple nutrition
labels must declare precise location, phone number, financial info and device
identifiers, and adding Crashlytics (P0.9) adds device identifiers to that list;
the account-deletion design in P0.3 keeps an anonymised financial ledger, which
must be described in the policy; and Egypt's ride-hailing licensing regime under
law 87/2018 (assumed — I did not verify the operator-licensing requirements
against a primary source) may require a transport-authority licence number in the
listing itself.

**→ T27 (Cross-App Parity).** This axis is full of drift, and every item is the
same shape: something was fixed in one app and not the other, or on one platform
and not the other. The rider `Info.plist` declares Always-location and a
background mode it has no use for while the captain — which does need it — has it
removed on Android (`apps/rider/ios/Runner/Info.plist:50-60` vs
`apps/captain/android/…/AndroidManifest.xml:6`). `apps/captain/pubspec.yaml:54`
sets `generate: true` and the rider does not, so the two halves of one product
use different l10n mechanisms. 2,750,499 bytes of byte-identical assets are
duplicated between the two apps instead of living in `packages/flutter_shared`.
The rider's camera usage string describes uploading documents, which is the
captain's flow (`apps/rider/ios/Runner/Info.plist:53`). And when P0.4's
force-upgrade screen is built, it must live in `packages/flutter_shared` — this
is exactly the kind of screen that gets written twice.

**→ T22 (Observability).** Crashlytics (P0.9) is the client half of the
observability story and should join whatever dashboard you define for the Worker;
a spike in client crashes and a spike in 5xx are the same incident seen from two
ends. `device_tokens.app_version` from P0.4 also gives you version-segmented
error rates for free.

**→ T19 (Growth & Notifications).** The push platform string is hardcoded to
`'android'` in both apps (`apps/captain/lib/services/captain_state.dart:1113`,
`apps/rider/lib/services/app_state.dart:526`), so every iOS device will be
registered as Android and APNs routing will break silently on the day iOS ships.
P0.4 fixes it as a side effect, but you should know the token table is wrong by
construction today.

**→ T14 (Localisation & Content).** The four iOS usage strings in each app are
user-facing Arabic copy that Apple reads during review and that no l10n process
covers — they live in `Info.plist`, not in the string catalogue. The rider's
camera string is wrong. Store-listing copy in both languages (§6.1) needs the
same editorial pass as in-app copy.

**→ T18 (Fraud & Risk).** P2.2's root/emulator detection on the captain app is
only worth building if something consumes the signal; that is your engine, not
mine.

**→ T24 (Performance, Cost & Scale).** The runtime font fetch
(`google_fonts` in all three pubspecs, no bundled fallback) is a first-launch
performance cost on a slow connection, and the ~1.6 MB of dead assets per APK is
pure download cost in a data-constrained market.

---

## 10. Open questions

**Q1 — Does v1 ship without background location?**
Options: (a) launch foreground-only, captains must keep the app open;
(b) delay launch several weeks for Play's background-location declaration review
and the foreground-service implementation. **Recommendation: (a).** The
declaration review is measured in weeks and is not parallelisable with anything
else on the critical path, and a foreground-only v1 is a real product that can
be tested with real captains in one city. Ship (a), start the declaration process
in parallel, and treat background tracking as the first post-launch release. What
this costs must be said out loud to the captain community, not discovered.

**Q2 — Android-only launch, or wait for iOS?**
Options: (a) Android first, iOS in a later phase; (b) both together.
**Recommendation: (a).** iOS has never been built (§3.5): no team, no
entitlements, no Podfile, no Apple account, and the D-U-N-S prerequisite alone is
weeks. Egypt's ride-hailing market is Android-dominant (assumed — worth checking
against real market data before committing). Start the Apple enrolment paperwork
now so it matures while Android launches.

**Q3 — Does the in-app wallet change the payments-policy analysis?**
Ride payments for a real-world service are exempt from Google Play Billing and
Apple IAP — Play's payments policy carves out transportation, and Apple's
guideline 3.1.3(e) requires non-IAP for physical services consumed outside the
app. A stored-value wallet that can only be spent on rides is a greyer case, and
a top-up flow can be read as a digital purchase. **Recommendation:** ship v1 with
cash and direct card payment for rides only, and hold the wallet top-up flow
behind the P0.4/P1.1 flag until someone has confirmed the treatment with both
platforms in writing. Getting this wrong is an account-level enforcement risk,
not a rejected build. (→ T04 owns the payments mechanics; this is the store-policy
half.)

**Q4 — One Firebase project or two?**
Two apps × two platforms is four Firebase apps. One project with four apps is
simpler for FCM and gives a single Crashlytics view; two projects isolate
rider and captain data. **Recommendation: one project, four apps**, split later
if analytics governance demands it.

**Q5 — What is the halt threshold for a staged rollout?**
Needs a number the team agrees to in advance, when nobody is panicking.
**Recommendation:** halt at 10% if the crash-free user rate drops below 99.0% or
the ANR rate exceeds 0.47%, and require a written go/no-go before each widening.

**Q6 — Who holds the keys?**
Play App Signing means Google holds the distribution key, but the upload key, the
Apple certificates and the Firebase service account still need an owner and a
recovery path. Today all of it would live on one laptop. **Recommendation:**
a shared password manager entry owned by two named people, with the upload
keystore also stored as a GitHub secret, and this written down in
`docs/mobile/SIGNING.md` rather than remembered.

**Q7 — Is branch protection actually on for `main`?**
`ci.yml:6-9` says the checks only block a merge if they are configured as
required status checks, and I cannot read that setting from the repository. If it
is off, every gate discussed here and in T23 is advisory. Someone with admin
access should confirm it in one click. `needs-check`.
