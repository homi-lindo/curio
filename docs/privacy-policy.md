# Curió Privacy Policy Draft

Last updated: 2026-05-20

Curió is a local-first personal agenda and notes app. It is designed for
personal use and does not include advertising, analytics, tracking SDKs, or a
developer-operated cloud service.

## Data Stored On Device

Curió stores agenda items, tasks, notes, reminder settings, sync settings, and
local app metadata on the user's device. This data stays local unless the user
enables sync.

Android system backup and automatic device-transfer extraction are disabled for
Curió, so local notes, tasks, and sync settings are not intentionally copied into
OS backup or migration flows by the app.

## Optional Sync

If sync is enabled, Curió sends tasks, notes, reminders (their title, message,
time and recurrence), tombstones, and sync metadata to the server URL configured
by the user. The optional sync server can be self-hosted with Docker, started as
an in-app Windows local server, or replaced by another user-controlled endpoint
that implements the same API.

Release builds require HTTPS for sync URLs. Debug builds may use plain HTTP for
local LAN and Docker testing. The Windows local server is started by the user, uses
the same sync token, and is intended for trusted personal local-network setups.
For self-hosted HTTPS, the app can pin the server's self-signed certificate by
fingerprint; the pinned fingerprint is public information stored locally and is
not transmitted to any third party.

## Credentials

The sync token is stored locally with platform-provided protection
(Android Keystore-backed encryption on Android and user-scoped DPAPI on
Windows) and is sent only to the configured sync server as the
`x-lume-sync-token` header.

The in-app activity log avoids storing task titles, note titles, note bodies,
local file paths, raw notification payloads, and sync token values.

## Notifications

Curió uses local notification permissions to show task and agenda reminders.
Notifications are scheduled on the device. Curió does not send notification
content to a third-party notification service.

## Data Sharing

Curió does not sell user data and does not share user data with advertising,
analytics, or marketing services.

## Data Deletion

Users can delete tasks and notes inside the app. If sync is enabled, deletion
markers may be sent to the configured sync server so other devices can remove
the same records. Data stored on a self-hosted server must be deleted from that
server or its Docker volume by the server operator.

## Store Disclosure Notes

For Google Play Data safety and Microsoft Store privacy fields, disclose that:

- The app stores user-provided notes, tasks, and calendar/reminder content.
- The app transmits that content only when the user configures sync.
- Sync traffic goes to a user-configured server, not to a developer-operated
  analytics or advertising service.
- The app uses notification and exact alarm permissions for user-visible
  reminders.
