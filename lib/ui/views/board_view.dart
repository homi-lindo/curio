import 'package:flutter/material.dart';
import 'package:lume_core/domain/app_snapshot.dart';
import 'package:lume_core/domain/reminder.dart';

import '../agenda_calendar.dart';
import '../task_view_helpers.dart';
import '../widgets/page_frame.dart';
import '../widgets/status_pill.dart';
import '../widgets/surface.dart';

final class BoardView extends StatelessWidget {
  const BoardView({
    super.key,
    required this.notes,
    required this.scheduledNotifications,
    required this.visibleMonth,
    required this.onOpenDay,
    required this.onPreviousMonth,
    required this.onNextMonth,
  });

  final List<NoteItem> notes;
  final List<ScheduledNotificationRecord> scheduledNotifications;
  final DateTime visibleMonth;
  final ValueChanged<DateTime> onOpenDay;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;

  @override
  Widget build(BuildContext context) {
    final month = DateTime(visibleMonth.year, visibleMonth.month);
    final digests = _dayDigests(
      notes: notes,
      notifications: scheduledNotifications,
      month: month,
    );

    return PageFrame(
      title: 'Quadro',
      subtitle: '${monthLabel(month.month)} ${month.year}',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            onPressed: onPreviousMonth,
            icon: const Icon(Icons.chevron_left_outlined),
            tooltip: 'Mês anterior',
          ),
          Text(
            '${monthLabel(month.month)} ${month.year}',
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          IconButton(
            onPressed: onNextMonth,
            icon: const Icon(Icons.chevron_right_outlined),
            tooltip: 'Próximo mês',
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 1060
              ? 4
              : constraints.maxWidth >= 760
              ? 3
              : constraints.maxWidth >= 520
              ? 2
              : 1;
          if (digests.isEmpty) {
            return Surface(
              child: Text(
                'Nenhum dia com notas ou alertas neste mês.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            );
          }

          return GridView.builder(
            itemCount: digests.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: columns == 1 ? 4.2 : 2.05,
            ),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemBuilder: (context, index) {
              final digest = digests[index];
              return _DayBoardCard(
                digest: digest,
                onTap: () => onOpenDay(digest.date),
              );
            },
          );
        },
      ),
    );
  }
}

final class _DayDigest {
  const _DayDigest({
    required this.date,
    required this.notes,
    required this.notifications,
  });

  final DateTime date;
  final List<NoteItem> notes;
  final List<ScheduledNotificationRecord> notifications;

  int get alertCount => notifications.length;

  int get count => notes.length + alertCount;
}

List<_DayDigest> _dayDigests({
  required List<NoteItem> notes,
  required List<ScheduledNotificationRecord> notifications,
  required DateTime month,
}) {
  final dates = <DateTime>{};

  final notesByDate = <DateTime, List<NoteItem>>{};
  for (final note in notes) {
    final date = dailyNoteDate(note);
    if (date == null || !_isSameMonth(date, month)) {
      continue;
    }
    dates.add(date);
    notesByDate.putIfAbsent(date, () => <NoteItem>[]).add(note);
  }

  final notificationsByDate = <DateTime, List<ScheduledNotificationRecord>>{};
  for (final notification in notifications) {
    final date = dateOnly(notification.scheduledForUtc);
    if (!_isSameMonth(date, month)) {
      continue;
    }
    dates.add(date);
    notificationsByDate
        .putIfAbsent(date, () => <ScheduledNotificationRecord>[])
        .add(notification);
  }

  final sortedDates = dates.toList()..sort();
  return <_DayDigest>[
    for (final date in sortedDates)
      _DayDigest(
        date: date,
        notes: notesByDate[date] ?? const <NoteItem>[],
        notifications:
            notificationsByDate[date] ?? const <ScheduledNotificationRecord>[],
      ),
  ];
}

bool _isSameMonth(DateTime date, DateTime month) {
  return date.year == month.year && date.month == month.month;
}

final class _DayBoardCard extends StatelessWidget {
  const _DayBoardCard({required this.digest, required this.onTap});

  final _DayDigest digest;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        formatLocalDate(digest.date),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    StatusPill(
                      icon: Icons.edit_notifications_outlined,
                      label: digest.count.toString(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _CardMetricLine('Notas', digest.notes.length.toString()),
                _CardMetricLine('Alertas', digest.alertCount.toString()),
                const Spacer(),
                Align(
                  alignment: Alignment.bottomRight,
                  child: Text(
                    'Abrir em Notas',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class _CardMetricLine extends StatelessWidget {
  const _CardMetricLine(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 68,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}
