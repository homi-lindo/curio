import 'package:lume_core/domain/app_snapshot.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

final class CalendarIcsCodec {
  const CalendarIcsCodec();

  String encode(AppSnapshot snapshot, {DateTime? generatedAtUtc}) {
    final generated = generatedAtUtc ?? DateTime.now().toUtc();
    final calendarTimeZone = snapshot.scheduledNotifications
        .map((record) => record.scheduledTimeZone.trim())
        .where((timeZone) => timeZone.isNotEmpty)
        .firstOrNull;
    final buffer = StringBuffer();
    _writeLine(buffer, 'BEGIN:VCALENDAR');
    _writeLine(buffer, 'VERSION:2.0');
    _writeLine(buffer, 'PRODID:-//Curio//Agenda//PT-BR');
    _writeLine(buffer, 'CALSCALE:GREGORIAN');
    _writeLine(buffer, 'METHOD:PUBLISH');
    _writeLine(buffer, 'X-WR-CALNAME:Curio');
    _writeLine(buffer, 'X-WR-TIMEZONE:${calendarTimeZone ?? 'UTC'}');

    for (final note in snapshot.notes) {
      final date = _dailyNoteDate(note);
      if (date == null) {
        continue;
      }

      _writeEvent(
        buffer,
        uid: 'curio-note-${note.id}@curio.local',
        generatedAtUtc: generated,
        summary: note.title,
        description: note.body,
        allDayDate: date,
        curioType: 'NOTE',
      );
    }

    final notifications = [...snapshot.scheduledNotifications]
      ..sort((a, b) => a.scheduledForUtc.compareTo(b.scheduledForUtc));
    for (final record in notifications) {
      _writeEvent(
        buffer,
        uid: 'curio-notification-${record.id}@curio.local',
        generatedAtUtc: generated,
        summary: record.title.trim().isEmpty
            ? 'Notificação'
            : record.title.trim(),
        description: record.body,
        startsAtUtc: record.scheduledForUtc,
        endsAtUtc: record.scheduledForUtc.add(const Duration(minutes: 15)),
        curioType: 'NOTIFICATION',
        timeZoneId: record.scheduledTimeZone,
        alarmTrigger: Duration.zero,
      );
    }

    _writeLine(buffer, 'END:VCALENDAR');
    return buffer.toString();
  }

  CalendarIcsImport decode(String input) {
    final lines = _unfoldLines(input);
    final events = <CalendarIcsEvent>[];
    var inEvent = false;
    var properties = <_IcsProperty>[];

    for (final line in lines) {
      final trimmed = line.trimRight();
      if (trimmed.toUpperCase() == 'BEGIN:VEVENT') {
        inEvent = true;
        properties = <_IcsProperty>[];
        continue;
      }
      if (trimmed.toUpperCase() == 'END:VEVENT') {
        inEvent = false;
        final event = _eventFromProperties(properties);
        if (event != null) {
          events.add(event);
        }
        continue;
      }
      if (inEvent) {
        final property = _parseProperty(trimmed);
        if (property != null) {
          properties.add(property);
        }
      }
    }

    if (events.isEmpty) {
      throw const CalendarIcsException('Nenhum evento encontrado no .ics.');
    }
    return CalendarIcsImport(events: events);
  }

