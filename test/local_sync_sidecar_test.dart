import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lume/services/local_sync_sidecar.dart';
import 'package:lume_core/domain/app_snapshot.dart';
import 'package:lume_core/domain/reminder.dart';

void main() {
  test(
    'local sidecar protects sync endpoints and strips projections',
    () async {
      final now = DateTime.utc(2026, 5, 20, 15);
      var current = AppSnapshot(
        tasks: <TaskItem>[
          TaskItem(
            id: 'task-local',
            title: 'Local',
            status: TaskStatus.open,
            createdAtUtc: now,
            updatedAtUtc: now,
          ),
        ],
        notes: const <NoteItem>[],
        scheduledNotifications: <ScheduledNotificationRecord>[
          ScheduledNotificationRecord(
            id: 42,
            deviceId: 'lume-windows',
            reminderIntentId: 'reminder-local',
            ownerId: 'task-local',
            ownerType: ReminderOwnerType.task,
            occurrenceKey: now.toIso8601String(),
            scheduledForUtc: now,
            payload: 'local notification',
          ),
        ],
      );
      final sidecar = LocalSyncSidecar(
        loadSnapshot: () async => current,
        saveSnapshot: (snapshot) async {
          current = snapshot;
        },
      );
      addTearDown(sidecar.stop);

      const token = '0123456789abcdef';
      final state = await sidecar.start(
        token: token,
        host: InternetAddress.loopbackIPv4.address,
        port: 0,
      );

      final health = await _requestJson(
        'GET',
        Uri.parse('${state.localUrl}/health'),
      );
      expect(health.statusCode, HttpStatus.ok);
      expect(health.body['ok'], isTrue);

      final denied = await _requestJson(
        'GET',
        Uri.parse('${state.localUrl}/snapshot'),
      );
      expect(denied.statusCode, HttpStatus.unauthorized);
      expect(denied.body['error'], 'invalid sync token');

      final snapshot = await _requestJson(
        'GET',
        Uri.parse('${state.localUrl}/snapshot'),
        token: token,
      );
      expect(snapshot.statusCode, HttpStatus.ok);
      final snapshotBody = snapshot.body['snapshot']! as Map<String, Object?>;
      expect(snapshotBody['scheduledNotifications'], isEmpty);

      final incoming = AppSnapshot(
        tasks: <TaskItem>[
          TaskItem(
            id: 'task-remote',
            title: 'Remote',
            status: TaskStatus.open,
            createdAtUtc: now,
            updatedAtUtc: now.add(const Duration(minutes: 1)),
          ),
        ],
        notes: const <NoteItem>[],
        scheduledNotifications: <ScheduledNotificationRecord>[
          ScheduledNotificationRecord(
            id: 77,
            deviceId: 'lume-android',
            reminderIntentId: 'remote-reminder',
            ownerId: 'task-remote',
            ownerType: ReminderOwnerType.task,
            occurrenceKey: now.toIso8601String(),
            scheduledForUtc: now,
            payload: 'remote notification',
          ),
        ],
      );

      final synced = await _requestJson(
        'POST',
        Uri.parse('${state.localUrl}/sync'),
        token: token,
        body: <String, Object?>{'snapshot': incoming.toJson()},
      );
      expect(synced.statusCode, HttpStatus.ok);
      final syncedBody = synced.body['snapshot']! as Map<String, Object?>;
      expect(syncedBody['scheduledNotifications'], isEmpty);
      expect(
        current.tasks.map((task) => task.id),
        containsAll(<String>['task-local', 'task-remote']),
      );
      expect(current.scheduledNotifications, hasLength(1));
    },
  );

  test('local sidecar rejects weak tokens before binding', () async {
    final sidecar = LocalSyncSidecar(
      loadSnapshot: () async => const AppSnapshot(
        tasks: <TaskItem>[],
        notes: <NoteItem>[],
        scheduledNotifications: <ScheduledNotificationRecord>[],
      ),
      saveSnapshot: (_) async {},
    );
    addTearDown(sidecar.stop);

    await expectLater(
      sidecar.start(
        token: 'short',
        host: InternetAddress.loopbackIPv4.address,
        port: 0,
      ),
      throwsA(isA<LocalSyncSidecarException>()),
    );
    expect(sidecar.isRunning, isFalse);
  });
}

Future<_JsonResponse> _requestJson(
  String method,
  Uri uri, {
  String? token,
  Map<String, Object?>? body,
}) async {
  final client = HttpClient();
  try {
    final request = method == 'POST'
        ? await client.postUrl(uri)
        : await client.getUrl(uri);
    request.headers.contentType = ContentType.json;
    if (token != null) {
      request.headers.set('x-lume-sync-token', token);
    }
    if (body != null) {
      request.write(jsonEncode(body));
    }

    final response = await request.close();
    final raw = await utf8.decodeStream(response);
    return _JsonResponse(
      statusCode: response.statusCode,
      body: Map<String, Object?>.from(jsonDecode(raw) as Map<dynamic, dynamic>),
    );
  } finally {
    client.close(force: true);
  }
}

final class _JsonResponse {
  const _JsonResponse({required this.statusCode, required this.body});

  final int statusCode;
  final Map<String, Object?> body;
}
