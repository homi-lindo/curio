import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:lume_core/domain/app_snapshot.dart';
import 'package:lume_core/sync/serial_task_queue.dart';
import 'package:lume_core/sync/sync_adapter.dart';

typedef SnapshotLoader = Future<AppSnapshot> Function();
typedef SnapshotSaver = Future<void> Function(AppSnapshot snapshot);

final class LocalSyncSidecar {
  LocalSyncSidecar({
    required this.loadSnapshot,
    required this.saveSnapshot,
    this.maxBodyBytes = _defaultMaxBodyBytes,
  });

  final SnapshotLoader loadSnapshot;
  final SnapshotSaver saveSnapshot;
  final int maxBodyBytes;

  HttpServer? _server;
  LocalSyncSidecarState? _state;

  /// Serializa a seção read→merge→save de `/sync`: dois clientes simultâneos
  /// nunca podem intercalar a mutação do estado, ou o save de um engole o
  /// merge do outro.
  final SerialTaskQueue _stateLock = SerialTaskQueue();

  LocalSyncSidecarState? get state => _state;
  bool get isRunning => _server != null;

  Future<LocalSyncSidecarState> start({
    required String token,
    String host = '0.0.0.0',
    int port = 8787,
  }) async {
    if (_server != null) {
      return _state!;
    }
    final trimmedToken = token.trim();
    if (trimmedToken.length < 16) {
      throw const LocalSyncSidecarException(
        'Use um token de sync com pelo menos 16 caracteres.',
      );
    }
    if (maxBodyBytes <= 0) {
      throw const LocalSyncSidecarException(
        'Use um limite positivo para o servidor local.',
      );
    }

    final server = await HttpServer.bind(host, port);
    _server = server;
    _state = LocalSyncSidecarState(
      host: host,
      port: server.port,
      startedAtUtc: DateTime.now().toUtc(),
    );
    unawaited(_serve(server, trimmedToken));
    return _state!;
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _state = null;
    await server?.close(force: true);
  }

  Future<void> _serve(HttpServer server, String token) async {
    try {
      // Despacho concorrente: um upload lento não bloqueia /health. A mutação
      // de estado continua serializada pelo [_stateLock] dentro do handler.
      await for (final request in server) {
        unawaited(
          _handleRequest(request, token).catchError((Object _) {
            // Falha ao responder (ex.: cliente desconectou). Nada a fazer.
          }),
        );
      }
    } on Object {
      _server = null;
      _state = null;
    }
  }

  Future<void> _handleRequest(HttpRequest request, String token) async {
    try {
      if (request.method == 'GET' && request.uri.path == '/health') {
        await _writeJson(request.response, <String, Object?>{
          'ok': true,
          'serverTimeUtc': DateTime.now().toUtc().toIso8601String(),
        });
        return;
      }

      if (!await _authorize(request, token)) {
        return;
      }

      if (request.method == 'GET' && request.uri.path == '/snapshot') {
        await _writeJson(request.response, <String, Object?>{
          'snapshot': _syncable(await loadSnapshot()).toJson(),
        });
        return;
      }

      if (request.method == 'POST' && request.uri.path == '/sync') {
        final payload = await _readJson(request, maxBodyBytes: maxBodyBytes);
        final incoming = AppSnapshot.fromJson(
          Map<String, Object?>.from(
            payload['snapshot']! as Map<dynamic, dynamic>,
          ),
        );
        final next = await _stateLock.run(() async {
          final current = await loadSnapshot();
          final merged = const SnapshotSyncMerger().merge(
            local: current,
            remote: _syncable(incoming),
          );
          await saveSnapshot(merged);
          return merged;
        });
        await _writeJson(request.response, <String, Object?>{
          'snapshot': _syncable(next).toJson(),
          'serverTimeUtc': DateTime.now().toUtc().toIso8601String(),
        });
        return;
      }

      request.response.statusCode = HttpStatus.notFound;
      await _writeJson(request.response, <String, Object?>{
        'error': 'not found',
      });
    } on _RequestTooLargeException {
      request.response.statusCode = HttpStatus.requestEntityTooLarge;
      await _writeJson(request.response, <String, Object?>{
        'error': 'request too large',
      });
    } on Object {
      request.response.statusCode = HttpStatus.badRequest;
      await _writeJson(request.response, <String, Object?>{
        'error': 'invalid request',
      });
    }
  }

  Future<bool> _authorize(HttpRequest request, String token) async {
    if (_constantTimeEquals(
      request.headers.value(_syncTokenHeader) ?? '',
      token,
    )) {
      return true;
    }

    request.response.statusCode = HttpStatus.unauthorized;
    await _writeJson(request.response, <String, Object?>{
      'error': 'invalid sync token',
    });
    return false;
  }
}

final class LocalSyncSidecarState {
  const LocalSyncSidecarState({
    required this.host,
    required this.port,
    required this.startedAtUtc,
  });

  final String host;
  final int port;
  final DateTime startedAtUtc;

  String get localUrl => 'http://127.0.0.1:$port';
}

final class LocalSyncSidecarException implements Exception {
  const LocalSyncSidecarException(this.message);

  final String message;

  @override
  String toString() => message;
}

Future<Map<String, Object?>> _readJson(
  HttpRequest request, {
  required int maxBodyBytes,
}) async {
  final declaredLength = request.headers.contentLength;
  if (declaredLength > maxBodyBytes) {
    throw const _RequestTooLargeException();
  }

  final bytes = BytesBuilder(copy: false);
  var byteCount = 0;
  await for (final chunk in request) {
    byteCount += chunk.length;
    if (byteCount > maxBodyBytes) {
      throw const _RequestTooLargeException();
    }
    bytes.add(chunk);
  }

  final raw = utf8.decode(bytes.takeBytes());
  return Map<String, Object?>.from(jsonDecode(raw) as Map<dynamic, dynamic>);
}

Future<void> _writeJson(
  HttpResponse response,
  Map<String, Object?> payload,
) async {
  response.headers.contentType = ContentType.json;
  response.write(jsonEncode(payload));
  await response.close();
}

AppSnapshot _syncable(AppSnapshot snapshot) {
  return snapshot.copyWith(scheduledNotifications: const []);
}

bool _constantTimeEquals(String received, String expected) {
  final receivedBytes = utf8.encode(received);
  final expectedBytes = utf8.encode(expected);
  var diff = receivedBytes.length ^ expectedBytes.length;
  final length = receivedBytes.length > expectedBytes.length
      ? receivedBytes.length
      : expectedBytes.length;

  for (var index = 0; index < length; index++) {
    final receivedByte = index < receivedBytes.length
        ? receivedBytes[index]
        : 0;
    final expectedByte = index < expectedBytes.length
        ? expectedBytes[index]
        : 0;
    diff |= receivedByte ^ expectedByte;
  }

  return diff == 0;
}

const _syncTokenHeader = 'x-lume-sync-token';
const _defaultMaxBodyBytes = 10 * 1024 * 1024;

final class _RequestTooLargeException implements Exception {
  const _RequestTooLargeException();
}
