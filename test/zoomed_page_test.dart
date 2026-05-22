import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/ui/agenda_calendar.dart';
import 'package:lume/ui/zoomed_page.dart';

void main() {
  for (final scale in <double>[0.2, 1, 2]) {
    testWidgets(
      'zoomed page keeps agenda actions tappable at ${scale * 100}%',
      (tester) async {
        var selected = DateTime(2026, 5, 21);
        DateTime? editDate;

        await tester.pumpWidget(
          MaterialApp(
            home: StatefulBuilder(
              builder: (context, setState) {
                return Scaffold(
                  body: SizedBox(
                    width: 900,
                    height: 700,
                    child: ZoomedPage(
                      scale: scale,
                      child: SingleChildScrollView(
                        child: AgendaCalendar(
                          selectedDate: selected,
                          now: DateTime(2026, 5, 21),
                          taskCounts: const <DateTime, int>{},
                          onDateSelected: (value) {
                            setState(() => selected = value);
                          },
                          onEditDate: (value) => editDate = value,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );

        await tester.ensureVisible(find.byTooltip('Editar dia'));
        await tester.pump();
        await tester.tap(find.byTooltip('Editar dia'));
        await tester.pump();

        expect(editDate, DateTime(2026, 5, 21));
      },
    );
  }

  test('page zoom helpers clamp and label the supported range', () {
    expect(clampPageZoom(0), 0.2);
    expect(clampPageZoom(3), 2);
    expect(pageZoomLabel(0.2), '20%');
    expect(pageZoomLabel(2), '200%');
    expect(stepPageZoom(1, 1), closeTo(1.1, 0.0001));
    expect(stepPageZoom(1, -1), closeTo(0.9, 0.0001));
    expect(stepPageZoom(1.95, 1), 2);
    expect(stepPageZoom(0.25, -1), 0.2);
  });

  testWidgets('zoom interaction surface handles control mouse wheel', (
    tester,
  ) async {
    var zoom = 1.0;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            return ZoomInteractionSurface(
              scale: zoom,
              onScaleChanged: (value) => setState(() => zoom = value),
              child: const SizedBox(width: 300, height: 300),
            );
          },
        ),
      ),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    tester.binding.handlePointerEvent(
      const PointerScrollEvent(
        position: Offset(20, 20),
        scrollDelta: Offset(0, -120),
      ),
    );
    await tester.pump();
    expect(zoom, closeTo(1.1, 0.0001));

    tester.binding.handlePointerEvent(
      const PointerScrollEvent(
        position: Offset(20, 20),
        scrollDelta: Offset(0, 120),
      ),
    );
    await tester.pump();
    expect(zoom, closeTo(1.0, 0.0001));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  });
}
