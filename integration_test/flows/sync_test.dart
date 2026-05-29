// Sync view integration tests.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/pump_app.dart';

void main() => syncTests();

void syncTests() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Sync', () {
    testWidgets('navega para Sync e renderiza controles de servidor', (
      tester,
    ) async {
      final harness = await pumpApp(tester);
      addTearDown(harness.dispose);

      await tester.tap(find.text('Sync').first, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('Sync'), findsWidgets);
      expect(find.text('Sincronizar'), findsOneWidget);
      expect(find.text('Salvar sync'), findsOneWidget);
    });

    testWidgets('campos Servidor e Token estao presentes em Sync', (
      tester,
    ) async {
      final harness = await pumpApp(tester);
      addTearDown(harness.dispose);

      await tester.tap(find.text('Sync').first, warnIfMissed: false);
      await tester.pumpAndSettle();

      // TextField decoration labels appear multiple times (label + floating label).
      expect(find.text('Servidor'), findsWidgets);
      expect(find.text('Token'), findsWidgets);
    });

    testWidgets('salvar sync com URL vazia offline nao lanca excecao', (
      tester,
    ) async {
      final harness = await pumpApp(tester);
      addTearDown(harness.dispose);

      await tester.tap(find.text('Sync').first, warnIfMissed: false);
      await tester.pumpAndSettle();

      // With empty URL, Salvar sync just saves empty settings (offline mode).
      await _tapSyncButton(
        tester,
        find.widgetWithText(OutlinedButton, 'Salvar sync'),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('sincronizar com URL vazia usa OfflineSyncAdapter sem excecao', (
      tester,
    ) async {
      final harness = await pumpApp(tester);
      addTearDown(harness.dispose);

      await tester.tap(find.text('Sync').first, warnIfMissed: false);
      await tester.pumpAndSettle();

      // With empty server URL, tapping Sincronizar triggers OfflineSyncAdapter.
      await _tapSyncButton(
        tester,
        find.widgetWithText(FilledButton, 'Sincronizar'),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('validacao URL com userinfo exibe SnackBar', (tester) async {
      final harness = await pumpApp(tester);
      addTearDown(harness.dispose);

      await tester.tap(find.text('Sync').first, warnIfMissed: false);
      await tester.pumpAndSettle();

      // Find the server URL TextField by its decoration labelText 'Servidor'.
      // The Sync surface shows TextField with labelText 'Servidor' (no hint
      // visible initially). Enter invalid URL.
      final textFields = tester
          .widgetList<TextField>(find.byType(TextField))
          .toList();
      // First TextField on Sync view is the Servidor field.
      if (textFields.isNotEmpty) {
        await tester.enterText(
          find.byType(TextField).first,
          'http://u:p@bad.host',
        );
        await tester.pumpAndSettle();

        await _tapSyncButton(
          tester,
          find.widgetWithText(OutlinedButton, 'Salvar sync'),
        );
        await tester.pumpAndSettle();

        // _runAction catches ArgumentError from validator and shows SnackBar.
        // In debug builds http is allowed but userinfo is always rejected.
        // Expect SnackBar with validation message.
        expect(find.byType(SnackBar), findsOneWidget);
      }
    });

    testWidgets('lembrete criado sem servidor sobrevive a um sync offline', (
      tester,
    ) async {
      final harness = await pumpApp(tester);
      addTearDown(harness.dispose);

      // Boot lands on "Hoje". Create a standalone reminder with NO server
      // configured — proves reminders work fully standalone.
      final novaNotificacao = find.text('Nova notificação');
      await tester.ensureVisible(novaNotificacao);
      await tester.tap(novaNotificacao, warnIfMissed: false);
      await tester.pumpAndSettle();

      // The notification editor dialog: first field is the title.
      await tester.enterText(find.byType(TextField).first, 'Lembrete offline');
      await tester.pumpAndSettle();
      final salvar = find.widgetWithText(FilledButton, 'Salvar');
      await tester.tap(salvar, warnIfMissed: false);
      await tester.pumpAndSettle();

      // The reminder is scheduled locally and listed, no server involved.
      expect(find.text('Lembrete offline'), findsWidgets);

      // Run an offline sync (empty server URL → OfflineSyncAdapter).
      await tester.tap(find.text('Sync').first, warnIfMissed: false);
      await tester.pumpAndSettle();
      await _tapSyncButton(
        tester,
        find.widgetWithText(FilledButton, 'Sincronizar'),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Back on Hoje, the reminder is still there after the offline sync.
      await tester.tap(find.text('Hoje').first, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('Lembrete offline'), findsWidgets);
    });

    testWidgets('Copiar TXT e Restaurar TXT estao presentes em Sync', (
      tester,
    ) async {
      final harness = await pumpApp(tester);
      addTearDown(harness.dispose);

      await tester.tap(find.text('Sync').first, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('Copiar TXT'), findsOneWidget);
      expect(find.text('Restaurar TXT'), findsOneWidget);
    });
  });
}

Future<void> _tapSyncButton(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder, warnIfMissed: false);
}
