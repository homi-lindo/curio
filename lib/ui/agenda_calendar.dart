import 'package:flutter/material.dart';

import 'task_view_helpers.dart';

final class AgendaCalendar extends StatelessWidget {
  const AgendaCalendar({
    super.key,
    required this.selectedDate,
    required this.taskCounts,
    required this.onDateSelected,
    this.onVisibleDateChanged,
    this.throughYear = agendaThroughYear,
    this.now,
  });

  final DateTime selectedDate;
  final Map<DateTime, int> taskCounts;
  final ValueChanged<DateTime> onDateSelected;
  final ValueChanged<DateTime>? onVisibleDateChanged;
  final int throughYear;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final selected = dateOnly(selectedDate);
    final years = agendaYears(now: now, throughYear: throughYear);
    final months = List<int>.generate(12, (index) => index + 1);
    final dayCount = daysInMonth(selected.year, selected.month);
    final leadingBlanks = DateTime(selected.year, selected.month).weekday - 1;
    final totalCells = leadingBlanks + dayCount;
    final navigate = onVisibleDateChanged ?? onDateSelected;

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
        const SizedBox(height: 16),
        Row(
          children: <Widget>[
            for (final label in weekdayLabels)
              Expanded(
                child: Center(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: const Color(0xFF706A60),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            childAspectRatio: 1.16,
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
  });

  final DateTime date;
  final bool selected;
  final int taskCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = selected ? Colors.white : const Color(0xFF252525);
    return Material(
      color: selected ? scheme.primary : const Color(0xFFF8F6F1),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                date.day.toString(),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              SizedBox(
                height: 14,
                child: taskCount == 0
                    ? null
                    : Text(
                        taskCount.toString(),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: selected ? Colors.white : scheme.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
            ],
          ),
        ),
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
