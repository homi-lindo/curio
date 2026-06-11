import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../domain/app_snapshot.dart';

/// Identificador estável do estado sincronizável: SHA-256 do JSON canônico,
/// sem as notificações locais (que nunca trafegam). Dois estados iguais têm a
/// mesma revision em qualquer aparelho ou servidor. Exposta como
/// ETag/`revision` nas respostas de sync — base para um If-Match
/// (compare-and-swap) futuro sem quebrar clientes atuais.
///
/// Canonicalização: as listas são ordenadas por chave estável (id/key) antes
/// do encode. O merger ordena por `updatedAtUtc`, que empata quando dois
/// aparelhos gravam no mesmo instante — e a ordem do empate depende de quem
/// processou primeiro. Sem isto, o MESMO estado lógico produziria revisions
/// diferentes em aparelhos diferentes.
String snapshotRevision(AppSnapshot snapshot) {
  final canonical = snapshot.copyWith(
    tasks: [...snapshot.tasks]..sort((a, b) => a.id.compareTo(b.id)),
    notes: [...snapshot.notes]..sort((a, b) => a.id.compareTo(b.id)),
    reminders: [...snapshot.reminders]..sort((a, b) => a.id.compareTo(b.id)),
    deletedRecords: [...snapshot.deletedRecords]
      ..sort((a, b) => a.key.compareTo(b.key)),
    scheduledNotifications: const [],
  );
  return sha256.convert(utf8.encode(jsonEncode(canonical.toJson()))).toString();
}
