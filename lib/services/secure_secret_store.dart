import 'package:flutter/services.dart';

abstract interface class SecretBackend {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

final class SecureSecretStore {
  const SecureSecretStore({this.backend = const MethodChannelSecretBackend()});

  final SecretBackend backend;

  Future<String> readSyncToken() async {
    return await backend.read(_syncTokenKey) ?? '';
  }

  Future<void> writeSyncToken(String token) async {
    final trimmed = token.trim();
    if (trimmed.isEmpty) {
      await backend.delete(_syncTokenKey);
      return;
    }

    await backend.write(_syncTokenKey, trimmed);
  }
}

final class MethodChannelSecretBackend implements SecretBackend {
  const MethodChannelSecretBackend();

  static const MethodChannel _channel = MethodChannel(
    'app.lume.personal/secure_secrets',
  );

  @override
  Future<String?> read(String key) async {
    return _channel.invokeMethod<String>('read', <String, Object?>{'key': key});
  }

  @override
  Future<void> write(String key, String value) async {
    await _channel.invokeMethod<void>('write', <String, Object?>{
      'key': key,
      'value': value,
    });
  }

  @override
  Future<void> delete(String key) async {
    await _channel.invokeMethod<void>('delete', <String, Object?>{'key': key});
  }
}

const _syncTokenKey = 'syncToken';
