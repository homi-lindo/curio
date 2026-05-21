# Store Readiness

This checklist keeps release builds explicit and reviewable for Microsoft Store
and Google Play submissions.

Use `docs/store-review-evidence.md` for copy-ready reviewer notes and the
official policy references checked for the current release.

## Android

- Release builds reject plain HTTP sync URLs in code and set
  `usesCleartextTraffic=false` in the Android manifest.
- The release network security config also sets
  `cleartextTrafficPermitted=false`; only the debug resource override permits
  HTTP and user-installed certificates for local LAN testing.
- URL input without a scheme defaults to HTTPS in release and HTTP only in
  debug, so local Docker testing stays simple without relaxing packaged builds.
- Sync URLs must be plain origins such as `https://sync.example.com`; the app
  rejects userinfo, paths, query strings, and fragments so tokens are not sent
  to ambiguous endpoints.
- Use HTTPS for the optional self-hosted sync server before distributing a
  release build.
- Release signing must use `android/key.properties`; the real file and key
  material are ignored by source control. Use
  `tool\android\create-release-keystore.ps1` to create a local upload key and
  matching ignored `android/key.properties` file. The helper prompts for
  passwords and feeds them to `keytool` through stdin instead of command-line
  arguments.
- Play release bundling requires Android SDK Command-line Tools. Install
  `Android SDK Command-line Tools (latest)` with Android Studio's SDK Manager
  and accept Android licenses before running `flutter build appbundle
  --release`; otherwise Flutter cannot perform its final native-symbol checks
  even after Gradle reports a successful build.
- Build the Play artifact with `tool\android\build-release-appbundle.ps1`. The
  wrapper runs `flutter build appbundle --release --no-pub`, verifies the
  resulting App Bundle with `jarsigner`, and writes a hash/size success marker
  consumed by `tool\verify-release-readiness.ps1 -Strict`.
- The strict readiness gate checks the generated release manifest after the
  bundle build: version name/code, cleartext disabled, backup disabled,
  `dataExtractionRules`, absence of `ProfileInstallReceiver`, and no exported
  components except the launcher activity.
- If `app-release.aab` exists after a failed Flutter bundle run, do not upload
  it. Fix the Android SDK toolchain, rebuild the App Bundle, and rerun
  `tool\verify-release-readiness.ps1 -Strict` so the final artifact is newer
  than any failed bundle log.
- The current Flutter/AGP toolchain still requires the template
  `android.newDsl=false` and `android.builtInKotlin=false` flags. Removing them
  currently breaks `dev.flutter.flutter-gradle-plugin`; revisit this only with a
  Flutter/AGP migration test.
- `SCHEDULE_EXACT_ALARM` is intentional because the app's core value is agenda
  reminders. If Play Console asks for an exact alarm declaration, describe the
  user-visible task/reminder scheduling feature: users create dated tasks and
  reminders, and the app notifies them at the selected time.
- Do not switch to `USE_EXACT_ALARM` unless the app is listed and reviewed as a
  strict alarm/timer/calendar app. `SCHEDULE_EXACT_ALARM` keeps user control and
  a broader review posture. Verified against Android exact alarm guidance and
  Google Play policy on 2026-05-21:
  https://developer.android.com/about/versions/14/changes/schedule-exact-alarms
  https://developer.android.com/develop/background-work/services/alarms/schedule
  https://support.google.com/googleplay/android-developer/answer/16070163
- If exact alarms are denied on-device, the app falls back to inexact
  allow-while-idle Android scheduling instead of silently dropping reminders.
- `POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED`, and `VIBRATE` are tied to
  local reminders and reboot recovery.
- The release manifest removes AndroidX ProfileInstaller's exported diagnostic
  receiver during manifest merge, leaving the launcher activity as the only
  exported component from app code/dependencies.
- Android backup is explicitly disabled with `allowBackup=false`,
  `fullBackupContent=false`, and `dataExtractionRules` exclusions for cloud,
  device-to-device, and cross-platform transfer modes so private notes, tasks,
  and encrypted token blobs are not copied by OS backup or migration flows.
  Add a deliberate export/restore flow before changing this. Verified against
  Android Auto Backup documentation on 2026-05-20:
  https://developer.android.com/identity/data/autobackup
