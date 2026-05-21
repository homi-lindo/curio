import 'package:lume_core/domain/app_snapshot.dart';

final class SnapshotWriteQueue {
  SnapshotWriteQueue({required Future<void> Function(AppSnapshot) saveSnapshot})
    : this._(saveSnapshot);

  SnapshotWriteQueue._(this._saveSnapshot);

  final Future<void> Function(AppSnapshot) _saveSnapshot;
  Future<void> _tail = Future<void>.value();

  Future<void> save(AppSnapshot snapshot) {
    final operation = _tail
        .catchError((Object _) {})
        .then((_) => _saveSnapshot(snapshot));
    _tail = operation;
    return operation;
  }
}
