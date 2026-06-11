import 'package:flutter/material.dart';

import 'task_view_helpers.dart';

final class AgendaCalendar extends StatelessWidget {
  const AgendaCalendar({
    super.key,
    required this.selectedDate,
    required this.dayCounts,
    required this.onDateSelected,
    this.onEditDate,
    this.onVisibleDateChanged,
    this.throughYear = agendaThroughYear,
    this.now,
  });

  final DateTime selectedDate;
  final Map<DateTime, int> dayCounts;
  final ValueChanged<DateTime> onDateSelected;
  final ValueChanged<DateTime>? onEditDate;
  final ValueChanged<DateTime>? onVisibleDateChanged;
  final int throughYear;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = dateOnly(selectedDate);
    final months = List<int>.generate(12, (index) => index + 1);
    final dayCount = daysInMonth(selected.year, selected.month);
    final leadingBlanks = DateTime(selected.year, selected.month).weekday - 1;
    final totalCells = leadingBlanks + dayCount;
    final navigate = onVisibleDateChanged ?? onDateSelected;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final dayExtent = 50 + ((textScale - 1) * 28).clamp(0, 40).toDouble();

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
            IconButton(
              onPressed: () => navigate(
                sameDayOrLastValidDate(
                  year: selected.year - 1,
                  month: selected.month,
                  preferredDay: selected.day,
                ),
              ),
              icon: const Icon(Icons.chevron_left_outlined),
              tooltip: 'Ano anterior',
            ),
            Text(
              selected.year.toString(),
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            IconButton(
              onPressed: () => navigate(
                sameDayOrLastValidDate(
                  year: selected.year + 1,
                  month: selected.month,
                  preferredDay: selected.day,
                ),
              ),
              icon: const Icon(Icons.chevron_right_outlined),
              tooltip: 'Próximo ano',
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
            final count = dayCounts[date] ?? 0;
            return _CalendarDayButton(
              key: ValueKey<String>('agenda-day-${date.toIso8601String()}'),
              date: date,
              selected: selectedDay,
              entryCount: count,
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
    required this.entryCount,
    required this.onTap,
  });

  final DateTime date;
  final bool selected;
  final int entryCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = selected ? scheme.onPrimary : scheme.onSurface;
    // Sem isto o leitor de tela anuncia só o número do dia (e o contador,
    // sem contexto). A label descreve a célula inteira; excludeSemantics
    // evita o anúncio duplicado dos Texts internos.
    return Semantics(
      button: true,
      selected: selected,
      excludeSemantics: true,
      label:
          '${date.day} de ${monthLabel(date.month)} de ${date.year}'
          '${entryCount > 0 ? ', $entryCount item(ns)' : ''}',
      child: Material(
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
                    if (entryCount > 0) ...<Widget>[
                      const SizedBox(width: 4),
                      Text(
                        entryCount.toString(),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: selected ? scheme.onPrimary : scheme.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
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
