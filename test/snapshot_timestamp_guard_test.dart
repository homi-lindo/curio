import 'package:flutter_test/flutter_test.dart';
import 'package:lume_core/domain/app_snapshot.dart';
import 'package:lume_core/domain/reminder.dart';
import 'package:lume_core/sync/snapshot_timestamp_guard.dart';

void main() {
  final nowUtc = DateTime.utc(2026, 6, 9, 12);

  NoteItem note(DateTime updatedAtUtc) {
    return NoteItem(
      id: 'note-1',
      title: 'Nota',
      body: '',
      createdAtUtc: nowUtc,
      updatedAtUtc: updatedAtUtc,
    );
  }

  AppSnapshot snapshotWith({
    List<NoteItem> notes = const [],
    List<DeletedRecord> deleted = const [],
    List<ReminderIntent> reminders = const [],
  }) {
    return AppSnapshot(
      tasks: const [],
      notes: notes,
      scheduledNotifications: const [],
      reminders: reminders,
      deletedRecords: deleted,
    );
  }

  test('aceita timestamps dentro da tolerância', () {
    const guard = SnapshotTimestampGuard();
    final issues = guard.findFutureTimestamps(
      snapshotWith(notes: [note(nowUtc.add(const Duration(hours: 23)))]),
      nowUtc: nowUtc,
    );
    expect(issues, isEmpty);
  });

  test('detecta nota com updatedAtUtc impossível', () {
    const guard = SnapshotTimestampGuard();
    final issues = guard.findFutureTimestamps(
      snapshotWith(notes: [note(nowUtc.add(const Duration(days: 30)))]),
      nowUtc: nowUtc,
    );
    expect(issues, hasLength(1));
    expect(issues.single, contains('nota'));
    expect(issues.single, contains('2026-07-09'));
  });

  test('detecta tombstone e lembrete no futuro', () {
    const guard = SnapshotTimestampGuard();
    final issues = guard.findFutureTimestamps(
      snapshotWith(
        deleted: [
          DeletedRecord(
            recordType: SyncRecordType.note,
            recordId: 'note-x',
            deletedAtUtc: nowUtc.add(const Duration(days: 400)),
            deviceId: 'device-a',
          ),
        ],
        reminders: [
          ReminderIntent.oneShot(
            id: 'reminder-1',
            ownerId: 'note-1',
            ownerType: ReminderOwnerType.note,
            instantUtc: nowUtc,
            updatedAtUtc: nowUtc.add(const Duration(days: 2)),
            timeZone: 'UTC',
          ),
        ],
      ),
      nowUtc: nowUtc,
    );
    expect(issues, hasLength(2));
  });

  test('check lança ClockSkewDetectedException com mensagem acionável', () {
    const guard = SnapshotTimestampGuard();
    expect(
      () => guard.check(
        snapshotWith(notes: [note(nowUtc.add(const Duration(days: 30)))]),
        nowUtc: nowUtc,
      ),
      throwsA(
        isA<ClockSkewDetectedException>().having(
          (error) => error.message,
          'message',
          allOf(contains('relógio'), contains('24h')),
        ),
      ),
    );
  });

  test('instantUtc futuro de lembrete one-shot é legítimo (não flagra)', () {
    const guard = SnapshotTimestampGuard();
    final issues = guard.findFutureTimestamps(
      snapshotWith(
        reminders: [
          ReminderIntent.oneShot(
            id: 'reminder-futuro',
            ownerId: 'note-1',
            ownerType: ReminderOwnerType.note,
            // Agendado para daqui a um ano — válido; o que não pode é o
            // updatedAtUtc estar no futuro.
            instantUtc: nowUtc.add(const Duration(days: 365)),
            updatedAtUtc: nowUtc,
            timeZone: 'UTC',
          ),
        ],
      ),
      nowUtc: nowUtc,
    );
    expect(issues, isEmpty);
  });
}
