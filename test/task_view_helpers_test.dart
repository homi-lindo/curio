import 'package:flutter_test/flutter_test.dart';
import 'package:lume/ui/task_view_helpers.dart';
import 'package:lume_core/domain/app_snapshot.dart';
import 'package:lume_core/domain/reminder.dart';

void main() {
  test('filters tasks by status, due date and query', () {
    final now = DateTime(2026, 5, 21, 9);
    final todayUtc = now.toUtc();
    final tasks = <TaskItem>[
      _task(
        id: 'open',
        title: 'Comprar café',
        dueAtUtc: todayUtc,
        updatedAtUtc: todayUtc,
      ),
      _task(
        id: 'done',
        title: 'Fechar release',
        status: TaskStatus.done,
        updatedAtUtc: todayUtc.add(const Duration(minutes: 1)),
      ),
      _task(
        id: 'note',
        title: 'Revisar pauta',
        sourceNoteId: 'nota-sync',
        updatedAtUtc: todayUtc.add(const Duration(minutes: 2)),
      ),
    ];

    expect(
      filterTasks(tasks, 'café', TaskFilter.open).map((task) => task.id),
      <String>['open'],
    );
    expect(matchesTaskFilter(tasks[0], TaskFilter.today, now: now), isTrue);
    expect(
      filterTasks(tasks, 'nota-sync', TaskFilter.all).map((task) => task.id),
      <String>['note'],
    );
    expect(
      filterTasks(tasks, '', TaskFilter.done).map((task) => task.id),
      <String>['done'],
    );
  });

  test('agenda sort puts dated tasks first and undated by latest update', () {
    final now = DateTime.utc(2026, 5, 21, 9);
    final tasks = <TaskItem>[
      _task(id: 'loose-old', title: 'Loose old', updatedAtUtc: now),
      _task(
        id: 'dated-later',
        title: 'Later',
        dueAtUtc: now.add(const Duration(hours: 2)),
        updatedAtUtc: now,
      ),
      _task(
        id: 'dated-first',
        title: 'First',
        dueAtUtc: now.add(const Duration(hours: 1)),
        updatedAtUtc: now,
      ),
      _task(
        id: 'loose-new',
        title: 'Loose new',
        updatedAtUtc: now.add(const Duration(minutes: 1)),
      ),
    ]..sort(compareTasksByAgenda);

    expect(tasks.map((task) => task.id), <String>[
      'dated-first',
      'dated-later',
      'loose-new',
      'loose-old',
    ]);
  });

  test('labels task metadata without needing widget state', () {
    final now = DateTime(2026, 5, 21, 9);
    final task = _task(
      id: 'task',
      title: 'Task',
      dueAtUtc: now.toUtc(),
      reminderEnabled: true,
      sourceNoteId: 'note-1',
      updatedAtUtc: now.toUtc(),
    );

    expect(todayLabel(now: now), '21/05/2026');
    expect(taskFilterLabel(TaskFilter.scheduled), 'Com hora');
    expect(timelineLabel(task), formatLocalTime(now.toUtc()));
    expect(taskMeta(task, now: now), contains('Hoje'));
    expect(taskMeta(task, now: now), contains('alerta'));
    expect(taskMeta(task, now: now), contains('nota'));
  });

  test(
    'global search finds notes and notifications without accent sensitivity',
    () {
      final now = DateTime.utc(2026, 5, 21, 9);
      final snapshot = AppSnapshot(
        tasks: const <TaskItem>[],
        notes: <NoteItem>[
          NoteItem(
            id: 'note-sync',
            title: 'Roteiro do servidor',
            body: 'Preparar kit self hosted para o Curió.',
            createdAtUtc: now,
            updatedAtUtc: now.add(const Duration(minutes: 1)),
          ),
        ],
        scheduledNotifications: <ScheduledNotificationRecord>[
          ScheduledNotificationRecord(
            id: 42,
            deviceId: 'curio-test',
            reminderIntentId: 'note-note-sync-alert',
            ownerId: 'note-sync',
            ownerType: ReminderOwnerType.note,
            occurrenceKey: '2026-05-21T12:00:00.000Z',
            scheduledForUtc: now.add(const Duration(hours: 3)),
            payload: 'curio://reminder/note-note-sync-alert',
            title: 'Comprar café',
            body: 'Passar no mercado depois do trabalho.',
          ),
        ],
      );

      expect(normalizeSearchText('Curió café ação'), 'curio cafe acao');

      final cafeResults = searchSnapshotText(snapshot, 'cafe');
      expect(cafeResults.map((result) => result.id), <String>['42']);
      expect(cafeResults.single.kind, GlobalSearchResultKind.notification);

      final curioResults = searchSnapshotText(snapshot, 'curio');
      expect(curioResults.map((result) => result.id), <String>['note-sync']);
      expect(curioResults.single.kind, GlobalSearchResultKind.note);
    },
  );

  test('calendar helpers expose years through 2035 and count dated tasks', () {
    final now = DateTime(2026, 5, 21);
    final tasks = <TaskItem>[
      _task(
        id: 'first',
        title: 'First',
        dueAtUtc: DateTime(2026, 5, 21, 12),
        updatedAtUtc: now.toUtc(),
      ),
      _task(
        id: 'second',
        title: 'Second',
        dueAtUtc: DateTime(2026, 5, 21, 14),
        updatedAtUtc: now.toUtc(),
      ),
      _task(id: 'loose', title: 'Loose', updatedAtUtc: now.toUtc()),
    ];

    expect(agendaYears(now: now), containsAllInOrder(<int>[2026, 2027]));
    expect(agendaYears(now: now).last, 2035);
    expect(daysInMonth(2028, 2), 29);
    expect(
      sameDayOrLastValidDate(year: 2027, month: 2, preferredDay: 31),
      DateTime(2027, 2, 28),
    );
    expect(taskCountsByDate(tasks)[DateTime(2026, 5, 21)], 2);
    expect(
      tasksDueOnDate(tasks, DateTime(2026, 5, 21)).map((task) => task.id),
      <String>['first', 'second'],
    );
  });

  test('day helpers collect daily notes and notification queues', () {
    final day = DateTime(2026, 5, 22);
    final notes = <NoteItem>[
      _note(
        id: 'today-old',
        title: dailyNoteTitle(day),
        updatedAtUtc: DateTime.utc(2026, 5, 22, 12),
      ),
      _note(
        id: 'general',
        title: 'Ideias soltas',
        updatedAtUtc: DateTime.utc(2026, 5, 22, 13),
      ),
      _note(
        id: 'today-new',
        title: dailyNoteTitle(day),
        updatedAtUtc: DateTime.utc(2026, 5, 22, 14),
      ),
    ];
    final notifications = <ScheduledNotificationRecord>[
      _notification(id: 1, scheduledForUtc: DateTime.utc(2026, 5, 22, 12)),
      _notification(id: 2, scheduledForUtc: DateTime.utc(2026, 5, 23, 12)),
      _notification(id: 3, scheduledForUtc: DateTime.utc(2026, 5, 22, 15)),
    ];

    expect(dailyNotesForDate(notes, day).map((note) => note.id), <String>[
      'today-new',
      'today-old',
    ]);
    expect(
      notificationsForDate(notifications, day).map((record) => record.id),
      <int>[1, 3],
    );
    expect(
      upcomingNotifications(
        notifications,
        nowUtc: DateTime.utc(2026, 5, 22, 13),
      ).map((record) => record.id),
      <int>[3, 2],
    );
  });
}

