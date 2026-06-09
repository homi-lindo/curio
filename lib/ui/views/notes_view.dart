import 'package:flutter/material.dart';
import 'package:lume_core/domain/app_snapshot.dart';
import 'package:lume_core/domain/reminder.dart';

import '../../services/note_edit_history_store.dart';
import '../markdown_editor.dart';
import '../markdown_preview.dart';
import '../notification_editor.dart';
import '../task_view_helpers.dart';
import '../widgets/notification_record_tile.dart';
import '../widgets/page_frame.dart';
import '../widgets/status_pill.dart';
import '../widgets/surface.dart';

final class NotesView extends StatelessWidget {
  const NotesView({
    super.key,
    required this.notes,
    required this.scheduledNotifications,
    required this.noteHistory,
    required this.selectedNoteId,
    required this.selectedDate,
    required this.notificationComposerOpen,
    required this.controller,
    required this.onOpenCalendar,
    required this.onToggleNotificationComposer,
    required this.onCreateNotification,
    required this.onCancelNotificationComposer,
    required this.onEditNotification,
    required this.onCancelNotification,
    required this.onAddNote,
    required this.onRenameNote,
    required this.onDeleteNote,
    required this.onRestoreRevision,
    required this.onBodyChanged,
  });

  final List<NoteItem> notes;
  final List<ScheduledNotificationRecord> scheduledNotifications;
  final List<NoteEditRevision> noteHistory;
  final String? selectedNoteId;
  final DateTime selectedDate;
  final bool notificationComposerOpen;
  final TextEditingController controller;
  final VoidCallback onOpenCalendar;
  final VoidCallback onToggleNotificationComposer;
  final ValueChanged<NotificationDraft> onCreateNotification;
  final VoidCallback onCancelNotificationComposer;
  final ValueChanged<ScheduledNotificationRecord> onEditNotification;
  final ValueChanged<ScheduledNotificationRecord> onCancelNotification;
  final VoidCallback onAddNote;
  final VoidCallback onRenameNote;
  final VoidCallback onDeleteNote;
  final ValueChanged<NoteEditRevision> onRestoreRevision;
  final ValueChanged<String> onBodyChanged;

  @override
  Widget build(BuildContext context) {
    final selected = notes
        .where((note) => note.id == selectedNoteId)
        .firstOrNull;
    final dailyTitle = dailyNoteTitle(selectedDate);
    final isDailyNote = selected != null && dailyNoteDate(selected) != null;
    final selectedNotifications =
        scheduledNotifications.where((record) {
          if (selected != null && record.ownerId == selected.id) {
            return true;
          }
          return isSameDate(record.scheduledForUtc, selectedDate);
        }).toList()..sort(
          (left, right) =>
              left.scheduledForUtc.compareTo(right.scheduledForUtc),
        );
    final selectedHistory = selected == null
        ? noteHistory
        : noteHistory
              .where((revision) => revision.noteId == selected.id)
              .toList();

    return PageFrame(
      title: 'Notas',
      subtitle: formatLocalDate(selectedDate),
      trailing: const StatusPill(icon: Icons.save_outlined, label: 'Autosave'),
      child: Surface(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 980;
            final editor = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    FilledButton.icon(
                      onPressed: onOpenCalendar,
                      icon: const Icon(Icons.calendar_month_outlined),
                      label: const Text('Calendário'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(170, 48),
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: selected == null
                          ? null
                          : onToggleNotificationComposer,
                      icon: const Icon(Icons.notification_add_outlined),
                      label: const Text('Notificação'),
                    ),
                    IconButton(
                      onPressed: onAddNote,
                      icon: const Icon(Icons.note_add_outlined),
                      tooltip: 'Nova nota geral',
                    ),
                    IconButton(
                      onPressed: selected == null ? null : onRenameNote,
                      icon: const Icon(Icons.drive_file_rename_outline),
                      tooltip: 'Renomear nota',
                    ),
                    IconButton(
                      onPressed: selected == null ? null : onDeleteNote,
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Excluir nota',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      selected?.title ?? dailyTitle,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      selectedNotifications.isEmpty
                          ? 'Sem notificação neste dia'
                          : '${selectedNotifications.length} notificação(ões)',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                if (!isDailyNote && selected != null) ...<Widget>[
                  const SizedBox(height: 10),
                  Text(
                    'Nota geral selecionada. O botão Calendário volta para a seleção de dias.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                if (notificationComposerOpen && selected != null) ...<Widget>[
                  const SizedBox(height: 14),
                  InlineNotificationEditor(
                    key: ValueKey<String>(
                      'notification-composer-${selected.id}',
                    ),
                    initialTitle: notificationTitleFromNote(selected),
                    initialBody: notificationBodyFromNote(selected),
                    initialLocal: _initialComposerLocal(selected, selectedDate),
                    onSubmit: onCreateNotification,
                    onCancel: onCancelNotificationComposer,
                  ),
                ],
                const SizedBox(height: 14),
                _NoteEditorArea(
                  enabled: selected != null,
                  wide: wide,
                  controller: controller,
                  onBodyChanged: onBodyChanged,
                ),
                const SizedBox(height: 18),
                _NotificationList(
                  notifications: selectedNotifications,
                  notes: notes,
                  onEdit: onEditNotification,
                  onCancel: onCancelNotification,
                ),
                const SizedBox(height: 18),
                _RevisionList(
                  revisions: selectedHistory,
                  onRestore: onRestoreRevision,
                ),
              ],
            );
            return editor;
          },
        ),
      ),
    );
  }
}

