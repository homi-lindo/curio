import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lume/services/activity_log_store.dart';

void main() {
  late Directory tmpDir;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('lume_activity_');
  });

  tearDown(() async {
    await tmpDir.delete(recursive: true);
  });

  ActivityLogStore store({int maxBytes = 256 * 1024}) {
    return ActivityLogStore(
      directoryProvider: () async => tmpDir,
      maxBytes: maxBytes,
    );
  }

  test('acrescenta linhas com timestamp UTC em ordem', () async {
    final log = store();
    await log.append('primeira mensagem');
    await log.append('segunda mensagem');

    final content = await (await log.file).readAsString();
    final lines = content.trim().split('\n');
    expect(lines, hasLength(2));
    expect(lines[0], contains('primeira mensagem'));
    expect(lines[1], contains('segunda mensagem'));
    expect(lines[0], matches(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}'));
  });

  test('appends concorrentes são serializados sem perda', () async {
    final log = store();
    await Future.wait(<Future<void>>[
      for (var index = 0; index < 20; index++) log.append('mensagem $index'),
    ]);

    final content = await (await log.file).readAsString();
    expect(content.trim().split('\n'), hasLength(20));
  });

  test('rotaciona ao passar do tamanho máximo', () async {
    final log = store(maxBytes: 120);
    for (var index = 0; index < 10; index++) {
      await log.append('mensagem de rotação número $index');
    }

    final rotated = await log.rotatedFile;
    expect(await rotated.exists(), isTrue);
    final active = await log.file;
    if (await active.exists()) {
      expect(await active.length(), lessThanOrEqualTo(120));
    }
  });

  test('flush aguarda appends fire-and-forget pendentes', () async {
    final log = store();
    for (var index = 0; index < 10; index++) {
      // Sem await, como o AppStateController dispara na prática.
      unawaited(log.append('pendente $index'));
    }

    await log.flush();

    final content = await (await log.file).readAsString();
    expect(
      content.trim().split('\n'),
      hasLength(10),
      reason: 'após o flush não pode haver escrita em voo',
    );
  });

  test('quebras de linha na mensagem viram espaço', () async {
    final log = store();
    await log.append('linha um\nlinha dois');

    final content = await (await log.file).readAsString();
    expect(content.trim().split('\n'), hasLength(1));
    expect(content, contains('linha um linha dois'));
  });
}
