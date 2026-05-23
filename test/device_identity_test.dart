import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lume/services/device_identity.dart';

void main() {
  test('device identity is created once and reused', () async {
    final temp = await Directory.systemTemp.createTemp('lume_device_test_');
    addTearDown(() => temp.delete(recursive: true));

    final store = DeviceIdentityStore(
      directoryProvider: () async => temp,
      idFactory: () => 'lume-test-device',
    );

    final first = await store.load();
    final second = await store.load();

    expect(first, 'lume-test-device');
    expect(second, first);
    expect(await store.file.then((file) => file.exists()), isTrue);
  });

  test('device identity regenerates when persisted file is empty', () async {
    final temp = await Directory.systemTemp.createTemp('lume_device_empty_');
    addTearDown(() => temp.delete(recursive: true));

    final store = DeviceIdentityStore(
      directoryProvider: () async => temp,
      idFactory: () => 'lume-regenerated-device',
    );
    final target = await store.file;
    await target.writeAsString('');

    final loaded = await store.load();
    final archived = temp.listSync().where(
      (entity) => entity.path.contains('lume-device.json.invalid-'),
    );

    expect(loaded, 'lume-regenerated-device');
    expect(archived, isNotEmpty);
  });
}