/// Editor Markdown com visualização opcional: toolbar + toggle de preview,
/// lado a lado quando há largura, alternado quando não há. O estado do toggle
/// é local — não interessa ao resto do app.
final class _NoteEditorArea extends StatefulWidget {
  const _NoteEditorArea({
    required this.enabled,
    required this.wide,
    required this.controller,
    required this.onBodyChanged,
  });

  final bool enabled;
  final bool wide;
  final TextEditingController controller;
  final ValueChanged<String> onBodyChanged;

  @override
  State<_NoteEditorArea> createState() => _NoteEditorAreaState();
}

final class _NoteEditorAreaState extends State<_NoteEditorArea> {
  bool _showPreview = false;

  @override
  Widget build(BuildContext context) {
    final editorField = MarkdownShortcuts(
      enabled: widget.enabled,
      controller: widget.controller,
      onChanged: widget.onBodyChanged,
      child: TextField(
        controller: widget.controller,
        enabled: widget.enabled,
        onChanged: widget.onBodyChanged,
        minLines: widget.wide ? 22 : 14,
        maxLines: widget.wide ? 36 : 28,
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.newline,
        style: const TextStyle(fontSize: 15, height: 1.45),
        decoration: InputDecoration(
          hintText: widget.enabled
              ? 'Escreva em Markdown.'
              : 'Escolha um dia no calendário para criar a nota.',
          alignLabelWithHint: true,
        ),
      ),
    );

    final previewPane = Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 220, maxHeight: 560),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: SingleChildScrollView(
        // Reconstrói a cada tecla via controller; o parse do package:markdown
        // é barato na escala de uma nota.
        child: ValueListenableBuilder<TextEditingValue>(
          valueListenable: widget.controller,
          builder: (context, value, _) => MarkdownPreview(data: value.text),
        ),
      ),
    );

    final showSideBySide = _showPreview && widget.wide;
    final showPreviewOnly = _showPreview && !widget.wide;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Expanded(
              child: MarkdownToolbar(
                enabled: widget.enabled && !showPreviewOnly,
                onAction: (action) => applyMarkdownFormat(
                  controller: widget.controller,
                  onChanged: widget.onBodyChanged,
                  action: action,
                ),
              ),
            ),
            IconButton(
              onPressed: widget.enabled
                  ? () => setState(() => _showPreview = !_showPreview)
                  : null,
              isSelected: _showPreview,
              icon: const Icon(Icons.visibility_outlined),
              selectedIcon: const Icon(Icons.edit_note_outlined),
              tooltip: _showPreview
                  ? (widget.wide
                        ? 'Ocultar visualização'
                        : 'Voltar para a edição')
                  : 'Visualizar Markdown',
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (showSideBySide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: editorField),
              const SizedBox(width: 14),
              Expanded(child: previewPane),
            ],
          )
        else if (showPreviewOnly)
          previewPane
        else
          editorField,
      ],
    );
  }
}

