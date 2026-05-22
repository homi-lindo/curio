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