- In-app activity logs must stay content-free: no task/note text, raw
  notification payloads, local file paths, or sync token values.
- Sync tokens must stay out of `lume-sync.json`. The app migrates legacy
  plaintext tokens into platform secure storage during load.
- Use `docs/privacy-policy.md` as the base for the Play privacy policy and Data
  safety answers, and `docs/store-submission-notes.md` for copy-ready exact
  alarm and Data safety language.
- Android launcher assets now use the Curió app icon instead of the Flutter
  template icon.

## Windows

- MSIX network capabilities are limited to `internetClient` plus
  `privateNetworkClientServer` for user-configured cloud/LAN sync.
- The generated Flutter desktop package declares `runFullTrust`, which is
  expected for a packaged Win32 desktop app. Do not add other restricted
  capabilities without a store-review reason.
- No standalone sync server executable is bundled into the MSIX. The optional
  Windows local server runs in the Flutter process only after the user starts it
  from the Sync view; Docker remains documented as a separate self-hosted
  component.
- The Windows local server is not a service, does not auto-start with Windows, and
  does not bypass release sync URL validation. It is token-protected local/LAN
  HTTP for trusted personal setups; use Docker or another HTTPS endpoint for
  regular packaged Android/Windows release sync.
- Sync token storage uses user-scoped Windows DPAPI via the native runner,
  stores only encrypted bytes under package `LocalState` when packaged, and
  writes through a same-directory `.tmp` file plus `MoveFileEx` replacement to
  avoid corrupting the token file on interrupted writes.
- The optional sync server keeps CORS disabled by default, caps request bodies,
  rejects wildcard/ambiguous CORS origins, and returns generic external errors
  so it does not expose internal parse or file details to clients.
- The optional sync server writes state through a same-directory temp file and
  keeps a `.bak` copy so an interrupted JSON write can be recovered on the next
  read.
- The standalone Docker/Dart sync server requires `LUME_SYNC_TOKEN` by default.
  Tokenless mode exists only behind explicit `--allow-empty-token` and is
  limited to loopback development.
- App, local server, and standalone server all reject sync tokens shorter than 16
  characters.
- Generate the MSIX with `tool\windows\package-msix.ps1`. Configure signing
  with `LUME_MSIX_CERTIFICATE_THUMBPRINT` for a certificate already in the
  Windows certificate store, or `LUME_MSIX_CERTIFICATE_PATH` plus
  `LUME_MSIX_CERTIFICATE_PASSWORD` for PFX-based local signing. The script runs
  `msix:create`, replaces BadgeLogo assets with transparent store-valid PNGs,
  converts Flutter's compressed `NOTICES.Z` into plain `NOTICES`, repacks,
  signs, and verifies the package. Missing signing configuration fails before
  package mutation.
- Run Windows App Certification Kit against the final MSIX before store
  submission with `tool\windows\run-wack.ps1`. The script resolves
  `appcert.exe`, writes the report next to the Windows build output, prints a
  concise pass/fail summary, and exits nonzero only for required failures or an
  overall WACK failure. The latest completed local report is
  `build\windows\wack-report-1.0.22.xml` with overall result `PASS`, 24 tests,
  and 0 required failures. The convenience wrapper
  `tool\windows\run-wack-admin.ps1` opens the elevated process and keeps the
  result window open for future runs.
- The latest completed WACK report has one optional Flutter-runtime finding:
  `flutter_windows.dll` references `CreateProcessW`/`CMD`. This comes from the
  upstream Flutter Windows runtime, not app code, and does not change the
  overall WACK pass; keep it documented for Microsoft review notes.
- Windows package visual identity passes WACK and no longer uses the default
  Flutter template icon.
- Use `docs/privacy-policy.md` as the base for the Microsoft Store privacy
  policy URL/content.

## Release Commands

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tool\verify-release-readiness.ps1 -Strict
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tool\android\create-release-keystore.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tool\android\build-release-appbundle.ps1
$env:LUME_MSIX_CERTIFICATE_THUMBPRINT = "<certificate-thumbprint>"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tool\windows\package-msix.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tool\windows\run-wack-admin.ps1
```

For Android, create `android/key.properties` from
`android/key.properties.example`, or run `tool\android\create-release-keystore.ps1`,
before running a release build. The Play artifact is
`build\app\outputs\bundle\release\app-release.aab`.
