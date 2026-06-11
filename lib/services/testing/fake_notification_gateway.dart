import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:lume_core/domain/reminder.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../domain/occurrence_calculator.dart';
import '../notification_service.dart';

/// Implementação de [NotificationGateway] para testes: calcula ocorrências e
/// IDs com o [OccurrenceCalculator] real, mas registra agendamentos e
/// cancelamentos em memória em vez de tocar o plugin nativo. Permite que os
/// fluxos de teste afirmem que um lembrete foi de fato agendado — coisa que o
/// no-op do runner esconderia.
final class FakeNotificationGateway implements NotificationGateway {
  FakeNotificationGateway({
    this.timeZoneId = 'America/Sao_Paulo',
    NotificationPermissionState? permissionState,
  }) : permissionState =
           permissionState ??
           const NotificationPermissionState(
             notificationsGranted: true,
             exactAlarmsGranted: true,
           );

  final String timeZoneId;
  NotificationPermissionState permissionState;

  final List<ScheduledNotificationRecord> scheduled =
      <ScheduledNotificationRecord>[];
  final List<int> canceledIds = <int>[];
  bool initialized = false;

  final OccurrenceCalculator _calculator = const OccurrenceCalculator();

  @override
  late final String localTimeZoneId = timeZoneId;

  tz.Location get _location {
    tzdata.initializeTimeZones();
    return tz.getLocation(timeZoneId);
  }

  @override
  Future<void> initialize({
    void Function(String? payload)? onNotificationSelected,
  }) async {
    tzdata.initializeTimeZones();
    initialized = true;
  }

  @override
  Future<NotificationAppLaunchDetails?> getLaunchDetails() async => null;

  @override
  Future<NotificationPermissionState> requestPermissions() async =>
      permissionState;

  @override
  Future<NotificationPermissionState> currentPermissionState() async =>
      permissionState;

  @override
  Future<NotificationPermissionState> requestMissingSchedulePermissions({
    NotificationPermissionState? current,
  }) async => permissionState;

  @override
  Future<ScheduleResult?> scheduleReminder({
    required ReminderIntent intent,
    required String deviceId,
    required String title,
    required String body,
    tz.TZDateTime? now,
  }) async {
    final location = _location;
    final plan = _calculator.nextOccurrence(
      intent,
      location: location,
      from: now ?? tz.TZDateTime.now(location),
    );
    if (plan == null) {
      return null;
    }

    final notificationId = OccurrenceCalculator.stableNotificationId(
      deviceId: deviceId,
      reminderIntentId: intent.id,
      occurrenceKey: plan.occurrenceKey,
    );
    final record = ScheduledNotificationRecord(
      id: notificationId,
      deviceId: deviceId,
      reminderIntentId: intent.id,
      ownerId: intent.ownerId,
      ownerType: intent.ownerType,
      occurrenceKey: plan.occurrenceKey,
      scheduledForUtc: plan.scheduledUtc,
      payload: 'fake://reminder/${intent.id}',
      title: title,
      body: body,
      scheduledTimeZone: timeZoneId,
    );
    scheduled
      ..removeWhere((existing) => existing.id == record.id)
      ..add(record);

    return ScheduleResult(
      plan: plan,
      record: record,
      matchDateTimeComponents: switch (intent.kind) {
        ScheduleKind.oneShot => null,
        ScheduleKind.daily => DateTimeComponents.time,
        ScheduleKind.weekly => DateTimeComponents.dayOfWeekAndTime,
      },
      permissionState: permissionState,
      androidScheduleMode: androidScheduleModeForExactPermission(
        permissionState.exactAlarmsGranted,
      ),
    );
  }

  @override
  Future<void> cancel(int notificationId) async {
    canceledIds.add(notificationId);
    scheduled.removeWhere((record) => record.id == notificationId);
  }

  @override
  Future<List<PendingNotificationRequest>> pending() async {
    return <PendingNotificationRequest>[
      for (final record in scheduled)
        PendingNotificationRequest(
          record.id,
          record.title,
          record.body,
          record.payload,
        ),
    ];
  }
}
