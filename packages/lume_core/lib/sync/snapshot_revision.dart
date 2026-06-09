import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../domain/app_snapshot.dart';

/// Identificador estável do estado sincronizável: SHA-256 do JSON canônico,
/// sem as notificações locais (que nunca trafegam). Dois estados iguais têm a
/// mesma revision em qualquer aparelho ou servidor. Exposta como
/// ETag/`revision` nas respostas de sync — base para um If-Match
/// (compare-and-swap) futuro sem quebrar clientes atuais.
String snapshotRevision(AppSnapshot snapshot) {
  final canonical = jsonEncode(
    snapshot
        .copyWith(scheduledNotifications: const [])
        .toJson(),
  );
  return sha256.convert(utf8.encode(canonical)).toString();
}
