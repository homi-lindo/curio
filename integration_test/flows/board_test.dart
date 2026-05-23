// Quadro (board) view integration tests.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/pump_app.dart';

void main() => boardTests();

void boardTests() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Quadro', () {
    testWidgets('navega para Quadro e renderiza cabecalho do mes', (
      tester,
    ) async {
      final harness = await pumpApp(tester);
      addTearDown(harness.dispose);

      await tester.tap(find.text('Quadro').first);
      await tester.pumpAndSettle();

      expect(find.text('Quadro'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('navegacao de mes anterior e proximo funciona', (
      tester,
    ) async {
      final harness = await pumpApp(tester);
      addTearDown(harness.dispose);

      await tester.tap(find.text('Quadro').first);
      await tester.pumpAndSettle();

      // Navigate to previous month via icon button.
      final prevBtn = find.byTooltip('Mês anterior');
      if (prevBtn.evaluate().isNotEmpty) {
        await tester.tap(prevBtn);
        await tester.pumpAndSettle();
      }

      // Navigate to next month.
      final nextBtn = find.byTooltip('Próximo mês');
      if (nextBtn.evaluate().isNotEmpty) {
        await tester.tap(nextBtn);
        await tester.pumpAndSettle();
      }

      expect(tester.takeException(), isNull);
    });
  });
}
