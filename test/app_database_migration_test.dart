import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/data/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// Recria o schema exatamente como era em [version], espelhando a história
/// real das migrações (v1 base; v2 +source_note_id; v3 +deleted_record_rows;
/// v4 +scheduled_time_zone; v5 +title/body), e semeia uma linha por tabela.
void _buildLegacySchema(sqlite3.Database database, int version) {
  database.execute('''
    CREATE TABLE task_rows (
      id TEXT NOT NULL PRIMARY KEY,
      title TEXT NOT NULL,
      description TEXT NOT NULL DEFAULT '',
      status TEXT NOT NULL,
      due_at_utc INTEGER NULL,
      completed_at_utc INTEGER NULL,
      reminder_enabled INTEGER NOT NULL DEFAULT 0
        CHECK ("reminder_enabled" IN (0, 1)),
      created_at_utc INTEGER NOT NULL,
      updated_at_utc INTEGER NOT NULL
    );
  ''');
  database.execute('''
    CREATE TABLE note_rows (
      id TEXT NOT NULL PRIMARY KEY,
      title TEXT NOT NULL,
      body TEXT NOT NULL,
      created_at_utc INTEGER NOT NULL,
      updated_at_utc INTEGER NOT NULL
    );
  ''');
  database.execute('''
    CREATE TABLE scheduled_notification_rows (
      id INTEGER NOT NULL PRIMARY KEY,
      device_id TEXT NOT NULL,
      reminder_intent_id TEXT NOT NULL,
      owner_id TEXT NOT NULL,
      owner_type TEXT NOT NULL,
      occurrence_key TEXT NOT NULL,
      scheduled_for_utc INTEGER NOT NULL,
      payload TEXT NOT NULL
    );
  ''');

  if (version >= 2) {
    database.execute(
      'ALTER TABLE task_rows ADD COLUMN source_note_id TEXT NULL;',
    );
  }
  if (version >= 3) {
    database.execute('''
      CREATE TABLE deleted_record_rows (
        record_type TEXT NOT NULL,
        record_id TEXT NOT NULL,
        deleted_at_utc INTEGER NOT NULL,
        device_id TEXT NOT NULL,
        PRIMARY KEY (record_type, record_id)
      );
    ''');
  }
  if (version >= 4) {
    database.execute(
      "ALTER TABLE scheduled_notification_rows "
      "ADD COLUMN scheduled_time_zone TEXT NOT NULL DEFAULT '';",
    );
  }
  if (version >= 5) {
    database.execute(
      "ALTER TABLE scheduled_notification_rows "
      "ADD COLUMN title TEXT NOT NULL DEFAULT '';",
    );
    database.execute(
      "ALTER TABLE scheduled_notification_rows "
      "ADD COLUMN body TEXT NOT NULL DEFAULT '';",
    );
  }

  database.execute(
    "INSERT INTO task_rows (id, title, status, created_at_utc, updated_at_utc) "
    "VALUES ('task-legada', 'Tarefa antiga', 'open', 1000, 1000);",
  );
  database.execute(
    "INSERT INTO note_rows (id, title, body, created_at_utc, updated_at_utc) "
    "VALUES ('note-legada', 'Nota antiga', 'corpo preservado', 1000, 1000);",
  );
  database.execute(
    "INSERT INTO scheduled_notification_rows "
    "(id, device_id, reminder_intent_id, owner_id, owner_type, "
    "occurrence_key, scheduled_for_utc, payload) "
    "VALUES (77, 'device-legado', 'reminder-legado', 'note-legada', 'note', "
    "'2026-01-01T10:00:00.000Z', 2000, 'lume://reminder/reminder-legado');",
  );
  if (version >= 3) {
    database.execute(
      "INSERT INTO deleted_record_rows "
      "(record_type, record_id, deleted_at_utc, device_id) "
      "VALUES ('note', 'note-apagada', 500, 'device-legado');",
    );
  }

  database.execute('PRAGMA user_version = $version;');
}

