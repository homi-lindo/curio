# Curió

Curió is a personal local-first agenda and notes app for Windows and Android.
This repository is currently in Phase 0: validating the native notification
path, the app shell, and the reminder scheduling contract before adding sync.

## Current scope

- Flutter app shell for Windows and Android.
- Today, Agenda, Board, and Notes views.
- Sync view with server URL, shared token, device ID, and last sync result.
- Task create/edit/delete with optional due date and reminder toggle.
- Agenda search, task filters, and timeline/board display modes.
- Global text search across tasks and notes.
- Page zoom controls from 20% to 200% for dense agenda review and large text.
- Inline agenda day actions for editing a selected day or adding an item to it.
- Free-form notes editor with persisted note selection/content.
- Note create/rename/delete plus quick task creation from a note.
- Local notification service using `flutter_local_notifications`.
- Windows MSIX package with app identity for more reliable desktop toasts.
- Android manifest setup for scheduled exact notifications and reboot recovery.
- Deterministic occurrence keys and local notification IDs.
- SQLite local store, generated with Drift, for tasks, notes, and scheduled
  notification projections.
- Persistent per-install device identity.
- Sync tombstones for task/note deletes plus an offline merge adapter that keeps
  newer edits and prevents older remote records from reviving deleted items.
- Tiny self-hosted HTTP sync server implemented with `dart:io` in
  `server/bin/lume_sync_server.dart`.
- Optional shared-token protection for `/snapshot` and `/sync` via the
  `x-lume-sync-token` header.
- Sync server CORS is disabled by default; enable it only for browser-based
  diagnostics with `LUME_SYNC_CORS_ORIGIN`.
- Sync server request bodies are capped by `LUME_SYNC_MAX_BODY_BYTES`
  (`10485760` by default).
- Optional HTTPS transport for the sync server with PEM certificate/key files.
- Optional Docker/Compose setup for running the sync server outside the app
  installable.
- Optional Windows local sync server that runs the same HTTP API inside the
  Flutter process when started from the Sync view.
- Release builds require HTTPS sync URLs; plain HTTP is debug-only.
- Unit tests for one-shot, daily, weekly, storage, migration, timezone, sync,
  and notification projection contracts.

## Architecture notes

- `ReminderIntent` is the syncable domain object.
- `ScheduledNotificationRecord` is the device-local projection.
- One-shot occurrence keys use the UTC instant ISO string.
- Daily and weekly occurrence keys use the local occurrence date (`YYYY-MM-DD`).
- Local notification IDs are stable hashes of device, reminder, and occurrence.
- The MVP schedules notifications locally on each opted-in device; the server
  should only sync data, not fire notifications.
- Task reminders are one-shot local projections owned by the task ID. Editing,
  completing, or deleting a task cancels old projections before scheduling the
  replacement.
- Timezone setup is plugin-free: `LocalTimeZoneResolver` maps common platform
  names, including Windows Brasilia time, to IANA IDs before scheduling.
- `TaskItem.sourceNoteId` stores the lightweight note-to-task link. SQLite
  schema version 2 added this nullable column.
- SQLite schema version 3 adds `deleted_record_rows` so deletes can sync safely.
- `DeviceIdentityStore` writes `lume-device.json` next to the local database and
  keeps a stable ID for sync payloads.
- `SnapshotSyncMerger` treats tasks/notes as syncable records and leaves
  scheduled notification projections local to each device.
- `packages/lume_core` owns the syncable domain models and merge logic shared
  by the Flutter app and the optional Dart/Docker sync server.
- `HttpSyncAdapter` posts a syncable snapshot to `/sync`, receives the server
  snapshot, and merges it back into the local database. When a token is saved in
  the Sync view, the adapter sends it as `x-lume-sync-token`.
- The sync server can run as plain HTTP for trusted LAN testing or HTTPS when
  started with `--tls-cert` and `--tls-key`. Self-signed certificates must be
  trusted by Windows/Android before the app can use the HTTPS URL.
- Packaged Android/Windows release builds reject plain HTTP sync URLs. Use HTTP
  only while testing debug builds.
