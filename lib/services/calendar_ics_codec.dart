import 'package:lume_core/domain/app_snapshot.dart';

final class CalendarIcsCodec {
  const CalendarIcsCodec();

  String encode(AppSnapshot snapshot, {DateTime? generatedAtUtc}) {
    final generated = generatedAtUtc ?? DateTime.now().toUtc();
    final buffer = StringBuffer()
      ..writeln('BEGIN:VCALENDAR')
      ..writeln('VERSION:2.0')
      ..writeln('PRODID:-//Curio//Agenda//PT-BR')
      ..writeln('CALSCALE:GREGORIAN')
      ..writeln('METHOD:PUBLISH');

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
        curioType: 'NOTIFICATION',
      );
    }

    buffer.writeln('END:VCALENDAR');
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
    DateTime? allDayDate,
  }) {
    buffer
      ..writeln('BEGIN:VEVENT')
      ..writeln('UID:${_escapeText(uid)}')
      ..writeln('DTSTAMP:${_formatUtc(generatedAtUtc)}')
      ..writeln('SUMMARY:${_escapeText(summary)}')
      ..writeln('DESCRIPTION:${_escapeText(description)}')
      ..writeln('X-CURIO-TYPE:$curioType');
    if (allDayDate != null) {
      buffer.writeln('DTSTART;VALUE=DATE:${_formatDate(allDayDate)}');
    } else {
      buffer.writeln('DTSTART:${_formatUtc(startsAtUtc!.toUtc())}');
    }
    buffer.writeln('END:VEVENT');
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
    required this.allDay,
    required this.curioType,
  });

  final String uid;
  final String title;
  final String description;
  final DateTime startsAtUtc;
  final bool allDay;
  final String curioType;
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
  final startsAt = allDay
      ? _parseDate(dtStart.value)
      : _parseDateTime(dtStart.value);
  final title = _unescapeText(value('SUMMARY') ?? 'Evento importado').trim();

  return CalendarIcsEvent(
    uid: _unescapeText(value('UID') ?? title),
    title: title.isEmpty ? 'Evento importado' : title,
    description: _unescapeText(value('DESCRIPTION') ?? ''),
    startsAtUtc: startsAt.toUtc(),
    allDay: allDay,
    curioType: (value('X-CURIO-TYPE') ?? '').toUpperCase(),
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

DateTime _parseDateTime(String value) {
  final compact = value.trim();
  if (compact.length < 15) {
    throw const CalendarIcsException('Data/hora inválida no .ics.');
  }
  final dateTime = DateTime(
    int.parse(compact.substring(0, 4)),
    int.parse(compact.substring(4, 6)),
    int.parse(compact.substring(6, 8)),
    int.parse(compact.substring(9, 11)),
    int.parse(compact.substring(11, 13)),
    int.parse(compact.substring(13, 15)),
  );
  return compact.endsWith('Z')
      ? DateTime.utc(
          dateTime.year,
          dateTime.month,
          dateTime.day,
          dateTime.hour,
          dateTime.minute,
          dateTime.second,
        )
      : dateTime.toUtc();
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
