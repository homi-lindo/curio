import 'package:timezone/timezone.dart' as tz;

import 'package:lume_core/domain/reminder.dart';

final class OccurrenceCalculator {
  const OccurrenceCalculator();

  OccurrencePlan? nextOccurrence(
    ReminderIntent intent, {
    required tz.Location location,
    required tz.TZDateTime from,
  }) {
    if (!intent.enabled) {
      return null;
    }

    return switch (intent.kind) {
      ScheduleKind.oneShot => _oneShot(intent, location, from),
      ScheduleKind.daily => _daily(intent, location, from),
      ScheduleKind.weekly => _weekly(intent, location, from),
    };
  }

  List<OccurrencePlan> upcomingOccurrences(
    ReminderIntent intent, {
    required tz.Location location,
    required tz.TZDateTime from,
    required int count,
  }) {
    if (count <= 0 || !intent.enabled) {
      return const <OccurrencePlan>[];
    }

    final plans = <OccurrencePlan>[];
    var cursor = from;
    while (plans.length < count) {
      final plan = nextOccurrence(intent, location: location, from: cursor);
      if (plan == null) {
        break;
      }
      plans.add(plan);
      cursor = tz.TZDateTime.from(
        plan.scheduledLocal.add(const Duration(microseconds: 1)),
        location,
      );
    }
    return plans;
  }

  OccurrencePlan? _oneShot(
    ReminderIntent intent,
    tz.Location location,
    tz.TZDateTime from,
  ) {
    final instant = intent.instantUtc!.toUtc();
    final scheduledLocal = tz.TZDateTime.from(instant, location);

    if (!scheduledLocal.isAfter(from)) {
      return null;
    }

    return OccurrencePlan(
      reminderIntentId: intent.id,
      occurrenceKey: instant.toIso8601String(),
      scheduledLocal: scheduledLocal,
      scheduledUtc: instant,
    );
  }

  OccurrencePlan _daily(
    ReminderIntent intent,
    tz.Location location,
    tz.TZDateTime from,
  ) {
    final localTime = intent.localTime!;
    var localDate = DateTime(from.year, from.month, from.day);
    var candidate = _atLocalDate(location, localDate, localTime);

    while (!candidate.isAfter(from)) {
      localDate = localDate.add(const Duration(days: 1));
      candidate = _atLocalDate(location, localDate, localTime);
    }

    return _recurringPlan(intent.id, candidate);
  }

  OccurrencePlan _weekly(
    ReminderIntent intent,
    tz.Location location,
    tz.TZDateTime from,
  ) {
    final localTime = intent.localTime!;
    final targetWeekday = intent.byWeekday!;
    final anchor = intent.anchorLocalDate!;
    final firstDate = _firstWeekdayOnOrAfter(anchor, targetWeekday);
    final fromDate = DateTime(from.year, from.month, from.day);

    var candidateDate = firstDate;
    if (candidateDate.isBefore(fromDate)) {
      final daysBehind = fromDate.difference(candidateDate).inDays;
      candidateDate = candidateDate.add(Duration(days: (daysBehind ~/ 7) * 7));
      if (candidateDate.isBefore(fromDate)) {
        candidateDate = candidateDate.add(const Duration(days: 7));
      }
    }

    var candidate = _atLocalDate(location, candidateDate, localTime);
    while (!candidate.isAfter(from)) {
      candidateDate = candidateDate.add(const Duration(days: 7));
      candidate = _atLocalDate(location, candidateDate, localTime);
    }

    return _recurringPlan(intent.id, candidate);
  }

  static int stableNotificationId({
    required String deviceId,
    required String reminderIntentId,
    required String occurrenceKey,
  }) {
    var hash = 0x811c9dc5;
    for (final unit in '$deviceId|$reminderIntentId|$occurrenceKey'.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }

    final id = hash & 0x7fffffff;
    return id == 0 ? 1 : id;
  }

  static tz.TZDateTime _atLocalDate(
    tz.Location location,
    DateTime date,
    LocalClockTime time,
  ) {
    return tz.TZDateTime(
      location,
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
  }

  static DateTime _firstWeekdayOnOrAfter(DateTime date, int weekday) {
    final dateOnly = DateTime(date.year, date.month, date.day);
    final delta =
        (weekday - dateOnly.weekday + DateTime.daysPerWeek) %
        DateTime.daysPerWeek;
    return dateOnly.add(Duration(days: delta));
  }

  static OccurrencePlan _recurringPlan(
    String reminderIntentId,
    tz.TZDateTime scheduledLocal,
  ) {
    return OccurrencePlan(
      reminderIntentId: reminderIntentId,
      occurrenceKey: _localDateKey(scheduledLocal),
      scheduledLocal: scheduledLocal,
      scheduledUtc: scheduledLocal.toUtc(),
    );
  }

  static String _localDateKey(tz.TZDateTime dateTime) {
    final year = dateTime.year.toString().padLeft(4, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final day = dateTime.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}
