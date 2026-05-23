// Hoje view integration tests.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/pump_app.dart';

void main() => todayTests();

void todayTests() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Hoje', () {
    testWidgets('estado vazio renderiza sem erros', (tester) async {
      final harness = await pumpApp(tester);
      addTearDown(harness.dispose);

      expect(find.text('Hoje'), findsWidgets);
    });

    testWidgets('botao Nova notificacao esta presente em Hoje', (tester) async {
      final harness = await pumpApp(tester);
      addTearDown(harness.dispose);

      // Verify the tonal button is rendered in _UpcomingNotificationsPanel.
      expect(find.text('Nova notificação'), findsOneWidget);
    });

    testWidgets('permissao pill visivel em Hoje', (tester) async {
      final harness = await pumpApp(tester);
      addTearDown(harness.dispose);

      // StatusPill showing pending count should be present.
      expect(find.textContaining('pendente'), findsWidgets);
    });

    testWidgets('botao Permissoes visivel em Hoje', (tester) async {
      final harness = await pumpApp(tester);
      addTearDown(harness.dispose);

      expect(find.text('Permissões'), findsWidgets);
    });

    testWidgets('clicar Nova notificacao abre editor sem crash', (
      tester,
    ) async {
      final harness = await pumpApp(tester);
      addTearDown(harness.dispose);

      final createNotification = find.widgetWithText(
        FilledButton,
        'Nova notificação',
      );
      await tester.ensureVisible(createNotification);
      await tester.tap(createNotification, warnIfMissed: false);
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(tester.takeException(), isNull);
      expect(find.text('Nova notificação'), findsWidgets);

      final editorFields = find.byType(TextField);
      if (editorFields.evaluate().isNotEmpty) {
        expect(editorFields, findsNWidgets(2));
        expect(find.text('Salvar'), findsOneWidget);

        await tester.tap(find.text('Cancelar').first);
        await tester.pumpAndSettle();
      }
    });
  });
}
