import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lume_core/domain/app_snapshot.dart';
import 'package:lume_core/domain/reminder.dart';
import 'package:lume_core/sync/sync_adapter.dart';
import 'package:timezone/timezone.dart' as tz;

import 'app_brand.dart';
import 'services/action_error_describer.dart';
import 'services/device_identity.dart';
import 'services/async_action_gate.dart';
import 'services/local_store.dart';
import 'services/local_sync_sidecar.dart';
import 'services/lume_widgets_binding.dart';
import 'services/notification_service.dart';
import 'services/notification_timezone_audit.dart';
import 'services/snapshot_write_queue.dart';
import 'services/sync_settings_store.dart';
import 'services/sync_settings_validator.dart';
import 'sync/http_sync_adapter.dart';
import 'ui/agenda_calendar.dart';
import 'ui/task_view_helpers.dart';

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
  }) : store = store ?? LocalStore(),
       deviceIdentity = deviceIdentity ?? DeviceIdentityStore(),
       syncSettings = syncSettings ?? SyncSettingsStore();

  final NotificationService notifications;
  final LocalStore store;
  final DeviceIdentityStore deviceIdentity;
  final SyncSettingsStore syncSettings;

  @override
  State<CurioApp> createState() => _CurioAppState();
}

final class _CurioAppState extends State<CurioApp> {
  late final Future<void> _startup;
  late final TextEditingController _noteController;
  late final TextEditingController _taskSearchController;
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
  String _taskQuery = '';
  TaskFilter _taskFilter = TaskFilter.open;
  AgendaMode _agendaMode = AgendaMode.timeline;
  DateTime _agendaDate = dateOnly(DateTime.now());
  bool _busy = false;
  String _deviceId = 'lume-${defaultTargetPlatform.name}';
  SyncSettings _syncSettings = const SyncSettings();
  LocalSyncSidecarState? _syncSidecarState;
  SyncResult? _lastSyncResult;
  AppSnapshot? _snapshot;
  String? _selectedNoteId;
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
    _taskSearchController = TextEditingController();
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
    _taskSearchController.dispose();
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
    final snapshot = await widget.store.load();
    if (mounted) {
      setState(() {
        _deviceId = deviceId;
        _syncSettings = syncSettings;
        _syncServerController.text = syncSettings.serverUrl;
        _syncTokenController.text = syncSettings.authToken;
        _snapshot = snapshot;
        _selectedNoteId = snapshot.notes.firstOrNull?.id;
        _noteController.text = snapshot.notes.firstOrNull?.body ?? '';
      });
    } else {
      _deviceId = deviceId;
      _syncSettings = syncSettings;
      _syncServerController.text = syncSettings.serverUrl;
      _syncTokenController.text = syncSettings.authToken;
      _snapshot = snapshot;
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

  Future<void> _scheduleOneShot() async {
    await _runAction(() async {
      final location = widget.notifications.localLocation;
      final now = tz.TZDateTime.now(location);
      final fireAt = now.add(const Duration(minutes: 2));
      final intent = ReminderIntent.oneShot(
        id: 'demo-one-shot',
        ownerId: 'task-payments',
        ownerType: ReminderOwnerType.task,
        instantUtc: fireAt.toUtc(),
        updatedAtUtc: DateTime.now().toUtc(),
        timeZone: widget.notifications.localTimeZoneId,
      );
      await _schedule(
        intent,
        appDisplayName,
        'Teste rápido agendado para agora há pouco.',
      );
    });
  }

  Future<void> _scheduleDaily() async {
    await _runAction(() async {
      final location = widget.notifications.localLocation;
      final nextMinute = tz.TZDateTime.now(
        location,
      ).add(const Duration(minutes: 1));
      final intent = ReminderIntent.daily(
        id: 'demo-daily',
        ownerId: 'task-daily-review',
        ownerType: ReminderOwnerType.task,
        localTime: LocalClockTime(
          hour: nextMinute.hour,
          minute: nextMinute.minute,
        ),
        timeZone: widget.notifications.localTimeZoneId,
        updatedAtUtc: DateTime.now().toUtc(),
      );
      await _schedule(
        intent,
        'Revisão diária',
        'Passe rápido pela agenda de hoje.',
      );
    });
  }

  Future<void> _scheduleWeekly() async {
    await _runAction(() async {
      final location = widget.notifications.localLocation;
      final nextMinute = tz.TZDateTime.now(
        location,
      ).add(const Duration(minutes: 1));
      final intent = ReminderIntent.weekly(
        id: 'demo-weekly',
        ownerId: 'note-weekly-plan',
        ownerType: ReminderOwnerType.note,
        localTime: LocalClockTime(
          hour: nextMinute.hour,
          minute: nextMinute.minute,
        ),
        timeZone: widget.notifications.localTimeZoneId,
        anchorLocalDate: DateTime(
          nextMinute.year,
          nextMinute.month,
          nextMinute.day,
        ),
        byWeekday: nextMinute.weekday,
        updatedAtUtc: DateTime.now().toUtc(),
      );
      await _schedule(intent, 'Planejamento semanal', 'Abra a nota da semana.');
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

  Future<void> _schedule(
    ReminderIntent intent,
    String title,
    String body,
  ) async {
    final result = await widget.notifications.scheduleReminder(
      intent: intent,
      deviceId: _deviceId,
      title: title,
      body: body,
    );

    if (result == null) {
      _log('lembrete ignorado: ocorrência no passado');
      return;
    }

    setState(() {
      _lastSchedule = result;
      _permissionState = result.permissionState;
    });
    final snapshot = _snapshot;
    if (snapshot != null) {
      await _saveSnapshot(
        snapshot.copyWith(
          scheduledNotifications: <ScheduledNotificationRecord>[
            result.record,
            ...snapshot.scheduledNotifications.where(
              (record) => record.id != result.record.id,
            ),
          ],
        ),
      );
    }
    _log(
      'lembrete agendado para ${formatLocal(result.plan.scheduledLocal)} '
      '(${result.deliveryLabel})',
    );
    await _refreshPendingCount();
  }

  Future<void> _addTask() async {
    final draft = await _showTaskEditor();
    if (draft == null || draft.title.trim().isEmpty) {
      return;
    }

    await _createTaskFromDraft(draft);
  }

  Future<void> _addTaskForDate(DateTime date) async {
    final localDate = dateOnly(date);
    final draft = await _showTaskEditor(
      initialDueLocal: _defaultDueLocalForDate(localDate),
      dialogTitle: 'Novo item em ${formatLocalDate(localDate)}',
    );
    if (draft == null || draft.title.trim().isEmpty) {
      return;
    }

    await _createTaskFromDraft(draft, logMessage: 'item do dia criado');
  }

  Future<void> _createTaskFromDraft(
    _TaskDraft draft, {
    String logMessage = 'tarefa criada',
  }) async {
    final now = DateTime.now().toUtc();
    final task = TaskItem(
      id: _newId('task'),
      title: draft.title.trim(),
      description: draft.description.trim(),
      status: TaskStatus.open,
      dueAtUtc: draft.dueAtUtc,
      reminderEnabled: draft.reminderEnabled,
      createdAtUtc: now,
      updatedAtUtc: now,
    );

    await _upsertTask(task);
    _log(logMessage);
  }

  Future<void> _editTask(TaskItem task) async {
    final draft = await _showTaskEditor(task: task);
    if (draft == null || draft.title.trim().isEmpty) {
      return;
    }

    final updated = task.copyWith(
      title: draft.title.trim(),
      description: draft.description.trim(),
      dueAtUtc: draft.dueAtUtc,
      reminderEnabled: draft.reminderEnabled,
      updatedAtUtc: DateTime.now().toUtc(),
      clearDueAt: draft.dueAtUtc == null,
    );

    await _upsertTask(updated, existing: task);
    _log('tarefa atualizada');
  }

  Future<void> _deleteTask(TaskItem task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Excluir tarefa'),
          content: Text('Excluir "${task.title}"?'),
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

    final snapshot = _snapshot;
    if (snapshot == null) {
      return;
    }

    final deletedAtUtc = DateTime.now().toUtc();
    var next = _withDeletedRecord(
      snapshot.copyWith(
        tasks: snapshot.tasks
            .where((candidate) => candidate.id != task.id)
            .toList(),
      ),
      DeletedRecord(
        recordType: SyncRecordType.task,
        recordId: task.id,
        deletedAtUtc: deletedAtUtc,
        deviceId: _deviceId,
      ),
    );
    next = await _cancelTaskNotifications(next, task.id);
    await _saveSnapshot(next);
    _log('tarefa excluída');
    await _refreshPendingCount();
  }

  Future<void> _toggleTask(TaskItem task, bool done) async {
    final now = DateTime.now().toUtc();
    final updated = task.copyWith(
      status: done ? TaskStatus.done : TaskStatus.open,
      completedAtUtc: done ? now : null,
      clearCompletedAt: !done,
      updatedAtUtc: now,
    );
    await _upsertTask(updated, existing: task);
    await _refreshPendingCount();
  }

  Future<void> _upsertTask(TaskItem task, {TaskItem? existing}) async {
    final snapshot = _snapshot;
    if (snapshot == null) {
      return;
    }

    var next = snapshot.copyWith(
      tasks: existing == null
          ? <TaskItem>[task, ...snapshot.tasks]
          : snapshot.tasks
                .map((candidate) => candidate.id == task.id ? task : candidate)
                .toList(),
    );
    next = await _cancelTaskNotifications(next, task.id);
    next = await _scheduleTaskNotification(next, task);
    await _saveSnapshot(next);
    await _refreshPendingCount();
  }

  Future<AppSnapshot> _cancelTaskNotifications(
    AppSnapshot snapshot,
    String taskId,
  ) async {
    final records = snapshot.scheduledNotifications
        .where((record) => _isTaskRecord(record, taskId))
        .toList();

    for (final record in records) {
      await widget.notifications.cancel(record.id);
    }

    if (records.isEmpty) {
      return snapshot;
    }

    return snapshot.copyWith(
      scheduledNotifications: snapshot.scheduledNotifications
          .where((record) => !_isTaskRecord(record, taskId))
          .toList(),
    );
  }

  Future<AppSnapshot> _scheduleTaskNotification(
    AppSnapshot snapshot,
    TaskItem task,
  ) async {
    final dueAtUtc = task.dueAtUtc;
    if (!task.reminderEnabled || task.isDone || dueAtUtc == null) {
      return snapshot;
    }

    if (!dueAtUtc.isAfter(DateTime.now().toUtc())) {
      _log('notificação ignorada: horário no passado');
      return snapshot;
    }

    final intent = ReminderIntent.oneShot(
      id: 'task-${task.id}-due',
      ownerId: task.id,
      ownerType: ReminderOwnerType.task,
      instantUtc: dueAtUtc,
      updatedAtUtc: DateTime.now().toUtc(),
      timeZone: widget.notifications.localTimeZoneId,
    );

    final result = await widget.notifications.scheduleReminder(
      intent: intent,
      deviceId: _deviceId,
      title: task.title,
      body: task.description.isEmpty ? 'Tarefa com horário' : task.description,
    );
    if (result == null) {
      return snapshot;
    }

    setState(() {
      _lastSchedule = result;
      _permissionState = result.permissionState;
    });
    _log(
      'alerta da tarefa: ${formatLocal(result.plan.scheduledLocal)} '
      '(${result.deliveryLabel})',
    );

    return snapshot.copyWith(
      scheduledNotifications: <ScheduledNotificationRecord>[
        result.record,
        ...snapshot.scheduledNotifications.where(
          (record) =>
              record.id != result.record.id && !_isTaskRecord(record, task.id),
        ),
      ],
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

  Future<void> _createTaskFromSelectedNote() async {
    final selected = _selectedNote(_snapshot);
    if (selected == null) {
      return;
    }

    final now = DateTime.now().toUtc();
    final task = TaskItem(
      id: _newId('task'),
      title: selected.title,
      description: noteTaskDescription(selected),
      status: TaskStatus.open,
      sourceNoteId: selected.id,
      createdAtUtc: now,
      updatedAtUtc: now,
    );

    await _upsertTask(task);
    setState(() => _selectedIndex = 0);
    _log('tarefa criada da nota');
  }

  Future<void> _openDayEditor(DateTime date) async {
    final selectedDate = dateOnly(date);
    setState(() => _agendaDate = selectedDate);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final snapshot = _snapshot;
        final dayTasks = snapshot == null
            ? const <TaskItem>[]
            : tasksDueOnDate(snapshot.tasks, selectedDate);

        return AlertDialog(
          title: Text(formatLocalDate(selectedDate)),
          content: SizedBox(
            width: 520,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: dayTasks.isEmpty
                  ? Text(
                      'Nenhum item neste dia.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: dayTasks.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final task = dayTasks[index];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            task.isDone
                                ? Icons.check_circle_outline
                                : Icons.radio_button_unchecked,
                          ),
                          title: Text(task.title),
                          subtitle: Text(taskMeta(task)),
                          trailing: const Icon(Icons.edit_outlined),
                          onTap: () {
                            Navigator.of(dialogContext).pop();
                            unawaited(_editTask(task));
                          },
                        );
                      },
                    ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Fechar'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                unawaited(_addTaskForDate(selectedDate));
              },
              icon: const Icon(Icons.add_task_outlined),
              label: const Text('Adicionar'),
            ),
          ],
        );
      },
    );
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
      case GlobalSearchResultKind.task:
        final task =
            _snapshot?.tasks
                .where((candidate) => candidate.id == result.id)
                .firstOrNull ??
            result.task;
        if (task == null) {
          return;
        }
        setState(() {
          _selectedIndex = 1;
          _taskFilter = TaskFilter.all;
          _taskQuery = '';
          _taskSearchController.clear();
          final dueAtUtc = task.dueAtUtc;
          if (dueAtUtc != null) {
            _agendaDate = dateOnly(dueAtUtc);
          }
        });
        await _editTask(task);
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
        });
    }
  }

  void _setUiZoom(double value) {
    setState(() => _uiZoom = _clampZoom(value));
  }

  void _selectNote(String noteId) {
    final snapshot = _snapshot;
    if (snapshot == null) {
      return;
    }

    final note = snapshot.notes.firstWhere(
      (candidate) => candidate.id == noteId,
    );
    setState(() {
      _selectedNoteId = note.id;
      _noteController.text = note.body;
    });
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

  Future<_TaskDraft?> _showTaskEditor({
    TaskItem? task,
    DateTime? initialDueLocal,
    String? dialogTitle,
  }) async {
    final titleController = TextEditingController(text: task?.title ?? '');
    final descriptionController = TextEditingController(
      text: task?.description ?? '',
    );
    var dueLocal = task?.dueAtUtc?.toLocal() ?? initialDueLocal;
    var reminderEnabled = task?.reminderEnabled ?? false;

    try {
      return showDialog<_TaskDraft>(
        context: context,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              Future<void> pickDate() async {
                final fallback = DateTime.now().add(const Duration(hours: 1));
                final current = dueLocal ?? fallback;
                final picked = await showDatePicker(
                  context: context,
                  initialDate: current,
                  firstDate: DateTime(2024),
                  lastDate: DateTime(2100),
                );
                if (picked == null) {
                  return;
                }
                setDialogState(() {
                  dueLocal = DateTime(
                    picked.year,
                    picked.month,
                    picked.day,
                    current.hour,
                    current.minute,
                  );
                });
              }

              Future<void> pickTime() async {
                final fallback = DateTime.now().add(const Duration(hours: 1));
                final current = dueLocal ?? fallback;
                final picked = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay.fromDateTime(current),
                );
                if (picked == null) {
                  return;
                }
                setDialogState(() {
                  dueLocal = DateTime(
                    current.year,
                    current.month,
                    current.day,
                    picked.hour,
                    picked.minute,
                  );
                });
              }

              return AlertDialog(
                title: Text(
                  dialogTitle ??
                      (task == null ? 'Nova tarefa' : 'Editar tarefa'),
                ),
                content: SizedBox(
                  width: 420,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      TextField(
                        controller: titleController,
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: 'Título',
                          hintText: 'Nome da tarefa',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: descriptionController,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Nota / descrição',
                          hintText: 'Texto livre opcional',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: pickDate,
                              icon: const Icon(Icons.event_outlined),
                              label: Text(
                                dueLocal == null
                                    ? 'Definir data'
                                    : formatLocalDate(dueLocal!),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: pickTime,
                              icon: const Icon(Icons.schedule_outlined),
                              label: Text(
                                dueLocal == null
                                    ? 'Definir hora'
                                    : formatLocalTime(dueLocal!),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: dueLocal == null
                                ? null
                                : () {
                                    setDialogState(() {
                                      dueLocal = null;
                                      reminderEnabled = false;
                                    });
                                  },
                            icon: const Icon(Icons.event_busy_outlined),
                            tooltip: 'Remover data',
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Notificar no horário'),
                        value: reminderEnabled,
                        onChanged: (value) {
                          setDialogState(() {
                            if (value && dueLocal == null) {
                              dueLocal = DateTime.now().add(
                                const Duration(minutes: 15),
                              );
                            }
                            reminderEnabled = value;
                          });
                        },
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
                        _TaskDraft(
                          title: titleController.text,
                          description: descriptionController.text,
                          dueAtUtc: dueLocal?.toUtc(),
                          reminderEnabled: reminderEnabled && dueLocal != null,
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
      descriptionController.dispose();
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
      return;
    }

    setState(() {
      _activity.insert(0, message);
      if (_activity.length > 8) {
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
      theme: _theme(),
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
                    tasks: _snapshot!.tasks,
                    busy: _busy,
                    permissionState: _permissionState,
                    lastSchedule: _lastSchedule,
                    lastNotificationLabel: _lastNotificationLabel,
                    pendingCount: _pendingCount,
                    activity: _activity,
                    onAddTask: _addTask,
                    onEditTask: _editTask,
                    onDeleteTask: _deleteTask,
                    onToggleTask: _toggleTask,
                    onRequestPermissions: _requestPermissions,
                    onScheduleOneShot: _scheduleOneShot,
                    onScheduleDaily: _scheduleDaily,
                    onScheduleWeekly: _scheduleWeekly,
                    onCancelLast: _cancelLast,
                  ),
                  _AgendaView(
                    tasks: _snapshot!.tasks,
                    searchController: _taskSearchController,
                    query: _taskQuery,
                    filter: _taskFilter,
                    mode: _agendaMode,
                    selectedDate: _agendaDate,
                    onAddTaskForDate: _addTaskForDate,
                    onEditTask: _editTask,
                    onToggleTask: _toggleTask,
                    onQueryChanged: (value) =>
                        setState(() => _taskQuery = value),
                    onFilterChanged: (value) =>
                        setState(() => _taskFilter = value),
                    onModeChanged: (value) =>
                        setState(() => _agendaMode = value),
                    onVisibleDateChanged: (value) =>
                        setState(() => _agendaDate = dateOnly(value)),
                    onDateSelected: (value) =>
                        setState(() => _agendaDate = dateOnly(value)),
                    onEditDate: _openDayEditor,
                  ),
                  _BoardView(
                    tasks: _snapshot!.tasks,
                    onAddTask: _addTask,
                    onEditTask: _editTask,
                    onToggleTask: _toggleTask,
                  ),
                  _NotesView(
                    notes: _snapshot!.notes,
                    selectedNoteId: _selectedNoteId,
                    controller: _noteController,
                    onSelectNote: _selectNote,
                    onAddNote: _addNote,
                    onRenameNote: _renameSelectedNote,
                    onDeleteNote: _deleteSelectedNote,
                    onCreateTaskFromNote: _createTaskFromSelectedNote,
                    onBodyChanged: _updateSelectedNoteBody,
                  ),
                  _SyncView(
                    busy: _busy,
                    deviceId: _deviceId,
                    controller: _syncServerController,
                    tokenController: _syncTokenController,
                    settings: _syncSettings,
                    sidecarSupported: _syncSidecarSupported,
                    sidecarState: _syncSidecarState,
                    lastResult: _lastSyncResult,
                    snapshot: _snapshot!,
                    onSave: _saveSyncSettings,
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

  ThemeData _theme() {
    const paper = Color(0xFFF6F3ED);
    const ink = Color(0xFF252525);
    const moss = Color(0xFF4D6B5F);

    final scheme =
        ColorScheme.fromSeed(
          seedColor: moss,
          brightness: Brightness.light,
        ).copyWith(
          surface: paper,
          onSurface: ink,
          primary: moss,
          secondary: const Color(0xFF9A5B4B),
          tertiary: const Color(0xFF396D86),
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: paper,
      textTheme: Typography.blackMountainView.apply(
        bodyColor: ink,
        displayColor: ink,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: paper,
        selectedIconTheme: IconThemeData(color: scheme.primary),
        selectedLabelTextStyle: TextStyle(color: scheme.primary),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE2DDD3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE2DDD3)),
        ),
      ),
    );
  }
}

String _newId(String prefix) {
  return '$prefix-${DateTime.now().toUtc().microsecondsSinceEpoch}';
}

DateTime _defaultDueLocalForDate(DateTime date) {
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

final class _TaskDraft {
  const _TaskDraft({
    required this.title,
    required this.description,
    required this.dueAtUtc,
    required this.reminderEnabled,
  });

  final String title;
  final String description;
  final DateTime? dueAtUtc;
  final bool reminderEnabled;
}

bool _isTaskRecord(ScheduledNotificationRecord record, String taskId) {
  return record.ownerType == ReminderOwnerType.task && record.ownerId == taskId;
}

double _clampZoom(double value) {
  return value.clamp(0.2, 2.0).toDouble();
}

String _zoomLabel(double value) {
  return '${(_clampZoom(value) * 100).round()}%';
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

final class _ZoomedPage extends StatelessWidget {
  const _ZoomedPage({required this.scale, required this.child});

  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final effectiveScale = _clampZoom(scale);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.maxWidth.isFinite || !constraints.maxHeight.isFinite) {
          return Transform.scale(
            scale: effectiveScale,
            alignment: Alignment.topLeft,
            child: child,
          );
        }

        return ClipRect(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              child: Transform.scale(
                scale: effectiveScale,
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: max(320, constraints.maxWidth / effectiveScale),
                  height: max(480, constraints.maxHeight / effectiveScale),
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

final class _ZoomRailControl extends StatelessWidget {
  const _ZoomRailControl({required this.zoom, required this.onZoomChanged});

  final double zoom;
  final ValueChanged<double> onZoomChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        IconButton(
          onPressed: zoom >= 2 ? null : () => onZoomChanged(zoom + 0.1),
          icon: const Icon(Icons.zoom_in_outlined),
          tooltip: 'Aumentar zoom',
        ),
        Text(
          _zoomLabel(zoom),
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        IconButton(
          onPressed: zoom <= 0.2 ? null : () => onZoomChanged(zoom - 0.1),
          icon: const Icon(Icons.zoom_out_outlined),
          tooltip: 'Diminuir zoom',
        ),
        IconButton(
          onPressed: zoom == 1 ? null : () => onZoomChanged(1),
          icon: const Icon(Icons.restart_alt_outlined),
          tooltip: 'Restaurar zoom',
        ),
      ],
    );
  }
}

final class _ZoomBottomBar extends StatelessWidget {
  const _ZoomBottomBar({required this.zoom, required this.onZoomChanged});

  final double zoom;
  final ValueChanged<double> onZoomChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
          child: Row(
            children: <Widget>[
              IconButton(
                onPressed: zoom <= 0.2 ? null : () => onZoomChanged(zoom - 0.1),
                icon: const Icon(Icons.zoom_out_outlined),
                tooltip: 'Diminuir zoom',
              ),
              Expanded(
                child: Slider(
                  value: _clampZoom(zoom),
                  min: 0.2,
                  max: 2,
                  divisions: 18,
                  label: _zoomLabel(zoom),
                  onChanged: onZoomChanged,
                ),
              ),
              SizedBox(
                width: 48,
                child: Text(
                  _zoomLabel(zoom),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                onPressed: zoom >= 2 ? null : () => onZoomChanged(zoom + 0.1),
                icon: const Icon(Icons.zoom_in_outlined),
                tooltip: 'Aumentar zoom',
              ),
            ],
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

        if (wide) {
          return Scaffold(
            body: Row(
              children: <Widget>[
                NavigationRail(
                  selectedIndex: selectedIndex,
                  onDestinationSelected: onSelect,
                  labelType: NavigationRailLabelType.all,
                  minWidth: 104,
                  leading: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 28),
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
                const VerticalDivider(width: 1, color: Color(0xFFE1DCD2)),
                Expanded(
                  child: _ZoomedPage(scale: zoom, child: pages[selectedIndex]),
                ),
              ],
            ),
          );
        }

        return Scaffold(
          body: _ZoomedPage(scale: zoom, child: pages[selectedIndex]),
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
                hintText: 'Tarefas, notas, descrições',
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                query.isEmpty
                    ? 'Tarefas e notas'
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
        final isTask = result.kind == GlobalSearchResultKind.task;
        final preview = result.preview;

        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            isTask ? Icons.task_alt_outlined : Icons.sticky_note_2_outlined,
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
    required this.tasks,
    required this.busy,
    required this.permissionState,
    required this.lastSchedule,
    required this.lastNotificationLabel,
    required this.pendingCount,
    required this.activity,
    required this.onAddTask,
    required this.onEditTask,
    required this.onDeleteTask,
    required this.onToggleTask,
    required this.onRequestPermissions,
    required this.onScheduleOneShot,
    required this.onScheduleDaily,
    required this.onScheduleWeekly,
    required this.onCancelLast,
  });

  final List<TaskItem> tasks;
  final bool busy;
  final NotificationPermissionState permissionState;
  final ScheduleResult? lastSchedule;
  final String? lastNotificationLabel;
  final int pendingCount;
  final List<String> activity;
  final VoidCallback onAddTask;
  final ValueChanged<TaskItem> onEditTask;
  final ValueChanged<TaskItem> onDeleteTask;
  final void Function(TaskItem task, bool done) onToggleTask;
  final VoidCallback onRequestPermissions;
  final VoidCallback onScheduleOneShot;
  final VoidCallback onScheduleDaily;
  final VoidCallback onScheduleWeekly;
  final VoidCallback onCancelLast;

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
              tasks: tasks,
              lastNotificationLabel: lastNotificationLabel,
              onAddTask: onAddTask,
              onEditTask: onEditTask,
              onDeleteTask: onDeleteTask,
              onToggleTask: onToggleTask,
            ),
            _NotificationPanel(
              busy: busy,
              permissionState: permissionState,
              lastSchedule: lastSchedule,
              onRequestPermissions: onRequestPermissions,
              onScheduleOneShot: onScheduleOneShot,
              onScheduleDaily: onScheduleDaily,
              onScheduleWeekly: onScheduleWeekly,
              onCancelLast: onCancelLast,
            ),
            _ActivityPanel(activity: activity),
          ];

          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(flex: 6, child: children[0]),
                const SizedBox(width: 18),
                Expanded(
                  flex: 5,
                  child: Column(
                    children: <Widget>[
                      children[1],
                      const SizedBox(height: 18),
                      children[2],
                    ],
                  ),
                ),
              ],
            );
          }

          return Column(
            children: <Widget>[
              children[0],
              const SizedBox(height: 16),
              children[1],
              const SizedBox(height: 16),
              children[2],
            ],
          );
        },
      ),
    );
  }
}

final class _FocusPanel extends StatelessWidget {
  const _FocusPanel({
    required this.tasks,
    required this.lastNotificationLabel,
    required this.onAddTask,
    required this.onEditTask,
    required this.onDeleteTask,
    required this.onToggleTask,
  });

  final List<TaskItem> tasks;
  final String? lastNotificationLabel;
  final VoidCallback onAddTask;
  final ValueChanged<TaskItem> onEditTask;
  final ValueChanged<TaskItem> onDeleteTask;
  final void Function(TaskItem task, bool done) onToggleTask;

  @override
  Widget build(BuildContext context) {
    final visibleTasks = tasks.take(5).toList();

    return _Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _SectionHeader(
            icon: Icons.bolt_outlined,
            title: 'Fila curta',
            action: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const _StatusPill(
                  icon: Icons.link_outlined,
                  label: 'local-first',
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: onAddTask,
                  icon: const Icon(Icons.add_task_outlined),
                  tooltip: 'Nova tarefa',
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (visibleTasks.isEmpty)
            Text(
              'Nenhuma tarefa ainda.',
              style: Theme.of(context).textTheme.bodySmall,
            )
          else
            for (var index = 0; index < visibleTasks.length; index++)
              _TaskRow(
                task: visibleTasks[index],
                color: taskTone(index),
                onChanged: (done) => onToggleTask(visibleTasks[index], done),
                onEdit: () => onEditTask(visibleTasks[index]),
                onDelete: () => onDeleteTask(visibleTasks[index]),
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
        ],
      ),
    );
  }
}

final class _NotificationPanel extends StatelessWidget {
  const _NotificationPanel({
    required this.busy,
    required this.permissionState,
    required this.lastSchedule,
    required this.onRequestPermissions,
    required this.onScheduleOneShot,
    required this.onScheduleDaily,
    required this.onScheduleWeekly,
    required this.onCancelLast,
  });

  final bool busy;
  final NotificationPermissionState permissionState;
  final ScheduleResult? lastSchedule;
  final VoidCallback onRequestPermissions;
  final VoidCallback onScheduleOneShot;
  final VoidCallback onScheduleDaily;
  final VoidCallback onScheduleWeekly;
  final VoidCallback onCancelLast;

  @override
  Widget build(BuildContext context) {
    final scheduled = lastSchedule;

    return _Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const _SectionHeader(
            icon: Icons.notifications_none,
            title: 'Notificações',
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
              FilledButton.tonalIcon(
                onPressed: busy ? null : onScheduleOneShot,
                icon: const Icon(Icons.timer_outlined),
                label: const Text('Teste 2 min'),
              ),
              OutlinedButton.icon(
                onPressed: busy ? null : onScheduleDaily,
                icon: const Icon(Icons.repeat_outlined),
                label: const Text('Diário'),
              ),
              OutlinedButton.icon(
                onPressed: busy ? null : onScheduleWeekly,
                icon: const Icon(Icons.event_repeat_outlined),
                label: const Text('Semanal'),
              ),
              IconButton.filledTonal(
                onPressed: busy ? null : onCancelLast,
                icon: const Icon(Icons.notifications_off_outlined),
                tooltip: 'Cancelar último',
              ),
            ],
          ),
          if (scheduled != null) ...<Widget>[
            const Divider(height: 28),
            _MetricLine('ID', scheduled.record.id.toString()),
            _MetricLine('Ocorrência', scheduled.plan.occurrenceKey),
            _MetricLine('Entrega', scheduled.deliveryLabel),
            _MetricLine('Local', formatLocal(scheduled.plan.scheduledLocal)),
          ],
        ],
      ),
    );
  }
}

