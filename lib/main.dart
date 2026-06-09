import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lume_core/domain/app_snapshot.dart';
import 'package:lume_core/domain/reminder.dart';
import 'package:lume_core/sync/sync_adapter.dart';
import 'package:lume_core/sync/sync_pairing.dart';
import 'package:path_provider/path_provider.dart';

import 'app_brand.dart';
import 'services/action_error_describer.dart';
import 'services/alarm_playback_service.dart';
import 'services/alarm_settings_store.dart';
import 'services/appearance_settings_store.dart';
import 'services/async_action_gate.dart';
import 'services/calendar_ics_codec.dart';
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
import 'services/windows_attention_service.dart';
import 'sync/http_sync_adapter.dart';
import 'theme/curio_theme.dart';
import 'ui/global_search_dialog.dart';
import 'ui/notification_editor.dart';
import 'ui/task_view_helpers.dart';
import 'ui/views/agenda_view.dart';
import 'ui/views/board_view.dart';
import 'ui/views/notes_view.dart';
import 'ui/views/sync_view.dart';
import 'ui/views/tasks_view.dart';
import 'ui/views/today_view.dart';
import 'ui/zoomed_page.dart';

part 'main_backup_actions.dart';
part 'main_sync_actions.dart';
part 'main_task_actions.dart';

Future<void> main() async {
  LumeWidgetsBinding.ensureInitialized();
  runApp(CurioApp(notifications: NotificationService()));
}

/// Navigation tabs in display order. The order here defines `_selectedIndex`
/// values and must match both the `pages` list and `_HomeShell._destinations()`.
enum _AppTab { today, agenda, board, notes, tasks, sync }

final class CurioApp extends StatefulWidget {
  CurioApp({
    super.key,
    required this.notifications,
    LocalStore? store,
    DeviceIdentityStore? deviceIdentity,
    SyncSettingsStore? syncSettings,
    AppearanceSettingsStore? appearanceSettings,
    AlarmSettingsStore? alarmSettings,
    AlarmPlaybackService? alarmPlayback,
    NoteEditHistoryStore? noteHistory,
  }) : store = store ?? LocalStore(),
       deviceIdentity = deviceIdentity ?? DeviceIdentityStore(),
       syncSettings = syncSettings ?? SyncSettingsStore(),
       appearanceSettings = appearanceSettings ?? AppearanceSettingsStore(),
       alarmSettings = alarmSettings ?? AlarmSettingsStore(),
       alarmPlayback = alarmPlayback ?? AlarmPlaybackService(),
       noteHistory = noteHistory ?? NoteEditHistoryStore();

  final NotificationService notifications;
  final LocalStore store;
  final DeviceIdentityStore deviceIdentity;
  final SyncSettingsStore syncSettings;
  final AppearanceSettingsStore appearanceSettings;
  final AlarmSettingsStore alarmSettings;
  final AlarmPlaybackService alarmPlayback;
  final NoteEditHistoryStore noteHistory;

  @override
  State<CurioApp> createState() => _CurioAppState();
}

