import '../domain/app_snapshot.dart';

/// O merge LWW confia cegamente em `updatedAtUtc`: um aparelho com o relógio
/// um ano adiantado venceria todas as edições dos outros até essa data — e a
/// vitória é permanente. Esta guarda detecta timestamps além de
/// `now + tolerance` antes de um snapshot entrar no sync, dos dois lados.
///
/// A tolerância padrão de 24h não atrapalha skew normal de relógio nem fuso
/// mal configurado; só barra relógio realmente quebrado.
final class SnapshotTimestampGuard {
  const SnapshotTimestampGuard({this.tolerance = const Duration(hours: 24)});

  final Duration tolerance;

  /// Descrições legíveis dos registros com timestamp impossível; vazia quando
  /// o snapshot é são.
  List<String> findFutureTimestamps(
    AppSnapshot snapshot, {
    required DateTime nowUtc,
  }) {
    final limit = nowUtc.toUtc().add(tolerance);
    final issues = <String>[];

    void flag(String kind, String label, DateTime timestamp) {
      if (timestamp.toUtc().isAfter(limit)) {
        issues.add(
          '$kind "$label" com data ${timestamp.toUtc().toIso8601String()}',
        );
      }
    }

    for (final task in snapshot.tasks) {
      flag('tarefa', task.title, task.updatedAtUtc);
    }
    for (final note in snapshot.notes) {
      flag('nota', note.title, note.updatedAtUtc);
    }
    for (final reminder in snapshot.reminders) {
      flag('lembrete', reminder.title, reminder.updatedAtUtc);
    }
    for (final record in snapshot.deletedRecords) {
      flag('exclusão', record.key, record.deletedAtUtc);
    }

    return issues;
  }

  /// Lança [ClockSkewDetectedException] quando o snapshot contém timestamps
  /// impossíveis.
  void check(AppSnapshot snapshot, {required DateTime nowUtc}) {
    final issues = findFutureTimestamps(snapshot, nowUtc: nowUtc);
    if (issues.isNotEmpty) {
      throw ClockSkewDetectedException(issues: issues, tolerance: tolerance);
    }
  }
}

final class ClockSkewDetectedException implements Exception {
  const ClockSkewDetectedException({
    required this.issues,
    required this.tolerance,
  });

  final List<String> issues;
  final Duration tolerance;

  String get message {
    final example = issues.first;
    return 'sync bloqueado: ${issues.length} registro(s) com data mais de '
        '${tolerance.inHours}h no futuro (ex.: $example). Verifique o '
        'relógio do aparelho antes de sincronizar.';
  }

  @override
  String toString() => message;
}