TaskItem _task({
  required String id,
  required String title,
  required DateTime updatedAtUtc,
  String description = '',
  TaskStatus status = TaskStatus.open,
  DateTime? dueAtUtc,
  bool reminderEnabled = false,
  String? sourceNoteId,
}) {
  return TaskItem(
    id: id,
    title: title,
    description: description,
    status: status,
    dueAtUtc: dueAtUtc,
    reminderEnabled: reminderEnabled,
    sourceNoteId: sourceNoteId,
    createdAtUtc: DateTime.utc(2026, 5, 21),
    updatedAtUtc: updatedAtUtc,
  );
}

NoteItem _note({
  required String id,
  required String title,
  required DateTime updatedAtUtc,
}) {
  return NoteItem(
    id: id,
    title: title,
    body: 'corpo $id',
    createdAtUtc: DateTime.utc(2026, 5, 21),
    updatedAtUtc: updatedAtUtc,
  );
}

ScheduledNotificationRecord _notification({
  required int id,
  required DateTime scheduledForUtc,
}) {
  return ScheduledNotificationRecord(
    id: id,
    deviceId: 'curio-test',
    reminderIntentId: 'note-note-alert-$id',
    ownerId: 'note-1',
    ownerType: ReminderOwnerType.note,
    occurrenceKey: scheduledForUtc.toIso8601String(),
    scheduledForUtc: scheduledForUtc,
    payload: 'curio://reminder/note-note-alert-$id',
    title: 'Notificação $id',
  );
}