  void _writeEvent(
    StringBuffer buffer, {
    required String uid,
    required DateTime generatedAtUtc,
    required String summary,
    required String description,
    required String curioType,
    DateTime? startsAtUtc,
    DateTime? endsAtUtc,
    DateTime? allDayDate,
    String timeZoneId = '',
    String recurrenceRule = '',
    Duration? alarmTrigger,
  }) {
    _writeLine(buffer, 'BEGIN:VEVENT');
    _writeLine(buffer, 'UID:${_escapeText(uid)}');
    _writeLine(buffer, 'DTSTAMP:${_formatUtc(generatedAtUtc)}');
    _writeLine(buffer, 'CREATED:${_formatUtc(generatedAtUtc)}');
    _writeLine(buffer, 'LAST-MODIFIED:${_formatUtc(generatedAtUtc)}');
    _writeLine(buffer, 'SEQUENCE:0');
    _writeLine(buffer, 'STATUS:CONFIRMED');
    _writeLine(buffer, 'SUMMARY:${_escapeText(summary)}');
    _writeLine(buffer, 'DESCRIPTION:${_escapeText(description)}');
    _writeLine(buffer, 'X-CURIO-TYPE:$curioType');
    if (timeZoneId.trim().isNotEmpty) {
      _writeLine(buffer, 'X-CURIO-TIMEZONE:${_escapeText(timeZoneId.trim())}');
    }
    if (allDayDate != null) {
      _writeLine(buffer, 'DTSTART;VALUE=DATE:${_formatDate(allDayDate)}');
      _writeLine(
        buffer,
        'DTEND;VALUE=DATE:${_formatDate(allDayDate.add(const Duration(days: 1)))}',
      );
      _writeLine(buffer, 'TRANSP:TRANSPARENT');
    } else {
      _writeLine(buffer, 'DTSTART:${_formatUtc(startsAtUtc!.toUtc())}');
      _writeLine(
        buffer,
        'DTEND:${_formatUtc((endsAtUtc ?? startsAtUtc.add(const Duration(minutes: 15))).toUtc())}',
      );
      _writeLine(buffer, 'TRANSP:OPAQUE');
    }
    if (recurrenceRule.trim().isNotEmpty) {
      _writeLine(buffer, 'RRULE:${recurrenceRule.trim()}');
    }
    if (alarmTrigger != null) {
      _writeLine(buffer, 'BEGIN:VALARM');
      _writeLine(buffer, 'ACTION:DISPLAY');
      _writeLine(
        buffer,
        'DESCRIPTION:${_escapeText(summary.trim().isEmpty ? 'Notificação' : summary.trim())}',
      );
      _writeLine(buffer, 'TRIGGER:${_formatDuration(alarmTrigger)}');
      _writeLine(buffer, 'END:VALARM');
    }
    _writeLine(buffer, 'END:VEVENT');
  }
}

final class CalendarIcsImport {
  const CalendarIcsImport({required this.events});

  final List<CalendarIcsEvent> events;
}

final class CalendarIcsEvent {
  const CalendarIcsEvent({
    required this.uid,
    required this.title,
    required this.description,
    required this.startsAtUtc,
    this.endsAtUtc,
    required this.allDay,
    required this.curioType,
    this.timeZoneId = '',
    this.recurrenceRule = '',
    this.alarmTrigger,
  });

  final String uid;
  final String title;
  final String description;
  final DateTime startsAtUtc;
  final DateTime? endsAtUtc;
  final bool allDay;
  final String curioType;
  final String timeZoneId;
  final String recurrenceRule;
  final Duration? alarmTrigger;

  DateTime? get alarmAtUtc {
    final trigger = alarmTrigger;
    if (trigger == null) {
      return null;
    }
    return startsAtUtc.add(trigger).toUtc();
  }

  CalendarIcsRecurrence? get supportedRecurrence {
    return CalendarIcsRecurrence.tryParse(recurrenceRule, startsAtUtc);
  }
}

enum CalendarIcsRecurrenceKind { daily, weekly }

final class CalendarIcsRecurrence {
  const CalendarIcsRecurrence({required this.kind, this.weekday});

  static CalendarIcsRecurrence? tryParse(String rule, DateTime startsAtUtc) {
    final fields = _rruleFields(rule);
    final freq = fields['FREQ']?.toUpperCase();
    final interval = int.tryParse(fields['INTERVAL'] ?? '1') ?? 1;
    final isOpenEnded =
        !fields.containsKey('COUNT') && !fields.containsKey('UNTIL');
    if (freq == null || interval != 1 || !isOpenEnded) {
      return null;
    }

    if (freq == 'DAILY') {
      return const CalendarIcsRecurrence(kind: CalendarIcsRecurrenceKind.daily);
    }

    if (freq == 'WEEKLY') {
      final byDay = fields['BYDAY'];
      if (byDay == null || byDay.trim().isEmpty) {
        return CalendarIcsRecurrence(
          kind: CalendarIcsRecurrenceKind.weekly,
          weekday: startsAtUtc.toLocal().weekday,
        );
      }

      final days = byDay
          .split(',')
          .map((value) => _weekdayFromRRule(value.trim()))
          .whereType<int>()
          .toList();
      if (days.length != 1) {
        return null;
      }
      return CalendarIcsRecurrence(
        kind: CalendarIcsRecurrenceKind.weekly,
        weekday: days.single,
      );
    }

    return null;
  }

