import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/data/app_database.dart';

void main() {
  test(
    'database migration v1 to v4 adds sync and notification columns',
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
      expect(deletedTable, hasLength(1));
    },
  );
}
