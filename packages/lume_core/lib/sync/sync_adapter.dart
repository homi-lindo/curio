import '../domain/app_snapshot.dart';

abstract interface class SyncAdapter {
  Future<SyncResult> synchronize({
    required AppSnapshot snapshot,
    required String deviceId,
  });
}

final class SyncResult {
  const SyncResult({
    required this.startedAtUtc,
    required this.finishedAtUtc,
    required this.snapshot,
    required this.pushedRecords,
    required this.pulledRecords,
    required this.tombstones,
    required this.message,
  });

  final DateTime startedAtUtc;
  final DateTime finishedAtUtc;
  final AppSnapshot snapshot;
  final int pushedRecords;
  final int pulledRecords;
  final int tombstones;
  final String message;
}

final class OfflineSyncAdapter implements SyncAdapter {
  const OfflineSyncAdapter();

  @override
  Future<SyncResult> synchronize({
    required AppSnapshot snapshot,
    required String deviceId,
  }) async {
    final now = DateTime.now().toUtc();
    final recordCount = snapshot.notes.length;
    final tombstones = snapshot.deletedRecords.length;

    return SyncResult(
      startedAtUtc: now,
      finishedAtUtc: now,
      snapshot: snapshot,
      pushedRecords: 0,
      pulledRecords: 0,
      tombstones: tombstones,
      message:
          'offline: $recordCount registro(s) e $tombstones exclusão(ões) preservados',
    );
  }
}

final class SnapshotSyncMerger {
  const SnapshotSyncMerger();

  AppSnapshot merge({required AppSnapshot local, required AppSnapshot remote}) {
    final tombstones = _mergeDeletedRecords(
      local.deletedRecords,
      remote.deletedRecords,
    );
    final tombstonesByKey = <String, DeletedRecord>{
      for (final record in tombstones) record.key: record,
    };

    final tasks = _mergeTasks(local.tasks, remote.tasks)
        .where(
          (task) => !_isDeleted(
            tombstonesByKey,
            SyncRecordType.task,
            task.id,
            task.updatedAtUtc,
          ),
        )
        .toList();
    final notes = _mergeNotes(local.notes, remote.notes)
        .where(
          (note) => !_isDeleted(
            tombstonesByKey,
            SyncRecordType.note,
            note.id,
            note.updatedAtUtc,
          ),
        )
        .toList();

    return local.copyWith(
      tasks: tasks,
      notes: notes,
      deletedRecords: tombstones,
    );
  }

  List<DeletedRecord> _mergeDeletedRecords(
    List<DeletedRecord> local,
    List<DeletedRecord> remote,
  ) {
    final byKey = <String, DeletedRecord>{};
    for (final record in local) {
      _putLatestDeletedRecord(byKey, record);
    }
    for (final record in remote) {
      _putLatestDeletedRecord(byKey, record);
    }
    return byKey.values.toList()
      ..sort((a, b) => b.deletedAtUtc.compareTo(a.deletedAtUtc));
  }

  void _putLatestDeletedRecord(
    Map<String, DeletedRecord> byKey,
    DeletedRecord record,
  ) {
    final existing = byKey[record.key];
    if (existing == null ||
        record.deletedAtUtc.isAfter(existing.deletedAtUtc)) {
      byKey[record.key] = record;
    }
  }

  List<TaskItem> _mergeTasks(List<TaskItem> local, List<TaskItem> remote) {
    final byId = <String, TaskItem>{};
    for (final task in local) {
      _putLatestTask(byId, task);
    }
    for (final task in remote) {
      _putLatestTask(byId, task);
    }
    return byId.values.toList()
      ..sort((a, b) => b.updatedAtUtc.compareTo(a.updatedAtUtc));
  }

  void _putLatestTask(Map<String, TaskItem> byId, TaskItem task) {
    final existing = byId[task.id];
    if (existing == null || task.updatedAtUtc.isAfter(existing.updatedAtUtc)) {
      byId[task.id] = task;
    }
  }

  List<NoteItem> _mergeNotes(List<NoteItem> local, List<NoteItem> remote) {
    final byId = <String, NoteItem>{};
    for (final note in local) {
      _putLatestNote(byId, note);
    }
    for (final note in remote) {
      _putLatestNote(byId, note);
    }
    return byId.values.toList()
      ..sort((a, b) => b.updatedAtUtc.compareTo(a.updatedAtUtc));
  }

  void _putLatestNote(Map<String, NoteItem> byId, NoteItem note) {
    final existing = byId[note.id];
    if (existing == null || note.updatedAtUtc.isAfter(existing.updatedAtUtc)) {
      byId[note.id] = note;
    }
  }

  bool _isDeleted(
    Map<String, DeletedRecord> tombstonesByKey,
    SyncRecordType type,
    String recordId,
    DateTime updatedAtUtc,
  ) {
    final record = tombstonesByKey['${type.name}:$recordId'];
    return record != null && !updatedAtUtc.isAfter(record.deletedAtUtc);
  }
}
