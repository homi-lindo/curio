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

@DriftDatabase(
  tables: <Type>[
    TaskRows,
    NoteRows,
    ScheduledNotificationRows,
    DeletedRecordRows,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 5;

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
      },
    );
  }

  Future<bool> hasAnyUserData() async {
    final taskCount = await _count(taskRows);
    final noteCount = await _count(noteRows);
    final notificationCount = await _count(scheduledNotificationRows);
    final deletedCount = await _count(deletedRecordRows);
    return taskCount + noteCount + notificationCount + deletedCount > 0;
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

    return AppSnapshot(
      tasks: tasks.map(_taskFromRow).toList(),
      notes: notes.map(_noteFromRow).toList(),
      scheduledNotifications: notifications.map(_notificationFromRow).toList(),
      deletedRecords: deletedRecords.map(_deletedRecordFromRow).toList(),
    );
  }

  Future<void> replaceSnapshot(AppSnapshot snapshot) async {
    await transaction(() async {
      await delete(scheduledNotificationRows).go();
      await delete(deletedRecordRows).go();
      await delete(taskRows).go();
      await delete(noteRows).go();

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
          deletedRecordRows,
          snapshot.deletedRecords.map(_deletedRecordToCompanion).toList(),
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
