// applySnapshotDiff precisa produzir exatamente o mesmo estado final que
// replaceSnapshot — é isso que permite à SnapshotWriteQueue trocar o replace
// completo por escritas incrementais sem mudar a semântica.
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/data/app_database.dart';
import 'package:lume/services/snapshot_write_queue.dart';
import 'package:lume_core/domain/app_snapshot.dart';
import 'package:lume_core/domain/reminder.dart';

AppSnapshot _baseSnapshot() {
  final now = DateTime.utc(2026, 6, 1, 12);
  return AppSnapshot(
    tasks: [
      TaskItem(
        id: 'task-1',
        title: 'Comprar ração',
        status: TaskStatus.open,
        createdAtUtc: now,
        updatedAtUtc: now,
      ),
      TaskItem(
        id: 'task-2',
        title: 'Pagar boleto',
        status: TaskStatus.open,
        dueAtUtc: now.add(const Duration(days: 2)),
        createdAtUtc: now,
        updatedAtUtc: now,
      ),
    ],
    notes: [
      NoteItem(
        id: 'note-1',
        title: 'Entrada',
        body: 'corpo original',
        createdAtUtc: now,
        updatedAtUtc: now,
      ),
      NoteItem(
        id: 'note-2',
        title: 'Diário - 01/06/2026',
        body: '## 01/06/2026',
        createdAtUtc: now,
        updatedAtUtc: now,
      ),
    ],
    scheduledNotifications: [
      ScheduledNotificationRecord(
        id: 7,
        deviceId: 'device-a',
        reminderIntentId: 'reminder-1',
        ownerId: 'note-1',
        ownerType: ReminderOwnerType.note,
        occurrenceKey: '2026-06-02T09:00:00.000Z',
        scheduledForUtc: DateTime.utc(2026, 6, 2, 9),
        payload: 'lume://reminder/reminder-1',
        title: 'Lembrete',
        body: '',
        scheduledTimeZone: 'America/Sao_Paulo',
      ),
    ],
    reminders: [
      ReminderIntent.oneShot(
        id: 'reminder-1',
        ownerId: 'note-1',
        ownerType: ReminderOwnerType.note,
        instantUtc: DateTime.utc(2026, 6, 2, 9),
        updatedAtUtc: now,
        timeZone: 'America/Sao_Paulo',
        title: 'Lembrete',
        body: '',
      ),
    ],
    deletedRecords: [
      DeletedRecord(
        recordType: SyncRecordType.note,
        recordId: 'note-antiga',
        deletedAtUtc: now.subtract(const Duration(days: 1)),
        deviceId: 'device-a',
      ),
    ],
  );
}

/// Mutação representativa: edita nota, conclui uma tarefa e remove outra,
/// troca a notificação, desabilita o lembrete e remove o tombstone (como a
/// compaction faz), além de criar uma nota nova.
AppSnapshot _mutated(AppSnapshot base) {
  final later = DateTime.utc(2026, 6, 3, 8);
  return base.copyWith(
    tasks: [
      base.tasks
          .firstWhere((task) => task.id == 'task-1')
          .copyWith(
            status: TaskStatus.done,
            completedAtUtc: later,
            updatedAtUtc: later,
          ),
    ],
    notes: [
      for (final note in base.notes)
        note.id == 'note-1'
            ? note.copyWith(body: 'corpo editado', updatedAtUtc: later)
            : note,
      NoteItem(
        id: 'note-3',
        title: 'Nova ideia',
        body: 'rascunho',
        createdAtUtc: later,
        updatedAtUtc: later,
      ),
    ],
    scheduledNotifications: [
      ScheduledNotificationRecord(
        id: 9,
        deviceId: 'device-a',
        reminderIntentId: 'reminder-2',
        ownerId: 'note-3',
        ownerType: ReminderOwnerType.note,
        occurrenceKey: '2026-06-04T10:00:00.000Z',
        scheduledForUtc: DateTime.utc(2026, 6, 4, 10),
        payload: 'lume://reminder/reminder-2',
        title: 'Outro lembrete',
        body: 'detalhes',
        scheduledTimeZone: 'America/Sao_Paulo',
      ),
    ],
    reminders: [
      for (final reminder in base.reminders)
        reminder.copyWith(enabled: false, updatedAtUtc: later),
      ReminderIntent.oneShot(
        id: 'reminder-2',
        ownerId: 'note-3',
        ownerType: ReminderOwnerType.note,
        instantUtc: DateTime.utc(2026, 6, 4, 10),
        updatedAtUtc: later,
        timeZone: 'America/Sao_Paulo',
        title: 'Outro lembrete',
        body: 'detalhes',
      ),
    ],
    deletedRecords: const [],
  );
}

void main() {
  test('diff produz o mesmo estado final que replace', () async {
    final viaDiff = AppDatabase(NativeDatabase.memory());
    final viaReplace = AppDatabase(NativeDatabase.memory());
    addTearDown(viaDiff.close);
    addTearDown(viaReplace.close);

    final base = _baseSnapshot();
    final mutated = _mutated(base);

    await viaDiff.replaceSnapshot(base);
    await viaDiff.applySnapshotDiff(base, mutated);

    await viaReplace.replaceSnapshot(mutated);

    final diffState = await viaDiff.loadSnapshot();
    final replaceState = await viaReplace.loadSnapshot();
    expect(diffState.toJson(), replaceState.toJson());
  });

  test('diff sem mudanças não toca o banco e estado se preserva', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final base = _baseSnapshot();
    await db.replaceSnapshot(base);
    await db.applySnapshotDiff(base, base);

    final state = await db.loadSnapshot();
    expect(state.toJson(), base.toJson());
  });

  test('diff que esvazia tudo equivale a replace vazio', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final base = _baseSnapshot();
    final empty = AppSnapshot(
      tasks: const [],
      notes: const [],
      scheduledNotifications: const [],
      deletedRecords: const [],
    );

    await db.replaceSnapshot(base);
    await db.applySnapshotDiff(base, empty);

    final state = await db.loadSnapshot();
    expect(state.tasks, isEmpty);
    expect(state.notes, isEmpty);
    expect(state.scheduledNotifications, isEmpty);
    expect(state.reminders, isEmpty);
    expect(state.deletedRecords, isEmpty);
  });

  group('SnapshotWriteQueue', () {
    test('usa replace antes do prime e diff depois', () async {
      final calls = <String>[];
      final queue = SnapshotWriteQueue(
        saveSnapshot: (_) async => calls.add('replace'),
        applyDiff: (_, _) async => calls.add('diff'),
      );

      final base = _baseSnapshot();
      await queue.save(base);
      expect(calls, ['replace']);

      queue.prime(base);
      await queue.save(_mutated(base));
      // O save anterior já registrou o último persistido; prime não rebaixa.
      expect(calls, ['replace', 'diff']);
    });

    test('falha no diff derruba para replace no save seguinte', () async {
      final calls = <String>[];
      var failNext = true;
      final queue = SnapshotWriteQueue(
        saveSnapshot: (_) async => calls.add('replace'),
        applyDiff: (_, _) async {
          calls.add('diff');
          if (failNext) {
            failNext = false;
            throw StateError('disco indisponível');
          }
        },
      );

      final base = _baseSnapshot();
      queue.prime(base);

      await expectLater(queue.save(_mutated(base)), throwsStateError);
      await queue.save(_mutated(base));
      expect(calls, ['diff', 'replace']);
    });
  });
}
