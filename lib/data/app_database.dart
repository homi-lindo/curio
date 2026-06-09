import 'package:drift/drift.dart';

import 'package:lume_core/domain/app_snapshot.dart';
import 'package:lume_core/domain/reminder.dart';

part 'app_database.g.dart';

class TaskRows extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get status => text()();
  DateTimeColumn get dueAtUtc => dateTime().nullable()();
  DateTimeColumn get completedAtUtc => dateTime().nullable()();
  BoolColumn get reminderEnabled =>
      boolean().withDefault(const Constant(false))();
  TextColumn get sourceNoteId => text().nullable()();
  DateTimeColumn get createdAtUtc => dateTime()();
  DateTimeColumn get updatedAtUtc => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

class NoteRows extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get body => text()();
  DateTimeColumn get createdAtUtc => dateTime()();
  DateTimeColumn get updatedAtUtc => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

class ScheduledNotificationRows extends Table {
  IntColumn get id => integer()();
  TextColumn get deviceId => text()();
  TextColumn get reminderIntentId => text()();
  TextColumn get ownerId => text()();
  TextColumn get ownerType => text()();
  TextColumn get occurrenceKey => text()();
  DateTimeColumn get scheduledForUtc => dateTime()();
  TextColumn get payload => text()();
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get body => text().withDefault(const Constant(''))();
  TextColumn get scheduledTimeZone => text().withDefault(const Constant(''))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

class DeletedRecordRows extends Table {
  TextColumn get recordType => text()();
  TextColumn get recordId => text()();
  DateTimeColumn get deletedAtUtc => dateTime()();
  TextColumn get deviceId => text()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{recordType, recordId};
}

class ReminderRows extends Table {
  TextColumn get id => text()();
  TextColumn get ownerId => text()();
  TextColumn get ownerType => text()();
  TextColumn get kind => text()();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  TextColumn get timeZone => text().withDefault(const Constant('UTC'))();
  DateTimeColumn get instantUtc => dateTime().nullable()();
  IntColumn get localTimeHour => integer().nullable()();
  IntColumn get localTimeMinute => integer().nullable()();
  DateTimeColumn get anchorLocalDate => dateTime().nullable()();
  IntColumn get byWeekday => integer().nullable()();
  DateTimeColumn get updatedAtUtc => dateTime()();
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get body => text().withDefault(const Constant(''))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

@DriftDatabase(
  tables: <Type>[
    TaskRows,
    NoteRows,
    ScheduledNotificationRows,
    DeletedRecordRows,
    ReminderRows,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (migrator) => migrator.createAll(),
      onUpgrade: (migrator, from, to) async {
        if (from < 2) {
          await migrator.addColumn(taskRows, taskRows.sourceNoteId);
        }
        if (from < 3) {
          await migrator.createTable(deletedRecordRows);
        }
        if (from < 4) {
          await migrator.addColumn(
            scheduledNotificationRows,
            scheduledNotificationRows.scheduledTimeZone,
          );
        }
        if (from < 5) {
          await migrator.addColumn(
            scheduledNotificationRows,
            scheduledNotificationRows.title,
          );
          await migrator.addColumn(
            scheduledNotificationRows,
            scheduledNotificationRows.body,
          );
        }
        if (from < 6) {
          await migrator.createTable(reminderRows);
        }
      },
    );
  }

  Future<bool> hasAnyUserData() async {
    final taskCount = await _count(taskRows);
    final noteCount = await _count(noteRows);
    final notificationCount = await _count(scheduledNotificationRows);
    final deletedCount = await _count(deletedRecordRows);
    final reminderCount = await _count(reminderRows);
    return taskCount +
            noteCount +
            notificationCount +
            deletedCount +
            reminderCount >
        0;
  }

