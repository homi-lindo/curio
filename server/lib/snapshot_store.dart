import 'dart:convert';
import 'dart:io';

import 'package:lume_core/domain/app_snapshot.dart';

final class ServerSnapshotStore {
  const ServerSnapshotStore(this.file);

  final File file;

  File get _backupFile => File('${file.path}.bak');
  File get _tempFile => File('${file.path}.tmp');

  Future<AppSnapshot> load() async {
    if (await file.exists()) {
      try {
        return await _readSnapshot(file);
      } on FormatException {
        final backup = await _tryReadBackup();
        if (backup != null) {
          return backup;
        }
        rethrow;
      }
    }

    final backup = await _tryReadBackup();
    return backup ?? emptyServerSnapshot;
  }

  Future<void> save(AppSnapshot snapshot) async {
    final parent = file.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }

    const encoder = JsonEncoder.withIndent('  ');
    final payload =
        '${encoder.convert(syncableServerSnapshot(snapshot).toJson())}\n';
    final tempFile = _tempFile;
    final backupFile = _backupFile;

    await tempFile.writeAsString(payload, flush: true);

    if (await file.exists()) {
      if (await _canReadSnapshot(file)) {
        await file.copy(backupFile.path);
      }
      await file.delete();
    }

    try {
      await tempFile.rename(file.path);
    } on FileSystemException {
      if (await backupFile.exists() && !await file.exists()) {
        await backupFile.copy(file.path);
      }
      rethrow;
    }
  }

  Future<AppSnapshot?> _tryReadBackup() async {
    final backupFile = _backupFile;
    if (!await backupFile.exists()) {
      return null;
    }

    try {
      return await _readSnapshot(backupFile);
    } on FormatException {
      return null;
    }
  }
}

const emptyServerSnapshot = AppSnapshot(
  tasks: <TaskItem>[],
  notes: <NoteItem>[],
  scheduledNotifications: [],
  deletedRecords: <DeletedRecord>[],
);

AppSnapshot syncableServerSnapshot(AppSnapshot snapshot) {
  return snapshot.copyWith(scheduledNotifications: const []);
}

Future<AppSnapshot> _readSnapshot(File file) async {
  final raw = await file.readAsString();
  final json = Map<String, Object?>.from(
    jsonDecode(raw) as Map<dynamic, dynamic>,
  );
  return AppSnapshot.fromJson(json);
}

Future<bool> _canReadSnapshot(File file) async {
  try {
    await _readSnapshot(file);
    return true;
  } on FormatException {
    return false;
  }
}
