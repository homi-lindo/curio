import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lume_core/domain/app_snapshot.dart';
import 'package:lume_core/domain/reminder.dart';
import 'package:lume_core/sync/sync_adapter.dart';

import 'app_brand.dart';
import 'services/action_error_describer.dart';
import 'services/appearance_settings_store.dart';
import 'services/async_action_gate.dart';
import 'services/device_identity.dart';
import 'services/local_store.dart';
import 'services/local_sync_sidecar.dart';
import 'services/lume_widgets_binding.dart';
import 'services/note_edit_history_store.dart';
import 'services/notification_service.dart';
import 'services/notification_timezone_audit.dart';
import 'services/snapshot_write_queue.dart';
import 'services/sync_settings_store.dart';
import 'services/sync_settings_validator.dart';
import 'sync/http_sync_adapter.dart';
import 'theme/curio_theme.dart';
import 'ui/agenda_calendar.dart';
import 'ui/markdown_editor.dart';
import 'ui/task_view_helpers.dart';
import 'ui/zoomed_page.dart';

Future<void> main() async {
  LumeWidgetsBinding.ensureInitialized();
  runApp(CurioApp(notifications: NotificationService()));
}

final class CurioApp extends StatefulWidget {
  CurioApp({
    super.key,
    required this.notifications,
    LocalStore? store,
    DeviceIdentityStore? deviceIdentity,
    SyncSettingsStore? syncSettings,
    AppearanceSettingsStore? appearanceSettings,
    NoteEditHistoryStore? noteHistory,
  }) : store = store ?? LocalStore(),
       deviceIdentity = deviceIdentity ?? DeviceIdentityStore(),
       syncSettings = syncSettings ?? SyncSettingsStore(),
       appearanceSettings = appearanceSettings ?? AppearanceSettingsStore(),
       noteHistory = noteHistory ?? NoteEditHistoryStore();

  final NotificationService notifications;
  final LocalStore store;
  final DeviceIdentityStore deviceIdentity;
  final SyncSettingsStore syncSettings;
  final AppearanceSettingsStore appearanceSettings;
  final NoteEditHistoryStore noteHistory;

  @override
  State<CurioApp> createState() => _CurioAppState();
}

final class _CurioAppState extends State<CurioApp> {
  late final Future<void> _startup;
  late final TextEditingController _noteController;
  late final TextEditingController _syncServerController;
  late final TextEditingController _syncTokenController;
  late final LocalSyncSidecar _syncSidecar;
  late final SnapshotWriteQueue _snapshotWrites;
  final AsyncActionGate _actionGate = AsyncActionGate();
  final ActionErrorDescriber _errorDescriber = const ActionErrorDescriber();
  final SyncSettingsValidator _syncSettingsValidator =
      const SyncSettingsValidator();

  int _selectedIndex = 0;
  double _uiZoom = 1;
  DateTime _agendaDate = dateOnly(DateTime.now());
  DateTime _notesDate = dateOnly(DateTime.now());
  bool _busy = false;
  String _deviceId = 'lume-${defaultTargetPlatform.name}';
  SyncSettings _syncSettings = const SyncSettings();
  AppearanceSettings _appearance = const AppearanceSettings();
  LocalSyncSidecarState? _syncSidecarState;
  SyncResult? _lastSyncResult;
  AppSnapshot? _snapshot;
  String? _selectedNoteId;
  List<NoteEditRevision> _noteHistory = const <NoteEditRevision>[];
  final Map<String, DateTime> _lastHistoryAtByNote = <String, DateTime>{};
  NotificationPermissionState _permissionState =
      const NotificationPermissionState();
  ScheduleResult? _lastSchedule;
  String? _lastNotificationLabel;
  int _pendingCount = 0;
  final List<String> _activity = <String>[];

  @override
  void initState() {
    super.initState();
    _noteController = TextEditingController();
    _syncServerController = TextEditingController();
    _syncTokenController = TextEditingController();
    _snapshotWrites = SnapshotWriteQueue(saveSnapshot: widget.store.save);
    _syncSidecar = LocalSyncSidecar(
      loadSnapshot: () async => _snapshot ?? await widget.store.load(),
      saveSnapshot: (snapshot) async {
        await _saveSnapshot(snapshot);
        if (mounted) {
          setState(() => _syncSelectionAfterSnapshot(snapshot));
        }
      },
    );
    _startup = _initialize();
  }

  @override
  void dispose() {
    _noteController.dispose();
    _syncServerController.dispose();
    _syncTokenController.dispose();
    unawaited(_syncSidecar.stop());
    super.dispose();
  }

  Future<void> _initialize() async {
    await widget.notifications.initialize(
      onNotificationSelected: (payload) {
        if (!mounted) {
          return;
        }
        setState(() {
          _lastNotificationLabel = _notificationEventLabel(payload);
          _selectedIndex = 0;
        });
        _log('notificação aberta');
      },
    );

    final launchDetails = await widget.notifications.getLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp ?? false) {
      _lastNotificationLabel = _notificationEventLabel(
        launchDetails?.notificationResponse?.payload,
      );
    }

    final deviceId = await widget.deviceIdentity.load();
    final syncSettings = await widget.syncSettings.load();
    final appearance = await widget.appearanceSettings.load();
    final noteHistory = await widget.noteHistory.load();
    final snapshot = await widget.store.load();
    if (mounted) {
      setState(() {
        _deviceId = deviceId;
        _syncSettings = syncSettings;
        _appearance = appearance;
        _syncServerController.text = syncSettings.serverUrl;
        _syncTokenController.text = syncSettings.authToken;
        _snapshot = snapshot;
        _noteHistory = noteHistory;
        _selectedNoteId = snapshot.notes.firstOrNull?.id;
        _noteController.text = snapshot.notes.firstOrNull?.body ?? '';
      });
    } else {
      _deviceId = deviceId;
      _syncSettings = syncSettings;
      _appearance = appearance;
      _syncServerController.text = syncSettings.serverUrl;
      _syncTokenController.text = syncSettings.authToken;
      _snapshot = snapshot;
      _noteHistory = noteHistory;
      _selectedNoteId = snapshot.notes.firstOrNull?.id;
      _noteController.text = snapshot.notes.firstOrNull?.body ?? '';
    }

