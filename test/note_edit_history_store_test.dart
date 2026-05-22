import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lume/services/note_edit_history_store.dart';

void main() {
  test(
    'note edit history keeps newest 50 revisions and deduplicates',
    () async {
      final temp = await Directory.systemTemp.createTemp('curio_history_test_');
      final store = NoteEditHistoryStore(directoryProvider: () async => temp);
      addTearDown(() async => temp.delete(recursive: true));

      for (var index = 0; index < 55; index++) {
        await store.add(
          NoteEditRevision(
            id: 'revision-$index',
            noteId: 'note-1',
            noteTitle: 'Diário',
            body: 'corpo $index',
            savedAtUtc: DateTime.utc(2026, 5, 22, 12, index),
          ),
        );
      }
      final loaded = await store.load();

      expect(loaded, hasLength(noteEditHistoryLimit));
      expect(loaded.first.body, 'corpo 54');
      expect(loaded.last.body, 'corpo 5');

      final same = await store.add(loaded.first);

      expect(same, hasLength(noteEditHistoryLimit));
      expect(same.first.body, 'corpo 54');
    },
  );

  test('note edit history stores non-restorable notification logs', () async {
    final temp = await Directory.systemTemp.createTemp('curio_history_test_');
    final store = NoteEditHistoryStore(directoryProvider: () async => temp);
    addTearDown(() async => temp.delete(recursive: true));

    await store.add(
      NoteEditRevision(
        id: 'notification-log',
        noteId: 'note-1',
        noteTitle: 'Notificação · Café',
        body: 'Notificação editada',
        savedAtUtc: DateTime.utc(2026, 5, 22, 16),
        kind: NoteEditRevisionKind.notification,
      ),
    );

    final loaded = await store.load();

    expect(loaded.single.kind, NoteEditRevisionKind.notification);
    expect(loaded.single.restorable, isFalse);
  });
}