  Future<AppSnapshot> loadSnapshot() async {
    final tasks =
        await (select(taskRows)
              ..orderBy(<OrderingTerm Function($TaskRowsTable)>[
                (table) => OrderingTerm.desc(table.updatedAtUtc),
              ]))
            .get();
    final notes =
        await (select(noteRows)
              ..orderBy(<OrderingTerm Function($NoteRowsTable)>[
                (table) => OrderingTerm.desc(table.updatedAtUtc),
              ]))
            .get();
    final notifications =
        await (select(scheduledNotificationRows)..orderBy(
              <OrderingTerm Function($ScheduledNotificationRowsTable)>[
                (table) => OrderingTerm.asc(table.scheduledForUtc),
              ],
            ))
            .get();
    final deletedRecords =
        await (select(deletedRecordRows)
              ..orderBy(<OrderingTerm Function($DeletedRecordRowsTable)>[
                (table) => OrderingTerm.desc(table.deletedAtUtc),
              ]))
            .get();
    final reminders =
        await (select(reminderRows)
              ..orderBy(<OrderingTerm Function($ReminderRowsTable)>[
                (table) => OrderingTerm.desc(table.updatedAtUtc),
              ]))
            .get();

    return AppSnapshot(
      tasks: tasks.map(_taskFromRow).toList(),
      notes: notes.map(_noteFromRow).toList(),
      scheduledNotifications: notifications.map(_notificationFromRow).toList(),
      reminders: reminders.map(_reminderFromRow).toList(),
      deletedRecords: deletedRecords.map(_deletedRecordFromRow).toList(),
    );
  }

  Future<void> replaceSnapshot(AppSnapshot snapshot) async {
    await transaction(() async {
      await delete(scheduledNotificationRows).go();
      await delete(deletedRecordRows).go();
      await delete(taskRows).go();
      await delete(noteRows).go();
      await delete(reminderRows).go();

      await batch((batch) {
        batch.insertAllOnConflictUpdate(
          taskRows,
          snapshot.tasks.map(_taskToCompanion).toList(),
        );
        batch.insertAllOnConflictUpdate(
          noteRows,
          snapshot.notes.map(_noteToCompanion).toList(),
        );
        batch.insertAllOnConflictUpdate(
          scheduledNotificationRows,
          snapshot.scheduledNotifications
              .map(_notificationToCompanion)
              .toList(),
        );
        batch.insertAllOnConflictUpdate(
          reminderRows,
          snapshot.reminders.map(_reminderToCompanion).toList(),
        );
        batch.insertAllOnConflictUpdate(
          deletedRecordRows,
          snapshot.deletedRecords.map(_deletedRecordToCompanion).toList(),
        );
      });
    });
  }

  /// Persiste apenas o que mudou entre [previous] e [next]: upsert de linhas
  /// novas/alteradas e delete das removidas, tudo em uma transação. Produz o
  /// mesmo estado final que [replaceSnapshot] quando [previous] reflete o
  /// banco atual — sem reescrever as tabelas inteiras a cada save.
  Future<void> applySnapshotDiff(AppSnapshot previous, AppSnapshot next) async {
    final taskDiff = _TableDiff.build(
      previous.tasks,
      next.tasks,
      (task) => task.id,
      (task) => task.toJson(),
    );
    final noteDiff = _TableDiff.build(
      previous.notes,
      next.notes,
      (note) => note.id,
      (note) => note.toJson(),
    );
    final notificationDiff = _TableDiff.build(
      previous.scheduledNotifications,
      next.scheduledNotifications,
      (record) => record.id.toString(),
      (record) => record.toJson(),
    );
    final reminderDiff = _TableDiff.build(
      previous.reminders,
      next.reminders,
      (reminder) => reminder.id,
      (reminder) => reminder.toJson(),
    );
    final deletedDiff = _TableDiff.build(
      previous.deletedRecords,
      next.deletedRecords,
      (record) => record.key,
      (record) => record.toJson(),
    );

    if (taskDiff.isEmpty &&
        noteDiff.isEmpty &&
        notificationDiff.isEmpty &&
        reminderDiff.isEmpty &&
        deletedDiff.isEmpty) {
      return;
    }

    await transaction(() async {
      if (taskDiff.removedKeys.isNotEmpty) {
        await (delete(
          taskRows,
        )..where((row) => row.id.isIn(taskDiff.removedKeys))).go();
      }
      if (noteDiff.removedKeys.isNotEmpty) {
        await (delete(
          noteRows,
        )..where((row) => row.id.isIn(noteDiff.removedKeys))).go();
      }
      if (notificationDiff.removedKeys.isNotEmpty) {
        final ids = notificationDiff.removedKeys.map(int.parse).toList();
        await (delete(
          scheduledNotificationRows,
        )..where((row) => row.id.isIn(ids))).go();
      }
      if (reminderDiff.removedKeys.isNotEmpty) {
        await (delete(
          reminderRows,
        )..where((row) => row.id.isIn(reminderDiff.removedKeys))).go();
      }
      for (final removed in deletedDiff.removedItems) {
        // PK composto (recordType, recordId); remoções de tombstone são raras
        // (compaction), então o loop não pesa.
        await (delete(deletedRecordRows)..where(
              (row) =>
                  row.recordType.equals(removed.recordType.name) &
                  row.recordId.equals(removed.recordId),
            ))
            .go();
      }

      await batch((batch) {
        batch.insertAllOnConflictUpdate(
          taskRows,
          taskDiff.upserts.map(_taskToCompanion).toList(),
        );
        batch.insertAllOnConflictUpdate(
          noteRows,
          noteDiff.upserts.map(_noteToCompanion).toList(),
        );
        batch.insertAllOnConflictUpdate(
          scheduledNotificationRows,
          notificationDiff.upserts.map(_notificationToCompanion).toList(),
        );
        batch.insertAllOnConflictUpdate(
          reminderRows,
          reminderDiff.upserts.map(_reminderToCompanion).toList(),
        );
        batch.insertAllOnConflictUpdate(
          deletedRecordRows,
          deletedDiff.upserts.map(_deletedRecordToCompanion).toList(),
        );
      });
    });
  }

