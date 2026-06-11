import 'package:flutter_test/flutter_test.dart';
import 'package:lume_core/domain/app_snapshot.dart';
import 'package:lume_core/domain/reminder.dart';
import 'package:lume_core/sync/snapshot_revision.dart';

void main() {
  final now = DateTime.utc(2026, 6, 11, 12);

  NoteItem note(String id) => NoteItem(
    id: id,
    title: 'Nota $id',
    body: 'corpo',
    createdAtUtc: now,
    // Timestamp idêntico de propósito: é o caso em que a ordem da lista
    // depende de qual aparelho processou primeiro.
    updatedAtUtc: now,
  );

  test('revision é a mesma independente da ordem das listas', () {
    final snapshotAB = AppSnapshot(
      tasks: const [],
      notes: [note('a'), note('b')],
      scheduledNotifications: const [],
      deletedRecords: const [],
    );
    final snapshotBA = AppSnapshot(
      tasks: const [],
      notes: [note('b'), note('a')],
      scheduledNotifications: const [],
      deletedRecords: const [],
    );

    expect(snapshotRevision(snapshotAB), snapshotRevision(snapshotBA));
  });

  test('revision muda quando o conteúdo muda', () {
    final base = AppSnapshot(
      tasks: const [],
      notes: [note('a')],
      scheduledNotifications: const [],
      deletedRecords: const [],
    );
    final edited = base.copyWith(
      notes: [note('a').copyWith(body: 'corpo editado', updatedAtUtc: now)],
    );

    expect(snapshotRevision(base), isNot(snapshotRevision(edited)));
  });

  test('notificações locais não afetam a revision', () {
    final base = AppSnapshot(
      tasks: const [],
      notes: [note('a')],
      scheduledNotifications: const [],
      deletedRecords: const [],
    );
    final withLocalRecords = base.copyWith(
      scheduledNotifications: [
        ScheduledNotificationRecord(
          id: 1,
          deviceId: 'device-x',
          reminderIntentId: 'reminder-1',
          ownerId: 'a',
          ownerType: ReminderOwnerType.note,
          occurrenceKey: '2026-06-12T09:00:00.000Z',
          scheduledForUtc: DateTime.utc(2026, 6, 12, 9),
          payload: 'lume://reminder/reminder-1',
          title: 't',
          body: '',
          scheduledTimeZone: 'UTC',
        ),
      ],
    );

    expect(snapshotRevision(base), snapshotRevision(withLocalRecords));
  });
}
