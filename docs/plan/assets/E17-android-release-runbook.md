# E17 — Android release runbook (the human half of gate item 13)

Companion to `docs/plan/assets/release-mobile.yml`. Everything in this file needs a
person: a keystore that must never enter the repository, a Play Console enrolment, and
a workflow file no agent is permitted to commit.

Task `E17` changed three things in code:

| Change | File | Effect |
|---|---|---|
| `targetSdk` 34 → 35 | `apps/rider/android/app/build.gradle`, `apps/captain/android/app/build.gradle` | Play accepts the upload at all |
| Release signing fails closed | same two files | A missing keystore stops the build instead of quietly using the debug key |
| Dead iOS background-location declarations removed | `apps/rider/ios/Runner/Info.plist` | One fewer App Review rejection reason |

It could not do the fourth thing — produce the artefact in CI — because that is a
workflow file. That is what this runbook is for.

---

## 1. Create the upload keystore (once, ever)

Run this on a machine you trust, not in CI:

```bash
keytool -genkeypair -v \
  -keystore upload-keystore.jks \
  -storetype JKS \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias godrive-rider \
  -dname "CN=Synaptic Studio, OU=GoDrive, O=Synaptic Studio, L=Cairo, C=EG"
```

Repeat with `-alias godrive-captain` (same keystore file is fine — two aliases, one file —
or two files if you prefer them separated).

- **Never commit it.** `/.gitignore:77-79` and `apps/*/android/.gitignore:11-13` already
  ignore `*.jks`, `*.keystore` and `key.properties`. Keep it that way.
- Store the file and both passwords in the team password manager. If the upload key is
  lost you can ask Google to reset it **only if you enrolled in Play App Signing** (§2).
  Without that enrolment, a lost key means the app can never be updated again — every
  user must uninstall and reinstall. That is the failure mode the old
  `signingConfigs.debug` fallback was quietly walking towards.

## 2. Enrol in Play App Signing

Do this when the app is first created in the Play Console, before the first upload:

1. Play Console → your app → **Test and release → Setup → App signing**.
2. Choose **"Use Play App Signing"** (the default for new apps, and not reversible later).
3. Upload the certificate of the key from §1 as the **upload key**:
   `keytool -export -rfc -keystore upload-keystore.jks -alias godrive-rider -file upload_certificate.pem`
4. Google now holds the *app signing key* and re-signs every upload. Your `.jks` is only
   the *upload key* — replaceable, which is the entire point.

Record which alias belongs to which app in the password manager entry. The two apps are
separate Play listings: `tech.synapticstudio.synaptic_go_rider` and
`tech.synapticstudio.synaptic_go_captain`.

## 3. Add the repository secrets

Settings → Secrets and variables → Actions:

| Secret | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | `base64 -w0 upload-keystore.jks` |
| `ANDROID_KEYSTORE_PASSWORD` | the `-storepass` from §1 |
| `ANDROID_KEY_ALIAS_RIDER` | `godrive-rider` |
| `ANDROID_KEY_ALIAS_CAPTAIN` | `godrive-captain` |
| `ANDROID_KEY_PASSWORD` | the key password (same as the store password unless you set one) |
| `GOOGLE_SERVICES_JSON_RIDER` | the full contents of the rider's `google-services.json` |
| `GOOGLE_SERVICES_JSON_CAPTAIN` | the captain's |

The last two exist because `google-services.json` is absent from the repository and
gitignored (`/.gitignore:75`) while `app/build.gradle:7` applies the plugin
unconditionally — finding **F-26-06**, still open. Until those two secrets exist, **no
Android build can succeed anywhere**, in CI or on a laptop. E17 did not fix that and did
not pretend to: the negative-test job writes a stub so the fail-closed test does not
depend on it, and the real build job fails with a named error if the secret is missing.

## 4. Install the workflow

```bash
cp docs/plan/assets/release-mobile.yml .github/workflows/release-mobile.yml
git add .github/workflows/release-mobile.yml && git commit && git push
```

Do it in the same sitting as `E00`'s `deploy.yml`, so both workflow installs happen once.

Then confirm the negative test actually runs and actually passes — a green run URL is the
verification, not the presence of the file. `docs/DEPLOYMENT.md` records PR #46 adding a
workflow that went to `docs/` and has never run; do not repeat that.

## 5. Local release builds

Create `apps/<app>/android/key.properties` (gitignored):

```properties
storeFile=/absolute/path/to/upload-keystore.jks
storePassword=…
keyAlias=godrive-rider
keyPassword=…
```

`storeFile` may be relative, but it resolves against `android/app/`, not the repo root —
an absolute path is less surprising. The build also accepts the same four values from the
environment (`ANDROID_KEYSTORE_PATH`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`,
`ANDROID_KEY_PASSWORD`); `key.properties` wins where both are present.

With neither, `flutter build appbundle --release` now stops with:

```
Refusing to build :app:assembleRelease: release signing is not configured.
  Missing: storeFile / ANDROID_KEYSTORE_PATH, storePassword / …
```

Debug builds, `flutter run` and `flutter analyze` are unaffected — the check is on the
task graph, so it only fires for a build that would emit a release artefact.

The Windows batch files in `scripts/` (`run-rider.bat`, `run-captain.bat`,
`install-apks.bat`) still hardcode one laptop's paths. They are in no task's `owns` and
were left alone. Once the workflow above is installed they are dead weight; deleting them
belongs to a wave-2 cleanup, not here.

## 6. What targetSdk 35 changes at runtime — check these before shipping

Bumping the target is a behaviour change, not just a number. Neither belongs to E17's
files, so both are QA items rather than code changes here:

- **Edge-to-edge is mandatory on Android 15** for apps targeting API 35. The system bars
  become transparent and content draws behind them. Flutter 3.24.5 (pinned in
  `ci.yml:112`) does not fully compensate. Walk both apps on an Android 15 device and look
  for content under the status bar and the gesture pill — the fix, if needed, is
  `SafeArea` / `SystemChrome` in Dart, owned by nobody in this wave.
- **`elegantTextHeight` defaults to true** at API 35, which changes line height for
  Arabic. This is an RTL-first product, so check the dense screens (trip cards, wallet
  history) for clipping. The override lives in `res/values/styles.xml`, also unowned.

## 7. The deadline this does not solve

`targetSdk 35` clears today's Play floor. Per the plan's own finding **F-26-01 (S-047)**,
**API 36 becomes mandatory on 31 August 2026** — thirty days from this change. Going to 36
needs `compileSdk = 36` and an Android Gradle Plugin newer than the `8.3.2` pinned in
`apps/*/android/settings.gradle:22`, which is outside E17's `owns` and cannot be validated
without actually running a build. Schedule it now; it is a toolchain upgrade, not a
one-line edit.
