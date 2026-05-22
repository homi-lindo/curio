import 'dart:convert';

import 'package:lume_core/domain/app_snapshot.dart';
import 'package:lume_core/domain/reminder.dart';

final class ManualBackupCodec {
  const ManualBackupCodec();

  String encode(AppSnapshot snapshot, {DateTime? generatedAtUtc}) {
    final generatedAt = (generatedAtUtc ?? DateTime.now().toUtc()).toUtc();
    final buffer = StringBuffer()
      ..writeln('Curió Backup TXT')
      ..writeln('Versão: 1')
      ..writeln('Gerado em: ${_formatDateTime(generatedAt)}')
      ..writeln('Notas: ${snapshot.notes.length}')
      ..writeln('Notificações: ${snapshot.scheduledNotifications.length}')
      ..writeln()
      ..writeln('=== DIAS ===');

    final dailyNotes = <DateTime, List<NoteItem>>{};
    final generalNotes = <NoteItem>[];
    for (final note in snapshot.notes) {
      final date = _dailyNoteDate(note);
      if (date == null) {
        generalNotes.add(note);
      } else {
        dailyNotes.putIfAbsent(date, () => <NoteItem>[]).add(note);
      }
    }

    final notificationsByDate = <DateTime, List<ScheduledNotificationRecord>>{};
    for (final record in snapshot.scheduledNotifications) {
      final date = _dateOnly(record.scheduledForUtc);
      notificationsByDate
          .putIfAbsent(date, () => <ScheduledNotificationRecord>[])
          .add(record);
    }

    final dates = <DateTime>{
      ...dailyNotes.keys,
      ...notificationsByDate.keys,
    }.toList()..sort();

    if (dates.isEmpty) {
      buffer.writeln('Nenhum dia com nota ou notificação.');
    } else {
      for (final date in dates) {
        buffer
          ..writeln()
          ..writeln('## ${_formatDate(date)}');

        final notes = dailyNotes[date] ?? const <NoteItem>[];
        if (notes.isEmpty) {
          buffer.writeln('Notas: nenhuma.');
        } else {
          for (final note
              in notes..sort((a, b) => a.title.compareTo(b.title))) {
            _writeNote(buffer, note);
          }
        }

        final notifications =
            notificationsByDate[date] ?? const <ScheduledNotificationRecord>[];
        if (notifications.isEmpty) {
          buffer.writeln('Notificações: nenhuma.');
        } else {
          buffer.writeln('Notificações:');
          for (final record
              in notifications..sort(
                (a, b) => a.scheduledForUtc.compareTo(b.scheduledForUtc),
              )) {
            _writeNotification(buffer, record);
          }
        }
      }
    }

    buffer
      ..writeln()
      ..writeln('=== NOTAS GERAIS ===');
    if (generalNotes.isEmpty) {
      buffer.writeln('Nenhuma nota geral.');
    } else {
      for (final note
          in generalNotes..sort((a, b) => a.title.compareTo(b.title))) {
        _writeNote(buffer, note);
      }
    }

    final payload = base64.encode(utf8.encode(jsonEncode(snapshot.toJson())));
    buffer
      ..writeln()
      ..writeln('=== DADOS DE RESTAURAÇÃO CURIO ===')
      ..writeln(
        'O bloco abaixo mantém IDs, datas e notificações para restauração funcional.',
      )
      ..writeln(_backupBegin);
    for (var index = 0; index < payload.length; index += 76) {
      final end = index + 76 > payload.length ? payload.length : index + 76;
      buffer.writeln(payload.substring(index, end));
    }
    buffer.writeln(_backupEnd);

    return buffer.toString();
  }

  AppSnapshot decode(String backupText) {
    final start = backupText.indexOf(_backupBegin);
    final end = backupText.indexOf(_backupEnd);
    if (start < 0 || end < 0 || end <= start) {
      throw const ManualBackupException(
        'Backup TXT sem bloco de restauração Curió.',
      );
    }

    final rawPayload = backupText
        .substring(start + _backupBegin.length, end)
        .replaceAll(RegExp(r'\s+'), '');
    if (rawPayload.isEmpty) {
      throw const ManualBackupException('Bloco de restauração vazio.');
    }

    try {
      final jsonText = utf8.decode(base64.decode(rawPayload));
      final json = jsonDecode(jsonText);
      if (json is! Map) {
        throw const FormatException('raiz não é objeto');
      }
      return AppSnapshot.fromJson(Map<String, Object?>.from(json));
    } on Object catch (error) {
      throw ManualBackupException('Backup TXT inválido: $error');
    }
  }

  void _writeNote(StringBuffer buffer, NoteItem note) {
    buffer
      ..writeln()
      ..writeln('### Nota: ${note.title}')
      ..writeln('ID: ${note.id}')
      ..writeln('Criada: ${_formatDateTime(note.createdAtUtc)}')
      ..writeln('Atualizada: ${_formatDateTime(note.updatedAtUtc)}')
      ..writeln('Texto:')
      ..writeln('----- INÍCIO DA NOTA -----')
      ..writeln(note.body.trimRight())
      ..writeln('----- FIM DA NOTA -----');
  }

  void _writeNotification(
    StringBuffer buffer,
    ScheduledNotificationRecord record,
  ) {
    buffer
      ..writeln(
        '- ${_formatTime(record.scheduledForUtc)} | '
        '${record.title.trim().isEmpty ? 'Notificação' : record.title.trim()}',
      )
      ..writeln('  ID: ${record.id}')
      ..writeln('  Dono: ${record.ownerType.name}:${record.ownerId}')
      ..writeln('  UTC: ${record.scheduledForUtc.toUtc().toIso8601String()}')
      ..writeln(
        '  Timezone: ${record.scheduledTimeZone.isEmpty ? 'n/d' : record.scheduledTimeZone}',
      );
    final body = record.body.trim();
    if (body.isNotEmpty) {
      buffer.writeln('  Mensagem: $body');
    }
  }
}

final class ManualBackupException implements Exception {
  const ManualBackupException(this.message);

  final String message;

  @override
  String toString() => message;
}

DateTime? _dailyNoteDate(NoteItem note) {
  final match = RegExp(
    r'^Diário - (\d{2})/(\d{2})/(\d{4})$',
  ).firstMatch(note.title.trim());
  if (match == null) {
    return null;
  }

  final day = int.tryParse(match.group(1)!);
  final month = int.tryParse(match.group(2)!);
  final year = int.tryParse(match.group(3)!);
  if (day == null || month == null || year == null) {
    return null;
  }
  if (month < 1 || month > 12) {
    return null;
  }
  final lastDay = DateTime(year, month + 1, 0).day;
  if (day < 1 || day > lastDay) {
    return null;
  }
  return DateTime(year, month, day);
}

DateTime _dateOnly(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}

String _formatDateTime(DateTime dateTime) {
  return '${_formatDate(dateTime)} ${_formatTime(dateTime)}';
}

String _formatDate(DateTime dateTime) {
  final local = dateTime.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/'
      '${local.month.toString().padLeft(2, '0')}/${local.year}';
}

String _formatTime(DateTime dateTime) {
  final local = dateTime.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

const _backupBegin = '-----BEGIN CURIO BACKUP DATA-----';
const _backupEnd = '-----END CURIO BACKUP DATA-----';
