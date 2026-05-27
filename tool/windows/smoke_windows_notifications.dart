import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:lume/app_brand.dart';
import 'package:lume/services/notification_service.dart';
import 'package:lume_core/domain/reminder.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!Platform.isWindows) {
    stderr.writeln('Este smoke deve ser executado no Windows.');
    exitCode = 64;
    return;
  }

  final plugin = FlutterLocalNotificationsPlugin();
  final service = NotificationService(plugin: plugin);
  await service.initialize();

  final stamp = DateTime.now();
  final immediateId = 920527;
  final scheduleInstant = stamp.add(const Duration(minutes: 10));
  final scheduleTitle =
      'Curió smoke agendado ${_hhmm(scheduleInstant.toLocal())}';

  await plugin.show(
    id: immediateId,
    title: 'Curió smoke Windows ${_hhmm(stamp)}',
    body: 'Toast imediato do teste local.',
    notificationDetails: const NotificationDetails(
      windows: WindowsNotificationDetails(
        scenario: WindowsNotificationScenario.reminder,
        duration: WindowsNotificationDuration.long,
      ),
    ),
    payload: 'curio://smoke/windows/immediate',
  );

  final result = await service.scheduleReminder(
    intent: ReminderIntent.oneShot(
      id: 'windows-smoke-${stamp.microsecondsSinceEpoch}',
      ownerId: 'windows-smoke-note',
      ownerType: ReminderOwnerType.note,
      instantUtc: scheduleInstant.toUtc(),
      updatedAtUtc: stamp.toUtc(),
      timeZone: service.localTimeZoneId,
    ),
    deviceId: 'windows-smoke-device',
    title: scheduleTitle,
    body: 'Esta notificação é cancelada pelo smoke antes da entrega.',
  );

  if (result == null) {
    throw StateError('O smoke não conseguiu criar o plano de notificação.');
  }

  final pendingAfterSchedule = await service.pending();
  final scheduledId = result.record.id;
  if (!pendingAfterSchedule.any((request) => request.id == scheduledId)) {
    throw StateError(
      'Notificação agendada não apareceu na fila nativa: $scheduledId',
    );
  }

  await service.cancel(scheduledId);
  final pendingAfterCancel = await service.pending();
  if (pendingAfterCancel.any((request) => request.id == scheduledId)) {
    throw StateError(
      'Notificação agendada permaneceu na fila após cancelamento: $scheduledId',
    );
  }

  stdout.writeln('SMOKE_WINDOWS_NOTIFICATION_OK');
  stdout.writeln('AUMID: $appWindowsAppUserModelId');
  stdout.writeln('Toast imediato: $immediateId');
  stdout.writeln('Agendada e cancelada: $scheduledId');

  await Future<void>.delayed(const Duration(seconds: 3));
  exit(0);
}

String _hhmm(DateTime value) {
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
