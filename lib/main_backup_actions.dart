part of 'main.dart';

/// Upper bound for an imported `.ics` file. Real calendars are tiny; this just
/// stops a pathologically large picked file from being read fully into memory.
const int _maxIcsImportBytes = 10 * 1024 * 1024;

/// Manual TXT backup and calendar (.ics) import/export actions.
///
/// Self-contained: owns its codecs and depends only on the host state surface
/// declared below. Methods are moved verbatim and behave identically.
mixin _BackupActions on State<CurioApp> {
  final ManualBackupCodec _manualBackupCodec = const ManualBackupCodec();
  final CalendarIcsCodec _calendarIcsCodec = const CalendarIcsCodec();

  AppSnapshot? get _snapshot;
  String get _deviceId;
  BuildContext get _dialogContext;
  GlobalKey<ScaffoldMessengerState> get _messengerKey;
  ActionErrorDescriber get _errorDescriber;
  set _permissionState(NotificationPermissionState value);
  set _notificationComposerOpen(bool value);
  set _selectedIndex(int value);
  void _log(String message);
  void _applyState(VoidCallback mutate);
  Future<void> _saveSnapshot(AppSnapshot snapshot);
  Future<void> _runAction(Future<void> Function() action);
  Future<bool> _ensureNotificationCreationAuthorization();
  Future<void> _refreshPendingCount();
  void _syncSelectionAfterSnapshot(AppSnapshot snapshot);
  Future<AppSnapshot> _withoutNotificationRecord(
    AppSnapshot snapshot,
    ScheduledNotificationRecord record,
  );

  Future<void> _exportCalendarIcs() async {
    await _runAction(() async {
      final snapshot = _snapshot;
      if (snapshot == null) {
        return;
      }

      final ics = _calendarIcsCodec.encode(snapshot);
      final fileName =
          'curio-agenda-${_backupFileTimestamp(DateTime.now())}.ics';
      final path = await FilePicker.saveFile(
        dialogTitle: 'Exportar agenda para Outlook/Google',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const <String>['ics'],
        bytes: Uint8List.fromList(utf8.encode(ics)),
        lockParentWindow: true,
      );
      if (path == null) {
        return;
      }
      _log('agenda .ics exportada: $path');
    });
  }

  Future<void> _importCalendarIcs() async {
    await _runAction(() async {
      final result = await FilePicker.pickFiles(
        dialogTitle: 'Importar agenda do Outlook/Google',
        type: FileType.custom,
        allowedExtensions: const <String>['ics'],
        allowMultiple: false,
        withData: false,
      );
      final path = result?.files.single.path;
      if (path == null || path.trim().isEmpty) {
        return;
      }

      final file = File(path);
      final length = await file.length();
      if (length > _maxIcsImportBytes) {
        _log(
          'agenda não importada: arquivo .ics acima de '
          '${_maxIcsImportBytes ~/ (1024 * 1024)} MB',
        );
        return;
      }

      final import = _calendarIcsCodec.decode(await file.readAsString());
      await _applyCalendarImport(import);
      _log('agenda .ics importada: ${import.events.length} evento(s)');
      for (final warning in import.warnings) {
        _log('aviso do .ics: $warning');
      }
      if (import.warnings.isNotEmpty) {
        _messengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text(
              'Importação concluída com ${import.warnings.length} aviso(s) — '
              'detalhes na Atividade da aba Hoje.',
            ),
          ),
        );
      }
    });
  }

  Future<void> _applyCalendarImport(CalendarIcsImport import) async {
    final currentSnapshot = _snapshot;
    if (currentSnapshot == null) {
      return;
    }
    var snapshot = currentSnapshot;

    final nowUtc = DateTime.now().toUtc();
    final notificationEvents = import.events
        .where((event) => _calendarEventCanCreateNotification(event, nowUtc))
        .toList();
    if (notificationEvents.isNotEmpty) {
      final authorized = await _ensureNotificationCreationAuthorization();
      if (!authorized) {
        _log('agenda não importada: autorização de notificação pendente');
        return;
      }
    }

    final notes = <NoteItem>[...snapshot.notes];
    final importedRecords = <ScheduledNotificationRecord>[];
    final importedIntents = <ReminderIntent>[];
    final seenIntentIds = <String>{};
    var notesChanged = 0;
    var notificationsChanged = 0;

    for (final event in import.events) {
      final localDate = dateOnly(event.startsAtUtc.toLocal());
      final note = _upsertImportedDailyNote(
        notes,
        date: localDate,
        event: event,
        nowUtc: nowUtc,
      );
      if (note.changed) {
        notesChanged++;
      }

      if (!_calendarEventCanCreateNotification(event, nowUtc)) {
        continue;
      }

      final intentId = event.reminderId;
      final notificationUtc = _calendarEventNotificationUtc(event, nowUtc);

      // Dedup by stable identity: a repeated VEVENT in the same file is skipped,
      // and an event already imported before is updated in place (the old
      // record is removed, then rescheduled below). Two genuinely different
      // events are never collapsed just because they share a title and time.
      if (!seenIntentIds.add(intentId)) {
        continue;
      }
      final existingRecord = snapshot.scheduledNotifications
          .where((record) => record.reminderIntentId == intentId)
          .firstOrNull;
      if (existingRecord != null) {
        snapshot = await _withoutNotificationRecord(snapshot, existingRecord);
      }

      final intent = _calendarImportReminderIntent(
        event: event,
        noteId: note.note.id,
        notificationUtc: notificationUtc,
        nowUtc: nowUtc,
        timeZone: widget.notifications.localTimeZoneId,
      ).copyWith(title: event.title, body: event.description);
      final result = await widget.notifications.scheduleReminder(
        intent: intent,
        deviceId: _deviceId,
        title: intent.title,
        body: intent.body,
      );
      if (result != null) {
        importedRecords.add(result.record);
        importedIntents.add(intent);
        notificationsChanged++;
      }
    }

    snapshot = snapshot.copyWith(
      notes: notes,
      scheduledNotifications: <ScheduledNotificationRecord>[
        ...importedRecords,
        ...snapshot.scheduledNotifications,
      ],
      reminders: <ReminderIntent>[
        ...importedIntents,
        ...snapshot.reminders.where(
          (existing) =>
              !importedIntents.any((intent) => intent.id == existing.id),
        ),
      ],
    );
    await _saveSnapshot(snapshot);
    _syncSelectionAfterSnapshot(snapshot);
    await _refreshPendingCount();
    _log(
      'agenda aplicada: $notesChanged nota(s), '
      '$notificationsChanged notificação(ões)',
    );
  }

  Future<void> _copyManualBackup() async {
    await _runAction(() async {
      final snapshot = _snapshot;
      if (snapshot == null) {
        return;
      }

      final backup = _manualBackupCodec.encode(snapshot);
      File? file;
      try {
        file = await _writeManualBackupFile(backup);
      } on Object catch (error) {
        _log('backup TXT não salvo: ${_errorDescriber.describe(error)}');
        _messengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text(
              'Backup TXT não salvo: ${_errorDescriber.describe(error)}',
            ),
          ),
        );
      }
      await Clipboard.setData(ClipboardData(text: backup));
      _log(
        file == null
            ? 'backup TXT copiado: ${snapshot.notes.length} nota(s), '
                  '${snapshot.scheduledNotifications.length} notificação(ões)'
            : 'backup TXT salvo e copiado: ${file.path}',
      );
      if (file != null) {
        _log(
          'backup inclui ${snapshot.notes.length} nota(s), '
          '${snapshot.scheduledNotifications.length} notificação(ões)',
        );
      }
    });
  }

  Future<File> _writeManualBackupFile(String backup) async {
    final directory = await _manualBackupDirectory();
    final timestamp = _backupFileTimestamp(DateTime.now());
    final file = File(
      '${directory.path}${Platform.pathSeparator}curio-backup-$timestamp.txt',
    );
    await file.writeAsString(backup, flush: true);
    return file;
  }

  Future<Directory> _manualBackupDirectory() async {
    try {
      final downloads = await getDownloadsDirectory();
      if (downloads != null) {
        return downloads;
      }
    } on Object {
      // Android may not expose a public Downloads directory through path_provider.
    }
    return getApplicationDocumentsDirectory();
  }

  Future<void> _showRestoreBackupDialog() async {
    final controller = TextEditingController();
    try {
      final clipboard = await Clipboard.getData('text/plain');
      controller.text = clipboard?.text ?? '';
      controller.selection = TextSelection.collapsed(
        offset: controller.text.length,
      );

      if (!mounted) {
        return;
      }

      final backupText = await showDialog<String>(
        context: _dialogContext,
        builder: (context) {
          return AlertDialog(
            title: const Text('Restaurar backup TXT'),
            content: SizedBox(
              width: 620,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Cole o TXT gerado pelo Curió. A restauração substitui '
                    'as notas e notificações locais e reagenda alertas futuros.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    autofocus: controller.text.trim().isEmpty,
                    minLines: 12,
                    maxLines: 18,
                    keyboardType: TextInputType.multiline,
                    decoration: const InputDecoration(
                      alignLabelWithHint: true,
                      labelText: 'Backup TXT',
                      hintText: 'Curió Backup TXT...',
                    ),
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(controller.text),
                child: const Text('Restaurar'),
              ),
            ],
          );
        },
      );

      if (backupText == null || backupText.trim().isEmpty) {
        return;
      }

      final restored = _manualBackupCodec.decode(backupText);
      await _restoreManualBackup(restored);
    } on ManualBackupException catch (error) {
      _log('backup não restaurado: ${error.message}');
      _messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('Backup não restaurado: ${error.message}')),
      );
    } on Object catch (error) {
      _log('backup não restaurado: ${_errorDescriber.describe(error)}');
      _messengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text(
            'Backup não restaurado: ${_errorDescriber.describe(error)}',
          ),
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _restoreManualBackup(AppSnapshot backupSnapshot) async {
    await _runAction(() async {
      final current = _snapshot;
      if (current == null) {
        return;
      }

      final nowUtc = DateTime.now().toUtc();
      final futureRecords = backupSnapshot.scheduledNotifications
          .where((record) => record.scheduledForUtc.toUtc().isAfter(nowUtc))
          .toList();
      if (futureRecords.isNotEmpty) {
        final authorized = await _ensureNotificationCreationAuthorization();
        if (!authorized) {
          _log('backup não restaurado: autorização de notificação pendente');
          return;
        }
      }

      final rescheduled = <ScheduledNotificationRecord>[];
      final rescheduledIntents = <ReminderIntent>[];
      for (final record in futureRecords) {
        final intent = ReminderIntent.oneShot(
          id: record.reminderIntentId,
          ownerId: record.ownerId,
          ownerType: record.ownerType,
          instantUtc: record.scheduledForUtc,
          updatedAtUtc: nowUtc,
          timeZone: widget.notifications.localTimeZoneId,
          title: record.title.trim().isEmpty
              ? 'Notificação'
              : record.title.trim(),
          body: record.body.trim(),
        );
        try {
          final result = await widget.notifications.scheduleReminder(
            intent: intent,
            deviceId: _deviceId,
            title: intent.title,
            body: intent.body,
          );
          if (result != null) {
            rescheduled.add(result.record);
            rescheduledIntents.add(intent);
            _applyState(() => _permissionState = result.permissionState);
          } else {
            for (final scheduled in rescheduled) {
              await widget.notifications.cancel(scheduled.id);
            }
            _log('backup não restaurado: notificação sem próxima ocorrência');
            return;
          }
        } on Object catch (error) {
          for (final scheduled in rescheduled) {
            await widget.notifications.cancel(scheduled.id);
          }
          _log(
            'backup não restaurado: notificação não agendada '
            '(${_errorDescriber.describe(error)})',
          );
          return;
        }
      }

      for (final record in current.scheduledNotifications) {
        try {
          await widget.notifications.cancel(record.id);
        } on Object catch (error) {
          _log(
            'notificação antiga não cancelada: '
            '${_errorDescriber.describe(error)}',
          );
        }
      }

      final futureIds = futureRecords.map((record) => record.id).toSet();
      final retainedRecords = backupSnapshot.scheduledNotifications
          .where((record) => !futureIds.contains(record.id))
          .toList();
      final next = backupSnapshot.copyWith(
        scheduledNotifications: <ScheduledNotificationRecord>[
          ...rescheduled,
          ...retainedRecords,
        ],
        reminders: <ReminderIntent>[
          ...rescheduledIntents,
          ...backupSnapshot.reminders.where(
            (existing) =>
                !rescheduledIntents.any((intent) => intent.id == existing.id),
          ),
        ],
      );

      await _saveSnapshot(next);
      _syncSelectionAfterSnapshot(next);
      _applyState(() {
        _notificationComposerOpen = false;
        _selectedIndex = _AppTab.sync.index;
      });
      await _refreshPendingCount();
      _log(
        'backup TXT restaurado: ${next.notes.length} nota(s), '
        '${next.scheduledNotifications.length} notificação(ões)',
      );
    });
  }
}
