part of 'main.dart';

/// Sync-tab actions: sync settings, appearance/alarm settings, alarm audio,
/// remote sync and the local sidecar server.
///
/// Owns its settings validator; other dependencies come from the host state
/// surface declared below. Methods are moved verbatim and behave identically.
mixin _SyncActions on State<CurioApp> {
  final SyncSettingsValidator _syncSettingsValidator =
      const SyncSettingsValidator();

  AppSnapshot? get _snapshot;
  String get _deviceId;
  TextEditingController get _syncServerController;
  TextEditingController get _syncTokenController;
  LocalSyncSidecar get _syncSidecar;
  WindowsAttentionService get _windowsAttention;
  ActionErrorDescriber get _errorDescriber;
  SyncSettings get _syncSettings;
  set _syncSettings(SyncSettings value);
  AlarmSettings get _alarmSettings;
  set _alarmSettings(AlarmSettings value);
  set _appearance(AppearanceSettings value);
  set _activeAlarmRecord(ScheduledNotificationRecord? value);
  set _syncSidecarState(LocalSyncSidecarState? value);
  set _lastSyncResult(SyncResult? value);
  void _log(String message);
  void _applyState(VoidCallback mutate);
  Future<void> _saveSnapshot(AppSnapshot snapshot);
  Future<void> _runAction(Future<void> Function() action);
  void _syncSelectionAfterSnapshot(AppSnapshot snapshot);
  Future<AppSnapshot> _reconcileReminders(AppSnapshot snapshot);

  bool get _syncSidecarSupported =>
      defaultTargetPlatform == TargetPlatform.windows;

  Future<void> _applyPairingCode(String code) async {
    final pairing = SyncPairing.tryParse(code);
    if (pairing != null) {
      await _runAction(() async {
        final serverUrl = _syncSettingsValidator.normalizeServerUrl(
          pairing.serverUrl,
        );
        final authToken = pairing.authToken.trim();
        _syncSettingsValidator.validate(
          serverUrl: serverUrl,
          authToken: authToken,
        );
        final settings = _syncSettings.copyWith(
          serverUrl: serverUrl,
          authToken: authToken,
          pinnedCertSha256: pairing.certSha256,
        );
        await widget.syncSettings.save(settings);
        setState(() {
          _syncSettings = settings;
          _syncServerController.text = serverUrl;
          _syncTokenController.text = authToken;
        });
        _log(
          pairing.certSha256.isEmpty
              ? 'pareamento aplicado'
              : 'pareamento aplicado com certificado fixado',
        );
      });
      return;
    }

    // Fall back to a bare SHA-256 fingerprint, so the user can fill the server
    // and token manually (e.g. a server bound to 0.0.0.0) and just paste the
    // certificate fingerprint the server printed.
    final fingerprint = SyncPairing.normalizeFingerprint(code);
    if (fingerprint.length == 64) {
      await _runAction(() async {
        final settings = _syncSettings.copyWith(pinnedCertSha256: fingerprint);
        await widget.syncSettings.save(settings);
        setState(() => _syncSettings = settings);
        _log('certificado fixado');
      });
      return;
    }

    _log('código de pareamento inválido');
  }

  Future<void> _clearPinnedCert() async {
    if (_syncSettings.pinnedCertSha256.isEmpty) {
      return;
    }
    await _runAction(() async {
      final settings = _syncSettings.copyWith(pinnedCertSha256: '');
      await widget.syncSettings.save(settings);
      setState(() => _syncSettings = settings);
      _log('certificado fixado removido');
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
      _applyState(() => _appearance = settings);
      _log(
        'aparência: ${settings.themeProfile.label} · ${settings.themeMode.label}',
      );
    } on Object catch (error) {
      _log('aparência não salva: ${_errorDescriber.describe(error)}');
    }
  }

  Future<void> _saveAlarmSettings(AlarmSettings settings) async {
    try {
      await widget.alarmSettings.save(settings);
      _applyState(() => _alarmSettings = settings);
      _log('alarme: ${settings.label}');
    } on Object catch (error) {
      _log('alarme não salvo: ${_errorDescriber.describe(error)}');
    }
  }

  Future<void> _pickAlarmAudio() async {
    await _runAction(() async {
      final result = await FilePicker.pickFiles(
        dialogTitle: 'Escolher áudio do alarme',
        type: FileType.custom,
        allowedExtensions: alarmAudioExtensions,
        allowMultiple: false,
        withData: false,
      );
      final path = result?.files.single.path;
      if (path == null || path.trim().isEmpty) {
        return;
      }

      final settings = await widget.alarmSettings.installCustomAudio(
        path,
        current: _alarmSettings,
      );
      setState(() => _alarmSettings = settings);
      _log('áudio de alarme salvo: ${settings.customAudioName}');
    });
  }

  Future<void> _clearAlarmAudio() async {
    await _runAction(() async {
      final settings = await widget.alarmSettings.clearCustomAudio(
        _alarmSettings,
      );
      await widget.alarmPlayback.stop();
      setState(() {
        _alarmSettings = settings;
        _activeAlarmRecord = null;
      });
      _log('áudio personalizado removido');
    });
  }

  Future<void> _testAlarmAudio() async {
    await _runAction(() async {
      final result = await widget.alarmPlayback.start(
        _alarmSettings,
        windowsAttention: _windowsAttention,
      );
      final didFlash = defaultTargetPlatform == TargetPlatform.windows
          ? _windowsAttention.flashTaskbar(count: 16)
          : false;
      setState(() => _activeAlarmRecord = null);
      _log(didFlash ? '${result.message}; ícone piscando' : result.message);
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
              pinnedCertSha256: _syncSettings.pinnedCertSha256,
              allowInsecureHttp: kDebugMode,
            );
      try {
        final result = await adapter.synchronize(
          snapshot: snapshot,
          deviceId: _deviceId,
        );
        final latestSnapshot = _snapshot ?? snapshot;
        final mergedSnapshot = const SnapshotSyncMerger().merge(
          local: latestSnapshot,
          remote: result.snapshot,
        );
        // Arm/cancel this device's local notifications for reminders that
        // arrived or disappeared in the merge.
        final syncedSnapshot = await _reconcileReminders(mergedSnapshot);
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

  String _generateSyncToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}
