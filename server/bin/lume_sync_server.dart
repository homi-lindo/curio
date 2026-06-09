import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:lume_core/domain/app_snapshot.dart';
import 'package:lume_core/sync/serial_task_queue.dart';
import 'package:lume_core/sync/sync_adapter.dart';
import 'package:lume_core/sync/sync_pairing.dart';
import 'package:lume_sync_server/cert_fingerprint.dart';
import 'package:lume_sync_server/snapshot_store.dart';

Future<void> main(List<String> args) async {
  final _ServerConfig config;
  try {
    config = _ServerConfig.parse(args);
  } on ArgumentError catch (error) {
    stderr.writeln('Curió sync configuration error: ${error.message}');
    exitCode = 64;
    return;
  }

  final store = ServerSnapshotStore(config.file);
  final server = config.tlsEnabled
      ? await HttpServer.bindSecure(
          config.host,
          config.port,
          config.createSecurityContext(),
        )
      : await HttpServer.bind(config.host, config.port);
  final scheme = config.tlsEnabled ? 'https' : 'http';

  stdout.writeln('Curió sync server: $scheme://${config.host}:${server.port}');
  stdout.writeln('Transport: ${config.tlsEnabled ? 'https' : 'http'}');
  stdout.writeln('State file: configured');
  stdout.writeln('Max body: ${config.maxBodyBytes} byte(s)');
  stdout.writeln('CORS: ${config.corsOrigin ?? 'disabled'}');
  stdout.writeln(
    'Auth: ${config.token == null ? 'disabled for explicit loopback dev' : 'enabled with x-lume-sync-token'}',
  );
  if (!config.tlsEnabled && config.token != null) {
    stdout.writeln(
      'Warning: token auth over plain HTTP is only suitable for trusted LANs.',
    );
  }
  _printPairing(config, scheme, server.port);

  // As requisições são atendidas concorrentemente (um upload lento não
  // bloqueia /health), mas a seção read→merge→save do estado é serializada
  // pelo [stateLock] — sem ele, dois POST /sync simultâneos fariam o segundo
  // save engolir o merge do primeiro.
  final stateLock = SerialTaskQueue();
  await for (final request in server) {
    unawaited(
      _handleRequest(request, store, config, stateLock).catchError((
        Object error,
      ) {
        stderr.writeln('Curió sync request failed: ${error.runtimeType}');
      }),
    );
  }
}

/// Prints the device pairing information at startup: the certificate
/// fingerprint to pin and, when the reachable host is known, a ready-to-paste
/// pairing code (origin + token + fingerprint).
void _printPairing(_ServerConfig config, String scheme, int port) {
  if (!config.tlsEnabled) {
    stdout.writeln(
      'Pairing: HTTPS desativado. O pinning de certificado exige TLS '
      '(--tls-cert/--tls-key). Veja docs/self-hosted-sync.md.',
    );
    return;
  }
  final certFile = config.tlsCert;
  if (certFile == null) {
    return;
  }

  String? fingerprint;
  try {
    fingerprint = certificateSha256FromPem(certFile.readAsStringSync());
  } on Object {
    fingerprint = null;
  }
  if (fingerprint == null) {
    stdout.writeln(
      'Pairing: não foi possível calcular o fingerprint do certificado.',
    );
    return;
  }
  stdout.writeln('Certificate SHA-256: $fingerprint');

  final token = config.token;
  if (token == null) {
    stdout.writeln(
      'Pairing: defina LUME_SYNC_TOKEN para gerar o código de pareamento completo.',
    );
    return;
  }

  final bindHost = config.host.trim();
  final reachableHost =
      config.publicHost ??
      (_isLoopbackHost(bindHost) || bindHost == '0.0.0.0' ? null : bindHost);
  if (reachableHost == null) {
    stdout.writeln(
      'Pairing: no app, informe o servidor (https://SEU_HOST:$port) e cole este '
      'fingerprint; ou defina LUME_SYNC_PUBLIC_HOST com o endereço acessível '
      'para imprimir o código completo.',
    );
    return;
  }

  final code = SyncPairing(
    serverUrl: '$scheme://$reachableHost:$port',
    authToken: token,
    certSha256: fingerprint,
  ).encode();
  stdout.writeln('Pairing code (cole no app): $code');
}

