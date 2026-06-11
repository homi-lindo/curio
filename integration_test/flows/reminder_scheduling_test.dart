// Fluxo de agendamento com gateway fake: diferente dos demais flows (que usam
// o NotificationService real e viram no-op fora do dispositivo), aqui o
// FakeNotificationGateway registra cada agendamento — o teste afirma que o
// fluxo de UI realmente agendou e cancelou, em qualquer plataforma.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lume/services/testing/fake_notification_gateway.dart';

import '../harness/pump_app.dart';

void main() => reminderSchedulingTests();

void reminderSchedulingTests() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Agendamento com gateway fake', () {
    testWidgets('criar notificação pela UI agenda no gateway', (tester) async {
      final gateway = FakeNotificationGateway();
      final harness = await pumpApp(tester, notifications: gateway);
      addTearDown(harness.dispose);

      expect(gateway.initialized, isTrue);

      final createNotification = find.widgetWithText(
        FilledButton,
        'Nova notificação',
      );
      await tester.ensureVisible(createNotification);
      await tester.tap(createNotification, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('Nome da notificação'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Nome da notificação'),
        'Lembrete agendado de verdade',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Mensagem'),
        'corpo do lembrete',
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithText(FilledButton, 'Salvar').last,
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(gateway.scheduled, hasLength(1));
      final record = gateway.scheduled.single;
      expect(record.title, 'Lembrete agendado de verdade');
      expect(
        record.scheduledForUtc.isAfter(DateTime.now().toUtc()),
        isTrue,
        reason: 'a ocorrência calculada deve estar no futuro',
      );

      final snapshot = await harness.store.load();
      expect(
        snapshot.scheduledNotifications.map((item) => item.id),
        contains(record.id),
        reason: 'o registro persistido usa o mesmo ID estável do gateway',
      );

      final pending = await gateway.pending();
      expect(
        pending.map((request) => request.title),
        contains('Lembrete agendado de verdade'),
      );
    });
  });
}
