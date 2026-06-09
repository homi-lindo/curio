import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:lume_core/domain/app_snapshot.dart';

import '../services/activity_log_store.dart';
import '../services/local_store.dart';
import '../services/snapshot_write_queue.dart';

/// Dono do estado de domínio: o snapshot em memória, a fila de escrita e a
/// trilha de atividade. Primeira fatia da migração do `_CurioAppState`
/// (receita em docs/refatoracao-estado.md) — o estado sai do widget para um
/// ChangeNotifier que as views poderão escutar diretamente, matando o prop
/// drilling aos poucos sem big-bang.
///
/// Invariantes herdados do código original e preservados aqui:
/// - `snapshot` muda de forma síncrona (antes de qualquer await) ao salvar:
///   quem lê no mesmo microtask nunca observa rollback.
/// - Escritas em disco são serializadas e vão por diff quando o último estado
///   persistido é conhecido ([prime]).
/// - A atividade guarda no máximo [maxActivityEntries] mensagens em memória e
///   espelha tudo, best-effort, no [ActivityLogStore].
final class AppStateController extends ChangeNotifier {
  AppStateController({
    required LocalStore store,
    required ActivityLogStore activityLog,
  }) : this._(
         activityLog,
         SnapshotWriteQueue(
           saveSnapshot: store.save,
           applyDiff: store.applyDiff,
         ),
       );

  AppStateController._(this._activityLog, this._writes);

  static const int maxActivityEntries = 50;

  final ActivityLogStore _activityLog;
  final SnapshotWriteQueue _writes;

  AppSnapshot? _snapshot;
  final List<String> _activity = <String>[];
  bool _disposed = false;

  AppSnapshot? get snapshot => _snapshot;

  /// Mais recente primeiro; a lista é viva (a mesma instância é notificada a
  /// cada mudança), não a modifique fora daqui.
  List<String> get activity => _activity;

  /// Informa qual snapshot espelha o banco neste momento, habilitando o
  /// caminho de escrita por diff já no primeiro save.
  void prime(AppSnapshot loaded) {
    _writes.prime(loaded);
  }

  /// Publica [snapshot] em memória imediatamente e enfileira a persistência.
  /// Publicação sem await; o Future devolvido é só da escrita em disco.
  Future<void> save(AppSnapshot snapshot) {
    publish(snapshot);
    return _writes.save(snapshot);
  }

  /// Atualiza o snapshot em memória e notifica os ouvintes. Não toca o disco.
  void publish(AppSnapshot? snapshot) {
    if (identical(_snapshot, snapshot)) {
      return;
    }
    _snapshot = snapshot;
    _notify();
  }

  /// Como [publish], mas sem notificar — para o caminho quente do editor, em
  /// que cada tecla atualiza a memória mas um rebuild por tecla seria
  /// desperdício (a persistência e a notificação chegam no flush do
  /// debounce ou na próxima ação).
  void publishSilently(AppSnapshot? snapshot) {
    _snapshot = snapshot;
  }

  void log(String message) {
    _activity.insert(0, message);
    if (_activity.length > maxActivityEntries) {
      _activity.removeLast();
    }
    // Persistência best-effort para diagnóstico pós-fechamento (o append já
    // engole erros internamente).
    unawaited(_activityLog.append(message));
    _notify();
  }

  /// Escritas tardias (flush do autosave durante o teardown) ainda podem
  /// logar/publicar depois do dispose; notificar aí estouraria o assert do
  /// ChangeNotifier.
  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