final class _ActivityPanel extends StatelessWidget {
  const _ActivityPanel({required this.activity});

  final List<String> activity;

  @override
  Widget build(BuildContext context) {
    return _Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const _SectionHeader(icon: Icons.history_outlined, title: 'Log'),
          const SizedBox(height: 12),
          if (activity.isEmpty)
            Text(
              'Sem eventos nesta sessão.',
              style: Theme.of(context).textTheme.bodySmall,
            )
          else
            for (final item in activity)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(item, style: Theme.of(context).textTheme.bodySmall),
              ),
        ],
      ),
    );
  }
}

final class _AgendaView extends StatelessWidget {
  const _AgendaView({
    required this.tasks,
    required this.searchController,
    required this.query,
    required this.filter,
    required this.mode,
    required this.selectedDate,
    required this.onAddTaskForDate,
    required this.onEditTask,
    required this.onToggleTask,
    required this.onQueryChanged,
    required this.onFilterChanged,
    required this.onModeChanged,
    required this.onVisibleDateChanged,
    required this.onDateSelected,
    required this.onEditDate,
  });

  final List<TaskItem> tasks;
  final TextEditingController searchController;
  final String query;
  final TaskFilter filter;
  final AgendaMode mode;
  final DateTime selectedDate;
  final ValueChanged<DateTime> onAddTaskForDate;
  final ValueChanged<TaskItem> onEditTask;
  final void Function(TaskItem task, bool done) onToggleTask;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<TaskFilter> onFilterChanged;
  final ValueChanged<AgendaMode> onModeChanged;
  final ValueChanged<DateTime> onVisibleDateChanged;
  final ValueChanged<DateTime> onDateSelected;
  final ValueChanged<DateTime> onEditDate;