- In Docker, the server uses `/data/server-state.json` by default and keeps
  that state in the `curio-sync-data` volume. State writes use a temporary file
  plus a `.bak` copy so the server can recover from an interrupted JSON write.
- On Windows, the local server is a foreground, user-started helper. It binds
  `0.0.0.0:8787`, requires the same `x-lume-sync-token`, keeps scheduled
  notification projections local to each device, and stops with the app or the
  Sync view stop button.
- The local server does not replace the HTTPS requirement for packaged Android
  release sync. Use Docker or another HTTPS endpoint for regular Windows and
  Android release builds.
- Local state lives in `lume.sqlite` under the platform application support
  directory.
- Existing `lume-state.json` data is imported automatically on first launch when
  the SQLite database is still empty.

## Useful commands

From `apps/lume`:

```powershell
..\..\.tools\flutter\bin\dart.bat format lib test
..\..\.tools\flutter\bin\dart.bat run build_runner build
..\..\.tools\flutter\bin\flutter.bat analyze --no-pub
..\..\.tools\flutter\bin\flutter.bat test --no-pub
..\..\.tools\flutter\bin\flutter.bat build apk --debug --no-pub
..\..\.tools\flutter\bin\dart.bat run msix:create
```

Use the same token in the app's Sync view. Prefer `LUME_SYNC_TOKEN` so the
secret is not exposed in shell history or process listings. Keep the token long
and random; the app and server require at least 16 characters.
The standalone server refuses to start without a token unless
`--allow-empty-token` is used with a loopback-only host for local development.

To run the sync server directly without Docker:

```powershell
Push-Location server
$env:LUME_SYNC_TOKEN = "choose-a-long-token"
..\..\..\.tools\flutter\bin\dart.bat run bin\lume_sync_server.dart --host 0.0.0.0 --port 8787
Pop-Location
```

For HTTPS, pass PEM certificate and private key files:

```powershell
Push-Location server
$env:LUME_SYNC_TOKEN = "choose-a-long-token"
..\..\..\.tools\flutter\bin\dart.bat run bin\lume_sync_server.dart --host 0.0.0.0 --port 8787 --tls-cert ..\.lume-sync\cert.pem --tls-key ..\.lume-sync\key.pem
Pop-Location
```

Equivalent environment variables are `LUME_SYNC_TLS_CERT`,
`LUME_SYNC_TLS_KEY`, and `LUME_SYNC_TLS_KEY_PASSWORD`.

## Optional Docker sync server

The app does not need Docker. Docker is only for running the optional
self-hosted sync server as a separate component, especially when Android
release clients need a stable HTTPS endpoint.

From `apps/lume`:

```powershell
Copy-Item .env.example .env
# Edit .env and set a long private LUME_SYNC_TOKEN.
docker compose --env-file .env up -d --build
docker compose logs -f curio-sync
```

`Dockerfile.sync` builds the server from the pure Dart package under `server/`
using `dart:3.12.0`; it does not package the Flutter app into the container.
Override `DART_IMAGE` only if the replacement image includes Dart 3.12 or newer.

Use only the server origin in the app's Sync view. Do not include paths,
queries, fragments, usernames, or passwords:

```text
http://<windows-lan-ip>:8787
```

Use the same `LUME_SYNC_TOKEN` from `.env` in the token field. The server state
is persisted in the Docker volume named `curio-sync-data`. Native Windows and
Android clients do not need CORS, so the Docker server leaves it disabled unless
`LUME_SYNC_CORS_ORIGIN` is explicitly set to one exact `http://` or `https://`
origin. Wildcards, paths, query strings, fragments, and credentials are
rejected.

Useful Docker commands:

```powershell
docker compose ps
docker compose down
docker compose down --volumes
```

For HTTPS in Docker, place `cert.pem` and `key.pem` in `apps/lume/certs`, then
uncomment the `/certs` volume and `LUME_SYNC_TLS_*` lines in `compose.yaml`.

