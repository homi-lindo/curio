// O fake precisa se comportar como o serviço real no que importa para os
// fluxos: mesma derivação de ID estável, ocorrência futura calculada pelo
// OccurrenceCalculator real, pending() refletindo agendados e cancel()
// removendo.
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/domain/occurrence_calculator.dart';
import 'package:lume/services/testing/fake_notification_gateway.dart';
import 'package:lume_core/domain/reminder.dart';

void main() {
  test('agenda one-shot futuro com ID estável e expõe em pending', () async {
    final gateway = FakeNotificationGateway();
    await gateway.initialize();

    final instant = DateTime.now().toUtc().add(const Duration(hours: 2));
    final intent = ReminderIntent.oneShot(
      id: 'reminder-fake-1',
      ownerId: 'note-1',
      ownerType: ReminderOwnerType.note,
      instantUtc: instant,
      updatedAtUtc: DateTime.now().toUtc(),
      timeZone: gateway.localTimeZoneId,
      title: 'Título',
      body: 'Corpo',
    );

    final result = await gateway.scheduleReminder(
      intent: intent,
      deviceId: 'device-teste',
      title: 'Título',
      body: 'Corpo',
    );

    expect(result, isNotNull);
    expect(
      result!.record.id,
      OccurrenceCalculator.stableNotificationId(
        deviceId: 'device-teste',
        reminderIntentId: intent.id,
        occurrenceKey: result.plan.occurrenceKey,
      ),
    );
    expect(gateway.scheduled, hasLength(1));

    final pending = await gateway.pending();
    expect(pending.single.title, 'Título');

    await gateway.cancel(result.record.id);
    expect(gateway.scheduled, isEmpty);
    expect(gateway.canceledIds, contains(result.record.id));
  });

  test('one-shot no passado não agenda (sem próxima ocorrência)', () async {
    final gateway = FakeNotificationGateway();
    await gateway.initialize();

    final result = await gateway.scheduleReminder(
      intent: ReminderIntent.oneShot(
        id: 'reminder-passado',
        ownerId: 'note-1',
        ownerType: ReminderOwnerType.note,
        instantUtc: DateTime.now().toUtc().subtract(const Duration(days: 1)),
        updatedAtUtc: DateTime.now().toUtc(),
        timeZone: gateway.localTimeZoneId,
      ),
      deviceId: 'device-teste',
      title: 'Tarde demais',
      body: '',
    );

    expect(result, isNull);
    expect(gateway.scheduled, isEmpty);
  });

  test('reagendar o mesmo lembrete substitui o registro', () async {
    final gateway = FakeNotificationGateway();
    await gateway.initialize();

    final intent = ReminderIntent.oneShot(
      id: 'reminder-repetido',
      ownerId: 'note-1',
      ownerType: ReminderOwnerType.note,
      instantUtc: DateTime.now().toUtc().add(const Duration(hours: 1)),
      updatedAtUtc: DateTime.now().toUtc(),
      timeZone: gateway.localTimeZoneId,
    );

    await gateway.scheduleReminder(
      intent: intent,
      deviceId: 'device-teste',
      title: 'Primeira versão',
      body: '',
    );
    await gateway.scheduleReminder(
      intent: intent,
      deviceId: 'device-teste',
      title: 'Versão atualizada',
      body: '',
    );

    expect(gateway.scheduled, hasLength(1));
    expect(gateway.scheduled.single.title, 'Versão atualizada');
  });
}