  final CalendarIcsRecurrenceKind kind;
  final int? weekday;

  String get label {
    return switch (kind) {
      CalendarIcsRecurrenceKind.daily => 'diária',
      CalendarIcsRecurrenceKind.weekly => 'semanal',
    };
  }
}

final class CalendarIcsException implements Exception {
  const CalendarIcsException(this.message);

  final String message;
}

final class _IcsProperty {
  const _IcsProperty({
    required this.name,
    required this.parameters,
    required this.value,
  });

  final String name;
  final String parameters;
  final String value;
}

List<String> _unfoldLines(String input) {
  final rawLines = input.replaceAll('\r\n', '\n').split('\n');
  final lines = <String>[];
  for (final line in rawLines) {
    if ((line.startsWith(' ') || line.startsWith('\t')) && lines.isNotEmpty) {
      lines[lines.length - 1] = '${lines.last}${line.substring(1)}';
    } else {
      lines.add(line);
    }
  }
  return lines;
}

_IcsProperty? _parseProperty(String line) {
  final separator = line.indexOf(':');
  if (separator <= 0) {
    return null;
  }
  final key = line.substring(0, separator);
  final value = line.substring(separator + 1);
  final semicolon = key.indexOf(';');
  final name = (semicolon == -1 ? key : key.substring(0, semicolon))
      .toUpperCase();
  final parameters = semicolon == -1 ? '' : key.substring(semicolon + 1);
  return _IcsProperty(name: name, parameters: parameters, value: value);
}

CalendarIcsEvent? _eventFromProperties(List<_IcsProperty> properties) {
  String? value(String name) => properties
      .where((property) => property.name == name)
      .map((property) => property.value)
      .firstOrNull;

  final dtStart = properties
      .where((property) => property.name == 'DTSTART')
      .firstOrNull;
  if (dtStart == null) {
    return null;
  }

  final allDay = dtStart.parameters.toUpperCase().contains('VALUE=DATE');
  final startsAt = allDay ? _parseDate(dtStart.value) : _parseDateTime(dtStart);
  final dtEnd = properties
      .where((property) => property.name == 'DTEND')
      .firstOrNull;
  final duration = properties
      .where((property) => property.name == 'DURATION')
      .map((property) => _parseDuration(property.value))
      .firstOrNull;
  final endsAt = dtEnd == null
      ? duration == null
            ? null
            : startsAt.add(duration)
      : dtEnd.parameters.toUpperCase().contains('VALUE=DATE')
      ? _parseDate(dtEnd.value)
      : _parseDateTime(dtEnd);
  final title = _unescapeText(value('SUMMARY') ?? 'Evento importado').trim();
  final timeZoneId =
      _parameterValue(dtStart.parameters, 'TZID') ??
      _unescapeText(value('X-CURIO-TIMEZONE') ?? '');
  final recurrenceRule = value('RRULE')?.trim() ?? '';
  final triggerProperty = properties
      .where((property) => property.name == 'TRIGGER')
      .firstOrNull;
  final alarmTrigger = _alarmTriggerRelativeToStart(
    startsAt: startsAt,
    endsAt: endsAt,
    trigger: triggerProperty,
  );

  return CalendarIcsEvent(
    uid: _unescapeText(value('UID') ?? title),
    title: title.isEmpty ? 'Evento importado' : title,
    description: _unescapeText(value('DESCRIPTION') ?? ''),
    startsAtUtc: startsAt.toUtc(),
    endsAtUtc: endsAt?.toUtc(),
    allDay: allDay,
    curioType: (value('X-CURIO-TYPE') ?? '').toUpperCase(),
    timeZoneId: timeZoneId,
    recurrenceRule: recurrenceRule,
    alarmTrigger: alarmTrigger,
  );
}