  @override
  Widget build(BuildContext context) {
    final visibleTasks = filterTasks(tasks, query, filter);
    final timelineTasks = visibleTasks.toList()..sort(compareTasksByAgenda);
    final selectedTasks = tasksDueOnDate(visibleTasks, selectedDate);
    final countsByDate = taskCountsByDate(visibleTasks);
    final open = visibleTasks.where((task) => !task.isDone).toList();
    final scheduled = open.where((task) => task.dueAtUtc != null).toList();
    final inbox = open.where((task) => task.dueAtUtc == null).toList();
    final done = visibleTasks.where((task) => task.isDone).toList();

    return _PageFrame(
      title: 'Agenda',
      subtitle: '${visibleTasks.length} tarefa(s)',
      trailing: FilledButton.icon(
        onPressed: () => onAddTaskForDate(selectedDate),
        icon: const Icon(Icons.add_task_outlined),
        label: const Text('Adicionar'),
      ),
      child: Column(
        children: <Widget>[
          _Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                TextField(
                  controller: searchController,
                  onChanged: onQueryChanged,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_outlined),
                    suffixIcon: query.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              searchController.clear();
                              onQueryChanged('');
                            },
                            icon: const Icon(Icons.close_outlined),
                            tooltip: 'Limpar busca',
                          ),
                    hintText: 'Buscar por título, descrição ou nota vinculada',
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final item in TaskFilter.values)
                      FilterChip(
                        label: Text(taskFilterLabel(item)),
                        selected: filter == item,
                        onSelected: (_) => onFilterChanged(item),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                SegmentedButton<AgendaMode>(
                  segments: const <ButtonSegment<AgendaMode>>[
                    ButtonSegment<AgendaMode>(
                      value: AgendaMode.timeline,
                      icon: Icon(Icons.view_agenda_outlined),
                      label: Text('Linha'),
                    ),
                    ButtonSegment<AgendaMode>(
                      value: AgendaMode.board,
                      icon: Icon(Icons.view_kanban_outlined),
                      label: Text('Quadro'),
                    ),
                  ],
                  selected: <AgendaMode>{mode},
                  onSelectionChanged: (value) => onModeChanged(value.single),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _Surface(
            child: AgendaCalendar(
              selectedDate: selectedDate,
              taskCounts: countsByDate,
              onVisibleDateChanged: onVisibleDateChanged,
              onDateSelected: onDateSelected,
              onAddTaskForDate: onAddTaskForDate,
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
                  action: OutlinedButton.icon(
                    onPressed: () => onAddTaskForDate(selectedDate),
                    icon: const Icon(Icons.add_outlined),
                    label: const Text('Item do dia'),
                  ),
                ),
                const SizedBox(height: 10),
                if (selectedTasks.isEmpty)
                  Text(
                    'Nenhuma tarefa neste dia.',
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                else
                  for (var index = 0; index < selectedTasks.length; index++)
                    _TimelineRow(
                      time: timelineLabel(selectedTasks[index]),
                      title: selectedTasks[index].title,
                      subtitle: taskMeta(selectedTasks[index]),
                      tone: taskTone(index),
                      onTap: () => onEditTask(selectedTasks[index]),
                    ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (mode == AgendaMode.timeline)
            _Surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (timelineTasks.isEmpty)
                    Text(
                      'Nada encontrado.',
                      style: Theme.of(context).textTheme.bodySmall,
                    )
                  else
                    for (var index = 0; index < timelineTasks.length; index++)
                      _TimelineRow(
                        time: timelineLabel(timelineTasks[index]),
                        title: timelineTasks[index].title,
                        subtitle: taskMeta(timelineTasks[index]),
                        tone: taskTone(index),
                        onTap: () => onEditTask(timelineTasks[index]),
                      ),
                ],
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 820 ? 3 : 1;
                return GridView.count(
                  crossAxisCount: columns,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: columns == 1 ? 3.2 : 1.08,
                  children: <Widget>[
                    _BoardColumn(
                      title: 'Entrada',
                      items: inbox,
                      onEditTask: onEditTask,
                      onToggleTask: onToggleTask,
                    ),
                    _BoardColumn(
                      title: 'Com horário',
                      items: scheduled,
                      onEditTask: onEditTask,
                      onToggleTask: onToggleTask,
                    ),
                    _BoardColumn(
                      title: 'Feito',
                      items: done,
                      onEditTask: onEditTask,
                      onToggleTask: onToggleTask,
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

final class _BoardView extends StatelessWidget {
  const _BoardView({
    required this.tasks,
    required this.onAddTask,
    required this.onEditTask,
    required this.onToggleTask,
  });

  final List<TaskItem> tasks;
  final VoidCallback onAddTask;
  final ValueChanged<TaskItem> onEditTask;
  final void Function(TaskItem task, bool done) onToggleTask;

  @override
  Widget build(BuildContext context) {
    final open = tasks.where((task) => !task.isDone).toList();
    final done = tasks.where((task) => task.isDone).toList();
    final timed = open.where((task) => task.dueAtUtc != null).toList();

    return _PageFrame(
      title: 'Quadro',
      subtitle: 'Kanban simples',
      trailing: FilledButton.icon(
        onPressed: onAddTask,
        icon: const Icon(Icons.add_task_outlined),
        label: const Text('Adicionar'),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 820 ? 3 : 1;
          return GridView.count(
            crossAxisCount: columns,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: columns == 1 ? 3.3 : 1.12,
            children: <Widget>[
              _BoardColumn(
                title: 'Entrada',
                items: open.where((task) => task.dueAtUtc == null).toList(),
                onEditTask: onEditTask,
                onToggleTask: onToggleTask,
              ),
              _BoardColumn(
                title: 'Hoje',
                items: timed,
                onEditTask: onEditTask,
                onToggleTask: onToggleTask,
              ),
              _BoardColumn(
                title: 'Feito',
                items: done,
                onEditTask: onEditTask,
                onToggleTask: onToggleTask,
              ),
            ],
          );
        },
      ),
    );
  }
}

final class _NotesView extends StatelessWidget {
  const _NotesView({
    required this.notes,
    required this.selectedNoteId,
    required this.controller,
    required this.onSelectNote,
    required this.onAddNote,
    required this.onRenameNote,
    required this.onDeleteNote,
    required this.onCreateTaskFromNote,
    required this.onBodyChanged,
  });

  final List<NoteItem> notes;
  final String? selectedNoteId;
  final TextEditingController controller;
  final ValueChanged<String> onSelectNote;
  final VoidCallback onAddNote;
  final VoidCallback onRenameNote;
  final VoidCallback onDeleteNote;
  final VoidCallback onCreateTaskFromNote;
  final ValueChanged<String> onBodyChanged;

  @override
  Widget build(BuildContext context) {
    final selected = notes
        .where((note) => note.id == selectedNoteId)
        .firstOrNull;

    return _PageFrame(
      title: 'Notas',
      subtitle: 'Editor livre',
      trailing: const _StatusPill(
        icon: Icons.article_outlined,
        label: 'Markdown',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _Surface(
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      for (final note in notes)
                        ChoiceChip(
                          label: Text(note.title),
                          selected: note.id == selectedNoteId,
                          onSelected: (_) => onSelectNote(note.id),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                IconButton.filledTonal(
                  onPressed: onAddNote,
                  icon: const Icon(Icons.note_add_outlined),
                  tooltip: 'Nova nota',
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (selected != null) ...<Widget>[
            _Surface(
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      selected.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: onRenameNote,
                    icon: const Icon(Icons.drive_file_rename_outline),
                    tooltip: 'Renomear nota',
                  ),
                  IconButton(
                    onPressed: onCreateTaskFromNote,
                    icon: const Icon(Icons.add_task_outlined),
                    tooltip: 'Criar tarefa desta nota',
                  ),
                  IconButton(
                    onPressed: onDeleteNote,
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Excluir nota',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],
          TextField(
            controller: controller,
            enabled: selected != null,
            onChanged: onBodyChanged,
            minLines: 18,
            maxLines: 32,
            keyboardType: TextInputType.multiline,
            style: const TextStyle(fontSize: 15, height: 1.45),
            decoration: InputDecoration(
              hintText: selected == null
                  ? 'Crie uma nota para começar.'
                  : 'Escreva, cole, risque, reorganize.',
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
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
    required this.sidecarSupported,
    required this.sidecarState,
    required this.lastResult,
    required this.snapshot,
    required this.onSave,
    required this.onSync,
    required this.onStartSidecar,
    required this.onStopSidecar,
  });

  final bool busy;
  final String deviceId;
  final TextEditingController controller;
  final TextEditingController tokenController;
  final SyncSettings settings;
  final bool sidecarSupported;
  final LocalSyncSidecarState? sidecarState;
  final SyncResult? lastResult;
  final AppSnapshot snapshot;
  final VoidCallback onSave;
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
                _MetricLine('Tarefas', snapshot.tasks.length.toString()),
                _MetricLine('Notas', snapshot.notes.length.toString()),
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
                              ?.copyWith(color: const Color(0xFF666057)),
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE1DCD2)),
        boxShadow: const <BoxShadow>[
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

final class _TaskRow extends StatelessWidget {
  const _TaskRow({
    required this.task,
    required this.color,
    required this.onChanged,
    required this.onEdit,
    required this.onDelete,
  });

  final TaskItem task;
  final Color color;
  final ValueChanged<bool> onChanged;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final done = task.isDone;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: <Widget>[
          Container(
            width: 12,
            height: 42,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  task.title,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    decoration: done ? TextDecoration.lineThrough : null,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  taskMeta(task),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Checkbox(
            value: done,
            onChanged: (value) => onChanged(value ?? false),
            activeColor: color,
          ),
          IconButton(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Editar tarefa',
          ),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Excluir tarefa',
          ),
        ],
      ),
    );
  }
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
  });

  final String time;
  final String title;
  final String? subtitle;
  final Color tone;
  final VoidCallback? onTap;

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

final class _BoardTaskTile extends StatelessWidget {
  const _BoardTaskTile({
    required this.task,
    required this.onEditTask,
    required this.onToggleTask,
  });

  final TaskItem task;
  final ValueChanged<TaskItem> onEditTask;
  final void Function(TaskItem task, bool done) onToggleTask;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => onEditTask(task),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: <Widget>[
              Checkbox(
                value: task.isDone,
                onChanged: (value) => onToggleTask(task, value ?? false),
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      task.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      taskMeta(task),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => onEditTask(task),
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Editar',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _BoardColumn extends StatelessWidget {
  const _BoardColumn({
    required this.title,
    required this.items,
    required this.onEditTask,
    required this.onToggleTask,
  });

  final String title;
  final List<TaskItem> items;
  final ValueChanged<TaskItem> onEditTask;
  final void Function(TaskItem task, bool done) onToggleTask;

  @override
  Widget build(BuildContext context) {
    return _Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            Text('Vazio', style: Theme.of(context).textTheme.bodySmall)
          else
            for (final item in items)
              _BoardTaskTile(
                task: item,
                onEditTask: onEditTask,
                onToggleTask: onToggleTask,
              ),
        ],
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFEDE7DC),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}
