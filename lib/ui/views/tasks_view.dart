import 'package:flutter/material.dart';
import 'package:lume_core/domain/app_snapshot.dart';

import '../task_view_helpers.dart';
import '../widgets/page_frame.dart';
import '../widgets/section_header.dart';
import '../widgets/status_pill.dart';
import '../widgets/surface.dart';

final class TasksView extends StatelessWidget {
  const TasksView({
    super.key,
    required this.tasks,
    required this.filter,
    required this.busy,
    required this.selectedNoteTitle,
    required this.onFilterChanged,
    required this.onAddTask,
    required this.onCreateFromNote,
    required this.onToggleDone,
    required this.onRename,
    required this.onSetDue,
    required this.onClearDue,
    required this.onDelete,
  });

  final List<TaskItem> tasks;
  final TaskFilter filter;
  final bool busy;

  /// Title of the note currently selected in Notas, when any. Enables the
  /// "criar tarefa a partir da nota" shortcut.
  final String? selectedNoteTitle;

  final ValueChanged<TaskFilter> onFilterChanged;
  final VoidCallback onAddTask;
  final VoidCallback onCreateFromNote;
  final ValueChanged<TaskItem> onToggleDone;
  final ValueChanged<TaskItem> onRename;
  final ValueChanged<TaskItem> onSetDue;
  final ValueChanged<TaskItem> onClearDue;
  final ValueChanged<TaskItem> onDelete;

  @override
  Widget build(BuildContext context) {
    final openCount = tasks.where((task) => !task.isDone).length;
    final doneCount = tasks.length - openCount;
    final visible = filterTasks(tasks, '', filter)..sort(compareTasksByAgenda);

    return PageFrame(
      title: 'Tarefas',
      subtitle: openCount == 0
          ? 'Nenhuma tarefa aberta'
          : '$openCount aberta(s)',
      trailing: StatusPill(
        icon: Icons.checklist_outlined,
        label: '$doneCount/${tasks.length}',
      ),
      child: Surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SectionHeader(
              icon: Icons.task_alt_outlined,
              title: 'Lista de tarefas',
              action: FilledButton.icon(
                onPressed: busy ? null : onAddTask,
                icon: const Icon(Icons.add_task_outlined),
                label: const Text('Nova tarefa'),
              ),
            ),
            if (selectedNoteTitle != null) ...<Widget>[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  onPressed: busy ? null : onCreateFromNote,
                  icon: const Icon(Icons.note_add_outlined),
                  label: Text('Tarefa da nota "$selectedNoteTitle"'),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final option in TaskFilter.values)
                  ChoiceChip(
                    label: Text(taskFilterLabel(option)),
                    selected: option == filter,
                    onSelected: (_) => onFilterChanged(option),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (visible.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  _emptyLabel(filter),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              )
            else
              for (final task in visible)
                _TaskRow(
                  task: task,
                  onToggleDone: () => onToggleDone(task),
                  onRename: () => onRename(task),
                  onSetDue: () => onSetDue(task),
                  onClearDue: () => onClearDue(task),
                  onDelete: () => onDelete(task),
                ),
          ],
        ),
      ),
    );
  }
}

String _emptyLabel(TaskFilter filter) {
  return switch (filter) {
    TaskFilter.open =>
      'Nenhuma tarefa aberta. Crie a primeira com "Nova tarefa".',
    TaskFilter.today => 'Nenhuma tarefa com data para hoje.',
    TaskFilter.scheduled => 'Nenhuma tarefa com data definida.',
    TaskFilter.done => 'Nenhuma tarefa concluída ainda.',
    TaskFilter.all => 'Nenhuma tarefa cadastrada.',
  };
}

final class _TaskRow extends StatelessWidget {
  const _TaskRow({
    required this.task,
    required this.onToggleDone,
    required this.onRename,
    required this.onSetDue,
    required this.onClearDue,
    required this.onDelete,
  });

  final TaskItem task;
  final VoidCallback onToggleDone;
  final VoidCallback onRename;
  final VoidCallback onSetDue;
  final VoidCallback onClearDue;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final hasDue = task.dueAtUtc != null;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Checkbox(value: task.isDone, onChanged: (_) => onToggleDone()),
      title: Text(
        task.title,
        style: task.isDone
            ? const TextStyle(decoration: TextDecoration.lineThrough)
            : null,
      ),
      subtitle: Text(
        taskMeta(task),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            onPressed: onSetDue,
            icon: const Icon(Icons.event_outlined),
            tooltip: hasDue ? 'Alterar data' : 'Definir data',
          ),
          if (hasDue)
            IconButton(
              onPressed: onClearDue,
              icon: const Icon(Icons.event_busy_outlined),
              tooltip: 'Remover data',
            ),
          IconButton(
            onPressed: onRename,
            icon: const Icon(Icons.drive_file_rename_outline),
            tooltip: 'Renomear tarefa',
          ),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Excluir tarefa',
          ),
        ],
      ),
      onTap: onToggleDone,
    );
  }
}
