// O TasksController é a segunda fatia da migração do god-file: a lógica que
// vivia no mixin _TaskActions, agora testável sem widget. Os testes validam
// contra o banco real (drift em memória) — o que o mixin nunca permitiu.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/data/app_database.dart';
import 'package:lume/services/activity_log_store.dart';
import 'package:lume/services/local_store.dart';
import 'package:lume/state/app_state_controller.dart';
import 'package:lume/state/tasks_controller.dart';
import 'package:lume_core/domain/app_snapshot.dart';

void main() {
  late Directory tmpDir;
  late AppDatabase db;
  late AppStateController appState;
  late TasksController controller;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('lume_tasks_');
    db = AppDatabase(NativeDatabase.memory());
    appState = AppStateController(
      store: LocalStore.withDatabase(db, directoryProvider: () async => tmpDir),
      activityLog: ActivityLogStore(directoryProvider: () async => tmpDir),
    );
    controller = TasksController(appState);
    await appState.save(
      AppSnapshot(
        tasks: const [],
        notes: const [],
        scheduledNotifications: const [],
        deletedRecords: const [],
      ),
    );
  });

  tearDown(() async {
    await db.close();
    await tmpDir.delete(recursive: true);
  });

  TaskItem single() => appState.snapshot!.tasks.single;

  test('create insere tarefa aberta no topo e persiste', () async {
    await controller.create('Comprar ração');
    await controller.create('Pagar boleto');

    final tasks = appState.snapshot!.tasks;
    expect(tasks, hasLength(2));
    expect(tasks.first.title, 'Pagar boleto', reason: 'novas vão para o topo');
    expect(tasks.first.status, TaskStatus.open);

    final persisted = await db.loadSnapshot();
    expect(persisted.tasks, hasLength(2));
  });

  test('createFromNote vincula sourceNoteId e resume o corpo', () async {
    final now = DateTime.now().toUtc();
    final note = NoteItem(
      id: 'note-origem',
      title: 'Planejar viagem',
      body: '- passagens\n- hotel',
      createdAtUtc: now,
      updatedAtUtc: now,
    );

    await controller.createFromNote(note);

    final task = single();
    expect(task.title, 'Planejar viagem');
    expect(task.sourceNoteId, 'note-origem');
    expect(task.description, isNotEmpty);
  });

  test(
    'toggleDone conclui e reabre, mantendo updatedAtUtc em avanço',
    () async {
      await controller.create('Alternável');
      final created = single();

      await controller.toggleDone(created);
      final done = single();
      expect(done.status, TaskStatus.done);
      expect(done.completedAtUtc, isNotNull);
      expect(done.updatedAtUtc.isBefore(created.updatedAtUtc), isFalse);

      await controller.toggleDone(done);
      final reopened = single();
      expect(reopened.status, TaskStatus.open);
      expect(reopened.completedAtUtc, isNull);
    },
  );

  test('rename troca o título preservando o resto', () async {
    await controller.create('Nome antigo');
    final created = single();

    await controller.rename(created, 'Nome novo');

    final renamed = single();
    expect(renamed.title, 'Nome novo');
    expect(renamed.id, created.id);
    expect(renamed.createdAtUtc, created.createdAtUtc);
  });

  test('setDue converte horário local para UTC e clearDue remove', () async {
    await controller.create('Com prazo');
    final dueLocal = DateTime(2026, 12, 24, 18, 30);

    await controller.setDue(single(), dueLocal);
    expect(single().dueAtUtc, dueLocal.toUtc());

    await controller.clearDue(single());
    expect(single().dueAtUtc, isNull);
  });

  test('delete remove a tarefa e grava tombstone com o deviceId', () async {
    await controller.create('Condenada');
    final task = single();

    await controller.delete(task, deviceId: 'device-teste');

    expect(appState.snapshot!.tasks, isEmpty);
    final tombstone = appState.snapshot!.deletedRecords.single;
    expect(tombstone.recordType, SyncRecordType.task);
    expect(tombstone.recordId, task.id);
    expect(tombstone.deviceId, 'device-teste');

    final persisted = await db.loadSnapshot();
    expect(persisted.tasks, isEmpty);
    expect(persisted.deletedRecords.single.recordId, task.id);
  });

  test('métodos registram atividade legível', () async {
    await controller.create('Auditável');
    expect(appState.activity.first, 'tarefa criada');

    await controller.delete(single(), deviceId: 'device-teste');
    expect(appState.activity.first, 'tarefa excluída');
  });
}
