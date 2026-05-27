import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lume/services/alarm_settings_store.dart';

void main() {
  test('persists alarm sound settings', () async {
    final temp = await Directory.systemTemp.createTemp('curio-alarm-test-');
    addTearDown(() async => temp.delete(recursive: true));
    final store = AlarmSettingsStore(directoryProvider: () async => temp);

    const settings = AlarmSettings(
      soundSource: AlarmSoundSource.custom,
      customAudioPath: 'C:/audio/alarme.mp3',
      customAudioName: 'alarme.mp3',
    );

    await store.save(settings);

    final loaded = await store.load();
    expect(loaded.soundSource, AlarmSoundSource.custom);
    expect(loaded.customAudioPath, 'C:/audio/alarme.mp3');
    expect(loaded.customAudioName, 'alarme.mp3');
  });

  test('installs a custom audio file under app support', () async {
    final temp = await Directory.systemTemp.createTemp('curio-alarm-test-');
    addTearDown(() async => temp.delete(recursive: true));
    final source = File('${temp.path}${Platform.pathSeparator}som.mp3');
    await source.writeAsString('fake-audio');
    final appSupport = Directory('${temp.path}${Platform.pathSeparator}app');
    final store = AlarmSettingsStore(directoryProvider: () async => appSupport);

    final settings = await store.installCustomAudio(source.path);

    expect(settings.soundSource, AlarmSoundSource.custom);
    expect(settings.customAudioName, 'som.mp3');
    expect(await File(settings.customAudioPath).exists(), isTrue);
  });

  test('rejects unsupported audio extensions', () async {
    final temp = await Directory.systemTemp.createTemp('curio-alarm-test-');
    addTearDown(() async => temp.delete(recursive: true));
    final source = File('${temp.path}${Platform.pathSeparator}som.txt');
    await source.writeAsString('not-audio');
    final store = AlarmSettingsStore(directoryProvider: () async => temp);

    expect(
      () => store.installCustomAudio(source.path),
      throwsA(isA<AlarmSettingsException>()),
    );
  });
}
