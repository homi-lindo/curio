import 'package:lume_core/domain/app_snapshot.dart';

/// Serializa as escritas de snapshot e, quando conhece o último estado
/// persistido, grava apenas o diff (upserts/deletes por tabela) em vez de
/// reescrever o banco inteiro. Em qualquer dúvida sobre o que há em disco —
/// primeiro save sem [prime], erro no meio de uma escrita — volta ao replace
/// completo, que é idempotente.
final class SnapshotWriteQueue {
  SnapshotWriteQueue({
    required Future<void> Function(AppSnapshot) saveSnapshot,
    Future<void> Function(AppSnapshot previous, AppSnapshot next)? applyDiff,
  }) : this._(saveSnapshot, applyDiff);

  SnapshotWriteQueue._(this._saveSnapshot, this._applyDiff);

  final Future<void> Function(AppSnapshot) _saveSnapshot;
  final Future<void> Function(AppSnapshot previous, AppSnapshot next)?
  _applyDiff;
  Future<void> _tail = Future<void>.value();
  AppSnapshot? _lastPersisted;

  /// Informa qual snapshot reflete o banco neste momento (tipicamente o que
  /// acabou de ser carregado no boot), habilitando o caminho de diff já na
  /// primeira escrita.
  void prime(AppSnapshot snapshot) {
    _lastPersisted ??= snapshot;
  }

  Future<void> save(AppSnapshot snapshot) {
    final operation = _tail.catchError((Object _) {}).then((_) async {
      final previous = _lastPersisted;
      final applyDiff = _applyDiff;
      try {
        if (previous == null || applyDiff == null) {
          await _saveSnapshot(snapshot);
        } else {
          await applyDiff(previous, snapshot);
        }
        _lastPersisted = snapshot;
      } on Object {
        // Estado em disco desconhecido após a falha: o próximo save usa o
        // replace completo.
        _lastPersisted = null;
        rethrow;
      }
    });
    _tail = operation;
    return operation;
  }
}
