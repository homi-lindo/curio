import 'package:flutter_test/flutter_test.dart';
import 'package:lume/services/calendar_ics_codec.dart';
import 'package:lume_core/domain/app_snapshot.dart';
import 'package:lume_core/domain/reminder.dart';

void main() {
  test('exports notes and notifications as readable ICS events', () {
    final ics = const CalendarIcsCodec().encode(
      _snapshot(),
      generatedAtUtc: DateTime.utc(2026, 5, 22, 12),
    );

    expect(ics, contains('BEGIN:VCALENDAR'));
    expect(ics, contains('SUMMARY:Diário - 22/05/2026'));
    expect(ics, contains('DTSTART;VALUE=DATE:20260522'));
    expect(ics, contains('DTEND;VALUE=DATE:20260523'));
    expect(ics, contains('SUMMARY:Enviar relatório'));
    expect(ics, contains('DTSTART:20260522T154200Z'));
    expect(ics, contains('DTEND:20260522T155700Z'));
    expect(ics, contains('X-CURIO-TIMEZONE:America/Sao_Paulo'));
    expect(ics, contains('BEGIN:VALARM'));
    expect(ics, contains('TRIGGER:PT0S'));
  });

  test('reminderId is a stable identity used for import dedup', () {
    CalendarIcsEvent event({
      String uid = '',
      String title = 'Reunião',
      DateTime? startsAtUtc,
    }) {
      return CalendarIcsEvent(
        uid: uid,
        title: title,
        description: '',
        startsAtUtc: startsAtUtc ?? DateTime.utc(2026, 5, 22, 15),
        allDay: false,
        curioType: 'NOTIFICATION',
      );
    }

    // Prefixed and stable across instances.
    expect(event(uid: 'abc').reminderId, startsWith('ics-'));
    expect(event(uid: 'abc').reminderId, event(uid: 'abc').reminderId);

    // Distinct UIDs → distinct ids, even with identical title and time.
    expect(event(uid: 'abc').reminderId, isNot(event(uid: 'xyz').reminderId));

    // Without UID: same title + same instant collapse (genuinely the same
    // event); same title + different instant stay distinct (the dedup fix —
    // the old title+minute heuristic wrongly merged these).
    expect(
      event(startsAtUtc: DateTime.utc(2026, 5, 22, 15)).reminderId,
      event(startsAtUtc: DateTime.utc(2026, 5, 22, 15)).reminderId,
    );
    expect(
      event(startsAtUtc: DateTime.utc(2026, 5, 22, 15)).reminderId,
      isNot(event(startsAtUtc: DateTime.utc(2026, 5, 23, 15)).reminderId),
    );
  });

  test('imports timed, all-day, alarm and recurring ICS events', () {
    const ics = '''
BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
UID:evento-1
SUMMARY:Reunião Google
DESCRIPTION:Link no Meet
DTSTART:20260522T154200Z
END:VEVENT
BEGIN:VEVENT
UID:evento-2
SUMMARY:Dia livre
DTSTART;VALUE=DATE:20260523
END:VEVENT
BEGIN:VEVENT
UID:evento-3
SUMMARY:Revisão semanal
DESCRIPTION:Rotina de sexta
DTSTART;TZID=America/Sao_Paulo:20260522T154200
DTEND;TZID=America/Sao_Paulo:20260522T164200
RRULE:FREQ=WEEKLY;BYDAY=FR
BEGIN:VALARM
ACTION:DISPLAY
DESCRIPTION:Revisão semanal
TRIGGER:-PT10M
END:VALARM
END:VEVENT
END:VCALENDAR
''';

    final imported = const CalendarIcsCodec().decode(ics);

    expect(imported.events, hasLength(3));
    expect(imported.events.first.title, 'Reunião Google');
    expect(
      imported.events.first.startsAtUtc,
      DateTime.utc(2026, 5, 22, 15, 42),
    );
    expect(imported.events.first.allDay, isFalse);
    expect(imported.events[1].allDay, isTrue);
    final recurring = imported.events[2];
    expect(recurring.title, 'Revisão semanal');
    expect(recurring.startsAtUtc, DateTime.utc(2026, 5, 22, 18, 42));
    expect(recurring.endsAtUtc, DateTime.utc(2026, 5, 22, 19, 42));
    expect(recurring.alarmTrigger, const Duration(minutes: -10));
    expect(recurring.alarmAtUtc, DateTime.utc(2026, 5, 22, 18, 32));
    expect(recurring.timeZoneId, 'America/Sao_Paulo');
    expect(
      recurring.supportedRecurrence?.kind,
      CalendarIcsRecurrenceKind.weekly,
    );
    expect(recurring.supportedRecurrence?.weekday, DateTime.friday);
  });
}

AppSnapshot _snapshot() {
  return AppSnapshot(
    tasks: const <TaskItem>[],
    notes: <NoteItem>[
      NoteItem(
        id: 'note-day',
        title: 'Diário - 22/05/2026',
        body: '## 22/05/2026\n\nRevisar backup manual',
        createdAtUtc: DateTime.utc(2026, 5, 22, 10),
        updatedAtUtc: DateTime.utc(2026, 5, 22, 11),
      ),
    ],
    scheduledNotifications: <ScheduledNotificationRecord>[
      ScheduledNotificationRecord(
        id: 42,
        deviceId: 'device-a',
        reminderIntentId: 'reminder-day',
        ownerId: 'note-day',
        ownerType: ReminderOwnerType.note,
        occurrenceKey: '2026-05-22T15:42:00.000Z',
        scheduledForUtc: DateTime.utc(2026, 5, 22, 15, 42),
        payload: 'curio://reminder/reminder-day',
        title: 'Enviar relatório',
        body: 'Conferir anexos antes do envio',
        scheduledTimeZone: 'America/Sao_Paulo',
      ),
    ],
    deletedRecords: const <DeletedRecord>[],
  );
}