    await _refreshPendingCount();
    await _refreshPermissionState();
    await widget.store.file;
    _log('armazenamento local pronto');
    _log('identidade local pronta');
    _log('timezone local: ${widget.notifications.localTimeZoneId}');
    final driftedNotifications = const NotificationTimeZoneAudit()
        .driftedRecords(
          records: snapshot.scheduledNotifications,
          currentTimeZone: widget.notifications.localTimeZoneId,
        );
    if (driftedNotifications.isNotEmpty) {
      _log('timezone mudou: revise ${driftedNotifications.length} lembrete(s)');
    }
  }

  Future<void> _refreshPendingCount() async {
    try {
      final pending = await widget.notifications.pending();
      if (!mounted) {
        return;
      }
      setState(() => _pendingCount = pending.length);
    } on Object catch (error) {
      _log('pendentes indisponíveis: ${_errorDescriber.describe(error)}');
    }
  }

  Future<void> _refreshPermissionState() async {
    try {
      final state = await widget.notifications.currentPermissionState();
      if (!mounted) {
        return;
      }
      setState(() => _permissionState = state);
    } on Object catch (error) {
      _log('permissões indisponíveis: ${_errorDescriber.describe(error)}');
    }
  }

  Future<void> _requestPermissions() async {
    await _runAction(() async {
      final state = await widget.notifications.requestPermissions();
      setState(() => _permissionState = state);
      _log('permissões: ${state.label}');
    });
  }

  Future<void> _cancelLast() async {
    final last = _lastSchedule;
    if (last == null) {
      _log('nada para cancelar ainda');
      return;
    }

    await _runAction(() async {
      await widget.notifications.cancel(last.record.id);
      final snapshot = _snapshot;
      if (snapshot != null) {
        await _saveSnapshot(
          snapshot.copyWith(
            scheduledNotifications: snapshot.scheduledNotifications
                .where((record) => record.id != last.record.id)
                .toList(),
          ),
        );
      }
      _log('notificação cancelada');
      await _refreshPendingCount();
    });
  }

  Future<void> _addNotificationForSelectedNote() async {
    final note = _selectedNote(_snapshot);
    if (note == null) {
      return;
    }

    final localDate = dailyNoteDate(note) ?? _notesDate;
    final draft = await _showNotificationEditor(
      note: note,
      initialLocal: _defaultNotificationLocalForDate(localDate),
    );
    if (draft == null || draft.title.trim().isEmpty) {
      return;
    }

    await _upsertNoteNotification(note: note, draft: draft);
  }

  Future<void> _editNotification(ScheduledNotificationRecord record) async {
    final snapshot = _snapshot;
    final note = snapshot?.notes
        .where((candidate) => candidate.id == record.ownerId)
        .firstOrNull;
    final draft = await _showNotificationEditor(
      note: note,
      record: record,
      initialLocal: record.scheduledForUtc.toLocal(),
    );
    if (draft == null || draft.title.trim().isEmpty) {
      return;
    }

    await _upsertNoteNotification(note: note, draft: draft, existing: record);
  }

  Future<void> _cancelNotification(ScheduledNotificationRecord record) async {
    await _runAction(() async {
      final snapshot = _snapshot;
      if (snapshot == null) {
        return;
      }
      final next = await _withoutNotificationRecord(snapshot, record);
      await _saveSnapshot(next);
      _log('notificação removida');
      await _refreshPendingCount();
    });
  }

  Future<void> _upsertNoteNotification({
    required NoteItem? note,
    required _NotificationDraft draft,
    ScheduledNotificationRecord? existing,
  }) async {
    await _runAction(() async {
      var snapshot = _snapshot;
      if (snapshot == null) {
        return;
      }

      final scheduledAtUtc = draft.scheduledAtUtc.toUtc();
      if (!scheduledAtUtc.isAfter(DateTime.now().toUtc())) {
        _log('notificação ignorada: horário no passado');
        return;
      }

      if (existing != null) {
        snapshot = await _withoutNotificationRecord(snapshot, existing);
      }

      final ownerId = note?.id ?? existing?.ownerId ?? _newId('note-alert');
      final intent = ReminderIntent.oneShot(
        id:
            existing?.reminderIntentId ??
            'note-$ownerId-${DateTime.now().toUtc().microsecondsSinceEpoch}',
        ownerId: ownerId,
        ownerType: ReminderOwnerType.note,
        instantUtc: scheduledAtUtc,
        updatedAtUtc: DateTime.now().toUtc(),
        timeZone: widget.notifications.localTimeZoneId,
      );

      final ScheduleResult? result;
      try {
        result = await widget.notifications.scheduleReminder(
          intent: intent,
          deviceId: _deviceId,
          title: draft.title.trim(),
          body: draft.body.trim(),
        );
      } on Object catch (error) {
        _log('notificação não agendada: ${_errorDescriber.describe(error)}');
        return;
      }
      if (result == null) {
        return;
      }

      final scheduled = result;
      setState(() {
        _lastSchedule = scheduled;
        _permissionState = scheduled.permissionState;
      });
      await _saveSnapshot(
        snapshot.copyWith(
          scheduledNotifications: <ScheduledNotificationRecord>[
            scheduled.record,
            ...snapshot.scheduledNotifications.where(
              (record) =>
                  record.id != scheduled.record.id && record.id != existing?.id,
            ),
          ],
        ),
      );
      _log(
        '${existing == null ? 'notificação criada' : 'notificação atualizada'}: '
        '${formatLocal(scheduled.plan.scheduledLocal)}',
      );
      await _refreshPendingCount();
    });
  }

  Future<AppSnapshot> _withoutNotificationRecord(
    AppSnapshot snapshot,
    ScheduledNotificationRecord record,
  ) async {
    try {
      await widget.notifications.cancel(record.id);
    } on Object catch (error) {
      _log(
        'notificação antiga não cancelada: ${_errorDescriber.describe(error)}',
      );
    }

    return snapshot.copyWith(
      scheduledNotifications: snapshot.scheduledNotifications
          .where((candidate) => candidate.id != record.id)
          .toList(),
    );
  }

  Future<void> _addNote() async {
    final title = await _promptText(
      title: 'Nova nota',
      hint: 'Título da nota',
      confirmLabel: 'Criar',
    );
    if (title == null || title.trim().isEmpty) {
      return;
    }

    final snapshot = _snapshot;
    if (snapshot == null) {
      return;
    }

    final now = DateTime.now().toUtc();
    final note = NoteItem(
      id: _newId('note'),
      title: title.trim(),
      body: '',
      createdAtUtc: now,
      updatedAtUtc: now,
    );

    await _saveSnapshot(
      snapshot.copyWith(notes: <NoteItem>[note, ...snapshot.notes]),
    );
    setState(() {
      _selectedNoteId = note.id;
      _noteController.text = note.body;
    });
    _log('nota criada');
  }

  Future<void> _renameSelectedNote() async {
    final snapshot = _snapshot;
    final selected = _selectedNote(snapshot);
    if (snapshot == null || selected == null) {
      return;
    }

    final title = await _promptText(
      title: 'Renomear nota',
      hint: 'Título da nota',
      initialValue: selected.title,
      confirmLabel: 'Salvar',
    );
    if (title == null || title.trim().isEmpty) {
      return;
    }

    final now = DateTime.now().toUtc();
    await _saveSnapshot(
      snapshot.copyWith(
        notes: snapshot.notes
            .map(
              (note) => note.id == selected.id
                  ? note.copyWith(title: title.trim(), updatedAtUtc: now)
                  : note,
            )
            .toList(),
      ),
    );
    _log('nota renomeada');
  }

  Future<void> _deleteSelectedNote() async {
    final snapshot = _snapshot;
    final selected = _selectedNote(snapshot);
    if (snapshot == null || selected == null) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Excluir nota'),
          content: Text('Excluir "${selected.title}"?'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Excluir'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }

    final now = DateTime.now().toUtc();
    await _recordNoteRevision(selected, now);
    final nextNotes = snapshot.notes
        .where((note) => note.id != selected.id)
        .toList();
    final nextSelected = nextNotes.firstOrNull;
    final next = _withDeletedRecord(
      snapshot.copyWith(
        notes: nextNotes,
        tasks: snapshot.tasks.map((task) {
          if (task.sourceNoteId != selected.id) {
            return task;
          }
          return task.copyWith(clearSourceNoteId: true, updatedAtUtc: now);
        }).toList(),
      ),
      DeletedRecord(
        recordType: SyncRecordType.note,
        recordId: selected.id,
        deletedAtUtc: now,
        deviceId: _deviceId,
      ),
    );

    await _saveSnapshot(next);
    setState(() {
      _selectedNoteId = nextSelected?.id;
      _noteController.text = nextSelected?.body ?? '';
    });
    _log('nota excluída');
  }

  Future<void> _openDailyNote(DateTime date) async {
    final selectedDate = dateOnly(date);
    final title = dailyNoteTitle(selectedDate);
    final snapshot = _snapshot;
    if (snapshot == null) {
      return;
    }

    final existing = snapshot.notes
        .where((note) => note.title == title)
        .firstOrNull;
    if (existing != null) {
      setState(() {
        _selectedNoteId = existing.id;
        _noteController.text = existing.body;
        _notesDate = selectedDate;
        _selectedIndex = 3;
      });
      _log('nota do dia aberta');
      return;
    }

    await _runAction(() async {
      final now = DateTime.now().toUtc();
      final note = NoteItem(
        id: _newId('note'),
        title: title,
        body: '## ${formatLocalDate(selectedDate)}\n\n',
        createdAtUtc: now,
        updatedAtUtc: now,
      );
      final next = snapshot.copyWith(
        notes: <NoteItem>[note, ...snapshot.notes],
      );
      await _saveSnapshot(next);
      setState(() {
        _snapshot = next;
        _selectedNoteId = note.id;
        _noteController.text = note.body;
        _notesDate = selectedDate;
        _selectedIndex = 3;
      });
      _log('nota do dia criada');
    });
  }

  Future<void> _openNotificationTarget(
    ScheduledNotificationRecord record,
  ) async {
    switch (record.ownerType) {
      case ReminderOwnerType.task:
        await _openDailyNote(record.scheduledForUtc);
      case ReminderOwnerType.note:
        final note = _snapshot?.notes
            .where((candidate) => candidate.id == record.ownerId)
            .firstOrNull;
        if (note != null) {
          setState(() {
            _selectedNoteId = note.id;
            _noteController.text = note.body;
            _notesDate =
                dailyNoteDate(note) ?? dateOnly(record.scheduledForUtc);
            _selectedIndex = 3;
          });
          return;
        }
        await _openDailyNote(record.scheduledForUtc);
    }
  }

  Future<void> _openDayEditor(DateTime date) async {
    await _openDailyNote(date);
  }

  Future<void> _openGlobalSearch() async {
    final snapshot = _snapshot;
    if (snapshot == null) {
      return;
    }

    final result = await showDialog<GlobalSearchResult>(
      context: context,
      builder: (context) => _GlobalSearchDialog(snapshot: snapshot),
    );
    if (result == null || !mounted) {
      return;
    }

    switch (result.kind) {
      case GlobalSearchResultKind.note:
        final note =
            _snapshot?.notes
                .where((candidate) => candidate.id == result.id)
                .firstOrNull ??
            result.note;
        if (note == null) {
          return;
        }
        setState(() {
          _selectedIndex = 3;
          _selectedNoteId = note.id;
          _noteController.text = note.body;
          _notesDate = dailyNoteDate(note) ?? _notesDate;
        });
      case GlobalSearchResultKind.notification:
        final notification =
            _snapshot?.scheduledNotifications
                .where((candidate) => candidate.id.toString() == result.id)
                .firstOrNull ??
            result.notification;
        if (notification == null) {
          return;
        }
        await _openNotificationTarget(notification);
        await _editNotification(notification);
    }
  }

  void _setUiZoom(double value) {
    setState(() => _uiZoom = clampPageZoom(value));
  }

  void _stepUiZoom(int steps) {
    _setUiZoom(stepPageZoom(_uiZoom, steps));
  }

  NoteItem? _selectedNote(AppSnapshot? snapshot) {
    final selectedNoteId = _selectedNoteId;
    if (snapshot == null || selectedNoteId == null) {
      return null;
    }
    return snapshot.notes
        .where((note) => note.id == selectedNoteId)
        .firstOrNull;
  }

  void _updateSelectedNoteBody(String body) {
    final snapshot = _snapshot;
    final selectedNoteId = _selectedNoteId;
    if (snapshot == null || selectedNoteId == null) {
      return;
    }

    final now = DateTime.now().toUtc();
    final selected = snapshot.notes
        .where((note) => note.id == selectedNoteId)
        .firstOrNull;
    if (selected == null || selected.body == body) {
      return;
    }
    unawaited(_recordNoteRevision(selected, now));
    final next = snapshot.copyWith(
      notes: snapshot.notes.map((note) {
        if (note.id != selectedNoteId) {
          return note;
        }
        return note.copyWith(body: body, updatedAtUtc: now);
      }).toList(),
    );
    unawaited(
      _saveSnapshot(next).catchError((Object error, StackTrace stackTrace) {
        _log('nota não salva: ${_errorDescriber.describe(error)}');
      }),
    );
  }

  Future<void> _recordNoteRevision(NoteItem note, DateTime savedAtUtc) async {
    final lastHistoryAt = _lastHistoryAtByNote[note.id];
    if (lastHistoryAt != null &&
        savedAtUtc.difference(lastHistoryAt) < const Duration(seconds: 3)) {
      return;
    }
    if (_noteHistory.isNotEmpty &&
        _noteHistory.first.noteId == note.id &&
        _noteHistory.first.body == note.body) {
      return;
    }

    _lastHistoryAtByNote[note.id] = savedAtUtc;
    final revision = NoteEditRevision(
      id: _newId('revision'),
      noteId: note.id,
      noteTitle: note.title,
      body: note.body,
      savedAtUtc: savedAtUtc,
    );

    try {
      final next = await widget.noteHistory.add(revision);
      if (mounted) {
        setState(() => _noteHistory = next);
      } else {
        _noteHistory = next;
      }
      _log('histórico salvo: ${note.title}');
    } on Object catch (error) {
      _log('histórico não salvo: ${_errorDescriber.describe(error)}');
    }
  }

  Future<void> _restoreNoteRevision(NoteEditRevision revision) async {
    await _runAction(() async {
      final snapshot = _snapshot;
      if (snapshot == null) {
        return;
      }

      final now = DateTime.now().toUtc();
      final existing = snapshot.notes
          .where((note) => note.id == revision.noteId)
          .firstOrNull;
      if (existing != null) {
        await _recordNoteRevision(existing, now);
      }

      final restored = existing == null
          ? NoteItem(
              id: revision.noteId,
              title: revision.noteTitle,
              body: revision.body,
              createdAtUtc: revision.savedAtUtc,
              updatedAtUtc: now,
            )
          : existing.copyWith(
              title: revision.noteTitle,
              body: revision.body,
              updatedAtUtc: now,
            );
      final nextNotes = existing == null
          ? <NoteItem>[restored, ...snapshot.notes]
          : snapshot.notes
                .map((note) => note.id == restored.id ? restored : note)
                .toList();
      final next = snapshot.copyWith(notes: nextNotes);
      await _saveSnapshot(next);
      setState(() {
        _selectedIndex = 3;
        _selectedNoteId = restored.id;
        _notesDate = dailyNoteDate(restored) ?? _notesDate;
        _noteController.text = restored.body;
      });
      _log('versão restaurada: ${revision.noteTitle}');
    });
  }

  Future<void> _saveSyncSettings() async {
    await _runAction(() async {
      final serverUrl = _syncSettingsValidator.normalizeServerUrl(
        _syncServerController.text,
      );
      final authToken = _syncTokenController.text.trim();
      _syncSettingsValidator.validate(
        serverUrl: serverUrl,
        authToken: authToken,
      );
      final settings = _syncSettings.copyWith(
        serverUrl: serverUrl,
        authToken: authToken,
      );
      await widget.syncSettings.save(settings);
      setState(() {
        _syncSettings = settings;
        _syncServerController.text = serverUrl;
        _syncTokenController.text = authToken;
      });
      _log(serverUrl.isEmpty ? 'sync local salvo' : 'sync remoto salvo');
    });
  }

  Future<void> _saveAppearanceSettings(AppearanceSettings settings) async {
    try {
      await widget.appearanceSettings.save(settings);
      if (mounted) {
        setState(() => _appearance = settings);
      } else {
        _appearance = settings;
      }
      _log(
        'aparência: ${settings.themeProfile.label} · ${settings.themeMode.label}',
      );
    } on Object catch (error) {
      _log('aparência não salva: ${_errorDescriber.describe(error)}');
    }
  }

  Future<void> _runSync() async {
    await _runAction(() async {
      final snapshot = _snapshot;
      if (snapshot == null) {
        return;
      }

      final serverUrl = _syncSettingsValidator.normalizeServerUrl(
        _syncServerController.text,
      );
      final authToken = _syncTokenController.text.trim();
      _syncSettingsValidator.validate(
        serverUrl: serverUrl,
        authToken: authToken,
      );
      final adapter = serverUrl.isEmpty
          ? const OfflineSyncAdapter()
          : HttpSyncAdapter(
              serverUrl: Uri.parse(serverUrl),
              authToken: authToken,
              allowInsecureHttp: kDebugMode,
            );
      final result = await adapter.synchronize(
        snapshot: snapshot,
        deviceId: _deviceId,
      );
      final latestSnapshot = _snapshot ?? snapshot;
      final syncedSnapshot = const SnapshotSyncMerger().merge(
        local: latestSnapshot,
        remote: result.snapshot,
      );
      await _saveSnapshot(syncedSnapshot);

      final settings = _syncSettings.copyWith(
        serverUrl: serverUrl,
        authToken: authToken,
        lastMessage: result.message,
        lastSyncedAtUtc: result.finishedAtUtc,
      );
      await widget.syncSettings.save(settings);
      _syncSelectionAfterSnapshot(syncedSnapshot);
      final visibleResult = SyncResult(
        startedAtUtc: result.startedAtUtc,
        finishedAtUtc: result.finishedAtUtc,
        snapshot: syncedSnapshot,
        pushedRecords: result.pushedRecords,
        pulledRecords: result.pulledRecords,
        tombstones: syncedSnapshot.deletedRecords.length,
        message: result.message,
      );
      setState(() {
        _lastSyncResult = visibleResult;
        _syncSettings = settings;
        _syncServerController.text = serverUrl;
        _syncTokenController.text = authToken;
      });
      _log(result.message);
    });
  }

  Future<void> _startSyncSidecar() async {
    if (!_syncSidecarSupported) {
      return;
    }

    await _runAction(() async {
      var authToken = _syncTokenController.text.trim();
      if (authToken.isEmpty) {
        authToken = _generateSyncToken();
      }

      final state = await _syncSidecar.start(token: authToken);
      final settings = _syncSettings.copyWith(
        authToken: authToken,
        lastMessage: 'servidor local ativo',
      );
      await widget.syncSettings.save(settings);
      setState(() {
        _syncSidecarState = state;
        _syncSettings = settings;
        _syncTokenController.text = authToken;
      });
      _log('servidor local de sync iniciado');
    });
  }

  Future<void> _stopSyncSidecar() async {
    await _runAction(() async {
      await _syncSidecar.stop();
      final settings = _syncSettings.copyWith(
        lastMessage: 'servidor local parado',
      );
      await widget.syncSettings.save(settings);
      setState(() {
        _syncSidecarState = null;
        _syncSettings = settings;
      });
      _log('servidor local de sync parado');
    });
  }

  void _syncSelectionAfterSnapshot(AppSnapshot snapshot) {
    final selectedId = _selectedNoteId;
    final selected = selectedId == null
        ? null
        : snapshot.notes.where((note) => note.id == selectedId).firstOrNull;
    final nextSelected = selected ?? snapshot.notes.firstOrNull;
    _selectedNoteId = nextSelected?.id;
    _noteController.text = nextSelected?.body ?? '';
  }

  bool get _syncSidecarSupported =>
      defaultTargetPlatform == TargetPlatform.windows;

  String _generateSyncToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  Future<void> _saveSnapshot(AppSnapshot snapshot) async {
    await _snapshotWrites.save(snapshot);
    if (mounted) {
      setState(() => _snapshot = snapshot);
    } else {
      _snapshot = snapshot;
    }
  }

  Future<String?> _promptText({
    required String title,
    required String hint,
    String initialValue = '',
    String confirmLabel = 'Salvar',
  }) async {
    final controller = TextEditingController(text: initialValue);
    controller.selection = TextSelection.collapsed(offset: initialValue.length);
    try {
      return showDialog<String>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text(title),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(hintText: hint),
              textInputAction: TextInputAction.done,
              onSubmitted: (value) => Navigator.of(context).pop(value),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(controller.text),
                child: Text(confirmLabel),
              ),
            ],
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }

  Future<_NotificationDraft?> _showNotificationEditor({
    NoteItem? note,
    ScheduledNotificationRecord? record,
    DateTime? initialLocal,
  }) async {
    final titleController = TextEditingController(
      text: record?.title.isNotEmpty == true
          ? record!.title
          : note == null
          ? ''
          : _notificationTitleFromNote(note),
    );
    final bodyController = TextEditingController(
      text: record?.body.isNotEmpty == true
          ? record!.body
          : note == null
          ? ''
          : _notificationBodyFromNote(note),
    );
    var scheduledLocal =
        record?.scheduledForUtc.toLocal() ??
        initialLocal ??
        DateTime.now().add(const Duration(minutes: 15));

    try {
      return showDialog<_NotificationDraft>(
        context: context,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              Future<void> pickDate() async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: scheduledLocal,
                  firstDate: DateTime(2024),
                  lastDate: DateTime(2100),
                );
                if (picked == null) {
                  return;
                }
                setDialogState(() {
                  scheduledLocal = DateTime(
                    picked.year,
                    picked.month,
                    picked.day,
                    scheduledLocal.hour,
                    scheduledLocal.minute,
                  );
                });
              }

              Future<void> pickTime() async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay.fromDateTime(scheduledLocal),
                );
                if (picked == null) {
                  return;
                }
                setDialogState(() {
                  scheduledLocal = DateTime(
                    scheduledLocal.year,
                    scheduledLocal.month,
                    scheduledLocal.day,
                    picked.hour,
                    picked.minute,
                  );
                });
              }

              return AlertDialog(
                title: Text(
                  record == null ? 'Nova notificação' : 'Editar notificação',
                ),
                content: SizedBox(
                  width: 460,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      TextField(
                        controller: titleController,
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: 'Nome da notificação',
                          hintText: 'Texto que aparece no alerta',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: bodyController,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Mensagem',
                          hintText: 'Detalhe opcional',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: pickDate,
                              icon: const Icon(Icons.event_outlined),
                              label: Text(formatLocalDate(scheduledLocal)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: pickTime,
                              icon: const Icon(Icons.schedule_outlined),
                              label: Text(formatLocalTime(scheduledLocal)),
                            ),
                          ),
                        ],
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
                    onPressed: () {
                      Navigator.of(context).pop(
                        _NotificationDraft(
                          title: titleController.text,
                          body: bodyController.text,
                          scheduledAtUtc: scheduledLocal.toUtc(),
                        ),
                      );
                    },
                    child: const Text('Salvar'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      titleController.dispose();
      bodyController.dispose();
    }
  }

  Future<void> _runAction(Future<void> Function() action) async {
    if (!_actionGate.tryEnter()) {
      return;
    }

    setState(() => _busy = true);
    try {
      await action();
    } on Object catch (error) {
      _log('erro: ${_errorDescriber.describe(error)}');
    } finally {
      _actionGate.leave();
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _log(String message) {
    if (!mounted) {
      _activity.insert(0, message);
      if (_activity.length > 50) {
        _activity.removeLast();
      }
      return;
    }

    setState(() {
      _activity.insert(0, message);
      if (_activity.length > 50) {
        _activity.removeLast();
      }
    });
  }

  String _notificationEventLabel(String? payload) {
    if (payload == null || payload.isEmpty) {
      return 'Notificação aberta';
    }

    if (payload.startsWith('$appUriScheme://reminder/')) {
      return 'Lembrete aberto';
    }

    return 'Notificação aberta';
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: appDisplayName,
      theme: curioThemeData(_appearance.themeProfile, Brightness.light),
      darkTheme: curioThemeData(_appearance.themeProfile, Brightness.dark),
      themeMode: _appearance.themeMode,
      home: FutureBuilder<void>(
        future: _startup,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const _BootScreen();
          }

          return CallbackShortcuts(
            bindings: <ShortcutActivator, VoidCallback>{
              const SingleActivator(LogicalKeyboardKey.keyK, control: true):
                  _openGlobalSearch,
              const SingleActivator(LogicalKeyboardKey.keyF, control: true):
                  _openGlobalSearch,
              const SingleActivator(
                LogicalKeyboardKey.equal,
                control: true,
              ): () =>
                  _stepUiZoom(1),
              const SingleActivator(
                LogicalKeyboardKey.equal,
                control: true,
                shift: true,
              ): () =>
                  _stepUiZoom(1),
              const SingleActivator(
                LogicalKeyboardKey.numpadAdd,
                control: true,
              ): () =>
                  _stepUiZoom(1),
              const SingleActivator(
                LogicalKeyboardKey.minus,
                control: true,
              ): () =>
                  _stepUiZoom(-1),
              const SingleActivator(
                LogicalKeyboardKey.numpadSubtract,
                control: true,
              ): () =>
                  _stepUiZoom(-1),
              const SingleActivator(
                LogicalKeyboardKey.digit0,
                control: true,
              ): () =>
                  _setUiZoom(1),
            },
            child: Focus(
              autofocus: true,
              child: _HomeShell(
                selectedIndex: _selectedIndex,
                zoom: _uiZoom,
                onSelect: (index) => setState(() => _selectedIndex = index),
                onOpenSearch: _openGlobalSearch,
                onZoomChanged: _setUiZoom,
                pages: <Widget>[
                  _TodayView(
                    notes: _snapshot!.notes,
                    scheduledNotifications: _snapshot!.scheduledNotifications,
                    activity: _activity,
                    busy: _busy,
                    permissionState: _permissionState,
                    lastSchedule: _lastSchedule,
                    lastNotificationLabel: _lastNotificationLabel,
                    pendingCount: _pendingCount,
                    onRequestPermissions: _requestPermissions,
                    onCancelLast: _cancelLast,
                    onOpenNotification: (record) =>
                        unawaited(_editNotification(record)),
                  ),
                  _AgendaView(
                    notes: _snapshot!.notes,
                    scheduledNotifications: _snapshot!.scheduledNotifications,
                    selectedDate: _agendaDate,
                    onVisibleDateChanged: (value) =>
                        setState(() => _agendaDate = dateOnly(value)),
                    onDateSelected: (value) {
                      setState(() => _agendaDate = dateOnly(value));
                      unawaited(_openDailyNote(value));
                    },
                    onEditDate: _openDayEditor,
                    onOpenDailyNote: _openDailyNote,
                    onEditNotification: (record) =>
                        unawaited(_editNotification(record)),
                  ),
                  _BoardView(
                    notes: _snapshot!.notes,
                    scheduledNotifications: _snapshot!.scheduledNotifications,
                    visibleMonth: _agendaDate,
                    onOpenDay: _openDailyNote,
                    onPreviousMonth: () => setState(
                      () => _agendaDate = DateTime(
                        _agendaDate.year,
                        _agendaDate.month - 1,
                      ),
                    ),
                    onNextMonth: () => setState(
                      () => _agendaDate = DateTime(
                        _agendaDate.year,
                        _agendaDate.month + 1,
                      ),
                    ),
                  ),
                  _NotesView(
                    notes: _snapshot!.notes,
                    scheduledNotifications: _snapshot!.scheduledNotifications,
                    noteHistory: _noteHistory,
                    selectedNoteId: _selectedNoteId,
                    selectedDate: _notesDate,
                    controller: _noteController,
                    onOpenCalendar: () => setState(() {
                      _agendaDate = _notesDate;
                      _selectedIndex = 1;
                    }),
                    onAddNotification: _addNotificationForSelectedNote,
                    onEditNotification: (record) =>
                        unawaited(_editNotification(record)),
                    onCancelNotification: (record) =>
                        unawaited(_cancelNotification(record)),
                    onAddNote: _addNote,
                    onRenameNote: _renameSelectedNote,
                    onDeleteNote: _deleteSelectedNote,
                    onRestoreRevision: (revision) =>
                        unawaited(_restoreNoteRevision(revision)),
                    onBodyChanged: _updateSelectedNoteBody,
                  ),
                  _SyncView(
                    busy: _busy,
                    deviceId: _deviceId,
                    controller: _syncServerController,
                    tokenController: _syncTokenController,
                    settings: _syncSettings,
                    appearance: _appearance,
                    sidecarSupported: _syncSidecarSupported,
                    sidecarState: _syncSidecarState,
                    lastResult: _lastSyncResult,
                    snapshot: _snapshot!,
                    onSave: _saveSyncSettings,
                    onAppearanceChanged: _saveAppearanceSettings,
                    onSync: _runSync,
                    onStartSidecar: _startSyncSidecar,
                    onStopSidecar: _stopSyncSidecar,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

String _newId(String prefix) {
  return '$prefix-${DateTime.now().toUtc().microsecondsSinceEpoch}';
}

DateTime _defaultNotificationLocalForDate(DateTime date) {
  final localDate = dateOnly(date);
  final now = DateTime.now();
  final nextHour = now.add(const Duration(hours: 1));
  if (isSameDate(localDate, now) && isSameDate(localDate, nextHour)) {
    return DateTime(
      localDate.year,
      localDate.month,
      localDate.day,
      nextHour.hour,
      nextHour.minute,
    );
  }
  return DateTime(localDate.year, localDate.month, localDate.day, 9);
}

final class _NotificationDraft {
  const _NotificationDraft({
    required this.title,
    required this.body,
    required this.scheduledAtUtc,
  });

  final String title;
  final String body;
  final DateTime scheduledAtUtc;
}

String _notificationTitleFromNote(NoteItem note) {
  final heading = RegExp(
    r'^\s{0,3}#{1,6}\s+(.+)$',
    multiLine: true,
  ).firstMatch(note.body);
  final title = heading?.group(1)?.trim();
  if (title != null && title.isNotEmpty) {
    return _cleanNotificationText(title);
  }

  final line = RegExp(r'^\s*(?:[-*]\s*)?(.+?)\s*$', multiLine: true)
      .allMatches(note.body)
      .map((match) => match.group(1)?.trim() ?? '')
      .where((value) => value.isNotEmpty)
      .firstOrNull;
  if (line != null && line.isNotEmpty) {
    return _cleanNotificationText(line);
  }

  return note.title;
}

String _notificationBodyFromNote(NoteItem note) {
  final compact = note.body
      .replaceAll(RegExp(r'^\s{0,3}#{1,6}\s+', multiLine: true), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (compact.isEmpty) {
    return 'Notificação de ${note.title}';
  }
  return compact.length <= 140 ? compact : '${compact.substring(0, 140)}...';
}

String _cleanNotificationText(String value) {
  return value
      .replaceAll(RegExp(r'[*_`>#\[\]]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _revisionPreview(String body) {
  final compact = body.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (compact.isEmpty) {
    return 'vazio';
  }
  return compact.length <= 96 ? compact : '${compact.substring(0, 96)}...';
}

AppSnapshot _withDeletedRecord(AppSnapshot snapshot, DeletedRecord record) {
  return snapshot.copyWith(
    deletedRecords: <DeletedRecord>[
      record,
      ...snapshot.deletedRecords.where(
        (candidate) => candidate.key != record.key,
      ),
    ],
  );
}

final class _BootScreen extends StatelessWidget {
  const _BootScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: SizedBox.square(
          dimension: 36,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      ),
    );
  }
}

final class _ZoomRailControl extends StatelessWidget {
  const _ZoomRailControl({required this.zoom, required this.onZoomChanged});

  final double zoom;
  final ValueChanged<double> onZoomChanged;

  @override
  Widget build(BuildContext context) {
    final canReset = (clampPageZoom(zoom) - 1).abs() > 0.001;
    return IconButton(
      onPressed: canReset ? () => onZoomChanged(1) : null,
      icon: const Icon(Icons.restart_alt_outlined),
      tooltip: 'Restaurar zoom',
    );
  }
}

final class _ZoomBottomBar extends StatelessWidget {
  const _ZoomBottomBar({required this.zoom, required this.onZoomChanged});

  final double zoom;
  final ValueChanged<double> onZoomChanged;

  @override
  Widget build(BuildContext context) {
    final canReset = (clampPageZoom(zoom) - 1).abs() > 0.001;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: IconButton(
              onPressed: canReset ? () => onZoomChanged(1) : null,
              icon: const Icon(Icons.restart_alt_outlined),
              tooltip: 'Restaurar zoom',
            ),
          ),
        ),
      ),
    );
  }
}

final class _HomeShell extends StatelessWidget {
  const _HomeShell({
    required this.selectedIndex,
    required this.zoom,
    required this.onSelect,
    required this.onOpenSearch,
    required this.onZoomChanged,
    required this.pages,
  });

  final int selectedIndex;
  final double zoom;
  final ValueChanged<int> onSelect;
  final VoidCallback onOpenSearch;
  final ValueChanged<double> onZoomChanged;
  final List<Widget> pages;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 920;
        final destinationItems = _destinations();
        final page = ZoomInteractionSurface(
          scale: zoom,
          onScaleChanged: onZoomChanged,
          child: ZoomedPage(scale: zoom, child: pages[selectedIndex]),
        );

        if (wide) {
          return Scaffold(
            body: Row(
              children: <Widget>[
                NavigationRail(
                  selectedIndex: selectedIndex,
                  onDestinationSelected: onSelect,
                  labelType: NavigationRailLabelType.all,
                  leadingAtTop: false,
                  scrollable: true,
                  minWidth: 104,
                  leading: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const _LogoMark(),
                        const SizedBox(height: 18),
                        IconButton.filledTonal(
                          onPressed: onOpenSearch,
                          icon: const Icon(Icons.search_outlined),
                          tooltip: 'Pesquisa global',
                        ),
                        const SizedBox(height: 14),
                        _ZoomRailControl(
                          zoom: zoom,
                          onZoomChanged: onZoomChanged,
                        ),
                      ],
                    ),
                  ),
                  destinations: destinationItems
                      .map(
                        (item) => NavigationRailDestination(
                          icon: Icon(item.icon),
                          selectedIcon: Icon(item.selectedIcon),
                          label: Text(item.label),
                        ),
                      )
                      .toList(),
                ),
                VerticalDivider(
                  width: 1,
                  color: Theme.of(context).dividerColor,
                ),
                Expanded(child: page),
              ],
            ),
          );
        }

        return Scaffold(
          body: page,
          floatingActionButton: FloatingActionButton.small(
            onPressed: onOpenSearch,
            tooltip: 'Pesquisa global',
            child: const Icon(Icons.search_outlined),
          ),
          bottomNavigationBar: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _ZoomBottomBar(zoom: zoom, onZoomChanged: onZoomChanged),
              NavigationBar(
                selectedIndex: selectedIndex,
                onDestinationSelected: onSelect,
                destinations: destinationItems
                    .map(
                      (item) => NavigationDestination(
                        icon: Icon(item.icon),
                        selectedIcon: Icon(item.selectedIcon),
                        label: item.label,
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        );
      },
    );
  }

  List<_DestinationItem> _destinations() {
    return const <_DestinationItem>[
      _DestinationItem('Hoje', Icons.today_outlined, Icons.today),
      _DestinationItem(
        'Agenda',
        Icons.calendar_month_outlined,
        Icons.calendar_month,
      ),
      _DestinationItem('Quadro', Icons.view_kanban_outlined, Icons.view_kanban),
      _DestinationItem('Notas', Icons.notes_outlined, Icons.notes),
      _DestinationItem('Sync', Icons.sync_outlined, Icons.sync),
    ];
  }
}

final class _DestinationItem {
  const _DestinationItem(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

final class _GlobalSearchDialog extends StatefulWidget {
  const _GlobalSearchDialog({required this.snapshot});

  final AppSnapshot snapshot;

  @override
  State<_GlobalSearchDialog> createState() => _GlobalSearchDialogState();
}

final class _GlobalSearchDialogState extends State<_GlobalSearchDialog> {
  late final TextEditingController _controller;
  List<GlobalSearchResult> _results = const <GlobalSearchResult>[];

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _search(String value) {
    setState(() {
      _results = searchSnapshotText(widget.snapshot, value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final query = _controller.text.trim();
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Row(
        children: <Widget>[
          Icon(Icons.search_outlined),
          SizedBox(width: 10),
          Text('Pesquisa global'),
        ],
      ),
      content: SizedBox(
        width: min(MediaQuery.of(context).size.width * 0.86, 680),
        height: min(MediaQuery.of(context).size.height * 0.70, 560),
        child: Column(
          children: <Widget>[
            TextField(
              controller: _controller,
              autofocus: true,
              onChanged: _search,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.manage_search_outlined),
                labelText: 'Buscar',
                hintText: 'Notas e notificações',
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                query.isEmpty
                    ? 'Notas e notificações'
                    : '${_results.length} resultado(s)',
                style: theme.textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _SearchResultsBody(query: query, results: _results),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fechar'),
        ),
      ],
    );
  }
}

final class _SearchResultsBody extends StatelessWidget {
  const _SearchResultsBody({required this.query, required this.results});

  final String query;
  final List<GlobalSearchResult> results;

  @override
  Widget build(BuildContext context) {
    if (query.isEmpty) {
      return const Center(child: Text('Digite para pesquisar.'));
    }

    if (results.isEmpty) {
      return const Center(child: Text('Nada encontrado.'));
    }

    return ListView.separated(
      itemCount: results.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final result = results[index];
        final isNotification =
            result.kind == GlobalSearchResultKind.notification;
        final preview = result.preview;

        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            isNotification
                ? Icons.notifications_none_outlined
                : Icons.sticky_note_2_outlined,
          ),
          title: Text(
            result.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            preview.isEmpty ? result.subtitle : '${result.subtitle}\n$preview',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => Navigator.of(context).pop(result),
        );
      },
    );
  }
}

final class _LogoMark extends StatelessWidget {
  const _LogoMark();

  @override
  Widget build(BuildContext context) {
    const logoSize = 72.0;
    final cacheSize = (logoSize * MediaQuery.devicePixelRatioOf(context))
        .ceil();
    final logoAsset = Theme.of(context).brightness == Brightness.dark
        ? 'assets/brand/curio_logo_dark_1024.png'
        : 'assets/brand/curio_logo_light_1024.png';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          width: logoSize,
          height: logoSize,
          child: Image.asset(
            logoAsset,
            fit: BoxFit.contain,
            cacheWidth: max(96, cacheSize),
            cacheHeight: max(96, cacheSize),
            filterQuality: FilterQuality.medium,
            semanticLabel: appDisplayName,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          appDisplayName,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

final class _TodayView extends StatelessWidget {
  const _TodayView({
    required this.notes,
    required this.scheduledNotifications,
    required this.activity,
    required this.busy,
    required this.permissionState,
    required this.lastSchedule,
    required this.lastNotificationLabel,
    required this.pendingCount,
    required this.onRequestPermissions,
    required this.onCancelLast,
    required this.onOpenNotification,
  });

  final List<NoteItem> notes;
  final List<ScheduledNotificationRecord> scheduledNotifications;
  final List<String> activity;
  final bool busy;
  final NotificationPermissionState permissionState;
  final ScheduleResult? lastSchedule;
  final String? lastNotificationLabel;
  final int pendingCount;
  final VoidCallback onRequestPermissions;
  final VoidCallback onCancelLast;
  final ValueChanged<ScheduledNotificationRecord> onOpenNotification;

  @override
  Widget build(BuildContext context) {
    return _PageFrame(
      title: 'Hoje',
      subtitle: todayLabel(),
      trailing: _StatusPill(
        icon: Icons.notifications_active_outlined,
        label: '$pendingCount pendente(s)',
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 980;
          final children = <Widget>[
            _FocusPanel(
              notes: notes,
              scheduledNotifications: scheduledNotifications,
              activity: activity,
              lastNotificationLabel: lastNotificationLabel,
              onOpenNotification: onOpenNotification,
            ),
            _NotificationPanel(
              notes: notes,
              scheduledNotifications: scheduledNotifications,
              busy: busy,
              permissionState: permissionState,
              lastSchedule: lastSchedule,
              pendingCount: pendingCount,
              onRequestPermissions: onRequestPermissions,
              onCancelLast: onCancelLast,
              onOpenNotification: onOpenNotification,
            ),
          ];

          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(flex: 6, child: children[0]),
                const SizedBox(width: 18),
                Expanded(flex: 5, child: children[1]),
              ],
            );
          }

          return Column(
            children: <Widget>[
              children[0],
              const SizedBox(height: 16),
              children[1],
            ],
          );
        },
      ),
    );
  }
}

final class _FocusPanel extends StatelessWidget {
  const _FocusPanel({
    required this.notes,
    required this.scheduledNotifications,
    required this.activity,
    required this.lastNotificationLabel,
    required this.onOpenNotification,
  });

  final List<NoteItem> notes;
  final List<ScheduledNotificationRecord> scheduledNotifications;
  final List<String> activity;
  final String? lastNotificationLabel;
  final ValueChanged<ScheduledNotificationRecord> onOpenNotification;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().toUtc();
    final visibleNotifications =
        scheduledNotifications
            .where((record) => record.scheduledForUtc.isAfter(now))
            .toList()
          ..sort(
            (left, right) =>
                left.scheduledForUtc.compareTo(right.scheduledForUtc),
          );

    return _Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const _SectionHeader(
            icon: Icons.bolt_outlined,
            title: 'Próximas notificações',
          ),
          const SizedBox(height: 18),
          if (visibleNotifications.isEmpty)
            Text(
              'Nenhuma notificação futura gravada.',
              style: Theme.of(context).textTheme.bodySmall,
            )
          else
            for (final record in visibleNotifications.take(8))
              _NotificationRecordTile(
                record: record,
                title: _notificationRecordTitle(record, notes),
                onTap: () => onOpenNotification(record),
              ),
          if (lastNotificationLabel != null) ...<Widget>[
            const Divider(height: 28),
            Text(
              'Última notificação',
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            SelectableText(
              lastNotificationLabel!,
              style: const TextStyle(fontSize: 13),
            ),
          ],
          if (activity.isNotEmpty) ...<Widget>[
            const Divider(height: 28),
            const _SectionHeader(icon: Icons.history_outlined, title: 'Log'),
            const SizedBox(height: 8),
            for (final item in activity.take(6))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(item, style: Theme.of(context).textTheme.bodySmall),
              ),
          ],
        ],
      ),
    );
  }
}