To generate a GitHub Release-ready self-hosted zip:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tool\sync\package-self-hosted-kit.ps1
```

## Public test downloads

Public test artifacts are attached to GitHub Releases. The intended files are:

- `curio-windows-portable-exe-*.exe` for a single-file Windows portable
  launcher.
- `curio-windows-portable-*.zip` for Windows testing without installing MSIX.
- `app-release.apk` for direct Android testing outside Play.
- `curio-sync-self-hosted-*.zip` for the optional Docker sync server kit.

The Play App Bundle (`app-release.aab`) is generated locally for store upload
and is not needed by regular testers.

To build the single-file portable Windows launcher from the latest portable zip:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tool\windows\package-portable-exe.ps1
```

## Store readiness

See `docs/store-readiness.md` for the release checklist. The short version:
release Android builds require `android/key.properties`, release sync uses
HTTPS, Android release bundling requires the SDK `cmdline-tools` component, and
the MSIX declares only the network capabilities needed for user-configured
cloud/LAN sync. Use `docs/privacy-policy.md` as the privacy policy and Data
Safety baseline before publishing. Use
`docs/store-submission-notes.md` and `docs/store-review-evidence.md` for
copy-ready Play/Microsoft review notes.

Run the local readiness gate at any point:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tool\verify-release-readiness.ps1
```

Before store submission, use strict mode so pending external steps fail the
gate too:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tool\verify-release-readiness.ps1 -Strict
```

To create a local Android upload key and ignored `android/key.properties`:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tool\android\create-release-keystore.ps1
```

Before generating the Play artifact, make sure Android Studio's SDK Manager has
installed `Android SDK Command-line Tools (latest)` and accepted Android
licenses. Build the Play artifact with the wrapper below; it captures the build
log, verifies the App Bundle signature, and writes a hash marker used by the
strict readiness gate:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tool\android\build-release-appbundle.ps1
```

The release App Bundle is written to:

```text
build\app\outputs\bundle\release\app-release.aab
```

The debug APK is written to:

```text
build\app\outputs\flutter-apk\app-debug.apk
```

Windows builds with native plugins require Windows Developer Mode because
Flutter creates plugin symlinks. After enabling it in Windows settings, run:

```powershell
..\..\.tools\flutter\bin\flutter.bat pub get
..\..\.tools\flutter\bin\flutter.bat build windows --debug
```

The Windows MSIX is written to:

```text
build\windows\x64\runner\Release\lume.msix
```

Create the MSIX with the project script so the package is repacked with
store-valid BadgeLogo assets and verified after signing:

```powershell
$env:LUME_MSIX_CERTIFICATE_THUMBPRINT = "<certificate-thumbprint>"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tool\windows\package-msix.ps1
```

For PFX-based local signing, set `LUME_MSIX_CERTIFICATE_PATH` and
`LUME_MSIX_CERTIFICATE_PASSWORD` instead. The bundled `msix` test certificate
can still be used for sideload testing, but the password is intentionally not
hardcoded in this repository.

Run Windows App Certification Kit through the project wrapper so the report
path and pass/fail summary stay consistent:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tool\windows\run-wack.ps1
```

If the current terminal is not elevated, launch the admin wrapper instead:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tool\windows\run-wack-admin.ps1
```

To summarize an existing report without launching WACK:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tool\windows\run-wack.ps1 -ReportOnly -ReportPath build\windows\wack-report-1.0.22.xml
```

For local sideload testing, the package is signed with the `msix` test
certificate. Trust the certificate once, then install the package:

```powershell
$pfx = "$env:LOCALAPPDATA\Pub\Cache\hosted\pub.dev\msix-3.16.13\lib\assets\test_certificate.pfx"
$password = Read-Host -AsSecureString "PFX password"
Import-PfxCertificate -FilePath $pfx -Password $password -CertStoreLocation Cert:\LocalMachine\Root
Add-AppxPackage -Path build\windows\x64\runner\Release\lume.msix -ForceApplicationShutdown
```

Increment `version` and `msix_config.msix_version` before reinstalling a changed
MSIX over an existing installation. Windows blocks same-version MSIX packages
when the contents differ.

## Next implementation slice

- Add a compact conflict review view for rare equal-timestamp edits.
- Add backup/export controls for the Docker sync volume.
- Add a task detail panel with note backlink navigation.
