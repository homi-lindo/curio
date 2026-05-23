import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lume_core/domain/app_snapshot.dart';
import 'package:lume_core/domain/reminder.dart';
import 'package:lume_core/sync/sync_adapter.dart';
import 'package:path_provider/path_provider.dart';

import 'app_brand.dart';
import 'services/action_error_describer.dart';
import 'services/appearance_settings_store.dart';
import 'services/async_action_gate.dart';
import 'services/device_identity.dart';
import 'services/id_generator.dart';
import 'services/local_store.dart';
import 'services/local_sync_sidecar.dart';
import 'services/lume_widgets_binding.dart';
import 'services/manual_backup_codec.dart';
import 'services/note_edit_history_store.dart';
import 'services/notification_service.dart';
import 'services/notification_timezone_audit.dart';
import 'services/snapshot_write_queue.dart';
import 'services/sync_settings_store.dart';
import 'services/sync_settings_validator.dart';
import 'sync/http_sync_adapter.dart';
import 'theme/curio_theme.dart';
import 'ui/global_search_dialog.dart';
import 'ui/notification_editor.dart';
import 'ui/task_view_helpers.dart';
import 'ui/views/agenda_view.dart';
import 'ui/views/board_view.dart';
import 'ui/views/notes_view.dart';
import 'ui/views/sync_view.dart';
import 'ui/views/today_view.dart';
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
  final ManualBackupCodec _manualBackupCodec = const ManualBackupCodec();
  final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  BuildContext get _dialogContext => _navigatorKey.currentContext ?? context;

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
  bool _notificationComposerOpen = false;
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
        _uiZoom = appearance.pageZoom;
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
      _uiZoom = appearance.pageZoom;
      _syncServerController.text = syncSettings.serverUrl;
      _syncTokenController.text = syncSettings.authToken;
      _snapshot = snapshot;
      _noteHistory = noteHistory;
      _selectedNoteId = snapshot.notes.firstOrNull?.id;
      _noteController.text = snapshot.notes.firstOrNull?.body ?? '';
    }

    final notificationsReady = await _initializeNotificationsSafely();
    await widget.store.file;
    _log('armazenamento local pronto');
    _log('identidade local pronta');
    if (notificationsReady) {
      _log('timezone local: ${widget.notifications.localTimeZoneId}');
      final driftedNotifications = const NotificationTimeZoneAudit()
          .driftedRecords(
            records: snapshot.scheduledNotifications,
            currentTimeZone: widget.notifications.localTimeZoneId,
          );
      if (driftedNotifications.isNotEmpty) {
        _log(
          'timezone mudou: revise ${driftedNotifications.length} lembrete(s)',
        );
      }
    }
  }

  Future<bool> _initializeNotificationsSafely() async {
    var notificationsReady = false;
    try {
      await widget.notifications.initialize(
        onNotificationSelected: (_) {
          if (!mounted) {
            return;
          }
          setState(() {
            _selectedIndex = 0;
          });
          _log('notificação aberta');
        },
      );
      notificationsReady = true;

      final launchDetails = await widget.notifications.getLaunchDetails();
      if (launchDetails?.didNotificationLaunchApp ?? false) {
        _log('app aberto por notificação');
      }
    } on Object catch (error) {
      _log('notificações indisponíveis: ${_errorDescriber.describe(error)}');
    }

    await _refreshPendingCount();
    await _refreshPermissionState();

    return notificationsReady;
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

  Future<void> _openNotificationComposerForSelectedNote() async {
    final note = _selectedNote(_snapshot);
    if (note == null) {
      return;
    }

    if (_notificationComposerOpen) {
      setState(() => _notificationComposerOpen = false);
      return;
    }

    final authorized = await _ensureNotificationCreationAuthorization();
    if (!authorized || !mounted) {
      return;
    }

    setState(() => _notificationComposerOpen = true);
  }

  Future<bool> _ensureNotificationCreationAuthorization() async {
    try {
      var state = await widget.notifications.currentPermissionState();
      if (mounted) {
        setState(() => _permissionState = state);
      } else {
        _permissionState = state;
      }

      if (state.canCreateExactReminders) {
        return true;
      }

      state = await widget.notifications.requestMissingSchedulePermissions(
        current: state,
      );
      if (mounted) {
        setState(() => _permissionState = state);
      } else {
        _permissionState = state;
      }

      if (state.canCreateExactReminders) {
        _log('autorizações de notificação prontas');
        return true;
      }

      _log('notificação não criada: ${state.authorizationBlockerLabel}');
      return false;
    } on Object catch (error) {
      _log('autorizações indisponíveis: ${_errorDescriber.describe(error)}');
      return false;
    }
  }

  Future<void> _createNotificationForSelectedNote(
    NotificationDraft draft,
  ) async {
    final note = _selectedNote(_snapshot);
    if (note == null) {
      return;
    }

    if (draft.title.trim().isEmpty) {
      return;
    }

    final saved = await _upsertNoteNotification(note: note, draft: draft);
    if (saved && mounted) {
      setState(() => _notificationComposerOpen = false);
    }
  }

  Future<void> _createStandaloneNotification({DateTime? defaultLocal}) async {
    final authorized = await _ensureNotificationCreationAuthorization();
    if (!authorized || !mounted) {
      return;
    }

    final initialLocal =
        defaultLocal ?? DateTime.now().add(const Duration(minutes: 15));
    final draft = await showNotificationEditorDialog(
      _dialogContext,
      initialLocal: initialLocal,
    );
    if (draft == null || draft.title.trim().isEmpty) {
      return;
    }

    await _upsertNoteNotification(note: null, draft: draft);
  }

  Future<void> _editNotification(ScheduledNotificationRecord record) async {
    final snapshot = _snapshot;
    final note = snapshot?.notes
        .where((candidate) => candidate.id == record.ownerId)
        .firstOrNull;
    final draft = await showNotificationEditorDialog(
      _dialogContext,
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
      await _recordNotificationRevision(
        record: record,
        note: _noteForNotification(record),
        action: 'cancelada',
      );
      _log('notificação removida');
      await _refreshPendingCount();
    });
  }

  Future<bool> _upsertNoteNotification({
    required NoteItem? note,
    required NotificationDraft draft,
    ScheduledNotificationRecord? existing,
  }) async {
    var saved = false;
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

      final authorized = await _ensureNotificationCreationAuthorization();
      if (!authorized) {
        return;
      }

      if (existing != null) {
        snapshot = await _withoutNotificationRecord(snapshot, existing);
      }

      final ownerId = note?.id ?? existing?.ownerId ?? newId('note-alert');
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
      setState(() => _permissionState = scheduled.permissionState);
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
      await _recordNotificationRevision(
        record: scheduled.record,
        note: note,
        action: existing == null ? 'criada' : 'editada',
      );
      saved = true;
      _log(
        '${existing == null ? 'notificação criada' : 'notificação atualizada'}: '
        '${formatLocal(scheduled.plan.scheduledLocal)}',
      );
      await _refreshPendingCount();
    });
    return saved;
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

  NoteItem? _noteForNotification(ScheduledNotificationRecord record) {
    return _snapshot?.notes
        .where((candidate) => candidate.id == record.ownerId)
        .firstOrNull;
  }

  Future<void> _recordNotificationRevision({
    required ScheduledNotificationRecord record,
    required NoteItem? note,
    required String action,
  }) async {
    final savedAtUtc = DateTime.now().toUtc();
    final title = _notificationRecordTitle(
      record,
      note == null ? const <NoteItem>[] : <NoteItem>[note],
    );
    final body = <String>[
      'Notificação $action',
      'Título: $title',
      'Quando: ${formatLocalDateTime(record.scheduledForUtc)}',
      if (record.body.trim().isNotEmpty) 'Mensagem: ${record.body.trim()}',
    ].join('\n');
    final revision = NoteEditRevision(
      id: newId('revision'),
      noteId: note?.id ?? record.ownerId,
      noteTitle: 'Notificação · $title',
      body: body,
      savedAtUtc: savedAtUtc,
      kind: NoteEditRevisionKind.notification,
    );

    try {
      final next = await widget.noteHistory.add(revision);
      if (mounted) {
        setState(() => _noteHistory = next);
      } else {
        _noteHistory = next;
      }
    } on Object catch (error) {
      _log('log de notificação não salvo: ${_errorDescriber.describe(error)}');
    }
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
      id: newId('note'),
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
      context: _dialogContext,
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
        _notificationComposerOpen = false;
      });
      _log('nota do dia aberta');
      return;
    }

    await _runAction(() async {
      final now = DateTime.now().toUtc();
      final note = NoteItem(
        id: newId('note'),
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
        _notificationComposerOpen = false;
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
            _notificationComposerOpen = false;
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
      context: _dialogContext,
      builder: (context) => GlobalSearchDialog(snapshot: snapshot),
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
    final clamped = clampPageZoom(value);
    setState(() => _uiZoom = clamped);
    unawaited(
      widget.appearanceSettings.save(_appearance.copyWith(pageZoom: clamped)),
    );
    _appearance = _appearance.copyWith(pageZoom: clamped);
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
      id: newId('revision'),
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
      for (final record in futureRecords) {
        final intent = ReminderIntent.oneShot(
          id: record.reminderIntentId,
          ownerId: record.ownerId,
          ownerType: record.ownerType,
          instantUtc: record.scheduledForUtc,
          updatedAtUtc: nowUtc,
          timeZone: widget.notifications.localTimeZoneId,
        );
        try {
          final result = await widget.notifications.scheduleReminder(
            intent: intent,
            deviceId: _deviceId,
            title: record.title.trim().isEmpty
                ? 'Notificação'
                : record.title.trim(),
            body: record.body.trim(),
          );
          if (result != null) {
            rescheduled.add(result.record);
            if (mounted) {
              setState(() => _permissionState = result.permissionState);
            } else {
              _permissionState = result.permissionState;
            }
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
      );

      await _saveSnapshot(next);
      _syncSelectionAfterSnapshot(next);
      if (mounted) {
        setState(() {
          _notificationComposerOpen = false;
          _selectedIndex = 4;
        });
      } else {
        _notificationComposerOpen = false;
        _selectedIndex = 4;
      }
      await _refreshPendingCount();
      _log(
        'backup TXT restaurado: ${next.notes.length} nota(s), '
        '${next.scheduledNotifications.length} notificação(ões)',
      );
    });
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
      try {
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
      } finally {
        if (adapter is HttpSyncAdapter) {
          adapter.dispose();
        }
      }
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
        context: _dialogContext,
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

  Future<void> _runAction(Future<void> Function() action) async {
    if (!_actionGate.tryEnter()) {
      return;
    }

    setState(() => _busy = true);
    try {
      await action();
    } on Object catch (error) {
      _log('erro: ${_errorDescriber.describe(error)}');
      _messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text(_errorDescriber.describe(error))),
      );
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

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: appDisplayName,
      scaffoldMessengerKey: _messengerKey,
      navigatorKey: _navigatorKey,
      theme: curioThemeData(_appearance.themeProfile, Brightness.light),
      darkTheme: curioThemeData(_appearance.themeProfile, Brightness.dark),
      themeMode: _appearance.themeMode,
      home: FutureBuilder<void>(
        future: _startup,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const _BootScreen();
          }
          if (snapshot.hasError) {
            return _StartupErrorScreen(
              message: _errorDescriber.describe(snapshot.error!),
            );
          }
          final appSnapshot = _snapshot;
          if (appSnapshot == null) {
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
                  TodayView(
                    notes: appSnapshot.notes,
                    scheduledNotifications: appSnapshot.scheduledNotifications,
                    activity: _activity,
                    busy: _busy,
                    permissionState: _permissionState,
                    pendingCount: _pendingCount,
                    onRequestPermissions: _requestPermissions,
                    onOpenNote: (date) => unawaited(_openDailyNote(date)),
                    onOpenNotification: (record) =>
                        unawaited(_openNotificationTarget(record)),
                    onCreateStandaloneNotification: () =>
                        unawaited(_createStandaloneNotification()),
                  ),
                  AgendaView(
                    notes: appSnapshot.notes,
                    scheduledNotifications: appSnapshot.scheduledNotifications,
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
                    onCreateStandaloneNotification: (date) => unawaited(
                      _createStandaloneNotification(
                        defaultLocal: defaultNotificationLocalForDate(date),
                      ),
                    ),
                  ),
                  BoardView(
                    notes: appSnapshot.notes,
                    scheduledNotifications: appSnapshot.scheduledNotifications,
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
                  NotesView(
                    notes: appSnapshot.notes,
                    scheduledNotifications: appSnapshot.scheduledNotifications,
                    noteHistory: _noteHistory,
                    selectedNoteId: _selectedNoteId,
                    selectedDate: _notesDate,
                    notificationComposerOpen: _notificationComposerOpen,
                    controller: _noteController,
                    onOpenCalendar: () => setState(() {
                      _agendaDate = _notesDate;
                      _selectedIndex = 1;
                    }),
                    onToggleNotificationComposer: () =>
                        unawaited(_openNotificationComposerForSelectedNote()),
                    onCreateNotification: (draft) =>
                        unawaited(_createNotificationForSelectedNote(draft)),
                    onCancelNotificationComposer: () =>
                        setState(() => _notificationComposerOpen = false),
                    onEditNotification: (record) =>
                        unawaited(_editNotification(record)),
                    onCancelNotification: (record) =>
                        unawaited(_cancelNotification(record)),
                    onAddNote: _addNote,
                    onRenameNote: _renameSelectedNote,
                    onDeleteNote: _deleteSelectedNote,
                    onRestoreRevision: (NoteEditRevision revision) =>
                        unawaited(_restoreNoteRevision(revision)),
                    onBodyChanged: _updateSelectedNoteBody,
                  ),
                  SyncView(
                    busy: _busy,
                    deviceId: _deviceId,
                    controller: _syncServerController,
                    tokenController: _syncTokenController,
                    settings: _syncSettings,
                    appearance: _appearance,
                    sidecarSupported: _syncSidecarSupported,
                    sidecarState: _syncSidecarState,
                    lastResult: _lastSyncResult,
                    snapshot: appSnapshot,
                    onSave: _saveSyncSettings,
                    onAppearanceChanged: _saveAppearanceSettings,
                    onSync: _runSync,
                    onCopyBackup: () => unawaited(_copyManualBackup()),
                    onRestoreBackup: () =>
                        unawaited(_showRestoreBackupDialog()),
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

// ---------------------------------------------------------------------------
// Private helpers (stay in main.dart)
// ---------------------------------------------------------------------------

String _backupFileTimestamp(DateTime value) {
  final local = value.toLocal();
  return '${local.year}'
      '${local.month.toString().padLeft(2, '0')}'
      '${local.day.toString().padLeft(2, '0')}-'
      '${local.hour.toString().padLeft(2, '0')}'
      '${local.minute.toString().padLeft(2, '0')}'
      '${local.second.toString().padLeft(2, '0')}';
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

// ---------------------------------------------------------------------------
// Boot screen
// ---------------------------------------------------------------------------

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

final class _StartupErrorScreen extends StatelessWidget {
  const _StartupErrorScreen({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Não foi possível iniciar o Curió',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(message, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Zoom controls
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Home shell
// ---------------------------------------------------------------------------

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
          final compact = MediaQuery.of(context).size.height < 620;
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
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          _LogoMark(compact: compact),
                          SizedBox(height: compact ? 10 : 18),
                          IconButton.filledTonal(
                            onPressed: onOpenSearch,
                            icon: const Icon(Icons.search_outlined),
                            tooltip: 'Pesquisa global',
                          ),
                          SizedBox(height: compact ? 8 : 14),
                          _ZoomRailControl(
                            zoom: zoom,
                            onZoomChanged: onZoomChanged,
                          ),
                        ],
                      ),
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

// ---------------------------------------------------------------------------
// Logo mark
// ---------------------------------------------------------------------------

final class _LogoMark extends StatelessWidget {
  const _LogoMark({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final logoSize = compact ? 48.0 : 72.0;
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
        if (!compact) ...<Widget>[
          const SizedBox(height: 10),
          Text(
            appDisplayName,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ],
    );
  }
}