final class _NotificationPanel extends StatelessWidget {
  const _NotificationPanel({
    required this.notes,
    required this.scheduledNotifications,
    required this.busy,
    required this.permissionState,
    required this.lastSchedule,
    required this.pendingCount,
    required this.onRequestPermissions,
    required this.onCancelLast,
    required this.onOpenNotification,
  });

  final List<NoteItem> notes;
  final List<ScheduledNotificationRecord> scheduledNotifications;
  final bool busy;
  final NotificationPermissionState permissionState;
  final ScheduleResult? lastSchedule;
  final int pendingCount;
  final VoidCallback onRequestPermissions;
  final VoidCallback onCancelLast;
  final ValueChanged<ScheduledNotificationRecord> onOpenNotification;

  @override
  Widget build(BuildContext context) {
    final scheduled = lastSchedule;
    final now = DateTime.now().toUtc();
    final active =
        scheduledNotifications
            .where((record) => record.scheduledForUtc.isAfter(now))
            .toList()
          ..sort(
            (left, right) =>
                left.scheduledForUtc.compareTo(right.scheduledForUtc),
          );

    return _Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _SectionHeader(
            icon: Icons.notifications_none,
            title: 'Notificações ativas',
            action: _StatusPill(
              icon: Icons.notifications_active_outlined,
              label: '$pendingCount pendente(s)',
            ),
          ),
          const SizedBox(height: 14),
          Text(
            permissionState.label,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              FilledButton.icon(
                onPressed: busy ? null : onRequestPermissions,
                icon: const Icon(Icons.verified_user_outlined),
                label: const Text('Permissões'),
              ),
              IconButton.filledTonal(
                onPressed: busy || scheduled == null ? null : onCancelLast,
                icon: const Icon(Icons.notifications_off_outlined),
                tooltip: 'Cancelar último',
              ),
            ],
          ),
          if (active.isEmpty) ...<Widget>[
            const SizedBox(height: 18),
            Text(
              'Nenhuma notificação futura gravada.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ] else ...<Widget>[
            const Divider(height: 28),
            for (final record in active.take(10))
              _NotificationRecordTile(
                record: record,
                title: _notificationRecordTitle(record, notes),
                onTap: () => onOpenNotification(record),
              ),
          ],
        ],
      ),
    );
  }
}

