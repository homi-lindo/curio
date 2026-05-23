import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'recoverable_store_file.dart';

const int noteEditHistoryLimit = 50;

final class NoteEditRevision {
  const NoteEditRevision({
    required this.id,
    required this.noteId,
    required this.noteTitle,
    required this.body,
    required this.savedAtUtc,
    this.kind = NoteEditRevisionKind.note,
  });

  factory NoteEditRevision.fromJson(Map<String, Object?> json) {
    return NoteEditRevision(
      id: json['id'] as String,
      noteId: json['noteId'] as String,
      noteTitle: json['noteTitle'] as String? ?? 'Nota',
      body: json['body'] as String? ?? '',
      savedAtUtc: DateTime.parse(json['savedAtUtc'] as String).toUtc(),
      kind: NoteEditRevisionKind.values.byName(
        json['kind'] as String? ?? NoteEditRevisionKind.note.name,
      ),
    );
  }

  final String id;
  final String noteId;
  final String noteTitle;
  final String body;
  final DateTime savedAtUtc;
  final NoteEditRevisionKind kind;

  bool get restorable => kind == NoteEditRevisionKind.note;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'noteId': noteId,
      'noteTitle': noteTitle,
      'body': body,
      'savedAtUtc': savedAtUtc.toUtc().toIso8601String(),
      'kind': kind.name,
    };
  }
}

enum NoteEditRevisionKind { note, notification }

final class NoteEditHistoryStore {
  NoteEditHistoryStore({Future<Directory> Function()? directoryProvider})
    : _directoryProvider =
          directoryProvider ?? (() => getApplicationSupportDirectory());

  final Future<Directory> Function() _directoryProvider;

  Future<File> get file async {
    final directory = await _directoryProvider();
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return File(p.join(directory.path, 'curio-note-history.json'));
  }

  Future<List<NoteEditRevision>> load() async {
    final target = await file;
    if (!await target.exists()) {
      return const <NoteEditRevision>[];
    }

    final raw = await target.readAsString();
    if (raw.trim().isEmpty) {
      return const <NoteEditRevision>[];
    }

    try {
      final payload = jsonDecode(raw) as Map<String, Object?>;
      final items = payload['revisions'] as List<Object?>? ?? const <Object?>[];
      return items
          .map(
            (item) => NoteEditRevision.fromJson(
              Map<String, Object?>.from(item! as Map<dynamic, dynamic>),
            ),
          )
          .take(noteEditHistoryLimit)
          .toList();
    } on Object catch (error) {
      if (!isRecoverableStoreFormatError(error)) {
        rethrow;
      }
      await preserveInvalidStoreFile(target);
      return const <NoteEditRevision>[];
    }
  }

  Future<List<NoteEditRevision>> add(NoteEditRevision revision) async {
    final current = await load();
    if (current.isNotEmpty &&
        current.first.noteId == revision.noteId &&
        current.first.body == revision.body) {
      return current;
    }

    final next = <NoteEditRevision>[
      revision,
      ...current.where(
        (candidate) =>
            candidate.noteId != revision.noteId ||
            candidate.body != revision.body,
      ),
    ].take(noteEditHistoryLimit).toList();
    await save(next);
    return next;
  }

  Future<void> save(List<NoteEditRevision> revisions) async {
    final target = await file;
    final tmp = File('${target.path}.tmp');
    final payload = <String, Object?>{
      'schemaVersion': 1,
      'revisions': revisions
          .take(noteEditHistoryLimit)
          .map((revision) => revision.toJson())
          .toList(),
    };
    await tmp.writeAsString(jsonEncode(payload), flush: true);
    if (await target.exists()) {
      await target.delete();
    }
    await tmp.rename(target.path);
  }
}
