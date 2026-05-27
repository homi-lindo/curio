// Hoje view integration tests.
import 'dart:io';

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
      await _pumpAction(tester);

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

    testWidgets('cria edita e cancela notificacao pela UI', (tester) async {
      final harness = await pumpApp(tester);
      addTearDown(harness.dispose);

      const originalTitle = 'E2E notificação original';
      const originalBody = 'Mensagem original do fluxo E2E';
      const editedTitle = 'E2E notificação editada';
      const editedBody = 'Mensagem editada do fluxo E2E';

      final createNotification = find.widgetWithText(
        FilledButton,
        'Nova notificação',
      );
      await tester.ensureVisible(createNotification);
      await tester.tap(createNotification, warnIfMissed: false);
      await _pumpAction(tester);

      expect(find.text('Nome da notificação'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Nome da notificação'),
        originalTitle,
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Mensagem'),
        originalBody,
      );
      await _pumpAction(tester);

      await tester.tap(
        find.widgetWithText(FilledButton, 'Salvar').last,
        warnIfMissed: false,
      );
      await _pumpAction(tester);

      final createdSnapshot = await harness.store.load();
      expect(createdSnapshot.scheduledNotifications, hasLength(1));
      expect(
        createdSnapshot.scheduledNotifications.single.title,
        originalTitle,
      );
      expect(createdSnapshot.scheduledNotifications.single.body, originalBody);
      if (Platform.isAndroid) {
        final pending = await harness.notifications.pending();
        expect(
          pending.map((request) => request.title),
          contains(originalTitle),
        );
      }
      expect(find.text(originalTitle), findsWidgets);

      await tester.tap(find.text('Notas').first, warnIfMissed: false);
      await _pumpAction(tester);
      expect(find.text('Notas'), findsWidgets);

      final notificationTileTitle = find.text('Notificações').last;
      await tester.ensureVisible(notificationTileTitle);
      await tester.tap(notificationTileTitle, warnIfMissed: false);
      await _pumpAction(tester);

      final editButton = find.widgetWithText(TextButton, 'Editar');
      await tester.ensureVisible(editButton);
      await tester.tap(editButton, warnIfMissed: false);
      await _pumpAction(tester);

      expect(find.text('Editar notificação'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Nome da notificação'),
        editedTitle,
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Mensagem'),
        editedBody,
      );
      await _pumpAction(tester);

      await tester.tap(
        find.widgetWithText(FilledButton, 'Salvar').last,
        warnIfMissed: false,
      );
      await _pumpAction(tester);

      final editedSnapshot = await harness.store.load();
      expect(editedSnapshot.scheduledNotifications, hasLength(1));
      expect(editedSnapshot.scheduledNotifications.single.title, editedTitle);
      expect(editedSnapshot.scheduledNotifications.single.body, editedBody);
      if (Platform.isAndroid) {
        final pending = await harness.notifications.pending();
        expect(pending.map((request) => request.title), contains(editedTitle));
        expect(
          pending.map((request) => request.title),
          isNot(contains(originalTitle)),
        );
      }
      expect(find.text(editedTitle), findsWidgets);

      final cancelButton = find.byTooltip('Cancelar notificação');
      await tester.ensureVisible(cancelButton);
      await tester.tap(cancelButton, warnIfMissed: false);
      await _pumpAction(tester);

      final cancelledSnapshot = await harness.store.load();
      expect(cancelledSnapshot.scheduledNotifications, isEmpty);
      if (Platform.isAndroid) {
        final pending = await harness.notifications.pending();
        expect(
          pending.map((request) => request.title),
          isNot(contains(editedTitle)),
        );
      }
      expect(tester.takeException(), isNull);
    });
  });
}

Future<void> _pumpAction(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}