final class _AgendaView extends StatelessWidget {
  const _AgendaView({
    required this.notes,
    required this.scheduledNotifications,
    required this.selectedDate,
    required this.onVisibleDateChanged,
    required this.onDateSelected,
    required this.onEditDate,
    required this.onOpenDailyNote,
    required this.onEditNotification,
  });

  final List<NoteItem> notes;
  final List<ScheduledNotificationRecord> scheduledNotifications;
  final DateTime selectedDate;
  final ValueChanged<DateTime> onVisibleDateChanged;
  final ValueChanged<DateTime> onDateSelected;
  final ValueChanged<DateTime> onEditDate;
  final ValueChanged<DateTime> onOpenDailyNote;
  final ValueChanged<ScheduledNotificationRecord> onEditNotification;

  @override
  Widget build(BuildContext context) {
    final countsByDate = <DateTime, int>{...noteCountsByDate(notes)};
    for (final record in scheduledNotifications) {
      final date = dateOnly(record.scheduledForUtc);
      countsByDate[date] = (countsByDate[date] ?? 0) + 1;
    }
    final selectedNotes = notes
        .where(
          (note) =>
              isSameDate(dailyNoteDate(note) ?? DateTime(1), selectedDate),
        )
        .toList();
    final selectedNotifications =
        scheduledNotifications
            .where((record) => isSameDate(record.scheduledForUtc, selectedDate))
            .toList()
          ..sort(
            (left, right) =>
                left.scheduledForUtc.compareTo(right.scheduledForUtc),
          );

    return _PageFrame(
      title: 'Agenda',
      subtitle: 'Calendário de notas e notificações',
      trailing: FilledButton.icon(
        onPressed: () => onOpenDailyNote(selectedDate),
        icon: const Icon(Icons.edit_note_outlined),
        label: const Text('Editar em Notas'),
      ),
      child: Column(
        children: <Widget>[
          _Surface(
            child: AgendaCalendar(
              selectedDate: selectedDate,
              dayCounts: countsByDate,
              onVisibleDateChanged: onVisibleDateChanged,
              onDateSelected: onDateSelected,
              onEditDate: onEditDate,
            ),
          ),
          const SizedBox(height: 14),
          _Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _SectionHeader(
                  icon: Icons.event_available_outlined,
                  title: formatLocalDate(selectedDate),
                  action: TextButton.icon(
                    onPressed: () => onOpenDailyNote(selectedDate),
                    icon: const Icon(Icons.article_outlined),
                    label: const Text('Notas'),
                  ),
                ),
                const SizedBox(height: 12),
                if (selectedNotes.isEmpty && selectedNotifications.isEmpty)
                  Text(
                    'Nenhuma nota ou notificação neste dia.',
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                else ...<Widget>[
                  for (final note in selectedNotes)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.article_outlined),
                      title: Text(note.title),
                      subtitle: Text(formatLocalDateTime(note.updatedAtUtc)),
                      onTap: () => onOpenDailyNote(selectedDate),
                    ),
                  for (
                    var index = 0;
                    index < selectedNotifications.length;
                    index++
                  )
                    _TimelineRow(
                      time: formatLocalTime(
                        selectedNotifications[index].scheduledForUtc,
                      ),
                      title: _notificationRecordTitle(
                        selectedNotifications[index],
                        notes,
                      ),
                      subtitle: selectedNotifications[index].body,
                      tone: entryTone(index),
                      onTap: () =>
                          onEditNotification(selectedNotifications[index]),
                      actionTooltip: 'Editar notificação',
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final class _BoardView extends StatelessWidget {
  const _BoardView({
    required this.notes,
    required this.scheduledNotifications,
    required this.visibleMonth,
    required this.onOpenDay,
    required this.onPreviousMonth,
    required this.onNextMonth,
  });

  final List<NoteItem> notes;
  final List<ScheduledNotificationRecord> scheduledNotifications;
  final DateTime visibleMonth;
  final ValueChanged<DateTime> onOpenDay;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;

  @override
  Widget build(BuildContext context) {
    final month = DateTime(visibleMonth.year, visibleMonth.month);
    final digests = _dayDigests(
      notes: notes,
      notifications: scheduledNotifications,
      month: month,
    );

    return _PageFrame(
      title: 'Quadro',
      subtitle: '${monthLabel(month.month)} ${month.year}',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            onPressed: onPreviousMonth,
            icon: const Icon(Icons.chevron_left_outlined),
            tooltip: 'Mês anterior',
          ),
          Text(
            '${monthLabel(month.month)} ${month.year}',
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          IconButton(
            onPressed: onNextMonth,
            icon: const Icon(Icons.chevron_right_outlined),
            tooltip: 'Próximo mês',
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 1060
              ? 4
              : constraints.maxWidth >= 760
              ? 3
              : constraints.maxWidth >= 520
              ? 2
              : 1;
          if (digests.isEmpty) {
            return _Surface(
              child: Text(
                'Nenhum dia com notas ou alertas neste mês.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            );
          }

          return GridView.builder(
            itemCount: digests.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: columns == 1 ? 4.2 : 2.05,
            ),
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemBuilder: (context, index) {
              final digest = digests[index];
              return _DayBoardCard(
                digest: digest,
                onTap: () => onOpenDay(digest.date),
              );
            },
          );
        },
      ),
    );
  }
}

final class _DayDigest {
  const _DayDigest({
    required this.date,
    required this.notes,
    required this.notifications,
  });

  final DateTime date;
  final List<NoteItem> notes;
  final List<ScheduledNotificationRecord> notifications;

  int get alertCount => notifications.length;

  int get count => notes.length + alertCount;
}

List<_DayDigest> _dayDigests({
  required List<NoteItem> notes,
  required List<ScheduledNotificationRecord> notifications,
  required DateTime month,
}) {
  final dates = <DateTime>{};

  final notesByDate = <DateTime, List<NoteItem>>{};
  for (final note in notes) {
    final date = dailyNoteDate(note);
    if (date == null || !_isSameMonth(date, month)) {
      continue;
    }
    dates.add(date);
    notesByDate.putIfAbsent(date, () => <NoteItem>[]).add(note);
  }

  final notificationsByDate = <DateTime, List<ScheduledNotificationRecord>>{};
  for (final notification in notifications) {
    final date = dateOnly(notification.scheduledForUtc);
    if (!_isSameMonth(date, month)) {
      continue;
    }
    dates.add(date);
    notificationsByDate
        .putIfAbsent(date, () => <ScheduledNotificationRecord>[])
        .add(notification);
  }

  final sortedDates = dates.toList()..sort();
  return <_DayDigest>[
    for (final date in sortedDates)
      _DayDigest(
        date: date,
        notes: notesByDate[date] ?? const <NoteItem>[],
        notifications:
            notificationsByDate[date] ?? const <ScheduledNotificationRecord>[],
      ),
  ];
}

bool _isSameMonth(DateTime date, DateTime month) {
  return date.year == month.year && date.month == month.month;
}

final class _DayBoardCard extends StatelessWidget {
  const _DayBoardCard({required this.digest, required this.onTap});

  final _DayDigest digest;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        formatLocalDate(digest.date),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    _StatusPill(
                      icon: Icons.edit_notifications_outlined,
                      label: digest.count.toString(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _CardMetricLine('Notas', digest.notes.length.toString()),
                _CardMetricLine('Alertas', digest.alertCount.toString()),
                const Spacer(),
                Align(
                  alignment: Alignment.bottomRight,
                  child: Text(
                    'Abrir em Notas',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class _CardMetricLine extends StatelessWidget {
  const _CardMetricLine(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 68,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

final class _NotesView extends StatelessWidget {
  const _NotesView({
    required this.notes,
    required this.scheduledNotifications,
    required this.noteHistory,
    required this.selectedNoteId,
    required this.selectedDate,
    required this.controller,
    required this.onOpenCalendar,
    required this.onAddNotification,
    required this.onEditNotification,
    required this.onCancelNotification,
    required this.onAddNote,
    required this.onRenameNote,
    required this.onDeleteNote,
    required this.onRestoreRevision,
    required this.onBodyChanged,
  });

  final List<NoteItem> notes;
  final List<ScheduledNotificationRecord> scheduledNotifications;
  final List<NoteEditRevision> noteHistory;
  final String? selectedNoteId;
  final DateTime selectedDate;
  final TextEditingController controller;
  final VoidCallback onOpenCalendar;
  final VoidCallback onAddNotification;
  final ValueChanged<ScheduledNotificationRecord> onEditNotification;
  final ValueChanged<ScheduledNotificationRecord> onCancelNotification;
  final VoidCallback onAddNote;
  final VoidCallback onRenameNote;
  final VoidCallback onDeleteNote;
  final ValueChanged<NoteEditRevision> onRestoreRevision;
  final ValueChanged<String> onBodyChanged;

  @override
  Widget build(BuildContext context) {
    final selected = notes
        .where((note) => note.id == selectedNoteId)
        .firstOrNull;
    final dailyTitle = dailyNoteTitle(selectedDate);
    final isDailyNote = selected != null && dailyNoteDate(selected) != null;
    final selectedNotifications =
        scheduledNotifications.where((record) {
          if (selected != null && record.ownerId == selected.id) {
            return true;
          }
          return isSameDate(record.scheduledForUtc, selectedDate);
        }).toList()..sort(
          (left, right) =>
              left.scheduledForUtc.compareTo(right.scheduledForUtc),
        );
    final selectedHistory = selected == null
        ? noteHistory
        : noteHistory
              .where((revision) => revision.noteId == selected.id)
              .toList();

    return _PageFrame(
      title: 'Notas',
      subtitle: formatLocalDate(selectedDate),
      trailing: const _StatusPill(icon: Icons.save_outlined, label: 'Autosave'),
      child: _Surface(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 980;
            final editor = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    FilledButton.icon(
                      onPressed: onOpenCalendar,
                      icon: const Icon(Icons.calendar_month_outlined),
                      label: const Text('Calendário'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(170, 48),
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: selected == null ? null : onAddNotification,
                      icon: const Icon(Icons.notification_add_outlined),
                      label: const Text('Notificação'),
                    ),
                    IconButton(
                      onPressed: onAddNote,
                      icon: const Icon(Icons.note_add_outlined),
                      tooltip: 'Nova nota geral',
                    ),
                    IconButton(
                      onPressed: selected == null ? null : onRenameNote,
                      icon: const Icon(Icons.drive_file_rename_outline),
                      tooltip: 'Renomear nota',
                    ),
                    IconButton(
                      onPressed: selected == null ? null : onDeleteNote,
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Excluir nota',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      selected?.title ?? dailyTitle,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      selectedNotifications.isEmpty
                          ? 'Sem notificação neste dia'
                          : '${selectedNotifications.length} notificação(ões)',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                if (!isDailyNote && selected != null) ...<Widget>[
                  const SizedBox(height: 10),
                  Text(
                    'Nota geral selecionada. O botão Calendário volta para a seleção de dias.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 14),
                MarkdownToolbar(
                  enabled: selected != null,
                  onAction: (action) => applyMarkdownFormat(
                    controller: controller,
                    onChanged: onBodyChanged,
                    action: action,
                  ),
                ),
                const SizedBox(height: 14),
                MarkdownShortcuts(
                  enabled: selected != null,
                  controller: controller,
                  onChanged: onBodyChanged,
                  child: TextField(
                    controller: controller,
                    enabled: selected != null,
                    onChanged: onBodyChanged,
                    minLines: wide ? 22 : 14,
                    maxLines: wide ? 36 : 28,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    style: const TextStyle(fontSize: 15, height: 1.45),
                    decoration: InputDecoration(
                      hintText: selected == null
                          ? 'Escolha um dia no calendário para criar a nota.'
                          : 'Escreva em Markdown.',
                      alignLabelWithHint: true,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                _NotificationList(
                  notifications: selectedNotifications,
                  notes: notes,
                  onEdit: onEditNotification,
                  onCancel: onCancelNotification,
                ),
                const SizedBox(height: 18),
                _RevisionList(
                  revisions: selectedHistory,
                  onRestore: onRestoreRevision,
                ),
              ],
            );
            return editor;
          },
        ),
      ),
    );
  }
}

final class _NotificationList extends StatelessWidget {
  const _NotificationList({
    required this.notifications,
    required this.notes,
    required this.onEdit,
    required this.onCancel,
  });

  final List<ScheduledNotificationRecord> notifications;
  final List<NoteItem> notes;
  final ValueChanged<ScheduledNotificationRecord> onEdit;
  final ValueChanged<ScheduledNotificationRecord> onCancel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const _SectionHeader(
          icon: Icons.notifications_none_outlined,
          title: 'Notificações',
        ),
        const SizedBox(height: 10),
        if (notifications.isEmpty)
          Text(
            'Nenhuma notificação vinculada a esta data.',
            style: Theme.of(context).textTheme.bodySmall,
          )
        else
          for (final record in notifications)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.alarm_on_outlined),
              title: Text(_notificationRecordTitle(record, notes)),
              subtitle: Text(formatLocalDateTime(record.scheduledForUtc)),
              trailing: Wrap(
                spacing: 4,
                children: <Widget>[
                  IconButton(
                    onPressed: () => onEdit(record),
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: 'Editar notificação',
                  ),
                  IconButton(
                    onPressed: () => onCancel(record),
                    icon: const Icon(Icons.notifications_off_outlined),
                    tooltip: 'Cancelar notificação',
                  ),
                ],
              ),
              onTap: () => onEdit(record),
            ),
      ],
    );
  }
}

final class _RevisionList extends StatelessWidget {
  const _RevisionList({required this.revisions, required this.onRestore});

  final List<NoteEditRevision> revisions;
  final ValueChanged<NoteEditRevision> onRestore;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const _SectionHeader(
          icon: Icons.restore_outlined,
          title: 'Histórico de autosave',
        ),
        const SizedBox(height: 10),
        if (revisions.isEmpty)
          Text(
            'As versões anteriores aparecerão aqui enquanto você escreve.',
            style: Theme.of(context).textTheme.bodySmall,
          )
        else
          for (final revision in revisions.take(50))
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.history_outlined),
              title: Text(revision.noteTitle),
              subtitle: Text(
                '${formatLocalDateTime(revision.savedAtUtc)} · '
                '${_revisionPreview(revision.body)}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: TextButton.icon(
                onPressed: () => onRestore(revision),
                icon: const Icon(Icons.restore_outlined),
                label: const Text('Restaurar'),
              ),
            ),
      ],
    );
  }
}

final class _SyncView extends StatelessWidget {
  const _SyncView({
    required this.busy,
    required this.deviceId,
    required this.controller,
    required this.tokenController,
    required this.settings,
    required this.appearance,
    required this.sidecarSupported,
    required this.sidecarState,
    required this.lastResult,
    required this.snapshot,
    required this.onSave,
    required this.onAppearanceChanged,
    required this.onSync,
    required this.onStartSidecar,
    required this.onStopSidecar,
  });

  final bool busy;
  final String deviceId;
  final TextEditingController controller;
  final TextEditingController tokenController;
  final SyncSettings settings;
  final AppearanceSettings appearance;
  final bool sidecarSupported;
  final LocalSyncSidecarState? sidecarState;
  final SyncResult? lastResult;
  final AppSnapshot snapshot;
  final VoidCallback onSave;
  final ValueChanged<AppearanceSettings> onAppearanceChanged;
  final VoidCallback onSync;
  final VoidCallback onStartSidecar;
  final VoidCallback onStopSidecar;

  @override
  Widget build(BuildContext context) {
    final result = lastResult;
    final lastSyncedAt = settings.lastSyncedAtUtc;
    final sidecarRunning = sidecarState != null;
    final serverHint = kDebugMode
        ? 'http://192.168.0.10:8787'
        : 'https://sync.seu-dominio.com';

    return _PageFrame(
      title: 'Sync',
      subtitle: sidecarRunning
          ? 'Servidor local Windows ativo'
          : settings.serverUrl.isEmpty
          ? 'Offline'
          : settings.authToken.isEmpty
          ? 'Token necessário'
          : 'Self-hosted protegido',
      trailing: _StatusPill(
        icon: Icons.devices_outlined,
        label: '${snapshot.deletedRecords.length} tombstone(s)',
      ),
      child: Column(
        children: <Widget>[
          _AppearancePanel(
            settings: appearance,
            onChanged: onAppearanceChanged,
          ),
          const SizedBox(height: 14),
          _Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.dns_outlined),
                    labelText: 'Servidor',
                    hintText: serverHint,
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => onSave(),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: tokenController,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.key_outlined),
                    labelText: 'Token',
                    hintText: 'mesmo token do servidor',
                  ),
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => onSave(),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: <Widget>[
                    FilledButton.icon(
                      onPressed: busy ? null : onSync,
                      icon: const Icon(Icons.sync_outlined),
                      label: const Text('Sincronizar'),
                    ),
                    OutlinedButton.icon(
                      onPressed: busy ? null : onSave,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Salvar sync'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const _SectionHeader(
                  icon: Icons.cloud_download_outlined,
                  title: 'Kit self-hosted',
                ),
                const SizedBox(height: 12),
                Text(
                  'Docker/Compose pronto para publicar no GitHub Release.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                const _MetricLine('Guia', 'docs/self-hosted-sync.md'),
                const _MetricLine('Pacote', 'build/self-hosted'),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (sidecarSupported) ...<Widget>[
            _Surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _SectionHeader(
                    icon: Icons.power_outlined,
                    title: 'Servidor local opcional',
                    action: OutlinedButton.icon(
                      onPressed: busy
                          ? null
                          : sidecarRunning
                          ? onStopSidecar
                          : onStartSidecar,
                      icon: Icon(
                        sidecarRunning
                            ? Icons.stop_circle_outlined
                            : Icons.power_settings_new_outlined,
                      ),
                      label: Text(sidecarRunning ? 'Parar' : 'Iniciar'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Atalho de teste no Windows: inicia a API de sync dentro do app, sem Docker.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  _MetricLine('Servidor', sidecarRunning ? 'Ativo' : 'Parado'),
                  if (sidecarRunning) ...<Widget>[
                    _MetricLine('Local', sidecarState!.localUrl),
                    _MetricLine(
                      'LAN',
                      '${sidecarState!.host}:${sidecarState!.port}',
                    ),
                    _MetricLine(
                      'Iniciado',
                      formatLocalDateTime(sidecarState!.startedAtUtc),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],
          _Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const _SectionHeader(icon: Icons.hub_outlined, title: 'Estado'),
                const SizedBox(height: 12),
                _MetricLine('Device', deviceId),
                _MetricLine('Notas', snapshot.notes.length.toString()),
                _MetricLine(
                  'Notificações',
                  snapshot.scheduledNotifications.length.toString(),
                ),
                _MetricLine(
                  'Exclusões',
                  snapshot.deletedRecords.length.toString(),
                ),
                _MetricLine(
                  'Proteção',
                  settings.authToken.isEmpty
                      ? 'Token necessário'
                      : 'Token ativo',
                ),
                _MetricLine(
                  'Último',
                  lastSyncedAt == null
                      ? 'Nunca'
                      : formatLocalDateTime(lastSyncedAt),
                ),
                if (settings.lastMessage != null)
                  _MetricLine('Status', settings.lastMessage!),
              ],
            ),
          ),
          if (result != null) ...<Widget>[
            const SizedBox(height: 14),
            _Surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const _SectionHeader(
                    icon: Icons.receipt_long_outlined,
                    title: 'Última troca',
                  ),
                  const SizedBox(height: 12),
                  _MetricLine('Push', result.pushedRecords.toString()),
                  _MetricLine('Pull', result.pulledRecords.toString()),
                  _MetricLine('Tombstones', result.tombstones.toString()),
                  _MetricLine('Fim', formatLocalDateTime(result.finishedAtUtc)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

final class _AppearancePanel extends StatelessWidget {
  const _AppearancePanel({required this.settings, required this.onChanged});

  final AppearanceSettings settings;
  final ValueChanged<AppearanceSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    return _Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const _SectionHeader(
            icon: Icons.palette_outlined,
            title: 'Aparência',
          ),
          const SizedBox(height: 14),
          _SegmentedControlRow<ThemeMode>(
            label: 'Modo',
            segments: const <ButtonSegment<ThemeMode>>[
              ButtonSegment<ThemeMode>(
                value: ThemeMode.system,
                icon: Icon(Icons.brightness_auto_outlined),
                label: Text('Sistema'),
              ),
              ButtonSegment<ThemeMode>(
                value: ThemeMode.light,
                icon: Icon(Icons.light_mode_outlined),
                label: Text('Claro'),
              ),
              ButtonSegment<ThemeMode>(
                value: ThemeMode.dark,
                icon: Icon(Icons.dark_mode_outlined),
                label: Text('Escuro'),
              ),
            ],
            selected: settings.themeMode,
            onChanged: (themeMode) {
              onChanged(settings.copyWith(themeMode: themeMode));
            },
          ),
          const SizedBox(height: 12),
          _SegmentedControlRow<CurioThemeProfile>(
            label: 'Tema',
            segments: const <ButtonSegment<CurioThemeProfile>>[
              ButtonSegment<CurioThemeProfile>(
                value: CurioThemeProfile.aurora,
                icon: Icon(Icons.wb_twilight_outlined),
                label: Text('Aurora'),
              ),
              ButtonSegment<CurioThemeProfile>(
                value: CurioThemeProfile.slate,
                icon: Icon(Icons.terminal_outlined),
                label: Text('Slate'),
              ),
              ButtonSegment<CurioThemeProfile>(
                value: CurioThemeProfile.lumen,
                icon: Icon(Icons.auto_awesome_outlined),
                label: Text('Lumen'),
              ),
            ],
            selected: settings.themeProfile,
            onChanged: (themeProfile) {
              onChanged(settings.copyWith(themeProfile: themeProfile));
            },
          ),
        ],
      ),
    );
  }
}

final class _SegmentedControlRow<T> extends StatelessWidget {
  const _SegmentedControlRow({
    required this.label,
    required this.segments,
    required this.selected,
    required this.onChanged,
  });

  final String label;
  final List<ButtonSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 560;
        final control = SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<T>(
            showSelectedIcon: false,
            segments: segments,
            selected: <T>{selected},
            onSelectionChanged: (values) => onChanged(values.single),
          ),
        );

        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              control,
            ],
          );
        }

        return Row(
          children: <Widget>[
            SizedBox(
              width: 92,
              child: Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            Expanded(child: control),
          ],
        );
      },
    );
  }
}

final class _PageFrame extends StatelessWidget {
  const _PageFrame({
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 30),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          title,
                          style: Theme.of(context).textTheme.displaySmall
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                  ?trailing,
                ],
              ),
              const SizedBox(height: 24),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

final class _Surface extends StatelessWidget {
  const _Surface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: isDark
            ? null
            : const <BoxShadow>[
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
      ),
      child: child,
    );
  }
}

final class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.title, this.action});

  final IconData icon;
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        ?action,
      ],
    );
  }
}

