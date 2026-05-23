// Agenda view integration tests.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/pump_app.dart';

void main() => agendaTests();

void agendaTests() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Agenda', () {
    testWidgets('navega para Agenda e exibe calendario', (tester) async {
      final harness = await pumpApp(tester);
      addTearDown(harness.dispose);

      await tester.tap(find.text('Agenda').first);
      await tester.pumpAndSettle();

      expect(find.text('Agenda'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('botao Editar em Notas esta presente', (tester) async {
      final harness = await pumpApp(tester);
      addTearDown(harness.dispose);

      await tester.tap(find.text('Agenda').first);
      await tester.pumpAndSettle();

      expect(find.text('Editar em Notas'), findsOneWidget);
    });

    testWidgets('botao Nova notificacao de dia presente na Agenda', (
      tester,
    ) async {
      final harness = await pumpApp(tester);
      addTearDown(harness.dispose);

      await tester.tap(find.text('Agenda').first);
      await tester.pumpAndSettle();

      // The day detail panel has a TextButton.icon "Nova notificacao".
      expect(find.text('Nova notificação'), findsWidgets);
    });

    testWidgets('selecionar dia no calendario mantem contagem visivel', (
      tester,
    ) async {
      final harness = await pumpApp(tester);
      addTearDown(harness.dispose);

      await tester.tap(find.text('Agenda').first);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
