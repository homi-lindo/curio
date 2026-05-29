import 'package:flutter_test/flutter_test.dart';
import 'package:lume_core/domain/app_snapshot.dart';
import 'package:lume_core/domain/reminder.dart';
import 'package:lume_core/sync/sync_adapter.dart';

void main() {
  test(
    'offline sync adapter reports local record count without side effects',
    () async {
      final snapshot = AppSnapshot.seeded(DateTime.utc(2026, 5, 20, 15));

      final result = await const OfflineSyncAdapter().synchronize(
        snapshot: snapshot,
        deviceId: 'lume-test',
      );

      expect(result.pushedRecords, 0);
      expect(result.pulledRecords, 0);
      expect(result.tombstones, 0);
      expect(result.message, contains('1 registro(s)'));
    },
  );

  test('snapshot merger keeps tombstone over older task', () {
    final base = DateTime.utc(2026, 5, 20, 15);
    final task = TaskItem(
      id: 'task-1',
      title: 'Remota antiga',
      status: TaskStatus.open,
      createdAtUtc: base,
      updatedAtUtc: base,
    );
    final tombstone = DeletedRecord(
      recordType: SyncRecordType.task,
      recordId: task.id,
      deletedAtUtc: base.add(const Duration(minutes: 1)),
      deviceId: 'lume-windows',
    );

    final merged = const SnapshotSyncMerger().merge(
      local: AppSnapshot(
        tasks: const <TaskItem>[],
        notes: const <NoteItem>[],
        scheduledNotifications: const [],
        deletedRecords: <DeletedRecord>[tombstone],
      ),
      remote: AppSnapshot(
        tasks: <TaskItem>[task],
        notes: const <NoteItem>[],
        scheduledNotifications: const [],
      ),
    );

    expect(merged.tasks, isEmpty);
    expect(merged.deletedRecords.single.recordId, 'task-1');
  });

  test('snapshot merger keeps newer note over older tombstone', () {
    final base = DateTime.utc(2026, 5, 20, 15);
    final note = NoteItem(
      id: 'note-1',
      title: 'Nota editada',
      body: 'texto',
      createdAtUtc: base,
      updatedAtUtc: base.add(const Duration(minutes: 2)),
    );
    final tombstone = DeletedRecord(
      recordType: SyncRecordType.note,
      recordId: note.id,
      deletedAtUtc: base.add(const Duration(minutes: 1)),
      deviceId: 'lume-android',
    );

    final merged = const SnapshotSyncMerger().merge(
      local: AppSnapshot(
        tasks: const <TaskItem>[],
        notes: <NoteItem>[note],
        scheduledNotifications: const [],
      ),
      remote: AppSnapshot(
        tasks: const <TaskItem>[],
        notes: const <NoteItem>[],
        scheduledNotifications: const [],
        deletedRecords: <DeletedRecord>[tombstone],
      ),
    );

    expect(merged.notes.single.id, 'note-1');
    expect(merged.deletedRecords.single.recordId, 'note-1');
  });

  test(
    'offline sync keeps reminders intact (self-hosted server optional)',
    () async {
      final base = DateTime.utc(2026, 5, 20, 15);
      final reminder = ReminderIntent.oneShot(
        id: 'rem-1',
        ownerId: 'note-1',
        ownerType: ReminderOwnerType.note,
        instantUtc: base.add(const Duration(hours: 1)),
        updatedAtUtc: base,
        title: 'Lembrete local',
      );
      final snapshot = AppSnapshot(
        tasks: const <TaskItem>[],
        notes: const <NoteItem>[],
        scheduledNotifications: const [],
        reminders: <ReminderIntent>[reminder],
      );

      // The offline adapter (used when no server URL is set) must return the
      // snapshot untouched...
      final result = await const OfflineSyncAdapter().synchronize(
        snapshot: snapshot,
        deviceId: 'lume-standalone',
      );
      expect(result.snapshot.reminders.single.id, 'rem-1');

      // ...and the merge that `_runSync` performs offline (local against the
      // unchanged offline result) must be idempotent — reminders never dropped.
      final merged = const SnapshotSyncMerger().merge(
        local: snapshot,
        remote: result.snapshot,
      );
      expect(merged.reminders.single.id, 'rem-1');
      expect(merged.reminders.single.title, 'Lembrete local');
    },
  );

  test('snapshot merger pulls remote reminders and keeps the newest edit', () {
    final base = DateTime.utc(2026, 5, 20, 15);
    final localReminder = ReminderIntent.oneShot(
      id: 'rem-1',
      ownerId: 'note-1',
      ownerType: ReminderOwnerType.note,
      instantUtc: base.add(const Duration(hours: 1)),
      updatedAtUtc: base,
      title: 'Versão antiga',
    );
    final remoteReminder = ReminderIntent.oneShot(
      id: 'rem-1',
      ownerId: 'note-1',
      ownerType: ReminderOwnerType.note,
      instantUtc: base.add(const Duration(hours: 2)),
      updatedAtUtc: base.add(const Duration(minutes: 5)),
      title: 'Versão nova',
    );
    final remoteOnly = ReminderIntent.oneShot(
      id: 'rem-2',
      ownerId: 'note-2',
      ownerType: ReminderOwnerType.note,
      instantUtc: base.add(const Duration(hours: 3)),
      updatedAtUtc: base,
      title: 'Só no remoto',
    );

    final merged = const SnapshotSyncMerger().merge(
      local: AppSnapshot(
        tasks: const <TaskItem>[],
        notes: const <NoteItem>[],
        scheduledNotifications: const [],
        reminders: <ReminderIntent>[localReminder],
      ),
      remote: AppSnapshot(
        tasks: const <TaskItem>[],
        notes: const <NoteItem>[],
        scheduledNotifications: const [],
        reminders: <ReminderIntent>[remoteReminder, remoteOnly],
      ),
    );

    expect(merged.reminders.map((r) => r.id).toSet(), {'rem-1', 'rem-2'});
    expect(
      merged.reminders.firstWhere((r) => r.id == 'rem-1').title,
      'Versão nova',
    );
  });

  test('snapshot merger keeps reminder tombstone over older reminder', () {
    final base = DateTime.utc(2026, 5, 20, 15);
    final reminder = ReminderIntent.oneShot(
      id: 'rem-1',
      ownerId: 'note-1',
      ownerType: ReminderOwnerType.note,
      instantUtc: base.add(const Duration(hours: 1)),
      updatedAtUtc: base,
    );
    final tombstone = DeletedRecord(
      recordType: SyncRecordType.reminder,
      recordId: reminder.id,
      deletedAtUtc: base.add(const Duration(minutes: 1)),
      deviceId: 'lume-windows',
    );

    final merged = const SnapshotSyncMerger().merge(
      local: AppSnapshot(
        tasks: const <TaskItem>[],
        notes: const <NoteItem>[],
        scheduledNotifications: const [],
        deletedRecords: <DeletedRecord>[tombstone],
      ),
      remote: AppSnapshot(
        tasks: const <TaskItem>[],
        notes: const <NoteItem>[],
        scheduledNotifications: const [],
        reminders: <ReminderIntent>[reminder],
      ),
    );

    expect(merged.reminders, isEmpty);
    expect(merged.deletedRecords.single.recordId, 'rem-1');
  });

  test('backfill rebuilds reminders for pre-existing notifications', () {
    final now = DateTime.utc(2026, 5, 20, 15);
    final snapshot = AppSnapshot(
      tasks: const <TaskItem>[],
      notes: const <NoteItem>[],
      scheduledNotifications: <ScheduledNotificationRecord>[
        ScheduledNotificationRecord(
          id: 7,
          deviceId: 'lume-windows',
          reminderIntentId: 'legacy-rem',
          ownerId: 'note-1',
          ownerType: ReminderOwnerType.note,
          occurrenceKey: '2026-05-21T15:00:00.000Z',
          scheduledForUtc: now.add(const Duration(days: 1)),
          payload: 'curio://reminder/legacy-rem',
          title: 'Lembrete antigo',
          body: 'corpo',
          scheduledTimeZone: 'America/Sao_Paulo',
        ),
      ],
      // No reminders yet — exactly the state right after a v5→v6 upgrade.
    );

    final backfilled = backfillRemindersFromRecords(snapshot, nowUtc: now);

    // A matching reminder now exists, so the per-device reconcile won't treat
    // the notification as an orphan and cancel it.
    final reminder = backfilled.reminders.single;
    expect(reminder.id, 'legacy-rem');
    expect(reminder.title, 'Lembrete antigo');
    expect(reminder.timeZone, 'America/Sao_Paulo');
    expect(reminder.kind, ScheduleKind.oneShot);

    // Idempotent: a second pass adds nothing.
    expect(
      identical(
        backfillRemindersFromRecords(backfilled, nowUtc: now),
        backfilled,
      ),
      isTrue,
    );
  });

  test('compaction drops expired tombstones and long-fired reminders', () {
    final now = DateTime.utc(2026, 5, 20, 15);
    final snapshot = AppSnapshot(
      tasks: const <TaskItem>[],
      notes: const <NoteItem>[],
      scheduledNotifications: const [],
      reminders: <ReminderIntent>[
        // Fired long ago → dropped.
        ReminderIntent.oneShot(
          id: 'old-oneshot',
          ownerId: 'note-1',
          ownerType: ReminderOwnerType.note,
          instantUtc: now.subtract(const Duration(days: 60)),
          updatedAtUtc: now.subtract(const Duration(days: 60)),
        ),
        // Recent one-shot → kept.
        ReminderIntent.oneShot(
          id: 'recent-oneshot',
          ownerId: 'note-2',
          ownerType: ReminderOwnerType.note,
          instantUtc: now.add(const Duration(days: 1)),
          updatedAtUtc: now,
        ),
        // Recurring → always kept, even with an old anchor.
        ReminderIntent.daily(
          id: 'recurring',
          ownerId: 'note-3',
          ownerType: ReminderOwnerType.note,
          localTime: const LocalClockTime(hour: 8, minute: 0),
          timeZone: 'America/Sao_Paulo',
          updatedAtUtc: now.subtract(const Duration(days: 400)),
        ),
      ],
      deletedRecords: <DeletedRecord>[
        DeletedRecord(
          recordType: SyncRecordType.note,
          recordId: 'gone-old',
          deletedAtUtc: now.subtract(const Duration(days: 365)),
          deviceId: 'lume-a',
        ),
        DeletedRecord(
          recordType: SyncRecordType.note,
          recordId: 'gone-recent',
          deletedAtUtc: now.subtract(const Duration(days: 10)),
          deviceId: 'lume-a',
        ),
      ],
    );

    final compacted = compactSnapshot(snapshot, nowUtc: now);

    expect(compacted.reminders.map((r) => r.id).toSet(), {
      'recent-oneshot',
      'recurring',
    });
    expect(compacted.deletedRecords.map((d) => d.recordId).toSet(), {
      'gone-recent',
    });
  });

  test('compaction returns the same instance when nothing is expired', () {
    final now = DateTime.utc(2026, 5, 20, 15);
    final snapshot = AppSnapshot(
      tasks: const <TaskItem>[],
      notes: const <NoteItem>[],
      scheduledNotifications: const [],
      reminders: <ReminderIntent>[
        ReminderIntent.oneShot(
          id: 'rem-1',
          ownerId: 'note-1',
          ownerType: ReminderOwnerType.note,
          instantUtc: now.add(const Duration(hours: 1)),
          updatedAtUtc: now,
        ),
      ],
      deletedRecords: <DeletedRecord>[
        DeletedRecord(
          recordType: SyncRecordType.note,
          recordId: 'gone',
          deletedAtUtc: now.subtract(const Duration(days: 1)),
          deviceId: 'lume-a',
        ),
      ],
    );

    expect(identical(compactSnapshot(snapshot, nowUtc: now), snapshot), isTrue);
  });

  test('reminder intents round-trip through JSON for every schedule kind', () {
    final base = DateTime.utc(2026, 5, 20, 15);
    final intents = <ReminderIntent>[
      ReminderIntent.oneShot(
        id: 'one',
        ownerId: 'note-1',
        ownerType: ReminderOwnerType.note,
        instantUtc: base,
        updatedAtUtc: base,
        timeZone: 'America/Sao_Paulo',
        title: 'Único',
        body: 'corpo',
      ),
      ReminderIntent.daily(
        id: 'day',
        ownerId: 'note-2',
        ownerType: ReminderOwnerType.note,
        localTime: const LocalClockTime(hour: 8, minute: 30),
        timeZone: 'America/Sao_Paulo',
        updatedAtUtc: base,
        title: 'Diário',
      ),
      ReminderIntent.weekly(
        id: 'week',
        ownerId: 'note-3',
        ownerType: ReminderOwnerType.note,
        localTime: const LocalClockTime(hour: 9, minute: 0),
        timeZone: 'America/Sao_Paulo',
        anchorLocalDate: DateTime(2026, 5, 18),
        byWeekday: DateTime.monday,
        updatedAtUtc: base,
      ),
    ];

    for (final intent in intents) {
      final decoded = ReminderIntent.fromJson(intent.toJson());
      expect(decoded.id, intent.id);
      expect(decoded.kind, intent.kind);
      expect(decoded.timeZone, intent.timeZone);
      expect(decoded.instantUtc, intent.instantUtc);
      expect(decoded.localTime?.hour, intent.localTime?.hour);
      expect(decoded.localTime?.minute, intent.localTime?.minute);
      expect(decoded.byWeekday, intent.byWeekday);
      expect(decoded.anchorLocalDate, intent.anchorLocalDate);
      expect(decoded.title, intent.title);
      expect(decoded.body, intent.body);
    }
  });
}
