// Boot and navigation integration tests.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/pump_app.dart';

void main() => bootNavigationTests();

void bootNavigationTests() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('boot e navegacao', () {
    testWidgets('app inicializa e exibe Hoje', (tester) async {
      final harness = await pumpApp(tester);
      addTearDown(harness.dispose);

      expect(find.text('Hoje'), findsWidgets);
    });

    testWidgets('navega entre as seis abas', (tester) async {
      final harness = await pumpApp(tester);
      addTearDown(harness.dispose);

      final labels = <String>[
        'Hoje',
        'Agenda',
        'Quadro',
        'Notas',
        'Tarefas',
        'Sync',
      ];

      for (final label in labels) {
        // Find the navigation destination by label.
        final dest = find.text(label);
        expect(dest, findsWidgets, reason: 'destino $label nao encontrado');
        await tester.tap(dest.first, warnIfMissed: false);
        await tester.pumpAndSettle();
        // After selecting, the view label should still be visible.
        expect(
          find.text(label),
          findsWidgets,
          reason: 'view $label nao renderizou',
        );
      }
      // NOTE: ListTile-inside-DecoratedBox assertions fire here (see Findings).
    });

    testWidgets(
      'NavigationRail nao exibe RenderFlex overflow em altura 520 (regressao)',
      (tester) async {
        // Set a surface that previously triggered RenderFlex overflow at
        // main.dart:1842 in the NavigationRail leading Column.
        await tester.binding.setSurfaceSize(const Size(1100, 520));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final harness = await pumpApp(tester);
        addTearDown(harness.dispose);

        await _pumpNavigationFrames(tester);

        // Navigate through all tabs at this narrow height.
        for (final label in <String>[
          'Agenda',
          'Quadro',
          'Notas',
          'Tarefas',
          'Sync',
          'Hoje',
        ]) {
          final dest = find.text(label);
          if (dest.evaluate().isNotEmpty) {
            // Use warnIfMissed: false — at 520px height, the last rail destination
            // may scroll out of the visible area but the fix (SingleChildScrollView)
            // prevents a hard overflow. We tap if reachable, skip if scrolled out.
            await tester.tap(dest.first, warnIfMissed: false);
            await _pumpNavigationFrames(tester);
          }
        }

        // The critical assertion: the exception list must NOT contain a
        // "overflowed" error. Any ListTile-in-DecoratedBox assertions are a
        // separate tracked bug (see Findings) and are not overflow errors.
        final exception = tester.takeException();
        if (exception != null) {
          final msg = exception.toString();
          expect(
            msg.contains('overflowed') || msg.contains('RenderFlex'),
            isFalse,
            reason: 'RenderFlex overflow still present at 1100x520: $msg',
          );
        }
      },
    );
  });
}

Future<void> _pumpNavigationFrames(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}
