import '../domain/app_snapshot.dart';
import '../domain/reminder.dart';

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

/// Reconstructs a syncable reminder for every locally scheduled notification
/// that has no matching [ReminderIntent] yet. This backfills state created
/// before reminders were synced (so the per-device reconcile does not mistake
/// pre-existing notifications for orphans and cancel them on first launch after
/// an upgrade). Recurrence is not recoverable from a record, so backfilled
/// intents are one-shot at their stored occurrence — lossless for the reminders
/// the app creates, and harmless for the rest.
AppSnapshot backfillRemindersFromRecords(
  AppSnapshot snapshot, {
  required DateTime nowUtc,
}) {
  if (snapshot.scheduledNotifications.isEmpty) {
    return snapshot;
  }
  final knownIds = snapshot.reminders.map((reminder) => reminder.id).toSet();
  final additions = <ReminderIntent>[];
  for (final record in snapshot.scheduledNotifications) {
    if (!knownIds.add(record.reminderIntentId)) {
      continue;
    }
    additions.add(
      ReminderIntent.oneShot(
        id: record.reminderIntentId,
        ownerId: record.ownerId,
        ownerType: record.ownerType,
        instantUtc: record.scheduledForUtc,
        updatedAtUtc: nowUtc.toUtc(),
        timeZone: record.scheduledTimeZone.trim().isEmpty
            ? 'UTC'
            : record.scheduledTimeZone.trim(),
        title: record.title,
        body: record.body,
      ),
    );
  }
  if (additions.isEmpty) {
    return snapshot;
  }
  return snapshot.copyWith(
    reminders: <ReminderIntent>[...snapshot.reminders, ...additions],
  );
}

/// Default retention windows for [compactSnapshot].
///
/// Tombstones are kept long enough that a device offline for months still
/// receives the deletion before the tombstone is dropped (which would let it
/// resurrect the record). Fired one-shot reminders are dropped sooner since
/// they can never fire again.
const Duration kTombstoneRetention = Duration(days: 180);
const Duration kFiredReminderRetention = Duration(days: 30);

/// Bounds long-term growth of the synced snapshot without affecting active
/// data: drops tombstones older than [tombstoneRetention] and one-shot
/// reminders whose instant is more than [firedReminderRetention] in the past.
/// Recurring reminders and anything still recent are always kept.
AppSnapshot compactSnapshot(
  AppSnapshot snapshot, {
  required DateTime nowUtc,
  Duration tombstoneRetention = kTombstoneRetention,
  Duration firedReminderRetention = kFiredReminderRetention,
}) {
  final now = nowUtc.toUtc();
  final tombstoneCutoff = now.subtract(tombstoneRetention);
  final reminderCutoff = now.subtract(firedReminderRetention);

  final reminders = snapshot.reminders.where((reminder) {
    if (reminder.kind != ScheduleKind.oneShot) {
      return true;
    }
    final instant = reminder.instantUtc;
    if (instant == null) {
      return true;
    }
    return instant.toUtc().isAfter(reminderCutoff);
  }).toList();

  final deletedRecords = snapshot.deletedRecords
      .where((record) => record.deletedAtUtc.toUtc().isAfter(tombstoneCutoff))
      .toList();

  if (reminders.length == snapshot.reminders.length &&
      deletedRecords.length == snapshot.deletedRecords.length) {
    return snapshot;
  }
  return snapshot.copyWith(
    reminders: reminders,
    deletedRecords: deletedRecords,
  );
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
    final reminders = _mergeReminders(local.reminders, remote.reminders)
        .where(
          (reminder) => !_isDeleted(
            tombstonesByKey,
            SyncRecordType.reminder,
            reminder.id,
            reminder.updatedAtUtc,
          ),
        )
        .toList();

    return local.copyWith(
      tasks: tasks,
      notes: notes,
      reminders: reminders,
      deletedRecords: tombstones,
    );
  }

  List<ReminderIntent> _mergeReminders(
    List<ReminderIntent> local,
    List<ReminderIntent> remote,
  ) {
    final byId = <String, ReminderIntent>{};
    for (final reminder in local) {
      _putLatestReminder(byId, reminder);
    }
    for (final reminder in remote) {
      _putLatestReminder(byId, reminder);
    }
    return byId.values.toList()
      ..sort((a, b) => b.updatedAtUtc.compareTo(a.updatedAtUtc));
  }

  void _putLatestReminder(
    Map<String, ReminderIntent> byId,
    ReminderIntent reminder,
  ) {
    final existing = byId[reminder.id];
    if (existing == null ||
        reminder.updatedAtUtc.isAfter(existing.updatedAtUtc)) {
      byId[reminder.id] = reminder;
    }
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
