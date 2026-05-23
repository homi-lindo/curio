import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:lume_core/domain/app_snapshot.dart';
import 'package:lume_core/sync/sync_adapter.dart';

final class HttpSyncAdapter implements SyncAdapter {
  HttpSyncAdapter({
    required this.serverUrl,
    String authToken = '',
    this.allowInsecureHttp = false,
    this.networkTimeout = _defaultSyncNetworkTimeout,
    this.maxResponseBytes = _defaultMaxSyncResponseBytes,
    HttpClient? client,
  }) : authToken = authToken.trim(),
       _client = client ?? (HttpClient()..connectionTimeout = networkTimeout) {
    if (maxResponseBytes <= 0) {
      throw ArgumentError.value(
        maxResponseBytes,
        'maxResponseBytes',
        'Use um limite positivo para respostas de sync.',
      );
    }
    if (authToken.length < _minSyncTokenLength) {
      throw ArgumentError.value(
        '<redacted>',
        'authToken',
        'Use um token de sync com pelo menos $_minSyncTokenLength caracteres.',
      );
    }
    _validateServerUrl(serverUrl, allowInsecureHttp: allowInsecureHttp);
  }

  final Uri serverUrl;
  final String authToken;
  final bool allowInsecureHttp;
  final Duration networkTimeout;
  final int maxResponseBytes;
  final HttpClient _client;
  final SnapshotSyncMerger _merger = const SnapshotSyncMerger();
  bool _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _client.close(force: false);
  }

  @override
  Future<SyncResult> synchronize({
    required AppSnapshot snapshot,
    required String deviceId,
  }) async {
    if (_disposed) {
      throw StateError('HttpSyncAdapter has been disposed.');
    }
    final started = DateTime.now().toUtc();
    final response = await _postJson(
      serverUrl.resolve('/sync'),
      <String, Object?>{
        'deviceId': deviceId,
        'snapshot': _syncable(snapshot).toJson(),
      },
    );
    final remote = AppSnapshot.fromJson(
      Map<String, Object?>.from(response['snapshot']! as Map<dynamic, dynamic>),
    );
    final merged = _merger.merge(local: snapshot, remote: remote);
    final finished = DateTime.now().toUtc();

    return SyncResult(
      startedAtUtc: started,
      finishedAtUtc: finished,
      snapshot: merged,
      pushedRecords: snapshot.notes.length,
      pulledRecords: remote.notes.length,
      tombstones: merged.deletedRecords.length,
      message:
          'sync ok: ${remote.notes.length} nota(s), '
          '${remote.scheduledNotifications.length} notificação(ões)',
    );
  }

  Future<Map<String, Object?>> _postJson(
    Uri uri,
    Map<String, Object?> payload,
  ) async {
    final request = await _client.postUrl(uri);
    request.headers.contentType = ContentType.json;
    request.headers.set(_syncTokenHeader, authToken);
    request.write(jsonEncode(payload));

    final response = await request.close().timeout(networkTimeout);
    final body = await _readUtf8Body(
      response,
      maxBytes: maxResponseBytes,
    ).timeout(networkTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'sync server ${response.statusCode}: ${_shortErrorBody(body)}',
        uri: uri,
      );
    }

    return Map<String, Object?>.from(jsonDecode(body) as Map<dynamic, dynamic>);
  }

  AppSnapshot _syncable(AppSnapshot snapshot) {
    return snapshot.copyWith(scheduledNotifications: const []);
  }
}

Future<String> _readUtf8Body(
  Stream<List<int>> stream, {
  required int maxBytes,
}) async {
  final bytes = BytesBuilder(copy: false);
  var byteCount = 0;
  await for (final chunk in stream) {
    byteCount += chunk.length;
    if (byteCount > maxBytes) {
      throw const HttpException('sync server response too large');
    }
    bytes.add(chunk);
  }
  return utf8.decode(bytes.takeBytes());
}

String _shortErrorBody(String body) {
  final trimmed = body.trim();
  if (trimmed.length <= _maxSyncErrorBodyChars) {
    return trimmed;
  }
  return '${trimmed.substring(0, _maxSyncErrorBodyChars)}...';
}

void _validateServerUrl(Uri serverUrl, {required bool allowInsecureHttp}) {
  if (serverUrl.scheme != 'https' && serverUrl.scheme != 'http') {
    throw ArgumentError.value(
      serverUrl.toString(),
      'serverUrl',
      'Use uma URL http:// ou https://.',
    );
  }

  if (serverUrl.scheme == 'http' && !allowInsecureHttp) {
    throw ArgumentError.value(
      serverUrl.toString(),
      'serverUrl',
      'HTTP só é permitido em builds de debug. Use HTTPS no app empacotado.',
    );
  }
  if (!serverUrl.hasAuthority || serverUrl.host.trim().isEmpty) {
    throw ArgumentError.value(
      serverUrl.toString(),
      'serverUrl',
      'Informe o host do servidor de sync.',
    );
  }
  if (serverUrl.userInfo.isNotEmpty) {
    throw ArgumentError.value(
      '<redacted>',
      'serverUrl',
      'Não inclua usuário ou senha na URL de sync.',
    );
  }
  if ((serverUrl.path.isNotEmpty && serverUrl.path != '/') ||
      serverUrl.hasQuery ||
      serverUrl.hasFragment) {
    throw ArgumentError.value(
      serverUrl.toString(),
      'serverUrl',
      'Informe apenas a origem do servidor, sem caminho, query ou fragmento.',
    );
  }
}

const _syncTokenHeader = 'x-lume-sync-token';
const _minSyncTokenLength = 16;
const _defaultSyncNetworkTimeout = Duration(seconds: 30);
const _defaultMaxSyncResponseBytes = 10 * 1024 * 1024;
const _maxSyncErrorBodyChars = 500;