Future<void> _handleRequest(
  HttpRequest request,
  ServerSnapshotStore store,
  _ServerConfig config,
  SerialTaskQueue stateLock,
) async {
  try {
    _setCommonHeaders(request.response, config);
    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return;
    }

    final path = request.uri.path;
    if (request.method == 'GET' && path == '/health') {
      await _writeJson(request.response, <String, Object?>{
        'ok': true,
        'serverTimeUtc': DateTime.now().toUtc().toIso8601String(),
      });
      return;
    }

    if (request.method == 'GET' && path == '/snapshot') {
      if (!await _authorize(request, config)) {
        return;
      }
      await _writeJson(request.response, <String, Object?>{
        'snapshot': (await store.load()).toJson(),
      });
      return;
    }

    if (request.method == 'POST' && path == '/sync') {
      if (!await _authorize(request, config)) {
        return;
      }
      final payload = await _readJson(
        request,
        maxBodyBytes: config.maxBodyBytes,
      );
      final deviceId = payload['deviceId'] as String? ?? 'unknown-device';
      final incoming = AppSnapshot.fromJson(
        Map<String, Object?>.from(
          payload['snapshot']! as Map<dynamic, dynamic>,
        ),
      );
      // Somente a mutação do estado entra no lock: a leitura do corpo (acima)
      // e a escrita da resposta (abaixo) podem rodar em paralelo com outras
      // requisições.
      final next = await stateLock.run(() async {
        final current = await store.load();
        final merged = const SnapshotSyncMerger().merge(
          local: current,
          remote: syncableServerSnapshot(incoming),
        );
        // Bound long-term growth of the shared state with the same retention
        // policy the clients use.
        final compacted = compactSnapshot(
          merged,
          nowUtc: DateTime.now().toUtc(),
        );
        await store.save(compacted);
        return compacted;
      });

      await _writeJson(request.response, <String, Object?>{
        'deviceId': deviceId,
        'snapshot': syncableServerSnapshot(next).toJson(),
        'serverTimeUtc': DateTime.now().toUtc().toIso8601String(),
      });
      return;
    }

    request.response.statusCode = HttpStatus.notFound;
    await _writeJson(request.response, <String, Object?>{'error': 'not found'});
  } on _RequestTooLargeException {
    request.response.statusCode = HttpStatus.requestEntityTooLarge;
    await _writeJson(request.response, <String, Object?>{
      'error': 'request too large',
    });
  } on Object catch (error) {
    stderr.writeln('Curió sync invalid request: ${error.runtimeType}');
    request.response.statusCode = HttpStatus.badRequest;
    await _writeJson(request.response, <String, Object?>{
      'error': 'invalid request',
    });
  }
}

