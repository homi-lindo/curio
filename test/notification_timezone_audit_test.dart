import 'package:flutter_test/flutter_test.dart';
import 'package:lume/services/notification_timezone_audit.dart';
import 'package:lume_core/domain/reminder.dart';

void main() {
  test(
    'timezone audit returns only records scheduled in another known zone',
    () {
      final now = DateTime.utc(2026, 5, 21, 15);
      final records = <ScheduledNotificationRecord>[
        _record(id: 1, scheduledTimeZone: 'America/Sao_Paulo', now: now),
        _record(id: 2, scheduledTimeZone: 'Europe/London', now: now),
        _record(id: 3, scheduledTimeZone: '', now: now),
      ];

      final drifted = const NotificationTimeZoneAudit().driftedRecords(
        records: records,
        currentTimeZone: 'America/Sao_Paulo',
      );

      expect(drifted.map((record) => record.id), <int>[2]);
    },
  );
}

ScheduledNotificationRecord _record({
  required int id,
  required String scheduledTimeZone,
  required DateTime now,
}) {
  return ScheduledNotificationRecord(
    id: id,
    deviceId: 'lume-test',
    reminderIntentId: 'reminder-$id',
    ownerId: 'task-$id',
    ownerType: ReminderOwnerType.task,
    occurrenceKey: now.toIso8601String(),
    scheduledForUtc: now,
    payload: 'payload-$id',
    scheduledTimeZone: scheduledTimeZone,
  );
}
