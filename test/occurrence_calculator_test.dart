import 'package:flutter_test/flutter_test.dart';
import 'package:lume/domain/occurrence_calculator.dart';
import 'package:lume_core/domain/reminder.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  late tz.Location saoPaulo;
  const calculator = OccurrenceCalculator();

  setUpAll(() {
    tzdata.initializeTimeZones();
    saoPaulo = tz.getLocation('America/Sao_Paulo');
  });

  test(
    'daily reminders move to the next local day when time already passed',
    () {
      final intent = ReminderIntent.daily(
        id: 'daily-review',
        ownerId: 'task-1',
        ownerType: ReminderOwnerType.task,
        localTime: const LocalClockTime(hour: 8, minute: 30),
        timeZone: 'America/Sao_Paulo',
        updatedAtUtc: DateTime.utc(2026, 5, 20, 12),
      );

      final plan = calculator.nextOccurrence(
        intent,
        location: saoPaulo,
        from: tz.TZDateTime(saoPaulo, 2026, 5, 20, 9),
      );

      expect(plan, isNotNull);
      expect(plan!.occurrenceKey, '2026-05-21');
      expect(plan.scheduledLocal.hour, 8);
      expect(plan.scheduledLocal.minute, 30);
    },
  );

  test('weekly reminders honor first target weekday on or after anchor', () {
    final intent = ReminderIntent.weekly(
      id: 'weekly-plan',
      ownerId: 'note-1',
      ownerType: ReminderOwnerType.note,
      localTime: const LocalClockTime(hour: 10, minute: 15),
      timeZone: 'America/Sao_Paulo',
      anchorLocalDate: DateTime(2026, 5, 20),
      byWeekday: DateTime.friday,
      updatedAtUtc: DateTime.utc(2026, 5, 20, 12),
    );

    final plan = calculator.nextOccurrence(
      intent,
      location: saoPaulo,
      from: tz.TZDateTime(saoPaulo, 2026, 5, 20, 9),
    );

    expect(plan, isNotNull);
    expect(plan!.occurrenceKey, '2026-05-22');
    expect(plan.scheduledLocal.weekday, DateTime.friday);
    expect(plan.scheduledLocal.hour, 10);
    expect(plan.scheduledLocal.minute, 15);
  });

  test('one shot reminders use the utc instant as occurrence key', () {
    final instantUtc = DateTime.utc(2026, 5, 20, 15, 45);
    final intent = ReminderIntent.oneShot(
      id: 'once',
      ownerId: 'task-2',
      ownerType: ReminderOwnerType.task,
      instantUtc: instantUtc,
      updatedAtUtc: DateTime.utc(2026, 5, 20, 12),
    );

    final plan = calculator.nextOccurrence(
      intent,
      location: saoPaulo,
      from: tz.TZDateTime(saoPaulo, 2026, 5, 20, 12),
    );

    expect(plan, isNotNull);
    expect(plan!.occurrenceKey, '2026-05-20T15:45:00.000Z');
    expect(plan.scheduledUtc, instantUtc);
  });

  test('upcoming occurrences queue recurring reminders without duplicates', () {
    final intent = ReminderIntent.daily(
      id: 'daily-review',
      ownerId: 'task-1',
      ownerType: ReminderOwnerType.task,
      localTime: const LocalClockTime(hour: 8, minute: 30),
      timeZone: 'America/Sao_Paulo',
      updatedAtUtc: DateTime.utc(2026, 5, 20, 12),
    );

    final plans = calculator.upcomingOccurrences(
      intent,
      location: saoPaulo,
      from: tz.TZDateTime(saoPaulo, 2026, 5, 20, 9),
      count: 3,
    );

    expect(plans.map((plan) => plan.occurrenceKey), <String>[
      '2026-05-21',
      '2026-05-22',
      '2026-05-23',
    ]);
  });

  test('upcoming occurrences returns at most one one-shot reminder', () {
    final instantUtc = DateTime.utc(2026, 5, 20, 15, 45);
    final intent = ReminderIntent.oneShot(
      id: 'once',
      ownerId: 'task-2',
      ownerType: ReminderOwnerType.task,
      instantUtc: instantUtc,
      updatedAtUtc: DateTime.utc(2026, 5, 20, 12),
    );

    final plans = calculator.upcomingOccurrences(
      intent,
      location: saoPaulo,
      from: tz.TZDateTime(saoPaulo, 2026, 5, 20, 12),
      count: 3,
    );

    expect(plans, hasLength(1));
    expect(plans.single.occurrenceKey, '2026-05-20T15:45:00.000Z');
  });

  test('stable notification ids are deterministic and positive', () {
    final first = OccurrenceCalculator.stableNotificationId(
      deviceId: 'lume-windows',
      reminderIntentId: 'daily-review',
      occurrenceKey: '2026-05-21',
    );
    final second = OccurrenceCalculator.stableNotificationId(
      deviceId: 'lume-windows',
      reminderIntentId: 'daily-review',
      occurrenceKey: '2026-05-21',
    );

    expect(first, second);
    expect(first, greaterThan(0));
  });
}
