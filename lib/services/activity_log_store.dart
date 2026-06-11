import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Persiste as mensagens da Atividade em arquivo com rotação por tamanho.
/// O buffer em memória continua alimentando a UI (50 mensagens e evapora ao
/// fechar); o arquivo existe para diagnóstico post-mortem — "o alarme não
/// tocou ontem" só é investigável se o log sobreviver ao processo.
final class ActivityLogStore {
  ActivityLogStore({
    Future<Directory> Function()? directoryProvider,
    this.maxBytes = 256 * 1024,
  }) : _directoryProvider =
           directoryProvider ?? (() => getApplicationSupportDirectory());

  final Future<Directory> Function() _directoryProvider;

  /// Tamanho-alvo do arquivo ativo; ao passar dele o arquivo vira `.1` e um
  /// novo começa. No pior caso o disco guarda ~2x [maxBytes].
  final int maxBytes;

  Future<void> _tail = Future<void>.value();

  Future<File> get file async {
    final directory = await _directoryProvider();
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return File(p.join(directory.path, 'curio-activity.log'));
  }

  Future<File> get rotatedFile async {
    final directory = await _directoryProvider();
    return File(p.join(directory.path, 'curio-activity.1.log'));
  }

  /// Acrescenta uma linha com timestamp UTC. Best-effort e serializado: uma
  /// falha não derruba as gravações seguintes nem o chamador.
  Future<void> append(String message) {
    final operation = _tail.then((_) async {
      final target = await file;
      final line =
          '${DateTime.now().toUtc().toIso8601String()}  '
          '${message.replaceAll('\n', ' ')}\n';
      await target.writeAsString(line, mode: FileMode.append, flush: true);
      await _rotateIfNeeded(target);
    });
    _tail = operation.then((_) {}, onError: (Object _) {});
    return _tail;
  }

  Future<void> _rotateIfNeeded(File target) async {
    if (await target.length() <= maxBytes) {
      return;
    }
    final backup = await rotatedFile;
    if (await backup.exists()) {
      await backup.delete();
    }
    await target.rename(backup.path);
  }
}
