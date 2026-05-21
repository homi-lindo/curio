import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'secure_secret_store.dart';

final class SyncSettings {
  const SyncSettings({
    this.serverUrl = '',
    this.authToken = '',
    this.lastMessage,
    this.lastSyncedAtUtc,
  });

  factory SyncSettings.fromJson(Map<String, Object?> json) {
    return SyncSettings(
      serverUrl: json['serverUrl'] as String? ?? '',
      authToken: json['authToken'] as String? ?? '',
      lastMessage: json['lastMessage'] as String?,
      lastSyncedAtUtc: _optionalDate(json['lastSyncedAtUtc']),
    );
  }

  final String serverUrl;
  final String authToken;
  final String? lastMessage;
  final DateTime? lastSyncedAtUtc;

  SyncSettings copyWith({
    String? serverUrl,
    String? authToken,
    String? lastMessage,
    DateTime? lastSyncedAtUtc,
  }) {
    return SyncSettings(
      serverUrl: serverUrl ?? this.serverUrl,
      authToken: authToken ?? this.authToken,
      lastMessage: lastMessage ?? this.lastMessage,
      lastSyncedAtUtc: lastSyncedAtUtc ?? this.lastSyncedAtUtc,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'serverUrl': serverUrl,
      'lastMessage': lastMessage,
      'lastSyncedAtUtc': lastSyncedAtUtc?.toUtc().toIso8601String(),
    };
  }
}

final class SyncSettingsStore {
  SyncSettingsStore({
    Future<Directory> Function()? directoryProvider,
    this.secureSecrets = const SecureSecretStore(),
  }) : _directoryProvider =
           directoryProvider ?? (() => getApplicationSupportDirectory());

  final SecureSecretStore secureSecrets;
  final Future<Directory> Function() _directoryProvider;

  Future<File> get file async {
    final directory = await _directoryProvider();
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return File(p.join(directory.path, 'lume-sync.json'));
  }

  Future<SyncSettings> load() async {
    final settingsFile = await file;
    if (!await settingsFile.exists()) {
      final authToken = await secureSecrets.readSyncToken();
      return SyncSettings(authToken: authToken);
    }

    final raw = await settingsFile.readAsString();
    final json = Map<String, Object?>.from(
      jsonDecode(raw) as Map<dynamic, dynamic>,
    );
    final settings = SyncSettings.fromJson(json);
    final secureToken = await secureSecrets.readSyncToken();
    final legacyToken = settings.authToken.trim();
    final authToken = secureToken.isNotEmpty ? secureToken : legacyToken;

    if (secureToken.isEmpty && legacyToken.isNotEmpty) {
      await secureSecrets.writeSyncToken(legacyToken);
    }

    final hydrated = settings.copyWith(authToken: authToken);
    if (json.containsKey('authToken')) {
      await _writeSettingsFile(settingsFile, hydrated);
    }
    return hydrated;
  }

  Future<void> save(SyncSettings settings) async {
    final settingsFile = await file;
    await secureSecrets.writeSyncToken(settings.authToken);
    await _writeSettingsFile(settingsFile, settings);
  }

  Future<void> _writeSettingsFile(File settingsFile, SyncSettings settings) {
    return settingsFile.writeAsString(jsonEncode(settings.toJson()));
  }
}

DateTime? _optionalDate(Object? value) {
  if (value == null) {
    return null;
  }
  return DateTime.parse(value as String).toUtc();
}
