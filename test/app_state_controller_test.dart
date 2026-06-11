import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/data/app_database.dart';
import 'package:lume/services/activity_log_store.dart';
import 'package:lume/services/local_store.dart';
import 'package:lume/state/app_state_controller.dart';
import 'package:lume_core/domain/app_snapshot.dart';

import 'dart:io';

void main() {
  late Directory tmpDir;
  late AppDatabase db;
  late ActivityLogStore activityLog;
  late AppStateController controller;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('lume_controller_');
    db = AppDatabase(NativeDatabase.memory());
    activityLog = ActivityLogStore(directoryProvider: () async => tmpDir);
    controller = AppStateController(
      store: LocalStore.withDatabase(db, directoryProvider: () async => tmpDir),
      activityLog: activityLog,
    );
  });

  tearDown(() async {
    // Drena os appends fire-and-forget do log antes de apagar o diretório;
    // sem isso o delete corre contra a fila e falha no Linux.
    await activityLog.flush();
    await db.close();
    await tmpDir.delete(recursive: true);
  });

  AppSnapshot snapshotWithNote(String body) {
    final now = DateTime.utc(2026, 6, 9, 12);
    return AppSnapshot(
      tasks: const [],
      notes: [
        NoteItem(
          id: 'note-1',
          title: 'Nota',
          body: body,
          createdAtUtc: now,
          updatedAtUtc: now,
        ),
      ],
      scheduledNotifications: const [],
      deletedRecords: const [],
    );
  }

  test('save publica em memória de forma síncrona e persiste', () async {
    final snapshot = snapshotWithNote('corpo');
    final future = controller.save(snapshot);

    // Antes de qualquer await o snapshot já é visível.
    expect(identical(controller.snapshot, snapshot), isTrue);

    await future;
    final persisted = await db.loadSnapshot();
    expect(persisted.notes.single.body, 'corpo');
  });

  test('publish notifica; publishSilently não', () {
    var notifications = 0;
    controller.addListener(() => notifications++);

    controller.publish(snapshotWithNote('a'));
    expect(notifications, 1);

    controller.publishSilently(snapshotWithNote('b'));
    expect(notifications, 1);
    expect(controller.snapshot?.notes.single.body, 'b');

    // Publicar a mesma instância não gera rebuild.
    final same = controller.snapshot;
    controller.publish(same);
    expect(notifications, 1);
  });

  test('log mantém no máximo 50 mensagens, mais novas primeiro', () {
    for (var index = 0; index < 60; index++) {
      controller.log('mensagem $index');
    }
    expect(controller.activity, hasLength(50));
    expect(controller.activity.first, 'mensagem 59');
    expect(controller.activity.last, 'mensagem 10');
  });

  test('log e publish após dispose não estouram o ChangeNotifier', () {
    controller.dispose();
    controller.log('mensagem tardia');
    controller.publish(snapshotWithNote('tardio'));
    expect(controller.activity.first, 'mensagem tardia');
  });
}
