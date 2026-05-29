import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lume/services/local_store.dart';
import 'package:lume_core/domain/app_snapshot.dart';
import 'package:lume_core/domain/reminder.dart';

void main() {
  test('local store round trips tasks and notes in sqlite', () async {
    final temp = await Directory.systemTemp.createTemp('lume_store_test_');

    final store = LocalStore(directoryProvider: () async => temp);
    addTearDown(() async {
      await store.close();
      await temp.delete(recursive: true);
    });
    final now = DateTime.utc(2026, 5, 20, 15);
    final snapshot = AppSnapshot.seeded(now).copyWith(
      tasks: <TaskItem>[
        TaskItem(
          id: 'task-custom',
          title: 'Persistir tarefa',
          status: TaskStatus.open,
          reminderEnabled: true,
          sourceNoteId: 'note-custom',
          createdAtUtc: now,
          updatedAtUtc: now,
        ),
      ],
      notes: <NoteItem>[
        NoteItem(
          id: 'note-custom',
          title: 'Persistir nota',
          body: 'corpo',
          createdAtUtc: now,
          updatedAtUtc: now,
        ),
      ],
      reminders: <ReminderIntent>[
        ReminderIntent.daily(
          id: 'rem-daily',
          ownerId: 'note-custom',
          ownerType: ReminderOwnerType.note,
          localTime: const LocalClockTime(hour: 7, minute: 45),
          timeZone: 'America/Sao_Paulo',
          updatedAtUtc: now,
          title: 'Tomar remédio',
          body: 'dose da manhã',
        ),
      ],
      deletedRecords: <DeletedRecord>[
        DeletedRecord(
          recordType: SyncRecordType.task,
          recordId: 'task-deleted',
          deletedAtUtc: now,
          deviceId: 'lume-test',
        ),
      ],
    );

    await store.save(snapshot);
    final loaded = await store.load();

    expect(loaded.tasks.single.title, 'Persistir tarefa');
    expect(loaded.tasks.single.reminderEnabled, isTrue);
    expect(loaded.tasks.single.sourceNoteId, 'note-custom');
    expect(loaded.notes.single.body, 'corpo');
    expect(loaded.deletedRecords.single.recordId, 'task-deleted');
    final reminder = loaded.reminders.single;
    expect(reminder.id, 'rem-daily');
    expect(reminder.kind, ScheduleKind.daily);
    expect(reminder.localTime?.hour, 7);
    expect(reminder.localTime?.minute, 45);
    expect(reminder.title, 'Tomar remédio');
    expect(reminder.timeZone, 'America/Sao_Paulo');
    expect(await store.file.then((file) => file.exists()), isTrue);
  });

  test('scheduled notification records keep owner contract', () {
    final record = ScheduledNotificationRecord(
      id: 123,
      deviceId: 'lume-windows',
      reminderIntentId: 'task-task-1-due',
      ownerId: 'task-1',
      ownerType: ReminderOwnerType.task,
      occurrenceKey: '2026-05-20T15:00:00.000Z',
      scheduledForUtc: DateTime.utc(2026, 5, 20, 15),
      payload: 'lume://reminder/task-task-1-due?owner=task-1',
      title: 'Título editável',
      body: 'Mensagem editável',
      scheduledTimeZone: 'America/Sao_Paulo',
    );

    final loaded = ScheduledNotificationRecord.fromJson(record.toJson());

    expect(loaded.ownerId, 'task-1');
    expect(loaded.ownerType, ReminderOwnerType.task);
    expect(loaded.title, 'Título editável');
    expect(loaded.body, 'Mensagem editável');
    expect(loaded.scheduledTimeZone, 'America/Sao_Paulo');
  });

  test(
    'scheduled notification records read older json without owner fields',
    () {
      final loaded = ScheduledNotificationRecord.fromJson(<String, Object?>{
        'id': 123,
        'deviceId': 'lume-windows',
        'reminderIntentId': 'legacy-reminder',
        'occurrenceKey': '2026-05-20T15:00:00.000Z',
        'scheduledForUtc': '2026-05-20T15:00:00.000Z',
        'payload': 'lume://reminder/legacy-reminder',
      });

      expect(loaded.ownerId, 'legacy-reminder');
      expect(loaded.ownerType, ReminderOwnerType.task);
      expect(loaded.scheduledTimeZone, isEmpty);
    },
  );

  test(
    'invalid legacy json is archived and does not block sqlite startup',
    () async {
      final temp = await Directory.systemTemp.createTemp('lume_store_invalid_');

      final store = LocalStore(directoryProvider: () async => temp);
      addTearDown(() async {
        await store.close();
        await temp.delete(recursive: true);
      });
      final legacy = await store.legacyJsonFile;
      await legacy.writeAsString('{');

      final loaded = await store.load();
      final archived = temp.listSync().where(
        (entity) => entity.path.contains('lume-state.json.invalid-'),
      );

      expect(loaded.notes, isNotEmpty);
      expect(await store.file.then((file) => file.exists()), isTrue);
      expect(archived, isNotEmpty);
    },
  );
}
