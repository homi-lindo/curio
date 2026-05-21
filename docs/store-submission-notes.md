# Store Submission Notes

Use this file as copy-ready review material when filling Microsoft Store and
Google Play forms. Keep it aligned with `docs/store-readiness.md` and
`docs/store-review-evidence.md`.

## Google Play

### Exact alarm declaration

Curió requests `SCHEDULE_EXACT_ALARM` so users can create dated tasks and
personal agenda reminders and receive a local notification at the selected
time. Reminder scheduling is a core app feature, not a background analytics,
advertising, or engagement mechanism.

If exact alarms are denied by the user or device policy, Curió falls back to
inexact allow-while-idle scheduling so reminders degrade gracefully instead of
being dropped.

### Data safety

- The app collects user-provided tasks, notes, reminder settings, and sync
  configuration only inside the app experience.
- The app does not include ads, analytics SDKs, tracking SDKs, or a
  developer-operated cloud service.
- Data is transmitted only when the user configures sync. Sync traffic goes to
  the user-configured server URL and uses the `x-lume-sync-token` header.
- The sync token is stored with Android Keystore-backed encryption on Android
  and Windows DPAPI on Windows.
- Android backup and device-transfer extraction are disabled so private app
  data is not intentionally copied by OS backup or migration flows.
- Users can delete tasks and notes in the app. If sync is enabled, deletion
  markers are sent to the configured sync server so other devices can delete the
  same records.

### Release signing

Create `android/key.properties` from `android/key.properties.example` only on
the release machine. Keep the real file and keystore outside source control.
The Gradle release task fails closed until all four fields are present:
`storeFile`, `storePassword`, `keyAlias`, and `keyPassword`.

Before creating the Play App Bundle, install Android SDK Command-line Tools
through Android Studio's SDK Manager and accept Android licenses. Without that
component, Gradle can finish successfully but Flutter still fails the final
release bundle native-symbol check.

If `app-release.aab` is present after that Flutter failure, rebuild it after
fixing the SDK toolchain before uploading to Play.

Use `tool\android\build-release-appbundle.ps1` for the upload artifact. It
captures the release build log, verifies the App Bundle with `jarsigner`, and
writes the success marker checked by `tool\verify-release-readiness.ps1 -Strict`.

The helper below creates `release-upload-key.jks` plus the ignored
`android/key.properties` file. It prompts for passwords and does not pass them
as `keytool` command-line arguments:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tool\android\create-release-keystore.ps1
```

## Microsoft Store

### Capabilities

The MSIX declares `internetClient` and `privateNetworkClientServer` because the
user can configure cloud or LAN sync endpoints. The package does not bundle a
standalone sync server. The optional Windows local server runs only inside the
app process after the user starts it from the Sync view.

### WACK

Run the current MSIX through Windows App Certification Kit with:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tool\windows\run-wack-admin.ps1
```

The wrapper opens an elevated PowerShell, runs `tool\windows\run-wack.ps1`,
writes `build\windows\wack-report-1.0.22.xml`, and leaves the window open so
the result can be reviewed.

The latest completed local WACK report is
`build\windows\wack-report-1.0.22.xml`: overall `PASS`, 24 tests, 0 required
failures, 1 optional Flutter-runtime finding for `CreateProcessW`/`CMD` inside
`flutter_windows.dll`.

### Privacy

Use `docs/privacy-policy.md` as the source text for the store privacy policy.
It intentionally states that Curió has no ads, analytics, tracking SDKs, or
developer-operated cloud service.
