import 'package:flutter/material.dart';
import 'package:lume_core/domain/app_snapshot.dart';
import 'package:lume_core/domain/reminder.dart';

import 'task_view_helpers.dart';
import 'widgets/section_header.dart';

// ---------------------------------------------------------------------------
// Domain helpers
// ---------------------------------------------------------------------------

DateTime defaultNotificationLocalForDate(DateTime date) {
  final localDate = dateOnly(date);
  final now = DateTime.now();
  final nextHour = now.add(const Duration(hours: 1));
  if (isSameDate(localDate, now) && isSameDate(localDate, nextHour)) {
    return DateTime(
      localDate.year,
      localDate.month,
      localDate.day,
      nextHour.hour,
      nextHour.minute,
    );
  }
  return DateTime(localDate.year, localDate.month, localDate.day, 9);
}

String notificationTitleFromNote(NoteItem note) {
  final heading = RegExp(
    r'^\s{0,3}#{1,6}\s+(.+)$',
    multiLine: true,
  ).firstMatch(note.body);
  final title = heading?.group(1)?.trim();
  if (title != null && title.isNotEmpty) {
    return cleanNotificationText(title);
  }

  final line = RegExp(r'^\s*(?:[-*]\s*)?(.+?)\s*$', multiLine: true)
      .allMatches(note.body)
      .map((match) => match.group(1)?.trim() ?? '')
      .where((value) => value.isNotEmpty)
      .firstOrNull;
  if (line != null && line.isNotEmpty) {
    return cleanNotificationText(line);
  }

  return note.title;
}

String notificationBodyFromNote(NoteItem note) {
  final compact = note.body
      .replaceAll(RegExp(r'^\s{0,3}#{1,6}\s+', multiLine: true), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (compact.isEmpty) {
    return 'Notificação de ${note.title}';
  }
  return compact.length <= 140 ? compact : '${compact.substring(0, 140)}...';
}

String cleanNotificationText(String value) {
  return value
      .replaceAll(RegExp(r'[*_`>#\[\]]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

// ---------------------------------------------------------------------------
// Data class
// ---------------------------------------------------------------------------

final class NotificationDraft {
  const NotificationDraft({
    required this.title,
    required this.body,
    required this.scheduledAtUtc,
  });

  final String title;
  final String body;
  final DateTime scheduledAtUtc;
}

// ---------------------------------------------------------------------------
// Form widget (shared by dialog and inline editor)
// ---------------------------------------------------------------------------

final class NotificationEditorForm extends StatefulWidget {
  const NotificationEditorForm({
    super.key,
    required this.initialTitle,
    required this.initialBody,
    required this.initialLocal,
    required this.onSubmit,
    required this.onCancel,
    this.submitLabel = 'Salvar',
  });

  final String initialTitle;
  final String initialBody;
  final DateTime initialLocal;
  final ValueChanged<NotificationDraft> onSubmit;
  final VoidCallback onCancel;
  final String submitLabel;

  @override
  State<NotificationEditorForm> createState() => _NotificationEditorFormState();
}

final class _NotificationEditorFormState extends State<NotificationEditorForm> {
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;
  late DateTime _scheduledLocal;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle);
    _bodyController = TextEditingController(text: widget.initialBody);
    _scheduledLocal = widget.initialLocal;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _scheduledLocal,
      firstDate: DateTime(2024),
      lastDate: DateTime(2100),
    );
    if (picked == null) {
      return;
    }
    setState(() {
      _scheduledLocal = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _scheduledLocal.hour,
        _scheduledLocal.minute,
      );
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_scheduledLocal),
    );
    if (picked == null) {
      return;
    }
    setState(() {
      _scheduledLocal = DateTime(
        _scheduledLocal.year,
        _scheduledLocal.month,
        _scheduledLocal.day,
        picked.hour,
        picked.minute,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final title = _titleController.text.trim();
    final scheduledInFuture = _scheduledLocal.toUtc().isAfter(
      DateTime.now().toUtc(),
    );
    final canSubmit = title.isNotEmpty && scheduledInFuture;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        TextField(
          controller: _titleController,
          autofocus: true,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Nome da notificação',
            hintText: 'Texto que aparece no alerta',
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _bodyController,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Mensagem',
            hintText: 'Detalhe opcional',
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: <Widget>[
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.event_outlined),
              label: Text(formatLocalDate(_scheduledLocal)),
            ),
            OutlinedButton.icon(
              onPressed: _pickTime,
              icon: const Icon(Icons.schedule_outlined),
              label: Text(formatLocalTime(_scheduledLocal)),
            ),
            TextButton(
              onPressed: widget.onCancel,
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: canSubmit
                  ? () => widget.onSubmit(
                      NotificationDraft(
                        title: title,
                        body: _bodyController.text,
                        scheduledAtUtc: _scheduledLocal.toUtc(),
                      ),
                    )
                  : null,
              icon: const Icon(Icons.save_outlined),
              label: Text(widget.submitLabel),
            ),
          ],
        ),
        if (!scheduledInFuture) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            'Escolha um horário futuro para salvar a notificação.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colorScheme.error),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Thin dialog wrapper
// ---------------------------------------------------------------------------

Future<NotificationDraft?> showNotificationEditorDialog(
  BuildContext context, {
  NoteItem? note,
  ScheduledNotificationRecord? record,
  DateTime? initialLocal,
}) async {
  final initialTitle = record?.title.trim().isNotEmpty == true
      ? record!.title.trim()
      : note == null
      ? 'Notificação'
      : notificationTitleFromNote(note);

  final initialBody = record?.body.isNotEmpty == true
      ? record!.body
      : note == null
      ? ''
      : notificationBodyFromNote(note);

  final scheduledLocal =
      record?.scheduledForUtc.toLocal() ??
      initialLocal ??
      DateTime.now().add(const Duration(minutes: 15));

  return showDialog<NotificationDraft>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(record == null ? 'Nova notificação' : 'Editar notificação'),
        content: SizedBox(
          width: 460,
          child: NotificationEditorForm(
            initialTitle: initialTitle,
            initialBody: initialBody,
            initialLocal: scheduledLocal,
            submitLabel: 'Salvar',
            onSubmit: (draft) => Navigator.of(context).pop(draft),
            onCancel: () => Navigator.of(context).pop(),
          ),
        ),
        actions: const <Widget>[],
      );
    },
  );
}

// ---------------------------------------------------------------------------
// Inline editor wrapper (card chrome)
// ---------------------------------------------------------------------------

final class InlineNotificationEditor extends StatelessWidget {
  const InlineNotificationEditor({
    super.key,
    required this.initialTitle,
    required this.initialBody,
    required this.initialLocal,
    required this.onSubmit,
    required this.onCancel,
  });

  final String initialTitle;
  final String initialBody;
  final DateTime initialLocal;
  final ValueChanged<NotificationDraft> onSubmit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.28),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SectionHeader(
              icon: Icons.notification_add_outlined,
              title: 'Nova notificação',
            ),
            const SizedBox(height: 12),
            NotificationEditorForm(
              initialTitle: initialTitle,
              initialBody: initialBody,
              initialLocal: initialLocal,
              onSubmit: onSubmit,
              onCancel: onCancel,
            ),
          ],
        ),
      ),
    );
  }
}