DateTime _parseDate(String value) {
  final compact = value.trim();
  if (compact.length < 8) {
    throw const CalendarIcsException('Data inválida no .ics.');
  }
  return DateTime.utc(
    int.parse(compact.substring(0, 4)),
    int.parse(compact.substring(4, 6)),
    int.parse(compact.substring(6, 8)),
  );
}

DateTime _parseDateTime(_IcsProperty property) {
  final compact = property.value.trim();
  if (compact.length < 15) {
    throw const CalendarIcsException('Data/hora inválida no .ics.');
  }
  final year = int.parse(compact.substring(0, 4));
  final month = int.parse(compact.substring(4, 6));
  final day = int.parse(compact.substring(6, 8));
  final hour = int.parse(compact.substring(9, 11));
  final minute = int.parse(compact.substring(11, 13));
  final second = int.parse(compact.substring(13, 15));
  if (compact.endsWith('Z')) {
    return DateTime.utc(year, month, day, hour, minute, second);
  }

  final timeZoneId = _parameterValue(property.parameters, 'TZID');
  if (timeZoneId != null && timeZoneId.trim().isNotEmpty) {
    final resolved = _dateTimeInTimeZone(
      timeZoneId.trim(),
      year: year,
      month: month,
      day: day,
      hour: hour,
      minute: minute,
      second: second,
    );
    if (resolved != null) {
      return resolved;
    }
  }

  return DateTime(year, month, day, hour, minute, second).toUtc();
}

String _formatUtc(DateTime value) {
  final utc = value.toUtc();
  return '${utc.year.toString().padLeft(4, '0')}'
      '${utc.month.toString().padLeft(2, '0')}'
      '${utc.day.toString().padLeft(2, '0')}T'
      '${utc.hour.toString().padLeft(2, '0')}'
      '${utc.minute.toString().padLeft(2, '0')}'
      '${utc.second.toString().padLeft(2, '0')}Z';
}

String _formatDate(DateTime value) {
  return '${value.year.toString().padLeft(4, '0')}'
      '${value.month.toString().padLeft(2, '0')}'
      '${value.day.toString().padLeft(2, '0')}';
}

String _formatDuration(Duration value) {
  final negative = value.inMicroseconds < 0;
  final positive = Duration(microseconds: value.inMicroseconds.abs());
  final days = positive.inDays;
  final hours = positive.inHours.remainder(24);
  final minutes = positive.inMinutes.remainder(60);
  final seconds = positive.inSeconds.remainder(60);
  final buffer = StringBuffer(negative ? '-' : '');
  buffer.write('P');
  if (days > 0) {
    buffer.write('${days}D');
  }
  if (hours > 0 || minutes > 0 || seconds > 0 || days == 0) {
    buffer.write('T');
    if (hours > 0) {
      buffer.write('${hours}H');
    }
    if (minutes > 0) {
      buffer.write('${minutes}M');
    }
    if (seconds > 0 || (hours == 0 && minutes == 0)) {
      buffer.write('${seconds}S');
    }
  }
  return buffer.toString();
}

Duration? _parseDuration(String value) {
  final compact = value.trim().toUpperCase();
  final match = RegExp(
    r'^([+-])?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$',
  ).firstMatch(compact);
  if (match == null) {
    return null;
  }

  final weeks = int.tryParse(match.group(2) ?? '') ?? 0;
  final days = int.tryParse(match.group(3) ?? '') ?? 0;
  final hours = int.tryParse(match.group(4) ?? '') ?? 0;
  final minutes = int.tryParse(match.group(5) ?? '') ?? 0;
  final seconds = int.tryParse(match.group(6) ?? '') ?? 0;
  final duration = Duration(
    days: weeks * 7 + days,
    hours: hours,
    minutes: minutes,
    seconds: seconds,
  );
  if (match.group(1) == '-') {
    return Duration(microseconds: -duration.inMicroseconds);
  }
  return duration;
}

Duration? _alarmTriggerRelativeToStart({
  required DateTime startsAt,
  required DateTime? endsAt,
  required _IcsProperty? trigger,
}) {
  if (trigger == null) {
    return null;
  }

  final triggerDuration = _parseDuration(trigger.value);
  if (triggerDuration == null) {
    return null;
  }

  final relatedToEnd =
      (_parameterValue(trigger.parameters, 'RELATED') ?? '').toUpperCase() ==
      'END';
  if (relatedToEnd && endsAt != null) {
    return endsAt.add(triggerDuration).difference(startsAt);
  }

  return triggerDuration;
}