final class _NotificationRecordTile extends StatelessWidget {
  const _NotificationRecordTile({
    required this.record,
    required this.title,
    required this.onTap,
  });

  final ScheduledNotificationRecord record;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ownerLabel = switch (record.ownerType) {
      ReminderOwnerType.task => 'Notificação',
      ReminderOwnerType.note => 'Nota',
    };

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: <Widget>[
              Icon(
                Icons.alarm_on_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$ownerLabel · ${formatLocalDateTime(record.scheduledForUtc)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.open_in_new_outlined, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

String _notificationRecordTitle(
  ScheduledNotificationRecord record,
  List<NoteItem> notes,
) {
  if (record.title.trim().isNotEmpty) {
    return record.title.trim();
  }

  if (record.ownerType == ReminderOwnerType.note) {
    final note = notes
        .where((candidate) => candidate.id == record.ownerId)
        .firstOrNull;
    return note?.title ?? 'Notificação';
  }

  return 'Notificação';
}

final class _MetricLine extends StatelessWidget {
  const _MetricLine(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 94,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

final class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.time,
    required this.title,
    this.subtitle,
    required this.tone,
    this.onTap,
    this.actionTooltip = 'Editar',
  });

  final String time;
  final String title;
  final String? subtitle;
  final Color tone;
  final VoidCallback? onTap;
  final String actionTooltip;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      children: <Widget>[
        SizedBox(
          width: 64,
          child: Text(
            time,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              if (subtitle != null) ...<Widget>[
                const SizedBox(height: 2),
                Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          ),
        ),
        if (onTap != null) ...<Widget>[
          const SizedBox(width: 8),
          IconButton(
            onPressed: onTap,
            icon: const Icon(Icons.edit_outlined),
            tooltip: actionTooltip,
          ),
        ],
      ],
    );

    final tap = onTap;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: tap == null
          ? row
          : Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: tap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: row,
                ),
              ),
            ),
    );
  }
}

final class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 16, color: scheme.onSecondaryContainer),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: scheme.onSecondaryContainer,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
