import 'package:flutter/material.dart';

import 'task_view_helpers.dart';

final class AgendaCalendar extends StatelessWidget {
  const AgendaCalendar({
    super.key,
    required this.selectedDate,
    required this.taskCounts,
    required this.onDateSelected,
    required this.onAddTaskForDate,
    required this.onEditDate,
    this.onVisibleDateChanged,
    this.throughYear = agendaThroughYear,
    this.now,
  });

  final DateTime selectedDate;
  final Map<DateTime, int> taskCounts;
  final ValueChanged<DateTime> onDateSelected;
  final ValueChanged<DateTime> onAddTaskForDate;
  final ValueChanged<DateTime> onEditDate;
  final ValueChanged<DateTime>? onVisibleDateChanged;
  final int throughYear;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = dateOnly(selectedDate);
    final years = agendaYears(now: now, throughYear: throughYear);
    final months = List<int>.generate(12, (index) => index + 1);
    final dayCount = daysInMonth(selected.year, selected.month);
    final leadingBlanks = DateTime(selected.year, selected.month).weekday - 1;
    final totalCells = leadingBlanks + dayCount;
    final navigate = onVisibleDateChanged ?? onDateSelected;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final dayExtent = 58 + ((textScale - 1) * 30).clamp(0, 42).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(
              Icons.calendar_today_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                formatLocalDate(selected),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final year in years)
              ChoiceChip(
                label: Text(year.toString()),
                selected: selected.year == year,
                onSelected: (_) => navigate(
                  sameDayOrLastValidDate(
                    year: year,
                    month: selected.month,
                    preferredDay: selected.day,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final month in months)
              ChoiceChip(
                label: Text(monthLabel(month)),
                selected: selected.month == month,
                onSelected: (_) => navigate(
                  sameDayOrLastValidDate(
                    year: selected.year,
                    month: month,
                    preferredDay: selected.day,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            for (final label in weekdayLabels)
              Expanded(
                child: Center(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            mainAxisExtent: dayExtent,
          ),
          itemCount: totalCells,
          itemBuilder: (context, index) {
            if (index < leadingBlanks) {
              return const SizedBox.shrink();
            }
            final day = index - leadingBlanks + 1;
            final date = DateTime(selected.year, selected.month, day);
            final selectedDay = isSameDate(date, selected);
            final count = taskCounts[date] ?? 0;
            return _CalendarDayButton(
              key: ValueKey<String>('agenda-day-${date.toIso8601String()}'),
              date: date,
              selected: selectedDay,
              taskCount: count,
              onTap: () => onDateSelected(date),
              onAdd: () => onAddTaskForDate(date),
              onEdit: () => onEditDate(date),
            );
          },
        ),
      ],
    );
  }
}

final class _CalendarDayButton extends StatelessWidget {
  const _CalendarDayButton({
    super.key,
    required this.date,
    required this.selected,
    required this.taskCount,
    required this.onTap,
    required this.onAdd,
    required this.onEdit,
  });

  final DateTime date;
  final bool selected;
  final int taskCount;
  final VoidCallback onTap;
  final VoidCallback onAdd;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = selected ? scheme.onPrimary : scheme.onSurface;
    return Material(
      color: selected ? scheme.primary : scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(
                    date.day.toString(),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (taskCount > 0) ...<Widget>[
                    const SizedBox(width: 4),
                    Text(
                      taskCount.toString(),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: selected ? scheme.onPrimary : scheme.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ],
              ),
              if (selected) ...<Widget>[
                const SizedBox(height: 2),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    _CalendarDayAction(
                      icon: Icons.edit_outlined,
                      tooltip: 'Editar dia',
                      selected: selected,
                      onPressed: onEdit,
                    ),
                    const SizedBox(width: 2),
                    _CalendarDayAction(
                      icon: Icons.add_outlined,
                      tooltip: 'Adicionar no dia',
                      selected: selected,
                      onPressed: onAdd,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

final class _CalendarDayAction extends StatelessWidget {
  const _CalendarDayAction({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: 15),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 24, height: 22),
      style: IconButton.styleFrom(
        foregroundColor: selected
            ? Theme.of(context).colorScheme.onPrimary
            : null,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

String monthLabel(int month) {
  return const <String>[
    'Jan',
    'Fev',
    'Mar',
    'Abr',
    'Mai',
    'Jun',
    'Jul',
    'Ago',
    'Set',
    'Out',
    'Nov',
    'Dez',
  ][month - 1];
}

const weekdayLabels = <String>['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];
