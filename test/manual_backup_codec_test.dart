import 'package:flutter_test/flutter_test.dart';
import 'package:lume/services/manual_backup_codec.dart';
import 'package:lume_core/domain/app_snapshot.dart';
import 'package:lume_core/domain/reminder.dart';

void main() {
  test('encodes a readable TXT grouped by day', () {
    final snapshot = _snapshot();
    final backup = const ManualBackupCodec().encode(
      snapshot,
      generatedAtUtc: DateTime.utc(2026, 5, 22, 12),
    );

    expect(backup, contains('Curió Backup TXT'));
    expect(backup, contains('=== DIAS ==='));
    expect(backup, contains('## 22/05/2026'));
    expect(backup, contains('### Nota: Diário - 22/05/2026'));
    expect(backup, contains('Revisar backup manual'));
    expect(backup, contains('Notificações:'));
    expect(backup, contains('Enviar relatório'));
    expect(backup, contains('=== NOTAS GERAIS ==='));
    expect(backup, contains('### Nota: Ideias'));
    expect(backup, contains('-----BEGIN CURIO BACKUP DATA-----'));
    expect(backup, contains('-----END CURIO BACKUP DATA-----'));
  });

  test('decodes the restoration block into the original snapshot', () {
    final snapshot = _snapshot();
    final backup = const ManualBackupCodec().encode(snapshot);

    final restored = const ManualBackupCodec().decode(backup);

    expect(restored.toJson(), snapshot.toJson());
  });

  test('rejects TXT without Curió restoration block', () {
    expect(
      () => const ManualBackupCodec().decode('somente texto comum'),
      throwsA(isA<ManualBackupException>()),
    );
  });

  test('escreve a linha de verificação SHA-256 após o bloco', () {
    final backup = const ManualBackupCodec().encode(_snapshot());

    final endIndex = backup.indexOf('-----END CURIO BACKUP DATA-----');
    final afterEnd = backup.substring(endIndex);
    expect(afterEnd, contains('Verificação SHA-256: '));
    expect(
      RegExp(r'Verificação SHA-256: [0-9a-f]{64}').hasMatch(afterEnd),
      isTrue,
    );
  });

  test('detecta payload adulterado pela verificação SHA-256', () {
    final backup = const ManualBackupCodec().encode(_snapshot());

    // Troca um caractere dentro do bloco base64 sem quebrar o formato.
    final begin =
        backup.indexOf('-----BEGIN CURIO BACKUP DATA-----') +
        '-----BEGIN CURIO BACKUP DATA-----'.length;
    final tamperIndex = begin + 10;
    final original = backup[tamperIndex];
    final replacement = original == 'A' ? 'B' : 'A';
    final tampered = backup.replaceRange(
      tamperIndex,
      tamperIndex + 1,
      replacement,
    );

    expect(
      () => const ManualBackupCodec().decode(tampered),
      throwsA(
        isA<ManualBackupException>().having(
          (error) => error.message,
          'message',
          contains('SHA-256'),
        ),
      ),
    );
  });

  test('detecta payload truncado pela verificação SHA-256', () {
    final backup = const ManualBackupCodec().encode(_snapshot());

    // Remove uma linha inteira do meio do bloco base64, mantendo os
    // marcadores e a linha de verificação — exatamente o cenário de arquivo
    // cortado que o base64 toleraria em silêncio.
    final lines = backup.split('\n');
    final beginLine = lines.indexWhere(
      (line) => line.contains('BEGIN CURIO BACKUP DATA'),
    );
    final truncated = [...lines]..removeAt(beginLine + 1);

    expect(
      () => const ManualBackupCodec().decode(truncated.join('\n')),
      throwsA(
        isA<ManualBackupException>().having(
          (error) => error.message,
          'message',
          contains('SHA-256'),
        ),
      ),
    );
  });

  test('aceita backup legado sem linha de verificação', () {
    final snapshot = _snapshot();
    final backup = const ManualBackupCodec().encode(snapshot);

    final legacy = backup
        .split('\n')
        .where((line) => !line.startsWith('Verificação SHA-256: '))
        .join('\n');

    final restored = const ManualBackupCodec().decode(legacy);
    expect(restored.toJson(), snapshot.toJson());
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
      NoteItem(
        id: 'note-general',
        title: 'Ideias',
        body: '- manter TXT legível\n- restaurar notificações',
        createdAtUtc: DateTime.utc(2026, 5, 21, 10),
        updatedAtUtc: DateTime.utc(2026, 5, 21, 11),
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
