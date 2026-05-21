import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lume_core/domain/app_snapshot.dart';
import 'package:lume_core/domain/reminder.dart';
import 'package:lume_sync_server/snapshot_store.dart';

void main() {
  test(
    'server snapshot store recovers from backup when main file is corrupt',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'lume_server_snapshot_',
      );
      addTearDown(() async {
        if (await temp.exists()) {
          await temp.delete(recursive: true);
        }
      });

      final stateFile = File('${temp.path}/server-state.json');
      final backupFile = File('${stateFile.path}.bak');
      await stateFile.writeAsString('{broken-json', flush: true);
      await backupFile.writeAsString(
        jsonEncode(_snapshotWithNote('note-backup').toJson()),
        flush: true,
      );

      final store = ServerSnapshotStore(stateFile);

      final loaded = await store.load();
      expect(loaded.notes.single.id, 'note-backup');

      await store.save(_snapshotWithNote('note-new'));

      final saved = AppSnapshot.fromJson(
        Map<String, Object?>.from(
          jsonDecode(await stateFile.readAsString()) as Map<dynamic, dynamic>,
        ),
      );
      final backup = AppSnapshot.fromJson(
        Map<String, Object?>.from(
          jsonDecode(await backupFile.readAsString()) as Map<dynamic, dynamic>,
        ),
      );

      expect(saved.notes.single.id, 'note-new');
      expect(backup.notes.single.id, 'note-backup');
    },
  );

  test('server snapshot store does not persist local notifications', () async {
    final temp = await Directory.systemTemp.createTemp('lume_server_snapshot_');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    final stateFile = File('${temp.path}/server-state.json');
    final store = ServerSnapshotStore(stateFile);

    await store.save(
      AppSnapshot(
        tasks: const <TaskItem>[],
        notes: <NoteItem>[_note('note-local')],
        scheduledNotifications: <ScheduledNotificationRecord>[
          ScheduledNotificationRecord(
            id: 1,
            deviceId: 'windows-local',
            reminderIntentId: 'reminder-1',
            ownerId: 'note-local',
            ownerType: ReminderOwnerType.note,
            occurrenceKey: '2026-05-21T15:00:00Z',
            scheduledForUtc: DateTime.utc(2026, 5, 21, 15),
            payload: 'local-only',
          ),
        ],
      ),
    );

    final raw =
        jsonDecode(await stateFile.readAsString()) as Map<String, Object?>;

    expect(raw['scheduledNotifications'], isEmpty);
  });
}

AppSnapshot _snapshotWithNote(String id) {
  return AppSnapshot(
    tasks: const <TaskItem>[],
    notes: <NoteItem>[_note(id)],
    scheduledNotifications: const <ScheduledNotificationRecord>[],
  );
}

NoteItem _note(String id) {
  final now = DateTime.utc(2026, 5, 21, 15);
  return NoteItem(
    id: id,
    title: id,
    body: 'body',
    createdAtUtc: now,
    updatedAtUtc: now,
  );
}