final class _CurioAppState extends State<CurioApp>
    with _TaskActions, _BackupActions, _SyncActions {
  /// Janela do autosave do editor: curta o bastante para o usuário nunca
  /// perceber, longa o bastante para coalescer a digitação contínua em uma
  /// única escrita no banco.
  static const Duration _noteAutosaveDelay = Duration(milliseconds: 500);

  late final Future<void> _startup;
  late final TextEditingController _noteController;
  @override
  late final TextEditingController _syncServerController;
  @override
  late final TextEditingController _syncTokenController;
  @override
  late final LocalSyncSidecar _syncSidecar;
  late final SnapshotWriteQueue _snapshotWrites;
  final AsyncActionGate _actionGate = AsyncActionGate();
  @override
  final ActionErrorDescriber _errorDescriber = const ActionErrorDescriber();
  @override
  final WindowsAttentionService _windowsAttention =
      const WindowsAttentionService();
  @override
  final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  BuildContext get _dialogContext => _navigatorKey.currentContext ?? context;

  int _selectedIndex = 0;
  double _uiZoom = 1;
  TaskFilter _taskFilter = TaskFilter.open;
  DateTime _agendaDate = dateOnly(DateTime.now());
  DateTime _notesDate = dateOnly(DateTime.now());
  bool _busy = false;
  @override
  String _deviceId = 'lume-${defaultTargetPlatform.name}';
  @override
  SyncSettings _syncSettings = const SyncSettings();
  AppearanceSettings _appearance = const AppearanceSettings();
  @override
  AlarmSettings _alarmSettings = const AlarmSettings();
  LocalSyncSidecarState? _syncSidecarState;
  SyncResult? _lastSyncResult;
  @override
  AppSnapshot? _snapshot;
  String? _selectedNoteId;
  ScheduledNotificationRecord? _activeAlarmRecord;
  List<NoteEditRevision> _noteHistory = const <NoteEditRevision>[];
  final Map<String, DateTime> _lastHistoryAtByNote = <String, DateTime>{};
  final Map<int, Timer> _localAlarmTimers = <int, Timer>{};
  Timer? _noteAutosaveDebounce;
  bool _noteAutosaveDirty = false;
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
    _snapshotWrites = SnapshotWriteQueue(
      saveSnapshot: widget.store.save,
      applyDiff: widget.store.applyDiff,
    );
    _syncSidecar = LocalSyncSidecar(
      loadSnapshot: () async => _snapshot ?? await widget.store.load(),
      saveSnapshot: (snapshot) async {
        // O sidecar montou `snapshot` a partir de uma leitura anterior de
        // `_snapshot`; edições locais feitas nesse meio-tempo (ex.: digitação
        // no editor) precisam ser fundidas para não serem revertidas.
        final latest = _snapshot;
        final next = latest == null || identical(latest, snapshot)
            ? snapshot
            : const SnapshotSyncMerger().merge(local: latest, remote: snapshot);
        await _saveSnapshot(next);
        if (mounted) {
          setState(() => _syncSelectionAfterSnapshot(next));
        }
      },
    );
    _startup = _initialize();
  }

  @override
  void dispose() {
    _flushNoteAutosave();
    _noteController.dispose();
    _syncServerController.dispose();
    _syncTokenController.dispose();
    for (final timer in _localAlarmTimers.values) {
      timer.cancel();
    }
    _localAlarmTimers.clear();
    unawaited(widget.alarmPlayback.stop());
    unawaited(_syncSidecar.stop());
    super.dispose();
  }

  Future<void> _initialize() async {
    final deviceId = await widget.deviceIdentity.load();
    final syncSettings = await widget.syncSettings.load();
    final appearance = await widget.appearanceSettings.load();
    final alarmSettings = await widget.alarmSettings.load();
    final noteHistory = await widget.noteHistory.load();
    final loaded = await widget.store.load();
    // O snapshot carregado espelha o banco: a partir daqui as escritas podem
    // ir por diff em vez de replace completo.
    _snapshotWrites.prime(loaded);
    final nowUtc = DateTime.now().toUtc();
    // Backfill syncable reminders for notifications scheduled before reminders
    // were synced (e.g. data from an older app version), so the reconcile below
    // does not treat them as orphans. Then bound long-term growth by dropping
    // expired tombstones and long-fired one-shot reminders.
    final snapshot = compactSnapshot(
      backfillRemindersFromRecords(loaded, nowUtc: nowUtc),
      nowUtc: nowUtc,
    );
    _applyState(() {
      _deviceId = deviceId;
      _syncSettings = syncSettings;
      _appearance = appearance;
      _alarmSettings = alarmSettings;
      _uiZoom = appearance.pageZoom;
      _syncServerController.text = syncSettings.serverUrl;
      _syncTokenController.text = syncSettings.authToken;
      _snapshot = snapshot;
      _noteHistory = noteHistory;
      _selectedNoteId = snapshot.notes.firstOrNull?.id;
      _noteController.text = snapshot.notes.firstOrNull?.body ?? '';
    });
    _refreshLocalAlarmTimers(snapshot.scheduledNotifications);

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

      // Arm any synced reminder this install hasn't scheduled locally yet
      // (e.g. after a fresh install that pulled reminders from another device),
      // and persist if either the reconcile or the boot compaction changed
      // anything relative to what was loaded.
      final current = _snapshot ?? snapshot;
      final reconciled = await _reconcileReminders(current);
      if (!identical(reconciled, loaded)) {
        await _saveSnapshot(reconciled);
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
            _selectedIndex = _AppTab.today.index;
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

  @override
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

  @override
  Future<bool> _ensureNotificationCreationAuthorization() async {
    try {
      var state = await widget.notifications.currentPermissionState();
      _applyState(() => _permissionState = state);

      if (state.canCreateExactReminders) {
        return true;
      }

      state = await widget.notifications.requestMissingSchedulePermissions(
        current: state,
      );
      _applyState(() => _permissionState = state);

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
      final withoutRecord = await _withoutNotificationRecord(snapshot, record);
      final next = _withoutReminderIntent(
        withoutRecord,
        record.reminderIntentId,
        _deviceId,
      );
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
        title: draft.title.trim(),
        body: draft.body.trim(),
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
        _withReminderIntent(snapshot, intent).copyWith(
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

  @override
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

  /// Aligns this device's locally scheduled notifications with the synced
  /// reminder list: arms any enabled reminder this device hasn't scheduled yet
  /// and cancels local notifications whose reminder was removed or disabled on
  /// another device. Each device keeps its own notification ids; only the
  /// reminder intents travel between devices. Returns the same snapshot when
  /// nothing changed.
  @override
  Future<AppSnapshot> _reconcileReminders(AppSnapshot snapshot) async {
    final activeById = <String, ReminderIntent>{
      for (final intent in snapshot.reminders)
        if (intent.enabled) intent.id: intent,
    };
    var records = snapshot.scheduledNotifications;

    final orphans = records
        .where((record) => !activeById.containsKey(record.reminderIntentId))
        .toList();
    for (final record in orphans) {
      try {
        await widget.notifications.cancel(record.id);
      } on Object catch (error) {
        _log('lembrete não cancelado: ${_errorDescriber.describe(error)}');
      }
    }
    if (orphans.isNotEmpty) {
      final orphanIds = orphans.map((record) => record.id).toSet();
      records = records
          .where((record) => !orphanIds.contains(record.id))
          .toList();
    }

    final scheduledIntentIds = records
        .map((record) => record.reminderIntentId)
        .toSet();
    final additions = <ScheduledNotificationRecord>[];
    for (final intent in activeById.values) {
      if (scheduledIntentIds.contains(intent.id)) {
        continue;
      }
      try {
        final result = await widget.notifications.scheduleReminder(
          intent: intent,
          deviceId: _deviceId,
          title: intent.title,
          body: intent.body,
        );
        if (result != null) {
          additions.add(result.record);
        }
      } on Object catch (error) {
        _log('lembrete não agendado: ${_errorDescriber.describe(error)}');
      }
    }

    if (orphans.isEmpty && additions.isEmpty) {
      return snapshot;
    }
    return snapshot.copyWith(
      scheduledNotifications: <ScheduledNotificationRecord>[
        ...additions,
        ...records,
      ],
    );
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
      _applyState(() => _noteHistory = next);
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
        _selectedIndex = _AppTab.notes.index;
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
        _selectedIndex = _AppTab.notes.index;
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
            _selectedIndex = _AppTab.notes.index;
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
          _selectedIndex = _AppTab.notes.index;
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

  @override
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
    // O texto digitado entra em `_snapshot` imediatamente (sync e demais ações
    // leem daqui), mas a persistência é adiada: sem o debounce cada tecla
    // reescreveria o banco inteiro via replaceSnapshot.
    _snapshot = next;
    _noteAutosaveDirty = true;
    _noteAutosaveDebounce?.cancel();
    _noteAutosaveDebounce = Timer(_noteAutosaveDelay, _flushNoteAutosave);
  }

  /// Persists the latest in-memory snapshot if the note editor has unsaved
  /// keystrokes. Safe to call at any time; saving the current `_snapshot` can
  /// only re-write data that newer actions already persisted.
  void _flushNoteAutosave() {
    _noteAutosaveDebounce?.cancel();
    _noteAutosaveDebounce = null;
    if (!_noteAutosaveDirty) {
      return;
    }
    _noteAutosaveDirty = false;
    final snapshot = _snapshot;
    if (snapshot == null) {
      return;
    }
    unawaited(
      _saveSnapshot(snapshot).catchError((Object error, StackTrace stackTrace) {
        _noteAutosaveDirty = true;
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
      _applyState(() => _noteHistory = next);
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
        _selectedIndex = _AppTab.notes.index;
        _selectedNoteId = restored.id;
        _notesDate = dailyNoteDate(restored) ?? _notesDate;
        _noteController.text = restored.body;
      });
      _log('versão restaurada: ${revision.noteTitle}');
    });
  }

  @override
  void _syncSelectionAfterSnapshot(AppSnapshot snapshot) {
    final selectedId = _selectedNoteId;
    final selected = selectedId == null
        ? null
        : snapshot.notes.where((note) => note.id == selectedId).firstOrNull;
    final nextSelected = selected ?? snapshot.notes.firstOrNull;
    _selectedNoteId = nextSelected?.id;
    final nextBody = nextSelected?.body ?? '';
    // Reatribuir o mesmo texto reposiciona o cursor no início — irritante
    // quando um sync em segundo plano termina no meio da digitação.
    if (_noteController.text != nextBody) {
      _noteController.text = nextBody;
    }
  }

  void _refreshLocalAlarmTimers(
    Iterable<ScheduledNotificationRecord> notifications,
  ) {
    for (final timer in _localAlarmTimers.values) {
      timer.cancel();
    }
    _localAlarmTimers.clear();

    final now = DateTime.now().toUtc();
    final upcoming =
        notifications
            .where((record) => record.scheduledForUtc.isAfter(now))
            .toList()
          ..sort((a, b) => a.scheduledForUtc.compareTo(b.scheduledForUtc));

    for (final record in upcoming.take(64)) {
      final delay = record.scheduledForUtc.difference(now);
      _localAlarmTimers[record.id] = Timer(delay, () {
        _localAlarmTimers.remove(record.id);
        unawaited(_startLocalAlarm(record));
      });
    }
  }

  Future<void> _startLocalAlarm(ScheduledNotificationRecord record) async {
    _applyState(() {
      _activeAlarmRecord = record;
      _selectedIndex = _AppTab.today.index;
    });

    final result = await widget.alarmPlayback.start(
      _alarmSettings,
      windowsAttention: _windowsAttention,
    );
    final didFlash = defaultTargetPlatform == TargetPlatform.windows
        ? _windowsAttention.flashTaskbar(count: 24)
        : false;
    _log(didFlash ? '${result.message}; ícone piscando' : result.message);
  }

  Future<void> _stopLocalAlarm() async {
    await widget.alarmPlayback.stop();
    _applyState(() => _activeAlarmRecord = null);
    _log('alarme contínuo parado');
  }

  Future<void> _snoozeActiveAlarm() async {
    final record = _activeAlarmRecord;
    if (record == null) {
      return;
    }

    await _runAction(() async {
      final snapshot = _snapshot;
      if (snapshot == null) {
        return;
      }

      await widget.alarmPlayback.stop();
      final scheduledAtUtc = DateTime.now().toUtc().add(
        const Duration(minutes: 5),
      );
      final intent = ReminderIntent.oneShot(
        id: record.reminderIntentId,
        ownerId: record.ownerId,
        ownerType: record.ownerType,
        instantUtc: scheduledAtUtc,
        updatedAtUtc: DateTime.now().toUtc(),
        timeZone: widget.notifications.localTimeZoneId,
      );

      final result = await widget.notifications.scheduleReminder(
        intent: intent,
        deviceId: _deviceId,
        title: record.title.trim().isEmpty ? 'Notificação' : record.title,
        body: record.body,
      );
      if (result == null) {
        _log('alarme não adiado: notificação sem próxima ocorrência');
        return;
      }

      final withoutCurrent = await _withoutNotificationRecord(snapshot, record);
      final next = withoutCurrent.copyWith(
        scheduledNotifications: <ScheduledNotificationRecord>[
          result.record,
          ...withoutCurrent.scheduledNotifications.where(
            (candidate) => candidate.id != result.record.id,
          ),
        ],
      );
      await _saveSnapshot(next);
      await _recordNotificationRevision(
        record: result.record,
        note: _noteForNotification(record),
        action: 'adiada 5 min',
      );
      await _refreshPendingCount();
      setState(() {
        _activeAlarmRecord = null;
        _selectedIndex = _AppTab.today.index;
      });
      _log('alarme adiado 5 min: ${formatLocalDateTime(scheduledAtUtc)}');
    });
  }

  Future<void> _cancelActiveAlarm() async {
    final record = _activeAlarmRecord;
    await widget.alarmPlayback.stop();
    _applyState(() => _activeAlarmRecord = null);
    if (record == null) {
      _log('alarme cancelado');
      return;
    }
    await _cancelNotification(record);
  }

  /// Applies [mutate] inside `setState` when still mounted, or directly when
  /// not — so state changes that land after an `await` still take effect even
  /// if the widget was disposed in the meantime.
  @override
  void _applyState(VoidCallback mutate) {
    if (mounted) {
      setState(mutate);
    } else {
      mutate();
    }
  }

  @override
  Future<void> _saveSnapshot(AppSnapshot snapshot) async {
    // O estado em memória muda de forma síncrona (antes de qualquer await):
    // assim quem leu `_snapshot` no mesmo microtask nunca observa rollback
    // enquanto a escrita em disco está em voo. Quando o snapshot já é o
    // atual (ex.: flush do autosave), não há rebuild a fazer.
    _refreshLocalAlarmTimers(snapshot.scheduledNotifications);
    if (!identical(_snapshot, snapshot)) {
      _applyState(() => _snapshot = snapshot);
    }
    await _snapshotWrites.save(snapshot);
  }

  @override
  Future<String?> _promptText({
    required String title,
    required String hint,
    String initialValue = '',
    String confirmLabel = 'Salvar',
  }) {
    return showDialog<String>(
      context: _dialogContext,
      builder: (context) => _TextPromptDialog(
        title: title,
        hint: hint,
        initialValue: initialValue,
        confirmLabel: confirmLabel,
      ),
    );
  }

  @override
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

  @override
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
                    activeAlarm: _activeAlarmRecord,
                    onRequestPermissions: _requestPermissions,
                    onSnoozeActiveAlarm: () => unawaited(_snoozeActiveAlarm()),
                    onCancelActiveAlarm: () => unawaited(_cancelActiveAlarm()),
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
                      _selectedIndex = _AppTab.agenda.index;
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
                  TasksView(
                    tasks: appSnapshot.tasks,
                    filter: _taskFilter,
                    busy: _busy,
                    selectedNoteTitle: _selectedNote(appSnapshot)?.title,
                    onFilterChanged: _setTaskFilter,
                    onAddTask: _addTask,
                    onCreateFromNote: () =>
                        unawaited(_createTaskFromSelectedNote()),
                    onToggleDone: (task) => unawaited(_toggleTaskDone(task)),
                    onRename: (task) => unawaited(_renameTask(task)),
                    onSetDue: (task) => unawaited(_setTaskDue(task)),
                    onClearDue: (task) => unawaited(_clearTaskDue(task)),
                    onDelete: (task) => unawaited(_deleteTask(task)),
                  ),
                  SyncView(
                    busy: _busy,
                    deviceId: _deviceId,
                    controller: _syncServerController,
                    tokenController: _syncTokenController,
                    settings: _syncSettings,
                    appearance: _appearance,
                    alarmSettings: _alarmSettings,
                    alarmPlaying: widget.alarmPlayback.isPlaying,
                    sidecarSupported: _syncSidecarSupported,
                    sidecarState: _syncSidecarState,
                    lastResult: _lastSyncResult,
                    snapshot: appSnapshot,
                    onSave: _saveSyncSettings,
                    onAppearanceChanged: _saveAppearanceSettings,
                    onAlarmSettingsChanged: (settings) =>
                        unawaited(_saveAlarmSettings(settings)),
                    onPickAlarmAudio: () => unawaited(_pickAlarmAudio()),
                    onClearAlarmAudio: () => unawaited(_clearAlarmAudio()),
                    onTestAlarmAudio: () => unawaited(_testAlarmAudio()),
                    onStopAlarmAudio: () => unawaited(_stopLocalAlarm()),
                    onExportCalendarIcs: () => unawaited(_exportCalendarIcs()),
                    onImportCalendarIcs: () => unawaited(_importCalendarIcs()),
                    onSync: _runSync,
                    onApplyPairing: (code) =>
                        unawaited(_applyPairingCode(code)),
                    onClearPin: () => unawaited(_clearPinnedCert()),
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

final class _ImportedNoteResult {
  const _ImportedNoteResult({required this.note, required this.changed});

  final NoteItem note;
  final bool changed;
}

_ImportedNoteResult _upsertImportedDailyNote(
  List<NoteItem> notes, {
  required DateTime date,
  required CalendarIcsEvent event,
  required DateTime nowUtc,
}) {
  final title = dailyNoteTitle(date);
  final existingIndex = notes.indexWhere((note) => note.title == title);
  final entry = _calendarEventMarkdown(event);

  if (existingIndex == -1) {
    final note = NoteItem(
      id: newId('note'),
      title: title,
      body: '## ${formatLocalDate(date)}\n\n$entry\n',
      createdAtUtc: nowUtc,
      updatedAtUtc: nowUtc,
    );
    notes.insert(0, note);
    return _ImportedNoteResult(note: note, changed: true);
  }

  final existing = notes[existingIndex];
  if (existing.body.contains(entry)) {
    return _ImportedNoteResult(note: existing, changed: false);
  }

  final separator = existing.body.trimRight().isEmpty ? '' : '\n';
  final updated = existing.copyWith(
    body: '${existing.body.trimRight()}$separator$entry\n',
    updatedAtUtc: nowUtc,
  );
  notes[existingIndex] = updated;
  return _ImportedNoteResult(note: updated, changed: true);
}

String _calendarEventMarkdown(CalendarIcsEvent event) {
  final label = event.allDay ? 'dia todo' : formatLocalTime(event.startsAtUtc);
  final description = event.description.trim();
  final buffer = StringBuffer('- $label · ${event.title}');
  if (description.isNotEmpty) {
    buffer.write(': $description');
  }
  if (!event.allDay && event.endsAtUtc != null) {
    buffer.write('\n  - fim: ${formatLocalTime(event.endsAtUtc!)}');
  }
  if (event.alarmAtUtc != null) {
    buffer.write('\n  - lembrete: ${formatLocalDateTime(event.alarmAtUtc!)}');
  }
  if (event.recurrenceRule.trim().isNotEmpty) {
    final supported = event.supportedRecurrence;
    buffer.write(
      '\n  - recorrência: ${supported?.label ?? event.recurrenceRule.trim()}',
    );
  }
  if (event.timeZoneId.trim().isNotEmpty) {
    buffer.write('\n  - timezone: ${event.timeZoneId.trim()}');
  }
  return buffer.toString();
}

bool _calendarEventCanCreateNotification(
  CalendarIcsEvent event,
  DateTime nowUtc,
) {
  if (event.allDay) {
    return false;
  }
  if (event.supportedRecurrence != null) {
    return true;
  }
  return _calendarEventNotificationUtc(event, nowUtc).isAfter(nowUtc);
}

DateTime _calendarEventNotificationUtc(
  CalendarIcsEvent event,
  DateTime nowUtc,
) {
  final alarmAt = event.alarmAtUtc;
  if (alarmAt != null && alarmAt.isAfter(nowUtc)) {
    return alarmAt;
  }
  return event.startsAtUtc;
}

ReminderIntent _calendarImportReminderIntent({
  required CalendarIcsEvent event,
  required String noteId,
  required DateTime notificationUtc,
  required DateTime nowUtc,
  required String timeZone,
}) {
  final recurrence = event.supportedRecurrence;
  final intentId = event.reminderId;
  if (recurrence == null) {
    return ReminderIntent.oneShot(
      id: intentId,
      ownerId: noteId,
      ownerType: ReminderOwnerType.note,
      instantUtc: notificationUtc,
      updatedAtUtc: nowUtc,
      timeZone: timeZone,
    );
  }

  final recurringLocal = (event.alarmAtUtc ?? event.startsAtUtc).toLocal();
  final localTime = LocalClockTime(
    hour: recurringLocal.hour,
    minute: recurringLocal.minute,
  );
  return switch (recurrence.kind) {
    CalendarIcsRecurrenceKind.daily => ReminderIntent.daily(
      id: intentId,
      ownerId: noteId,
      ownerType: ReminderOwnerType.note,
      localTime: localTime,
      timeZone: timeZone,
      updatedAtUtc: nowUtc,
    ),
    CalendarIcsRecurrenceKind.weekly => ReminderIntent.weekly(
      id: intentId,
      ownerId: noteId,
      ownerType: ReminderOwnerType.note,
      localTime: localTime,
      timeZone: timeZone,
      anchorLocalDate: recurringLocal,
      byWeekday: recurrence.weekday ?? recurringLocal.weekday,
      updatedAtUtc: nowUtc,
    ),
  };
}

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

/// Upserts the syncable [intent] into the snapshot's reminder list (the layer
/// replicated across devices); the per-device scheduled record stays local.
AppSnapshot _withReminderIntent(AppSnapshot snapshot, ReminderIntent intent) {
  return snapshot.copyWith(
    reminders: <ReminderIntent>[
      intent,
      ...snapshot.reminders.where((candidate) => candidate.id != intent.id),
    ],
  );
}

/// Removes a reminder intent and leaves a tombstone so the deletion replicates
/// instead of being resurrected by an older snapshot from another device.
AppSnapshot _withoutReminderIntent(
  AppSnapshot snapshot,
  String intentId,
  String deviceId,
) {
  return _withDeletedRecord(
    snapshot.copyWith(
      reminders: snapshot.reminders
          .where((candidate) => candidate.id != intentId)
          .toList(),
    ),
    DeletedRecord(
      recordType: SyncRecordType.reminder,
      recordId: intentId,
      deletedAtUtc: DateTime.now().toUtc(),
      deviceId: deviceId,
    ),
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
// Text prompt dialog
// ---------------------------------------------------------------------------

final class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog({
    required this.title,
    required this.hint,
    required this.initialValue,
    required this.confirmLabel,
  });

  final String title;
  final String hint;
  final String initialValue;
  final String confirmLabel;

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

final class _TextPromptDialogState extends State<_TextPromptDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue)
      ..selection = TextSelection.collapsed(offset: widget.initialValue.length);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(hintText: widget.hint),
        textInputAction: TextInputAction.done,
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(widget.confirmLabel),
        ),
      ],
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
    return _AppTab.values.map(_destinationFor).toList();
  }
}

_DestinationItem _destinationFor(_AppTab tab) {
  return switch (tab) {
    _AppTab.today => const _DestinationItem(
      'Hoje',
      Icons.today_outlined,
      Icons.today,
    ),
    _AppTab.agenda => const _DestinationItem(
      'Agenda',
      Icons.calendar_month_outlined,
      Icons.calendar_month,
    ),
    _AppTab.board => const _DestinationItem(
      'Quadro',
      Icons.view_kanban_outlined,
      Icons.view_kanban,
    ),
    _AppTab.notes => const _DestinationItem(
      'Notas',
      Icons.notes_outlined,
      Icons.notes,
    ),
    _AppTab.tasks => const _DestinationItem(
      'Tarefas',
      Icons.task_alt_outlined,
      Icons.task_alt,
    ),
    _AppTab.sync => const _DestinationItem(
      'Sync',
      Icons.sync_outlined,
      Icons.sync,
    ),
  };
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
