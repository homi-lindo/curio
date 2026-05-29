part of 'main.dart';

/// Task list actions for the app state.
///
/// Kept in a mixin so the main state class stays focused. The abstract members
/// below are satisfied by `_CurioAppState`'s own fields and core helpers; the
/// methods here are moved verbatim and behave identically.
mixin _TaskActions on State<CurioApp> {
  AppSnapshot? get _snapshot;
  String get _deviceId;
  BuildContext get _dialogContext;
  set _selectedIndex(int value);
  set _taskFilter(TaskFilter value);
  void _log(String message);
  Future<void> _saveSnapshot(AppSnapshot snapshot);
  NoteItem? _selectedNote(AppSnapshot? snapshot);
  Future<String?> _promptText({
    required String title,
    required String hint,
    String initialValue,
    String confirmLabel,
  });

  void _setTaskFilter(TaskFilter filter) {
    setState(() => _taskFilter = filter);
  }

  Future<void> _upsertTask(TaskItem task) async {
    final snapshot = _snapshot;
    if (snapshot == null) {
      return;
    }
    final exists = snapshot.tasks.any((candidate) => candidate.id == task.id);
    final nextTasks = exists
        ? snapshot.tasks
              .map((candidate) => candidate.id == task.id ? task : candidate)
              .toList()
        : <TaskItem>[task, ...snapshot.tasks];
    await _saveSnapshot(snapshot.copyWith(tasks: nextTasks));
  }

  Future<void> _addTask() async {
    final title = await _promptText(
      title: 'Nova tarefa',
      hint: 'Descrição da tarefa',
      confirmLabel: 'Criar',
    );
    if (title == null || title.trim().isEmpty) {
      return;
    }

    final now = DateTime.now().toUtc();
    await _upsertTask(
      TaskItem(
        id: newId('task'),
        title: title.trim(),
        status: TaskStatus.open,
        createdAtUtc: now,
        updatedAtUtc: now,
      ),
    );
    _log('tarefa criada');
  }

  Future<void> _createTaskFromSelectedNote() async {
    final note = _selectedNote(_snapshot);
    if (note == null) {
      return;
    }

    final now = DateTime.now().toUtc();
    await _upsertTask(
      TaskItem(
        id: newId('task'),
        title: note.title,
        description: noteTaskDescription(note),
        status: TaskStatus.open,
        sourceNoteId: note.id,
        createdAtUtc: now,
        updatedAtUtc: now,
      ),
    );
    setState(() => _selectedIndex = _AppTab.tasks.index);
    _log('tarefa criada a partir da nota');
  }

  Future<void> _toggleTaskDone(TaskItem task) async {
    final now = DateTime.now().toUtc();
    final next = task.isDone
        ? task.copyWith(
            status: TaskStatus.open,
            updatedAtUtc: now,
            clearCompletedAt: true,
          )
        : task.copyWith(
            status: TaskStatus.done,
            completedAtUtc: now,
            updatedAtUtc: now,
          );
    await _upsertTask(next);
  }

  Future<void> _renameTask(TaskItem task) async {
    final title = await _promptText(
      title: 'Renomear tarefa',
      hint: 'Descrição da tarefa',
      initialValue: task.title,
      confirmLabel: 'Salvar',
    );
    if (title == null || title.trim().isEmpty) {
      return;
    }

    await _upsertTask(
      task.copyWith(title: title.trim(), updatedAtUtc: DateTime.now().toUtc()),
    );
    _log('tarefa renomeada');
  }

  Future<void> _setTaskDue(TaskItem task) async {
    final initialLocal =
        task.dueAtUtc?.toLocal() ??
        defaultNotificationLocalForDate(DateTime.now());
    final date = await showDatePicker(
      context: _dialogContext,
      initialDate: initialLocal,
      firstDate: DateTime(2024),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) {
      return;
    }
    final time = await showTimePicker(
      context: _dialogContext,
      initialTime: TimeOfDay.fromDateTime(initialLocal),
    );
    final dueLocal = DateTime(
      date.year,
      date.month,
      date.day,
      time?.hour ?? initialLocal.hour,
      time?.minute ?? initialLocal.minute,
    );
    await _upsertTask(
      task.copyWith(
        dueAtUtc: dueLocal.toUtc(),
        updatedAtUtc: DateTime.now().toUtc(),
      ),
    );
    _log('data da tarefa: ${formatLocalDateTime(dueLocal.toUtc())}');
  }

  Future<void> _clearTaskDue(TaskItem task) async {
    await _upsertTask(
      task.copyWith(clearDueAt: true, updatedAtUtc: DateTime.now().toUtc()),
    );
    _log('data da tarefa removida');
  }

  Future<void> _deleteTask(TaskItem task) async {
    final snapshot = _snapshot;
    if (snapshot == null) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: _dialogContext,
      builder: (context) {
        return AlertDialog(
          title: const Text('Excluir tarefa'),
          content: Text('Excluir "${task.title}"?'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Excluir'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }

    final now = DateTime.now().toUtc();
    final next = _withDeletedRecord(
      snapshot.copyWith(
        tasks: snapshot.tasks
            .where((candidate) => candidate.id != task.id)
            .toList(),
      ),
      DeletedRecord(
        recordType: SyncRecordType.task,
        recordId: task.id,
        deletedAtUtc: now,
        deviceId: _deviceId,
      ),
    );
    await _saveSnapshot(next);
    _log('tarefa excluída');
  }
}
