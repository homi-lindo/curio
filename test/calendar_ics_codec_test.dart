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
    expect(ics, contains('SUMMARY:Enviar relatório'));
    expect(ics, contains('DTSTART:20260522T154200Z'));
  });

  test('imports timed and all-day ICS events', () {
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
END:VCALENDAR
''';

    final imported = const CalendarIcsCodec().decode(ics);

    expect(imported.events, hasLength(2));
    expect(imported.events.first.title, 'Reunião Google');
    expect(
      imported.events.first.startsAtUtc,
      DateTime.utc(2026, 5, 22, 15, 42),
    );
    expect(imported.events.first.allDay, isFalse);
    expect(imported.events.last.allDay, isTrue);
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
