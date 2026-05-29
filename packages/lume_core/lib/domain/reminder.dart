import 'package:timezone/timezone.dart' as tz;

enum ScheduleKind { oneShot, daily, weekly }

enum ReminderOwnerType { task, note }

final class LocalClockTime {
  const LocalClockTime({required this.hour, required this.minute})
    : assert(hour >= 0 && hour <= 23),
      assert(minute >= 0 && minute <= 59);

  final int hour;
  final int minute;

  String get label {
    final hh = hour.toString().padLeft(2, '0');
    final mm = minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
}

final class ReminderIntent {
  ReminderIntent({
    required this.id,
    required this.ownerId,
    required this.ownerType,
    required this.kind,
    required this.enabled,
    required this.timeZone,
    required this.updatedAtUtc,
    this.instantUtc,
    this.localTime,
    DateTime? anchorLocalDate,
    this.byWeekday,
    this.title = '',
    this.body = '',
  }) : anchorLocalDate = anchorLocalDate == null
           ? null
           : DateTime(
               anchorLocalDate.year,
               anchorLocalDate.month,
               anchorLocalDate.day,
             ) {
    if (kind == ScheduleKind.oneShot) {
      assert(instantUtc != null);
    } else {
      assert(localTime != null);
    }
    if (kind == ScheduleKind.weekly) {
      assert(byWeekday != null && byWeekday! >= 1 && byWeekday! <= 7);
      assert(anchorLocalDate != null);
    }
  }

  factory ReminderIntent.oneShot({
    required String id,
    required String ownerId,
    required ReminderOwnerType ownerType,
    required DateTime instantUtc,
    required DateTime updatedAtUtc,
    bool enabled = true,
    String timeZone = 'UTC',
    String title = '',
    String body = '',
  }) {
    return ReminderIntent(
      id: id,
      ownerId: ownerId,
      ownerType: ownerType,
      kind: ScheduleKind.oneShot,
      enabled: enabled,
      timeZone: timeZone,
      instantUtc: instantUtc.toUtc(),
      updatedAtUtc: updatedAtUtc.toUtc(),
      title: title,
      body: body,
    );
  }

  factory ReminderIntent.daily({
    required String id,
    required String ownerId,
    required ReminderOwnerType ownerType,
    required LocalClockTime localTime,
    required String timeZone,
    required DateTime updatedAtUtc,
    bool enabled = true,
    String title = '',
    String body = '',
  }) {
    return ReminderIntent(
      id: id,
      ownerId: ownerId,
      ownerType: ownerType,
      kind: ScheduleKind.daily,
      enabled: enabled,
      timeZone: timeZone,
      localTime: localTime,
      updatedAtUtc: updatedAtUtc.toUtc(),
      title: title,
      body: body,
    );
  }

  factory ReminderIntent.weekly({
    required String id,
    required String ownerId,
    required ReminderOwnerType ownerType,
    required LocalClockTime localTime,
    required String timeZone,
    required DateTime anchorLocalDate,
    required int byWeekday,
    required DateTime updatedAtUtc,
    bool enabled = true,
    String title = '',
    String body = '',
  }) {
    return ReminderIntent(
      id: id,
      ownerId: ownerId,
      ownerType: ownerType,
      kind: ScheduleKind.weekly,
      enabled: enabled,
      timeZone: timeZone,
      localTime: localTime,
      anchorLocalDate: anchorLocalDate,
      byWeekday: byWeekday,
      updatedAtUtc: updatedAtUtc.toUtc(),
      title: title,
      body: body,
    );
  }

  final String id;
  final String ownerId;
  final ReminderOwnerType ownerType;
  final ScheduleKind kind;
  final bool enabled;
  final String timeZone;
  final DateTime? instantUtc;
  final LocalClockTime? localTime;
  final DateTime? anchorLocalDate;
  final int? byWeekday;
  final DateTime updatedAtUtc;
  final String title;
  final String body;