DateTime _initialComposerLocal(NoteItem note, DateTime selectedDate) {
  final sourceDate = dailyNoteDate(note) ?? selectedDate;
  final candidate = defaultNotificationLocalForDate(sourceDate);
  if (candidate.toUtc().isAfter(DateTime.now().toUtc())) {
    return candidate;
  }
  return DateTime.now().add(const Duration(hours: 1));
}

final class _NotificationList extends StatelessWidget {
  const _NotificationList({
    required this.notifications,
    required this.notes,
    required this.onEdit,
    required this.onCancel,
  });

  final List<ScheduledNotificationRecord> notifications;
  final List<NoteItem> notes;
  final ValueChanged<ScheduledNotificationRecord> onEdit;
  final ValueChanged<ScheduledNotificationRecord> onCancel;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: EdgeInsets.zero,
      initiallyExpanded: false,
      leading: Icon(
        Icons.notifications_none_outlined,
        size: 20,
        color: Theme.of(context).colorScheme.primary,
      ),
      title: Text(
        'Notificações',
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
      ),
      children: <Widget>[
        const SizedBox(height: 10),
        if (notifications.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              'Nenhuma notificação vinculada a esta data.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          )
        else
          for (final record in notifications)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.alarm_on_outlined),
              title: Text(notificationRecordTitle(record, notes)),
              subtitle: Text(
                record.body.trim().isEmpty
                    ? formatLocalDateTime(record.scheduledForUtc)
                    : '${formatLocalDateTime(record.scheduledForUtc)}\n${record.body.trim()}',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  TextButton.icon(
                    onPressed: () => onEdit(record),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Editar'),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: () => onCancel(record),
                    icon: const Icon(Icons.notifications_off_outlined),
                    tooltip: 'Cancelar notificação',
                  ),
                ],
              ),
              onTap: () => onEdit(record),
            ),
      ],
    );
  }
}

final class _RevisionList extends StatelessWidget {
  const _RevisionList({required this.revisions, required this.onRestore});

  final List<NoteEditRevision> revisions;
  final ValueChanged<NoteEditRevision> onRestore;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: EdgeInsets.zero,
      initiallyExpanded: false,
      leading: Icon(
        Icons.restore_outlined,
        size: 20,
        color: Theme.of(context).colorScheme.primary,
      ),
      title: Text(
        'Histórico de autosave',
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
      ),
      children: <Widget>[
        const SizedBox(height: 10),
        if (revisions.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              'Edições de nota e notificações aparecerão aqui automaticamente.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          )
        else
          for (final revision in revisions.take(50))
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                revision.kind == NoteEditRevisionKind.notification
                    ? Icons.notifications_none_outlined
                    : Icons.history_outlined,
              ),
              title: Text(revision.noteTitle),
              subtitle: Text(
                '${formatLocalDateTime(revision.savedAtUtc)} · '
                '${_revisionPreview(revision.body)}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: revision.restorable
                  ? TextButton.icon(
                      onPressed: () => onRestore(revision),
                      icon: const Icon(Icons.restore_outlined),
                      label: const Text('Restaurar'),
                    )
                  : const StatusPill(
                      icon: Icons.receipt_long_outlined,
                      label: 'Log',
                    ),
            ),
      ],
    );
  }
}

String _revisionPreview(String body) {
  final compact = body.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (compact.isEmpty) {
    return 'vazio';
  }
  return compact.length <= 96 ? compact : '${compact.substring(0, 96)}...';
}
