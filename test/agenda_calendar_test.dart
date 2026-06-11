import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/ui/agenda_calendar.dart';

void main() {
  testWidgets('agenda calendar shows one inline year and selects days', (
    tester,
  ) async {
    var selected = DateTime(2026, 5, 21);

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            return Scaffold(
              body: SingleChildScrollView(
                child: AgendaCalendar(
                  selectedDate: selected,
                  now: DateTime(2026, 5, 21),
                  dayCounts: <DateTime, int>{DateTime(2026, 5, 22): 2},
                  onDateSelected: (value) => setState(() => selected = value),
                ),
              ),
            );
          },
        ),
      ),
    );

    expect(find.text('2026'), findsOneWidget);
    expect(find.text('2035'), findsNothing);
    expect(find.text('Mai'), findsOneWidget);
    expect(find.text('21'), findsOneWidget);
    expect(find.text('2'), findsWidgets);
    expect(find.byTooltip('Editar dia'), findsNothing);
    expect(find.byTooltip('Próximo ano'), findsOneWidget);

    await tester.tap(find.byTooltip('Próximo ano'));
    await tester.pump();

    expect(selected, DateTime(2027, 5, 21));

    final day22 = find.byKey(
      ValueKey<String>('agenda-day-${DateTime(2027, 5, 22).toIso8601String()}'),
    );
    await tester.tap(day22);
    await tester.pump();

    expect(selected, DateTime(2027, 5, 22));
  });

  testWidgets('dias do calendário expõem semântica completa para leitores', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AgendaCalendar(
              selectedDate: DateTime(2026, 5, 21),
              now: DateTime(2026, 5, 21),
              dayCounts: <DateTime, int>{DateTime(2026, 5, 22): 2},
              onDateSelected: (_) {},
            ),
          ),
        ),
      ),
    );

    // O dia com itens anuncia a data completa e a contagem, não só "22".
    expect(
      find.bySemanticsLabel('22 de Mai de 2026, 2 item(ns)'),
      findsOneWidget,
    );
    // Um dia comum anuncia a data completa.
    expect(find.bySemanticsLabel('21 de Mai de 2026'), findsOneWidget);

    handle.dispose();
  });
}
