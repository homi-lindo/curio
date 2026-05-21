import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lume/services/secure_secret_store.dart';
import 'package:lume/services/sync_settings_store.dart';

void main() {
  test('sync settings store keeps auth token outside settings file', () async {
    final temp = await Directory.systemTemp.createTemp('lume_sync_settings_');
    addTearDown(() => temp.delete(recursive: true));

    final secrets = _MemorySecretBackend();
    final store = SyncSettingsStore(
      directoryProvider: () async => temp,
      secureSecrets: SecureSecretStore(backend: secrets),
    );
    final settings = SyncSettings(
      serverUrl: 'http://127.0.0.1:8787',
      authToken: 'shared-secret',
      lastMessage: 'sync ok',
      lastSyncedAtUtc: DateTime.utc(2026, 5, 20, 15),
    );

    await store.save(settings);
    final raw = await store.file.then((file) => file.readAsString());
    final loaded = await store.load();

    expect(raw, isNot(contains('shared-secret')));
    expect(raw, isNot(contains('authToken')));
    expect(await secrets.read('syncToken'), 'shared-secret');
    expect(loaded.serverUrl, settings.serverUrl);
    expect(loaded.authToken, settings.authToken);
    expect(loaded.lastMessage, 'sync ok');
    expect(loaded.lastSyncedAtUtc, settings.lastSyncedAtUtc);
  });

  test('sync settings store migrates legacy plaintext auth token', () async {
    final temp = await Directory.systemTemp.createTemp(
      'lume_sync_settings_legacy_',
    );
    addTearDown(() => temp.delete(recursive: true));

    final secrets = _MemorySecretBackend();
    final store = SyncSettingsStore(
      directoryProvider: () async => temp,
      secureSecrets: SecureSecretStore(backend: secrets),
    );
    final settingsFile = await store.file;
    await settingsFile.writeAsString(
      '{"serverUrl":"https://sync.example","authToken":"legacy-secret"}',
    );

    final loaded = await store.load();
    final rewritten = await settingsFile.readAsString();

    expect(loaded.authToken, 'legacy-secret');
    expect(await secrets.read('syncToken'), 'legacy-secret');
    expect(rewritten, isNot(contains('legacy-secret')));
    expect(rewritten, isNot(contains('authToken')));
  });
}

final class _MemorySecretBackend implements SecretBackend {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}
