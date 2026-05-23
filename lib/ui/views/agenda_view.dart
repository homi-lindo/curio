import 'package:flutter/material.dart';
import 'package:lume_core/domain/app_snapshot.dart';
import 'package:lume_core/domain/reminder.dart';

import '../agenda_calendar.dart';
import '../task_view_helpers.dart';
import '../widgets/notification_record_tile.dart';
import '../widgets/page_frame.dart';
import '../widgets/section_header.dart';
import '../widgets/surface.dart';
import '../widgets/timeline_row.dart';

final class AgendaView extends StatelessWidget {
  const AgendaView({
    super.key,
    required this.notes,
    required this.scheduledNotifications,
    required this.selectedDate,
    required this.onVisibleDateChanged,
    required this.onDateSelected,
    required this.onEditDate,
    required this.onOpenDailyNote,
    required this.onEditNotification,
    required this.onCreateStandaloneNotification,
  });

  final List<NoteItem> notes;
  final List<ScheduledNotificationRecord> scheduledNotifications;
  final DateTime selectedDate;
  final ValueChanged<DateTime> onVisibleDateChanged;
  final ValueChanged<DateTime> onDateSelected;
  final ValueChanged<DateTime> onEditDate;
  final ValueChanged<DateTime> onOpenDailyNote;
  final ValueChanged<ScheduledNotificationRecord> onEditNotification;
  final ValueChanged<DateTime> onCreateStandaloneNotification;

  @override
  Widget build(BuildContext context) {
    final countsByDate = <DateTime, int>{...noteCountsByDate(notes)};
    for (final record in scheduledNotifications) {
      final date = dateOnly(record.scheduledForUtc);
      countsByDate[date] = (countsByDate[date] ?? 0) + 1;
    }
    final selectedNotes = notes
        .where(
          (note) =>
              isSameDate(dailyNoteDate(note) ?? DateTime(1), selectedDate),
        )
        .toList();
    final selectedNotifications =
        scheduledNotifications
            .where((record) => isSameDate(record.scheduledForUtc, selectedDate))
            .toList()
          ..sort(
            (left, right) =>
                left.scheduledForUtc.compareTo(right.scheduledForUtc),
          );

    return PageFrame(
      title: 'Agenda',
      subtitle: 'Calendário de notas e notificações',
      trailing: FilledButton.icon(
        onPressed: () => onOpenDailyNote(selectedDate),
        icon: const Icon(Icons.edit_note_outlined),
        label: const Text('Editar em Notas'),
      ),
      child: Column(
        children: <Widget>[
          Surface(
            child: AgendaCalendar(
              selectedDate: selectedDate,
              dayCounts: countsByDate,
              onVisibleDateChanged: onVisibleDateChanged,
              onDateSelected: onDateSelected,
              onEditDate: onEditDate,
            ),
          ),
          const SizedBox(height: 14),
          Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SectionHeader(
                  icon: Icons.event_available_outlined,
                  title: formatLocalDate(selectedDate),
                  action: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      TextButton.icon(
                        onPressed: () =>
                            onCreateStandaloneNotification(selectedDate),
                        icon: const Icon(Icons.notification_add_outlined),
                        label: const Text('Nova notificação'),
                      ),
                      TextButton.icon(
                        onPressed: () => onOpenDailyNote(selectedDate),
                        icon: const Icon(Icons.article_outlined),
                        label: const Text('Notas'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (selectedNotes.isEmpty && selectedNotifications.isEmpty)
                  Text(
                    'Nenhuma nota ou notificação neste dia.',
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                else ...<Widget>[
                  for (final note in selectedNotes)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.article_outlined),
                      title: Text(note.title),
                      subtitle: Text(formatLocalDateTime(note.updatedAtUtc)),
                      onTap: () => onOpenDailyNote(selectedDate),
                    ),
                  for (
                    var index = 0;
                    index < selectedNotifications.length;
                    index++
                  )
                    TimelineRow(
                      time: formatLocalTime(
                        selectedNotifications[index].scheduledForUtc,
                      ),
                      title: notificationRecordTitle(
                        selectedNotifications[index],
                        notes,
                      ),
                      subtitle: selectedNotifications[index].body,
                      tone: entryTone(index),
                      onTap: () =>
                          onEditNotification(selectedNotifications[index]),
                      actionTooltip: 'Editar notificação',
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
