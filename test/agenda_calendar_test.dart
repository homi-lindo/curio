import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/ui/agenda_calendar.dart';

void main() {
  testWidgets('agenda calendar renders years through 2035 and selects days', (
    tester,
  ) async {
    var selected = DateTime(2026, 5, 21);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AgendaCalendar(
              selectedDate: selected,
              now: DateTime(2026, 5, 21),
              taskCounts: <DateTime, int>{DateTime(2026, 5, 22): 2},
              onDateSelected: (value) => selected = value,
            ),
          ),
        ),
      ),
    );

    expect(find.text('2026'), findsOneWidget);
    expect(find.text('2035'), findsOneWidget);
    expect(find.text('Mai'), findsOneWidget);
    expect(find.text('21'), findsOneWidget);
    expect(find.text('2'), findsWidgets);

    final day22 = find.byKey(
      ValueKey<String>('agenda-day-${DateTime(2026, 5, 22).toIso8601String()}'),
    );
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -280),
    );
    await tester.pump();
    await tester.tap(day22);
    await tester.pump();

    expect(selected, DateTime(2026, 5, 22));
  });
}