Future<bool> _authorize(HttpRequest request, _ServerConfig config) async {
  final token = config.token;
  if (token == null) {
    return true;
  }

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

void _setCommonHeaders(HttpResponse response, _ServerConfig config) {
  final corsOrigin = config.corsOrigin;
  if (corsOrigin == null) {
    return;
  }

  response.headers.add('Access-Control-Allow-Origin', corsOrigin);
  response.headers.add('Vary', 'Origin');
  response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  response.headers.add(
    'Access-Control-Allow-Headers',
    'content-type, $_syncTokenHeader',
  );
}

final class _ServerConfig {
  const _ServerConfig({
    required this.host,
    required this.port,
    required this.file,
    required this.token,
    required this.tlsCert,
    required this.tlsKey,
    required this.tlsKeyPassword,
    required this.maxBodyBytes,
    required this.corsOrigin,
    required this.allowEmptyToken,
    required this.publicHost,
  });

  final String host;
  final int port;
  final File file;
  final String? token;
  final File? tlsCert;
  final File? tlsKey;
  final String? tlsKeyPassword;
  final int maxBodyBytes;
  final String? corsOrigin;
  final bool allowEmptyToken;

  /// Externally reachable host used only to print the pairing code (the bind
  /// [host] is often `0.0.0.0`). From `LUME_SYNC_PUBLIC_HOST`.
  final String? publicHost;

  bool get tlsEnabled => tlsCert != null && tlsKey != null;

  SecurityContext createSecurityContext() {
    final cert = tlsCert;
    final key = tlsKey;
    if (cert == null || key == null) {
      throw StateError('TLS certificate and private key are required.');
    }

    return SecurityContext()
      ..useCertificateChain(cert.path)
      ..usePrivateKey(key.path, password: tlsKeyPassword);
  }

  static _ServerConfig parse(List<String> args) {
    var host = _nonEmpty(Platform.environment['LUME_SYNC_HOST']) ?? '0.0.0.0';
    var port =
        _optionalInt(
          Platform.environment['LUME_SYNC_PORT'],
          name: 'LUME_SYNC_PORT',
        ) ??
        8787;
    var file = File(
      _nonEmpty(Platform.environment['LUME_SYNC_FILE']) ??
          '.lume-sync/server-state.json',
    );
    var token = _nonEmpty(Platform.environment['LUME_SYNC_TOKEN']);
    var publicHost = _nonEmpty(Platform.environment['LUME_SYNC_PUBLIC_HOST']);
    var tlsCert = _optionalFile(Platform.environment['LUME_SYNC_TLS_CERT']);
    var tlsKey = _optionalFile(Platform.environment['LUME_SYNC_TLS_KEY']);
    var tlsKeyPassword = _nonEmpty(
      Platform.environment['LUME_SYNC_TLS_KEY_PASSWORD'],
    );
    var maxBodyBytes =
        _optionalInt(
          Platform.environment['LUME_SYNC_MAX_BODY_BYTES'],
          name: 'LUME_SYNC_MAX_BODY_BYTES',
        ) ??
        _defaultMaxBodyBytes;
    var corsOrigin = _nonEmpty(Platform.environment['LUME_SYNC_CORS_ORIGIN']);
    var allowEmptyToken =
        _optionalBool(Platform.environment['LUME_SYNC_ALLOW_EMPTY_TOKEN']) ??
        false;

    for (var index = 0; index < args.length; index++) {
      final arg = args[index];
      String valueFor(String option) {
        if (index + 1 >= args.length) {
          throw ArgumentError('Missing value for $option.');
        }
        return args[++index];
      }

      switch (arg) {
        case '--host':
          host = valueFor(arg);
        case '--port':
          port = _parseIntOption(arg, valueFor(arg));
        case '--file':
          file = File(valueFor(arg));
        case '--token':
          token = _nonEmpty(valueFor(arg));
        case '--tls-cert':
          tlsCert = File(valueFor(arg));
        case '--tls-key':
          tlsKey = File(valueFor(arg));
        case '--tls-key-password':
          tlsKeyPassword = _nonEmpty(valueFor(arg));
        case '--max-body-bytes':
          maxBodyBytes = _parseIntOption(arg, valueFor(arg));
        case '--cors-origin':
          corsOrigin = _nonEmpty(valueFor(arg));
        case '--public-host':
          publicHost = _nonEmpty(valueFor(arg));
        case '--allow-empty-token':
          allowEmptyToken = true;
        default:
          throw ArgumentError('Unknown option: $arg.');
      }
    }

    if (port < 0 || port > 65535) {
      throw ArgumentError('LUME_SYNC_PORT must be between 0 and 65535.');
    }
    if ((tlsCert == null) != (tlsKey == null)) {
      throw ArgumentError(
        'Use --tls-cert and --tls-key together to enable HTTPS.',
      );
    }
    if (maxBodyBytes <= 0) {
      throw ArgumentError('LUME_SYNC_MAX_BODY_BYTES must be positive.');
    }
    if (token == null && !allowEmptyToken) {
      throw ArgumentError(
        'Set LUME_SYNC_TOKEN or pass --token. Use --allow-empty-token only for loopback development.',
      );
    }
    if (token == null && !_isLoopbackHost(host)) {
      throw ArgumentError(
        '--allow-empty-token is only permitted with 127.0.0.1, localhost, or ::1.',
      );
    }
    if (token != null && token.length < _minSyncTokenLength) {
      throw ArgumentError(
        'LUME_SYNC_TOKEN must be at least $_minSyncTokenLength characters.',
      );
    }
    if (corsOrigin != null) {
      corsOrigin = _validatedCorsOrigin(corsOrigin);
    }
    if (tlsCert != null && !tlsCert.existsSync()) {
      throw ArgumentError('TLS certificate file not found.');
    }
    if (tlsKey != null && !tlsKey.existsSync()) {
      throw ArgumentError('TLS private key file not found.');
    }

    return _ServerConfig(
      host: host,
      port: port,
      file: file,
      token: token,
      tlsCert: tlsCert,
      tlsKey: tlsKey,
      tlsKeyPassword: tlsKeyPassword,
      maxBodyBytes: maxBodyBytes,
      corsOrigin: corsOrigin,
      allowEmptyToken: allowEmptyToken,
      publicHost: publicHost,
    );
  }
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

String? _nonEmpty(String? value) {
  final trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}

File? _optionalFile(String? value) {
  final trimmed = _nonEmpty(value);
  return trimmed == null ? null : File(trimmed);
}

int? _optionalInt(String? value, {required String name}) {
  final trimmed = _nonEmpty(value);
  return trimmed == null ? null : _parseIntOption(name, trimmed);
}

int _parseIntOption(String name, String value) {
  final parsed = int.tryParse(value.trim());
  if (parsed == null) {
    throw ArgumentError('$name must be an integer.');
  }
  return parsed;
}

bool? _optionalBool(String? value) {
  final trimmed = _nonEmpty(value)?.toLowerCase();
  if (trimmed == null) {
    return null;
  }
  if (trimmed == '1' || trimmed == 'true' || trimmed == 'yes') {
    return true;
  }
  if (trimmed == '0' || trimmed == 'false' || trimmed == 'no') {
    return false;
  }
  throw ArgumentError('LUME_SYNC_ALLOW_EMPTY_TOKEN must be true or false.');
}

bool _isLoopbackHost(String host) {
  final normalized = host.trim().toLowerCase();
  return normalized == 'localhost' ||
      normalized == '127.0.0.1' ||
      normalized == '::1' ||
      normalized == '[::1]';
}

String _validatedCorsOrigin(String origin) {
  if (origin.trim() == '*') {
    throw ArgumentError('LUME_SYNC_CORS_ORIGIN must not be a wildcard.');
  }

  final uri = Uri.tryParse(origin);
  if (uri == null ||
      (uri.scheme != 'https' && uri.scheme != 'http') ||
      !uri.hasAuthority ||
      uri.host.trim().isEmpty ||
      uri.userInfo.isNotEmpty ||
      (uri.path.isNotEmpty && uri.path != '/') ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw ArgumentError(
      'LUME_SYNC_CORS_ORIGIN must be an explicit http:// or https:// origin.',
    );
  }

  return '${uri.scheme}://${uri.authority}';
}

const _syncTokenHeader = 'x-lume-sync-token';
const _minSyncTokenLength = 16;
const _defaultMaxBodyBytes = 10 * 1024 * 1024;

final class _RequestTooLargeException implements Exception {
  const _RequestTooLargeException();
}