  factory ReminderIntent.fromJson(Map<String, Object?> json) {
    final localTimeJson = json['localTime'];
    final localTime = localTimeJson is Map
        ? LocalClockTime(
            hour: (localTimeJson['hour'] as num).toInt(),
            minute: (localTimeJson['minute'] as num).toInt(),
          )
        : null;
    final anchor = json['anchorLocalDate'] as String?;
    final instant = json['instantUtc'] as String?;
    return ReminderIntent(
      id: json['id'] as String,
      ownerId: json['ownerId'] as String,
      ownerType: ReminderOwnerType.values.byName(json['ownerType'] as String),
      kind: ScheduleKind.values.byName(json['kind'] as String),
      enabled: json['enabled'] as bool? ?? true,
      timeZone: json['timeZone'] as String? ?? 'UTC',
      updatedAtUtc: DateTime.parse(json['updatedAtUtc'] as String).toUtc(),
      instantUtc: instant == null ? null : DateTime.parse(instant).toUtc(),
      localTime: localTime,
      anchorLocalDate: anchor == null ? null : DateTime.parse(anchor),
      byWeekday: (json['byWeekday'] as num?)?.toInt(),
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
    );
  }

  ReminderIntent copyWith({
    bool? enabled,
    String? timeZone,
    DateTime? updatedAtUtc,
    String? title,
    String? body,
  }) {
    return ReminderIntent(
      id: id,
      ownerId: ownerId,
      ownerType: ownerType,
      kind: kind,
      enabled: enabled ?? this.enabled,
      timeZone: timeZone ?? this.timeZone,
      instantUtc: instantUtc,
      localTime: localTime,
      anchorLocalDate: anchorLocalDate,
      byWeekday: byWeekday,
      updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
      title: title ?? this.title,
      body: body ?? this.body,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'ownerId': ownerId,
      'ownerType': ownerType.name,
      'kind': kind.name,
      'enabled': enabled,
      'timeZone': timeZone,
      'updatedAtUtc': updatedAtUtc.toUtc().toIso8601String(),
      'instantUtc': instantUtc?.toUtc().toIso8601String(),
      'localTime': localTime == null
          ? null
          : <String, int>{'hour': localTime!.hour, 'minute': localTime!.minute},
      'anchorLocalDate': anchorLocalDate?.toIso8601String(),
      'byWeekday': byWeekday,
      'title': title,
      'body': body,
    };
  }
}

final class OccurrencePlan {
  const OccurrencePlan({
    required this.reminderIntentId,
    required this.occurrenceKey,
    required this.scheduledLocal,
    required this.scheduledUtc,
  });

  final String reminderIntentId;
  final String occurrenceKey;
  final tz.TZDateTime scheduledLocal;
  final DateTime scheduledUtc;
}

final class ScheduledNotificationRecord {
  const ScheduledNotificationRecord({
    required this.id,
    required this.deviceId,
    required this.reminderIntentId,
    required this.ownerId,
    required this.ownerType,
    required this.occurrenceKey,
    required this.scheduledForUtc,
    required this.payload,
    this.title = '',
    this.body = '',
    this.scheduledTimeZone = '',
  });

  factory ScheduledNotificationRecord.fromJson(Map<String, Object?> json) {
    return ScheduledNotificationRecord(
      id: json['id'] as int,
      deviceId: json['deviceId'] as String,
      reminderIntentId: json['reminderIntentId'] as String,
      ownerId: json['ownerId'] as String? ?? json['reminderIntentId'] as String,
      ownerType: ReminderOwnerType.values.byName(
        json['ownerType'] as String? ?? ReminderOwnerType.task.name,
      ),
      occurrenceKey: json['occurrenceKey'] as String,
      scheduledForUtc: DateTime.parse(
        json['scheduledForUtc'] as String,
      ).toUtc(),
      payload: json['payload'] as String,
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      scheduledTimeZone: json['scheduledTimeZone'] as String? ?? '',
    );
  }

  final int id;
  final String deviceId;
  final String reminderIntentId;
  final String ownerId;
  final ReminderOwnerType ownerType;
  final String occurrenceKey;
  final DateTime scheduledForUtc;
  final String payload;
  final String title;
  final String body;
  final String scheduledTimeZone;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'deviceId': deviceId,
      'reminderIntentId': reminderIntentId,
      'ownerId': ownerId,
      'ownerType': ownerType.name,
      'occurrenceKey': occurrenceKey,
      'scheduledForUtc': scheduledForUtc.toUtc().toIso8601String(),
      'payload': payload,
      'title': title,
      'body': body,
      'scheduledTimeZone': scheduledTimeZone,
    };
  }
}