  Future<int> _count(TableInfo<Table, Object?> table) async {
    final count = countAll();
    final query = selectOnly(table)..addColumns(<Expression<int>>[count]);
    return await query.map((row) => row.read(count) ?? 0).getSingle();
  }
}

/// Mudanças de uma tabela entre dois snapshots, calculadas por chave primária
/// e igualdade profunda do JSON do item (os modelos de domínio não definem
/// operator==).
final class _TableDiff<T> {
  const _TableDiff({
    required this.upserts,
    required this.removedKeys,
    required this.removedItems,
  });

  factory _TableDiff.build(
    List<T> previous,
    List<T> next,
    String Function(T) keyOf,
    Map<String, Object?> Function(T) jsonOf,
  ) {
    final previousByKey = <String, T>{
      for (final item in previous) keyOf(item): item,
    };
    final upserts = <T>[];
    final nextKeys = <String>{};
    for (final item in next) {
      final key = keyOf(item);
      nextKeys.add(key);
      final existing = previousByKey[key];
      if (existing == null || !_jsonEquals(jsonOf(existing), jsonOf(item))) {
        upserts.add(item);
      }
    }
    final removedItems = <T>[
      for (final entry in previousByKey.entries)
        if (!nextKeys.contains(entry.key)) entry.value,
    ];
    return _TableDiff(
      upserts: upserts,
      removedKeys: <String>[
        for (final entry in previousByKey.entries)
          if (!nextKeys.contains(entry.key)) entry.key,
      ],
      removedItems: removedItems,
    );
  }

  final List<T> upserts;
  final List<String> removedKeys;
  final List<T> removedItems;

  bool get isEmpty => upserts.isEmpty && removedKeys.isEmpty;
}

bool _jsonEquals(Object? a, Object? b) {
  if (identical(a, b)) {
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) {
      return false;
    }
    for (final key in a.keys) {
      if (!b.containsKey(key) || !_jsonEquals(a[key], b[key])) {
        return false;
      }
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) {
      return false;
    }
    for (var index = 0; index < a.length; index++) {
      if (!_jsonEquals(a[index], b[index])) {
        return false;
      }
    }
    return true;
  }
  return a == b;
}

TaskItem _taskFromRow(TaskRow row) {
  return TaskItem(
    id: row.id,
    title: row.title,
    description: row.description,
    status: TaskStatus.values.byName(row.status),
    dueAtUtc: row.dueAtUtc?.toUtc(),
    completedAtUtc: row.completedAtUtc?.toUtc(),
    reminderEnabled: row.reminderEnabled,
    sourceNoteId: row.sourceNoteId,
    createdAtUtc: row.createdAtUtc.toUtc(),
    updatedAtUtc: row.updatedAtUtc.toUtc(),
  );
}

TaskRowsCompanion _taskToCompanion(TaskItem task) {
  return TaskRowsCompanion.insert(
    id: task.id,
    title: task.title,
    description: Value(task.description),
    status: task.status.name,
    dueAtUtc: Value(task.dueAtUtc),
    completedAtUtc: Value(task.completedAtUtc),
    reminderEnabled: Value(task.reminderEnabled),
    sourceNoteId: Value(task.sourceNoteId),
    createdAtUtc: task.createdAtUtc,
    updatedAtUtc: task.updatedAtUtc,
  );
}

