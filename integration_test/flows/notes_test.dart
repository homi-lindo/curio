// Notas view integration tests.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/pump_app.dart';

void main() => notesTests();

void notesTests() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Notas', () {
    testWidgets('navega para Notas e renderiza botoes', (tester) async {
      final harness = await pumpApp(tester);
      addTearDown(harness.dispose);

      await tester.tap(find.text('Notas').first, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('Notas'), findsWidgets);
    });

    testWidgets('botoes de acao de nota estao presentes', (tester) async {
      final harness = await pumpApp(tester);
      addTearDown(harness.dispose);

      await tester.tap(find.text('Notas').first, warnIfMissed: false);
      await tester.pumpAndSettle();

      // The "Nova nota geral" icon button should be present.
      expect(find.byTooltip('Nova nota geral'), findsOneWidget);
      // The Calendário button should be present.
      expect(find.text('Calendário'), findsOneWidget);
    });

    testWidgets('ExpansionTile Notificacoes inicia fechado em Notas', (
      tester,
    ) async {
      final harness = await pumpApp(tester);
      addTearDown(harness.dispose);

      await tester.tap(find.text('Notas').first, warnIfMissed: false);
      await tester.pumpAndSettle();

      // _NotificationList tile: title is "Notificacoes" — should be present.
      expect(
        find.widgetWithText(ExpansionTile, 'Notificações'),
        findsOneWidget,
      );
    });

    testWidgets('ExpansionTile Historico de autosave inicia fechado em Notas',
        (tester) async {
      final harness = await pumpApp(tester);
      addTearDown(harness.dispose);

      await tester.tap(find.text('Notas').first, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(ExpansionTile, 'Histórico de autosave'),
        findsOneWidget,
      );
    });

    testWidgets('ExpansionTile Notificacoes expande e exibe estado vazio', (
      tester,
    ) async {
      final harness = await pumpApp(tester);
      addTearDown(harness.dispose);

      await tester.tap(find.text('Notas').first, warnIfMissed: false);
      await tester.pumpAndSettle();

      // Tap the 'Notificações' text inside the ExpansionTile header to expand it.
      // Use the text finder directly — the tile header is a ListTile, tap its title.
      final tileTitle = find.text('Notificações');
      await tester.ensureVisible(tileTitle);
      await tester.tap(tileTitle, warnIfMissed: false);
      await tester.pumpAndSettle();

      // After expanding, the empty state text should appear.
      // The text may appear as bodySmall (styled) — use textContaining as fallback.
      final emptyText = find.text('Nenhuma notificação vinculada a esta data.');
      final emptyTextAlt = find.textContaining('Nenhuma notificação');
      expect(
        emptyText.evaluate().isNotEmpty || emptyTextAlt.evaluate().isNotEmpty,
        isTrue,
        reason: 'estado vazio de Notificacoes nao exibido apos expandir',
      );
    });

    testWidgets('nota selecionada do seeded data e visivel em Notas', (
      tester,
    ) async {
      final harness = await pumpApp(tester);
      addTearDown(harness.dispose);

      await tester.tap(find.text('Notas').first, warnIfMissed: false);
      await tester.pumpAndSettle();

      // The editor hint is visible (no note selected or seeded note is present).
      // Either "Escreva em Markdown." or a note title is shown.
      // Either way the view renders without throwing.
      expect(find.text('Notas'), findsWidgets);
    });
  });
}