String? _parameterValue(String parameters, String name) {
  final target = name.toUpperCase();
  for (final parameter in parameters.split(';')) {
    final separator = parameter.indexOf('=');
    if (separator <= 0) {
      continue;
    }
    final key = parameter.substring(0, separator).toUpperCase();
    if (key != target) {
      continue;
    }
    var value = parameter.substring(separator + 1).trim();
    if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
      value = value.substring(1, value.length - 1);
    }
    return value;
  }
  return null;
}

Map<String, String> _rruleFields(String rule) {
  final fields = <String, String>{};
  for (final part in rule.split(';')) {
    final separator = part.indexOf('=');
    if (separator <= 0) {
      continue;
    }
    fields[part.substring(0, separator).trim().toUpperCase()] = part
        .substring(separator + 1)
        .trim();
  }
  return fields;
}

int? _weekdayFromRRule(String value) {
  final day = RegExp(
    r'(MO|TU|WE|TH|FR|SA|SU)$',
  ).firstMatch(value.toUpperCase());
  return switch (day?.group(1)) {
    'MO' => DateTime.monday,
    'TU' => DateTime.tuesday,
    'WE' => DateTime.wednesday,
    'TH' => DateTime.thursday,
    'FR' => DateTime.friday,
    'SA' => DateTime.saturday,
    'SU' => DateTime.sunday,
    _ => null,
  };
}

DateTime? _dateTimeInTimeZone(
  String timeZoneId, {
  required int year,
  required int month,
  required int day,
  required int hour,
  required int minute,
  required int second,
}) {
  if (timeZoneId.toUpperCase() == 'UTC' ||
      timeZoneId.toUpperCase() == 'ETC/UTC') {
    return DateTime.utc(year, month, day, hour, minute, second);
  }

  try {
    _ensureTimeZonesInitialized();
    final location = tz.getLocation(timeZoneId);
    return tz.TZDateTime(
      location,
      year,
      month,
      day,
      hour,
      minute,
      second,
    ).toUtc();
  } on Object {
    return null;
  }
}

var _timeZonesInitialized = false;

void _ensureTimeZonesInitialized() {
  if (_timeZonesInitialized) {
    return;
  }
  tzdata.initializeTimeZones();
  _timeZonesInitialized = true;
}

void _writeLine(StringBuffer buffer, String line) {
  const maxLength = 75;
  if (line.length <= maxLength) {
    buffer.writeln(line);
    return;
  }

  var remaining = line;
  var first = true;
  while (remaining.isNotEmpty) {
    final chunkLength = first ? maxLength : maxLength - 1;
    final end = remaining.length > chunkLength ? chunkLength : remaining.length;
    buffer.writeln(
      first ? remaining.substring(0, end) : ' ${remaining.substring(0, end)}',
    );
    remaining = remaining.substring(end);
    first = false;
  }
}

String _escapeText(String value) {
  return value
      .replaceAll('\\', r'\\')
      .replaceAll('\n', r'\n')
      .replaceAll(';', r'\;')
      .replaceAll(',', r'\,');
}

String _unescapeText(String value) {
  final buffer = StringBuffer();
  for (var index = 0; index < value.length; index++) {
    final char = value[index];
    if (char != '\\' || index == value.length - 1) {
      buffer.write(char);
      continue;
    }

    index++;
    final escaped = value[index];
    buffer.write(switch (escaped) {
      'n' || 'N' => '\n',
      '\\' => '\\',
      ';' => ';',
      ',' => ',',
      _ => escaped,
    });
  }
  return buffer.toString();
}

DateTime? _dailyNoteDate(NoteItem note) {
  final match = RegExp(
    r'^Diário - (\d{2})/(\d{2})/(\d{4})$',
  ).firstMatch(note.title.trim());
  if (match == null) {
    return null;
  }
  return DateTime.utc(
    int.parse(match.group(3)!),
    int.parse(match.group(2)!),
    int.parse(match.group(1)!),
  );
}