NoteItem _noteFromRow(NoteRow row) {
  return NoteItem(
    id: row.id,
    title: row.title,
    body: row.body,
    createdAtUtc: row.createdAtUtc.toUtc(),
    updatedAtUtc: row.updatedAtUtc.toUtc(),
  );
}

NoteRowsCompanion _noteToCompanion(NoteItem note) {
  return NoteRowsCompanion.insert(
    id: note.id,
    title: note.title,
    body: note.body,
    createdAtUtc: note.createdAtUtc,
    updatedAtUtc: note.updatedAtUtc,
  );
}

ScheduledNotificationRecord _notificationFromRow(ScheduledNotificationRow row) {
  return ScheduledNotificationRecord(
    id: row.id,
    deviceId: row.deviceId,
    reminderIntentId: row.reminderIntentId,
    ownerId: row.ownerId,
    ownerType: ReminderOwnerType.values.byName(row.ownerType),
    occurrenceKey: row.occurrenceKey,
    scheduledForUtc: row.scheduledForUtc.toUtc(),
    payload: row.payload,
    title: row.title,
    body: row.body,
    scheduledTimeZone: row.scheduledTimeZone,
  );
}

ScheduledNotificationRowsCompanion _notificationToCompanion(
  ScheduledNotificationRecord record,
) {
  return ScheduledNotificationRowsCompanion.insert(
    id: Value(record.id),
    deviceId: record.deviceId,
    reminderIntentId: record.reminderIntentId,
    ownerId: record.ownerId,
    ownerType: record.ownerType.name,
    occurrenceKey: record.occurrenceKey,
    scheduledForUtc: record.scheduledForUtc,
    payload: record.payload,
    title: Value(record.title),
    body: Value(record.body),
    scheduledTimeZone: Value(record.scheduledTimeZone),
  );
}

DeletedRecord _deletedRecordFromRow(DeletedRecordRow row) {
  return DeletedRecord(
    recordType: SyncRecordType.values.byName(row.recordType),
    recordId: row.recordId,
    deletedAtUtc: row.deletedAtUtc.toUtc(),
    deviceId: row.deviceId,
  );
}

DeletedRecordRowsCompanion _deletedRecordToCompanion(DeletedRecord record) {
  return DeletedRecordRowsCompanion.insert(
    recordType: record.recordType.name,
    recordId: record.recordId,
    deletedAtUtc: record.deletedAtUtc,
    deviceId: record.deviceId,
  );
}

ReminderIntent _reminderFromRow(ReminderRow row) {
  final hour = row.localTimeHour;
  final minute = row.localTimeMinute;
  return ReminderIntent(
    id: row.id,
    ownerId: row.ownerId,
    ownerType: ReminderOwnerType.values.byName(row.ownerType),
    kind: ScheduleKind.values.byName(row.kind),
    enabled: row.enabled,
    timeZone: row.timeZone,
    instantUtc: row.instantUtc?.toUtc(),
    localTime: (hour != null && minute != null)
        ? LocalClockTime(hour: hour, minute: minute)
        : null,
    anchorLocalDate: row.anchorLocalDate,
    byWeekday: row.byWeekday,
    updatedAtUtc: row.updatedAtUtc.toUtc(),
    title: row.title,
    body: row.body,
  );
}

ReminderRowsCompanion _reminderToCompanion(ReminderIntent reminder) {
  return ReminderRowsCompanion.insert(
    id: reminder.id,
    ownerId: reminder.ownerId,
    ownerType: reminder.ownerType.name,
    kind: reminder.kind.name,
    enabled: Value(reminder.enabled),
    timeZone: Value(reminder.timeZone),
    instantUtc: Value(reminder.instantUtc),
    localTimeHour: Value(reminder.localTime?.hour),
    localTimeMinute: Value(reminder.localTime?.minute),
    anchorLocalDate: Value(reminder.anchorLocalDate),
    byWeekday: Value(reminder.byWeekday),
    updatedAtUtc: reminder.updatedAtUtc,
    title: Value(reminder.title),
    body: Value(reminder.body),
  );
}
