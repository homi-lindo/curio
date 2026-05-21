import 'package:lume_core/domain/reminder.dart';

final class NotificationTimeZoneAudit {
  const NotificationTimeZoneAudit();

  List<ScheduledNotificationRecord> driftedRecords({
    required Iterable<ScheduledNotificationRecord> records,
    required String currentTimeZone,
  }) {
    return records
        .where(
          (record) =>
              record.scheduledTimeZone.isNotEmpty &&
              record.scheduledTimeZone != currentTimeZone,
        )
        .toList(growable: false);
  }
}
