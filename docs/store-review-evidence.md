# Store Review Evidence

This file keeps reviewer-facing evidence for Google Play and Microsoft Store.
It is factual and tied to the current release artifacts.

Verified on 2026-05-21 against:

- Android exact alarm behavior:
  https://developer.android.com/about/versions/14/changes/schedule-exact-alarms
- Google Play sensitive permissions policy:
  https://support.google.com/googleplay/android-developer/answer/9888170
- Microsoft Windows App Certification Kit:
  https://learn.microsoft.com/en-us/windows/uwp/debug-test-perf/windows-app-certification-kit
- Microsoft Desktop Bridge app tests:
  https://learn.microsoft.com/en-us/windows/uwp/debug-test-perf/windows-desktop-bridge-app-tests

## Google Play exact alarm position

Curió declares `SCHEDULE_EXACT_ALARM`, not `USE_EXACT_ALARM`.

Why this is the safer policy posture:

- The app's core workflow is agenda/task reminders chosen by the user.
- The reminder notification is local, visible, and scheduled for the time the
  user selected.
- The app does not use exact alarms for analytics, engagement campaigns,
  background sync, ads, or any hidden task.
- Android exact alarm guidance says apps should check whether exact alarms can
  be scheduled before using them. Curió calls
  `canScheduleExactNotifications()` before scheduling.
- If exact alarms are denied, Curió falls back to
  `inexactAllowWhileIdle` instead of dropping the reminder or forcing the
  restricted `USE_EXACT_ALARM` permission.
- The release manifest does not declare `USE_FULL_SCREEN_INTENT`.

Copy-ready declaration:

Curió uses `SCHEDULE_EXACT_ALARM` only for user-created agenda/task reminders.
Users choose a date/time, and Curió schedules a local reminder notification for
that selected time. Reminder scheduling is a core, user-visible feature of the
app. Curió does not use exact alarms for ads, analytics, background sync, or
engagement nudges. If exact alarm access is not granted by the device/user,
Curió degrades to an inexact allow-while-idle reminder instead of silently
failing.

Evidence in the current app:

- Source manifest:
  `android/app/src/main/AndroidManifest.xml`
- Generated release manifest:
  `build/app/intermediates/merged_manifest/release/processReleaseMainManifest/AndroidManifest.xml`
- Notification implementation:
  `lib/services/notification_service.dart`
- Regression tests:
  `test/notification_service_test.dart`

## Microsoft Store WACK position

Current WACK report:

- Report: `build/windows/wack-report-1.0.22.xml`
- App: `App.Lume.Personal 1.0.22.0`
- Overall result: `PASS`
- Tests: 24
- Required failures: 0
- Optional failures: 1

The optional finding is the Desktop Bridge "Blocked executables" informational
test against `flutter_windows.dll`, where WACK reports references to
`CreateProcessW` and `CMD`. This DLL is the upstream Flutter Windows runtime,
not Curió application code. The app package does not bundle a standalone sync
server executable and does not auto-launch external tools.

Microsoft's Desktop Bridge test documentation says optional tests are
informational and are not used to evaluate Microsoft Store onboarding. The
strict local readiness gate still tracks this finding so any new optional WACK
failure is surfaced as a warning.

Copy-ready Microsoft note:

The submitted package passes WACK with 0 required failures. One optional
Desktop Bridge "Blocked executables" finding is reported for the upstream
Flutter runtime file `flutter_windows.dll`, which contains references to
`CreateProcessW` and `CMD`. This is not app-authored process-launch code, the
app does not include a standalone sync server executable in the MSIX, and the
package's required certification tests pass.
