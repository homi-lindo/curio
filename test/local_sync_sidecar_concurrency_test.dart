// Dois POST /sync simultâneos não podem se atropelar: a seção
// read→merge→save é serializada pelo SerialTaskQueue do sidecar. Sem essa
// serialização, o save da segunda requisição engoliria o merge da primeira e
// uma das notas sumiria do estado final.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lume/services/local_sync_sidecar.dart';
import 'package:lume_core/domain/app_snapshot.dart';
import 'package:lume_core/sync/snapshot_revision.dart';

const _token = 'token-de-teste-com-16+';

AppSnapshot _snapshotWithNote(String id, DateTime nowUtc) {
  return AppSnapshot(
    tasks: const [],
    notes: [
      NoteItem(
        id: id,
        title: id,
        body: 'corpo de $id',
        createdAtUtc: nowUtc,
        updatedAtUtc: nowUtc,
      ),
    ],
    scheduledNotifications: const [],
    deletedRecords: const [],
  );
}

Future<Map<String, Object?>> _postSync(int port, AppSnapshot snapshot) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(
      Uri.parse('http://127.0.0.1:$port/sync'),
    );
    request.headers.set('x-lume-sync-token', _token);
    request.headers.contentType = ContentType.json;
    request.write(
      jsonEncode(<String, Object?>{
        'deviceId': 'teste',
        'snapshot': snapshot.toJson(),
      }),
    );
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    expect(response.statusCode, HttpStatus.ok, reason: body);
    return Map<String, Object?>.from(jsonDecode(body) as Map);
  } finally {
    client.close(force: true);
  }
}

void main() {
  test('POSTs /sync concorrentes preservam o merge de ambos', () async {
    final nowUtc = DateTime.now().toUtc();
    var state = AppSnapshot(
      tasks: const [],
      notes: const [],
      scheduledNotifications: const [],
      deletedRecords: const [],
    );

    final sidecar = LocalSyncSidecar(
      // Latência artificial entre load e save abre a janela de corrida que o
      // lock precisa fechar.
      loadSnapshot: () async {
        final loaded = state;
        await Future<void>.delayed(const Duration(milliseconds: 30));
        return loaded;
      },
      saveSnapshot: (snapshot) async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        state = snapshot;
      },
    );
    final sidecarState = await sidecar.start(token: _token, host: '127.0.0.1');
    addTearDown(sidecar.stop);

    final results = await Future.wait(<Future<Map<String, Object?>>>[
      _postSync(sidecarState.port, _snapshotWithNote('nota-a', nowUtc)),
      _postSync(sidecarState.port, _snapshotWithNote('nota-b', nowUtc)),
    ]);
    expect(results, hasLength(2));

    final noteIds = state.notes.map((note) => note.id).toSet();
    expect(
      noteIds,
      containsAll(<String>{'nota-a', 'nota-b'}),
      reason:
          'os merges das duas requisições devem sobreviver — perder um deles '
          'significa que read→merge→save intercalou',
    );
  });

  test('/health responde enquanto um /sync lento está em andamento', () async {
    var state = AppSnapshot(
      tasks: const [],
      notes: const [],
      scheduledNotifications: const [],
      deletedRecords: const [],
    );

    final slowSaveStarted = Completer<void>();
    final releaseSave = Completer<void>();
    final sidecar = LocalSyncSidecar(
      loadSnapshot: () async => state,
      saveSnapshot: (snapshot) async {
        slowSaveStarted.complete();
        await releaseSave.future;
        state = snapshot;
      },
    );
    final sidecarState = await sidecar.start(token: _token, host: '127.0.0.1');
    addTearDown(sidecar.stop);

    final pendingSync = _postSync(
      sidecarState.port,
      _snapshotWithNote('nota-lenta', DateTime.now().toUtc()),
    );
    await slowSaveStarted.future;

    // Com despacho concorrente, /health não fica atrás do /sync em andamento.
    final client = HttpClient();
    try {
      final request = await client
          .getUrl(Uri.parse('http://127.0.0.1:${sidecarState.port}/health'))
          .timeout(const Duration(seconds: 2));
      final response = await request.close().timeout(
        const Duration(seconds: 2),
      );
      expect(response.statusCode, HttpStatus.ok);
      await response.drain<void>();
    } finally {
      client.close(force: true);
      releaseSave.complete();
    }

    await pendingSync;
    expect(state.notes.map((note) => note.id), contains('nota-lenta'));
  });

  test('snapshot com relógio quebrado é recusado com 400', () async {
    var state = AppSnapshot(
      tasks: const [],
      notes: const [],
      scheduledNotifications: const [],
      deletedRecords: const [],
    );
    final sidecar = LocalSyncSidecar(
      loadSnapshot: () async => state,
      saveSnapshot: (snapshot) async => state = snapshot,
    );
    final sidecarState = await sidecar.start(token: _token, host: '127.0.0.1');
    addTearDown(sidecar.stop);

    final brokenClock = _snapshotWithNote(
      'nota-do-futuro',
      DateTime.now().toUtc().add(const Duration(days: 30)),
    );

    final client = HttpClient();
    try {
      final request = await client.postUrl(
        Uri.parse('http://127.0.0.1:${sidecarState.port}/sync'),
      );
      request.headers.set('x-lume-sync-token', _token);
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode(<String, Object?>{
          'deviceId': 'teste',
          'snapshot': brokenClock.toJson(),
        }),
      );
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      expect(response.statusCode, HttpStatus.badRequest);
      expect(body, contains('relógio'));
    } finally {
      client.close(force: true);
    }

    expect(
      state.notes,
      isEmpty,
      reason: 'o snapshot com clock skew não pode contaminar o estado',
    );
  });

  test('respostas de /sync e /snapshot expõem revision estável', () async {
    var state = AppSnapshot(
      tasks: const [],
      notes: const [],
      scheduledNotifications: const [],
      deletedRecords: const [],
    );
    final sidecar = LocalSyncSidecar(
      loadSnapshot: () async => state,
      saveSnapshot: (snapshot) async => state = snapshot,
    );
    final sidecarState = await sidecar.start(token: _token, host: '127.0.0.1');
    addTearDown(sidecar.stop);

    final result = await _postSync(
      sidecarState.port,
      _snapshotWithNote('nota-rev', DateTime.now().toUtc()),
    );

    final revision = result['revision'];
    expect(revision, isA<String>());
    expect(revision, hasLength(64));
    expect(
      revision,
      snapshotRevision(state),
      reason: 'a revision da resposta deve refletir o estado salvo',
    );

    final client = HttpClient();
    try {
      final request = await client.getUrl(
        Uri.parse('http://127.0.0.1:${sidecarState.port}/snapshot'),
      );
      request.headers.set('x-lume-sync-token', _token);
      final response = await request.close();
      final etag = response.headers.value(HttpHeaders.etagHeader);
      final body = await utf8.decoder.bind(response).join();
      final payload = Map<String, Object?>.from(jsonDecode(body) as Map);
      expect(etag, '"$revision"');
      expect(payload['revision'], revision);
    } finally {
      client.close(force: true);
    }
  });
}
