import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lume/services/snapshot_write_queue.dart';
import 'package:lume_core/domain/app_snapshot.dart';

void main() {
  test('snapshot write queue serializes writes in request order', () async {
    final writes = <String>[];
    final firstWriteStarted = Completer<void>();
    final releaseFirstWrite = Completer<void>();

    final queue = SnapshotWriteQueue(
      saveSnapshot: (snapshot) async {
        final noteId = snapshot.notes.single.id;
        writes.add('start:$noteId');
        if (noteId == 'first') {
          firstWriteStarted.complete();
          await releaseFirstWrite.future;
        }
        writes.add('finish:$noteId');
      },
    );

    final first = queue.save(_snapshotWithNote('first'));
    await firstWriteStarted.future;
    final second = queue.save(_snapshotWithNote('second'));

    await Future<void>.delayed(Duration.zero);
    expect(writes, <String>['start:first']);

    releaseFirstWrite.complete();
    await Future.wait(<Future<void>>[first, second]);

    expect(writes, <String>[
      'start:first',
      'finish:first',
      'start:second',
      'finish:second',
    ]);
  });

  test('snapshot write queue recovers after a failed write', () async {
    var attempts = 0;
    final saved = <String>[];
    final queue = SnapshotWriteQueue(
      saveSnapshot: (snapshot) async {
        attempts += 1;
        if (attempts == 1) {
          throw StateError('disk unavailable');
        }
        saved.add(snapshot.notes.single.id);
      },
    );

    await expectLater(
      queue.save(_snapshotWithNote('first')),
      throwsA(isA<StateError>()),
    );
    await queue.save(_snapshotWithNote('second'));

    expect(saved, <String>['second']);
  });
}

AppSnapshot _snapshotWithNote(String id) {
  final now = DateTime.utc(2026, 5, 21, 12);
  return AppSnapshot(
    tasks: const [],
    notes: <NoteItem>[
      NoteItem(
        id: id,
        title: id,
        body: '',
        createdAtUtc: now,
        updatedAtUtc: now,
      ),
    ],
    scheduledNotifications: const [],
  );
}
