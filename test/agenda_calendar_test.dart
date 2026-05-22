import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/ui/agenda_calendar.dart';

void main() {
  testWidgets('agenda calendar renders years through 2035 and selects days', (
    tester,
  ) async {
    var selected = DateTime(2026, 5, 21);
    DateTime? editDate;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            return Scaffold(
              body: SingleChildScrollView(
                child: AgendaCalendar(
                  selectedDate: selected,
                  now: DateTime(2026, 5, 21),
                  taskCounts: <DateTime, int>{DateTime(2026, 5, 22): 2},
                  onDateSelected: (value) => setState(() => selected = value),
                  onEditDate: (value) => editDate = value,
                ),
              ),
            );
          },
        ),
      ),
    );

    expect(find.text('2026'), findsOneWidget);
    expect(find.text('2035'), findsOneWidget);
    expect(find.text('Mai'), findsOneWidget);
    expect(find.text('21'), findsOneWidget);
    expect(find.text('2'), findsWidgets);
    expect(find.byTooltip('Editar dia'), findsOneWidget);
    expect(find.byTooltip('Adicionar no dia'), findsNothing);

    await tester.tap(find.byTooltip('Editar dia'));
    await tester.pump();

    expect(editDate, DateTime(2026, 5, 21));

    final day22 = find.byKey(
      ValueKey<String>('agenda-day-${DateTime(2026, 5, 22).toIso8601String()}'),
    );
    await tester.tap(day22);
    await tester.pump();

    expect(selected, DateTime(2026, 5, 22));
    expect(find.byTooltip('Editar dia'), findsOneWidget);

    await tester.tap(find.byTooltip('Editar dia'));
    await tester.pump();

    expect(editDate, DateTime(2026, 5, 22));
  });
}
