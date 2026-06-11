// Autosave do editor de notas: cada tecla atualiza o estado em memória na
// hora, mas a persistência é coalescida por debounce — sem ele, toda tecla
// reescreveria o banco inteiro via replaceSnapshot. O flush em dispose garante
// que nada digitado fique só na memória.
//
// Nota de harness: testWidgets roda em zona FakeAsync, então o I/O real do
// boot (arquivos de settings, identidade) só completa dentro de
// tester.runAsync — daí o laço que alterna eventos reais e frames.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/data/app_database.dart';
import 'package:lume/main.dart';
import 'package:lume/services/activity_log_store.dart';
import 'package:lume/services/alarm_settings_store.dart';
import 'package:lume/services/appearance_settings_store.dart';
import 'package:lume/services/device_identity.dart';
import 'package:lume/services/local_store.dart';
import 'package:lume/services/note_edit_history_store.dart';
import 'package:lume/services/notification_service.dart';
import 'package:lume/services/secure_secret_store.dart';
import 'package:lume/services/sync_settings_store.dart';
import 'package:lume_core/domain/app_snapshot.dart';

final class _MemorySecretBackend implements SecretBackend {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}

final class _CountingDatabase extends AppDatabase {
  _CountingDatabase(super.executor);

  int saveCount = 0;

  @override
  Future<void> replaceSnapshot(AppSnapshot snapshot) {
    saveCount++;
    return super.replaceSnapshot(snapshot);
  }

  @override
  Future<void> applySnapshotDiff(AppSnapshot previous, AppSnapshot next) {
    saveCount++;
    return super.applySnapshotDiff(previous, next);
  }
}

final class _Harness {
  _Harness({required this.db, required this.tmpDir});

  final _CountingDatabase db;
  final Directory tmpDir;
}

Future<_Harness> _bootApp(WidgetTester tester) async {
  late final Directory tmpDir;
  await tester.runAsync(() async {
    tmpDir = await Directory.systemTemp.createTemp('lume_autosave_');
  });
  Future<Directory> tmpProvider() async => tmpDir;

  final db = _CountingDatabase(NativeDatabase.memory());
  final store = LocalStore.withDatabase(db, directoryProvider: tmpProvider);

  final app = CurioApp(
    notifications: NotificationService(),
    store: store,
    deviceIdentity: DeviceIdentityStore(directoryProvider: tmpProvider),
    syncSettings: SyncSettingsStore(
      directoryProvider: tmpProvider,
      // O backend real é um canal nativo (DPAPI no Windows) inexistente no
      // runner de testes de unidade.
      secureSecrets: SecureSecretStore(backend: _MemorySecretBackend()),
    ),
    appearanceSettings: AppearanceSettingsStore(directoryProvider: tmpProvider),
    alarmSettings: AlarmSettingsStore(directoryProvider: tmpProvider),
    noteHistory: NoteEditHistoryStore(directoryProvider: tmpProvider),
    activityLog: ActivityLogStore(directoryProvider: tmpProvider),
  );

  await tester.pumpWidget(app);
  for (var attempt = 0; attempt < 300; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (find.text('Notas').evaluate().isNotEmpty) {
      break;
    }
  }
  if (find.text('Notas').evaluate().isEmpty) {
    final texts = find
        .byType(Text)
        .evaluate()
        .map((element) => (element.widget as Text).data ?? '')
        .where((text) => text.trim().isNotEmpty)
        .toList();
    fail('o app não terminou o boot; textos visíveis: $texts');
  }

  return _Harness(db: db, tmpDir: tmpDir);
}

Future<void> _disposeHarness(WidgetTester tester, _Harness harness) async {
  await tester.runAsync(() async {
    await harness.db.close();
    try {
      await harness.tmpDir.delete(recursive: true);
    } on Object {
      // Limpeza best-effort; o diretório fica no temp do sistema.
    }
  });
}

Finder _noteEditor() {
  return find.byWidgetPredicate(
    (widget) =>
        widget is TextField &&
        widget.decoration?.hintText == 'Escreva em Markdown.',
  );
}

void main() {
  testWidgets('digitação contínua coalesce em uma única escrita no banco', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final harness = await _bootApp(tester);

    await tester.tap(find.text('Notas').first, warnIfMissed: false);
    await tester.pump();

    final baseline = harness.db.saveCount;
    final editor = _noteEditor();
    expect(editor, findsOneWidget);

    await tester.enterText(editor, 'primeira tecla');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(editor, 'primeira tecla, segunda');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(editor, 'primeira tecla, segunda e terceira');
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      harness.db.saveCount,
      baseline,
      reason: 'nenhuma escrita deve acontecer dentro da janela de debounce',
    );

    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();

    expect(
      harness.db.saveCount,
      baseline + 1,
      reason: 'a digitação coalescida deve virar exatamente uma escrita',
    );

    final persisted = await tester.runAsync(() => harness.db.loadSnapshot());
    expect(
      persisted!.notes.firstWhere((note) => note.id == 'note-inbox').body,
      'primeira tecla, segunda e terceira',
    );

    await _disposeHarness(tester, harness);
  });

  testWidgets('dispose dá flush no texto ainda não persistido', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final harness = await _bootApp(tester);

    await tester.tap(find.text('Notas').first, warnIfMissed: false);
    await tester.pump();

    final baseline = harness.db.saveCount;
    await tester.enterText(_noteEditor(), 'texto digitado e abandonado');
    await tester.pump(const Duration(milliseconds: 100));
    expect(harness.db.saveCount, baseline);

    // Troca a árvore inteira: o State é descartado e o flush de dispose deve
    // disparar a escrita pendente.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(harness.db.saveCount, baseline + 1);
    final persisted = await tester.runAsync(() => harness.db.loadSnapshot());
    expect(
      persisted!.notes.firstWhere((note) => note.id == 'note-inbox').body,
      'texto digitado e abandonado',
    );

    await _disposeHarness(tester, harness);
  });
}
