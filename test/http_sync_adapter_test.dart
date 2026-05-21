import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lume/sync/http_sync_adapter.dart';
import 'package:lume_core/domain/app_snapshot.dart';

void main() {
  test('http sync adapter posts local snapshot and merges response', () async {
    final now = DateTime.utc(2026, 5, 20, 15);
    final remote = AppSnapshot(
      tasks: const <TaskItem>[],
      notes: <NoteItem>[
        NoteItem(
          id: 'note-remote',
          title: 'Nota remota',
          body: 'ok',
          createdAtUtc: now,
          updatedAtUtc: now,
        ),
      ],
      scheduledNotifications: const [],
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    Object? receivedDeviceId;
    String? receivedToken;
    unawaited(() async {
      await for (final request in server) {
        final raw = await utf8.decodeStream(request);
        final json = jsonDecode(raw) as Map<String, Object?>;
        receivedDeviceId = json['deviceId'];
        receivedToken = request.headers.value('x-lume-sync-token');
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(<String, Object?>{'snapshot': remote.toJson()}),
        );
        await request.response.close();
      }
    }());

    final adapter = HttpSyncAdapter(
      serverUrl: Uri.parse('http://127.0.0.1:${server.port}'),
      authToken: 'shared-secret-012345',
      allowInsecureHttp: true,
    );
    final result = await adapter.synchronize(
      snapshot: const AppSnapshot(
        tasks: <TaskItem>[],
        notes: <NoteItem>[],
        scheduledNotifications: [],
      ),
      deviceId: 'lume-test',
    );

    expect(receivedDeviceId, 'lume-test');
    expect(receivedToken, 'shared-secret-012345');
    expect(result.snapshot.notes.single.id, 'note-remote');
    expect(result.pulledRecords, 1);
  });

  test('http sync adapter rejects plain http unless explicitly allowed', () {
    expect(
      () => HttpSyncAdapter(
        serverUrl: Uri.parse('http://127.0.0.1:8787'),
        authToken: 'shared-secret-012345',
      ),
      throwsArgumentError,
    );
  });

  test('http sync adapter requires a strong sync token', () {
    expect(
      () => HttpSyncAdapter(
        serverUrl: Uri.parse('https://sync.example.test'),
        authToken: 'short',
      ),
      throwsArgumentError,
    );
  });

  test('http sync adapter rejects ambiguous server origins', () {
    for (final url in <String>[
      'https://sync.example.test/api',
      'https://sync.example.test?env=prod',
      'https://sync.example.test#sync',
      'https://user:pass@sync.example.test',
    ]) {
      expect(
        () => HttpSyncAdapter(
          serverUrl: Uri.parse(url),
          authToken: 'shared-secret-012345',
        ),
        throwsArgumentError,
        reason: url,
      );
    }
  });

  test('http sync adapter caps response body size', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    unawaited(() async {
      await for (final request in server) {
        await utf8.decodeStream(request);
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"snapshot":');
        request.response.write('"too-large"}');
        await request.response.close();
      }
    }());

    final adapter = HttpSyncAdapter(
      serverUrl: Uri.parse('http://127.0.0.1:${server.port}'),
      authToken: 'shared-secret-012345',
      allowInsecureHttp: true,
      maxResponseBytes: 8,
    );

    await expectLater(
      adapter.synchronize(
        snapshot: const AppSnapshot(
          tasks: <TaskItem>[],
          notes: <NoteItem>[],
          scheduledNotifications: [],
        ),
        deviceId: 'lume-test',
      ),
      throwsA(
        isA<HttpException>().having(
          (error) => error.message,
          'message',
          'sync server response too large',
        ),
      ),
    );
  });
}
