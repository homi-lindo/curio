import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lume/sync/http_sync_adapter.dart';
import 'package:lume_core/domain/app_snapshot.dart';
import 'package:lume_core/domain/reminder.dart';
import 'package:lume_core/sync/sync_adapter.dart';
import 'package:lume_sync_server/snapshot_store.dart';

/// End-to-end reminder sync across two "devices" through a real HTTP server.
///
/// The in-process server mirrors `lume_sync_server`'s `/sync` handler exactly:
/// merge the incoming snapshot into the stored one with the shared
/// [SnapshotSyncMerger], persist via the real [ServerSnapshotStore], and return
/// the merged state (with device-local notifications stripped). This exercises
/// the real client adapter, the real merge, and the real server store together.
void main() {
  late HttpServer server;
  late ServerSnapshotStore store;
  late Directory temp;
  late String baseUrl;

  const token = 'shared-secret-012345';

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('lume_e2e_sync_');
    store = ServerSnapshotStore(File('${temp.path}/server-state.json'));
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUrl = 'http://127.0.0.1:${server.port}';

    unawaited(() async {
      await for (final request in server) {
        try {
          final raw = await utf8.decodeStream(request);
          final payload = jsonDecode(raw) as Map<String, Object?>;
          final incoming = AppSnapshot.fromJson(
            Map<String, Object?>.from(payload['snapshot']! as Map),
          );
          final current = await store.load();
          final next = const SnapshotSyncMerger().merge(
            local: current,
            remote: syncableServerSnapshot(incoming),
          );
          await store.save(next);
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode(<String, Object?>{
              'snapshot': syncableServerSnapshot(next).toJson(),
            }),
          );
          await request.response.close();
        } on Object {
          request.response.statusCode = HttpStatus.badRequest;
          await request.response.close();
        }
      }
    }());
  });

  tearDown(() async {
    await server.close(force: true);
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  // Simulates one device's sync round-trip: push local state, then merge the
  // server response back into local — exactly what `_runSync` does in the app.
  Future<AppSnapshot> deviceSync(AppSnapshot local, String deviceId) async {
    final adapter = HttpSyncAdapter(
      serverUrl: Uri.parse(baseUrl),
      authToken: token,
      allowInsecureHttp: true,
    );
    try {
      final result = await adapter.synchronize(
        snapshot: local,
        deviceId: deviceId,
      );
      return const SnapshotSyncMerger().merge(
        local: local,
        remote: result.snapshot,
      );
    } finally {
      adapter.dispose();
    }
  }

  AppSnapshot emptySnapshot() {
    return const AppSnapshot(
      tasks: <TaskItem>[],
      notes: <NoteItem>[],
      scheduledNotifications: <ScheduledNotificationRecord>[],
    );
  }

  ReminderIntent reminder({
    required String id,
    required DateTime updatedAtUtc,
    String title = 'Pagar conta',
  }) {
    return ReminderIntent.oneShot(
      id: id,
      ownerId: 'note-1',
      ownerType: ReminderOwnerType.note,
      instantUtc: DateTime.utc(2026, 5, 22, 14),
      updatedAtUtc: updatedAtUtc,
      title: title,
    );
  }

  test(
    'reminder created on device A reaches device B through the server',
    () async {
      final base = DateTime.utc(2026, 5, 22, 12);

      final deviceA = emptySnapshot().copyWith(
        reminders: <ReminderIntent>[reminder(id: 'rem-1', updatedAtUtc: base)],
      );
      final aAfterSync = await deviceSync(deviceA, 'device-a');
      expect(aAfterSync.reminders.single.id, 'rem-1');

      // Device B starts empty and pulls A's reminder on its first sync.
      final bAfterSync = await deviceSync(emptySnapshot(), 'device-b');
      expect(bAfterSync.reminders.single.id, 'rem-1');
      expect(bAfterSync.reminders.single.title, 'Pagar conta');
    },
  );

  test(
    'newer edit on device B wins over the older copy on the server',
    () async {
      final base = DateTime.utc(2026, 5, 22, 12);

      await deviceSync(
        emptySnapshot().copyWith(
          reminders: <ReminderIntent>[
            reminder(id: 'rem-1', updatedAtUtc: base, title: 'Versão A'),
          ],
        ),
        'device-a',
      );

      // Device B edits the same reminder later and syncs.
      final bEdited = emptySnapshot().copyWith(
        reminders: <ReminderIntent>[
          reminder(
            id: 'rem-1',
            updatedAtUtc: base.add(const Duration(minutes: 10)),
            title: 'Versão B',
          ),
        ],
      );
      final bAfterSync = await deviceSync(bEdited, 'device-b');
      expect(bAfterSync.reminders.single.title, 'Versão B');

      // Device A pulls the newer edit.
      final aAfterSync = await deviceSync(
        emptySnapshot().copyWith(
          reminders: <ReminderIntent>[
            reminder(id: 'rem-1', updatedAtUtc: base, title: 'Versão A'),
          ],
        ),
        'device-a',
      );
      expect(aAfterSync.reminders.single.title, 'Versão B');
    },
  );

  test(
    'reminder deleted on device A is removed on device B (tombstone wins)',
    () async {
      final base = DateTime.utc(2026, 5, 22, 12);

      // A creates and syncs; B pulls it.
      await deviceSync(
        emptySnapshot().copyWith(
          reminders: <ReminderIntent>[
            reminder(id: 'rem-1', updatedAtUtc: base),
          ],
        ),
        'device-a',
      );
      var deviceB = await deviceSync(emptySnapshot(), 'device-b');
      expect(deviceB.reminders.single.id, 'rem-1');

      // A deletes the reminder (tombstone) and syncs.
      final deletedA = emptySnapshot().copyWith(
        deletedRecords: <DeletedRecord>[
          DeletedRecord(
            recordType: SyncRecordType.reminder,
            recordId: 'rem-1',
            deletedAtUtc: base.add(const Duration(minutes: 30)),
            deviceId: 'device-a',
          ),
        ],
      );
      final aAfterDelete = await deviceSync(deletedA, 'device-a');
      expect(aAfterDelete.reminders, isEmpty);

      // B still holds the reminder locally; after syncing, the tombstone wins and
      // the reminder is not resurrected.
      deviceB = await deviceSync(deviceB, 'device-b');
      expect(deviceB.reminders, isEmpty);
      expect(
        deviceB.deletedRecords.any((record) => record.recordId == 'rem-1'),
        isTrue,
      );
    },
  );
}
