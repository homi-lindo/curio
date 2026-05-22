import 'package:flutter_test/flutter_test.dart';
import 'package:lume_core/domain/app_snapshot.dart';
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
}