void main() {
  test(
    'database migration v1 to v5 adds sync and notification columns',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'lume_migration_test_',
      );
      final file = File('${temp.path}${Platform.pathSeparator}lume.sqlite');

      final legacy = AppDatabase(
        NativeDatabase(
          file,
          enableMigrations: false,
          setup: (database) {
            database.execute('''
            CREATE TABLE task_rows (
              id TEXT NOT NULL PRIMARY KEY,
              title TEXT NOT NULL,
              description TEXT NOT NULL DEFAULT '',
              status TEXT NOT NULL,
              due_at_utc INTEGER NULL,
              completed_at_utc INTEGER NULL,
              reminder_enabled INTEGER NOT NULL DEFAULT 0
                CHECK ("reminder_enabled" IN (0, 1)),
              created_at_utc INTEGER NOT NULL,
              updated_at_utc INTEGER NOT NULL
            );
          ''');
            database.execute('''
            CREATE TABLE note_rows (
              id TEXT NOT NULL PRIMARY KEY,
              title TEXT NOT NULL,
              body TEXT NOT NULL,
              created_at_utc INTEGER NOT NULL,
              updated_at_utc INTEGER NOT NULL
            );
          ''');
            database.execute('''
            CREATE TABLE scheduled_notification_rows (
              id INTEGER NOT NULL PRIMARY KEY,
              device_id TEXT NOT NULL,
              reminder_intent_id TEXT NOT NULL,
              owner_id TEXT NOT NULL,
              owner_type TEXT NOT NULL,
              occurrence_key TEXT NOT NULL,
              scheduled_for_utc INTEGER NOT NULL,
              payload TEXT NOT NULL
            );
          ''');
            database.execute('PRAGMA user_version = 1;');
          },
        ),
      );

      addTearDown(() async {
        await temp.delete(recursive: true);
      });

      await legacy.customSelect('SELECT 1').get();
      await legacy.close();

      final migrated = AppDatabase(NativeDatabase(file));
      addTearDown(migrated.close);

      final columns = await migrated
          .customSelect("PRAGMA table_info('task_rows');")
          .get();
      final notificationColumns = await migrated
          .customSelect("PRAGMA table_info('scheduled_notification_rows');")
          .get();
      final deletedTable = await migrated
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'deleted_record_rows';",
          )
          .get();

      expect(
        columns.map((row) => row.data['name']),
        contains('source_note_id'),
      );
      expect(
        notificationColumns.map((row) => row.data['name']),
        contains('scheduled_time_zone'),
      );
      expect(
        notificationColumns.map((row) => row.data['name']),
        containsAll(<String>['title', 'body']),
      );
      expect(deletedTable, hasLength(1));
    },
  );

  for (var fromVersion = 1; fromVersion <= 5; fromVersion++) {
    test(
      'migração v$fromVersion → v6 preserva dados e aceita escrita',
      () async {
        final temp = await Directory.systemTemp.createTemp(
          'lume_migration_v${fromVersion}_',
        );
        addTearDown(() async {
          await temp.delete(recursive: true);
        });
        final file = File('${temp.path}${Platform.pathSeparator}lume.sqlite');

        final legacy = AppDatabase(
          NativeDatabase(
            file,
            enableMigrations: false,
            setup: (database) => _buildLegacySchema(database, fromVersion),
          ),
        );
        await legacy.customSelect('SELECT 1').get();
        await legacy.close();

        final migrated = AppDatabase(NativeDatabase(file));
        addTearDown(migrated.close);

        final userVersion = await migrated
            .customSelect('PRAGMA user_version;')
            .getSingle();
        expect(userVersion.data.values.single, 6);

        final snapshot = await migrated.loadSnapshot();
        expect(snapshot.tasks.single.id, 'task-legada');
        expect(snapshot.tasks.single.sourceNoteId, isNull);
        expect(snapshot.notes.single.body, 'corpo preservado');
        final record = snapshot.scheduledNotifications.single;
        expect(record.id, 77);
        expect(record.scheduledTimeZone, '');
        expect(record.title, '');
        if (fromVersion >= 3) {
          expect(snapshot.deletedRecords.single.recordId, 'note-apagada');
        } else {
          expect(snapshot.deletedRecords, isEmpty);
        }
        expect(snapshot.reminders, isEmpty);

        // O banco migrado precisa aceitar os dois caminhos de escrita.
        final edited = snapshot.copyWith(
          notes: [
            snapshot.notes.single.copyWith(
              body: 'corpo editado pós-migração',
              updatedAtUtc: DateTime.now().toUtc(),
            ),
          ],
        );
        await migrated.applySnapshotDiff(snapshot, edited);
        final roundTrip = await migrated.loadSnapshot();
        expect(roundTrip.notes.single.body, 'corpo editado pós-migração');
      },
    );
  }
}
