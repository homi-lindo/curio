import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/services/appearance_settings_store.dart';
import 'package:lume/theme/curio_theme.dart';

void main() {
  test('appearance settings default to system brightness and Aurora', () async {
    final temp = await Directory.systemTemp.createTemp(
      'curio_appearance_default_',
    );
    addTearDown(() => temp.delete(recursive: true));

    final store = AppearanceSettingsStore(directoryProvider: () async => temp);
    final settings = await store.load();

    expect(settings.themeMode, ThemeMode.system);
    expect(settings.themeProfile, CurioThemeProfile.aurora);
  });

  test(
    'appearance settings store persists selected mode and profile',
    () async {
      final temp = await Directory.systemTemp.createTemp('curio_appearance_');
      addTearDown(() => temp.delete(recursive: true));

      final store = AppearanceSettingsStore(
        directoryProvider: () async => temp,
      );
      const settings = AppearanceSettings(
        themeMode: ThemeMode.dark,
        themeProfile: CurioThemeProfile.slate,
      );

      await store.save(settings);
      final loaded = await store.load();
      final raw = await store.file.then((file) => file.readAsString());

      expect(raw, contains('slate'));
      expect(raw, contains('dark'));
      expect(loaded.themeMode, ThemeMode.dark);
      expect(loaded.themeProfile, CurioThemeProfile.slate);
    },
  );

  test('pageZoom defaults to 1.0', () {
    const settings = AppearanceSettings();
    expect(settings.pageZoom, 1.0);
  });

  test('pageZoom round-trips through save and load', () async {
    final temp = await Directory.systemTemp.createTemp(
      'curio_appearance_zoom_',
    );
    addTearDown(() => temp.delete(recursive: true));

    final store = AppearanceSettingsStore(directoryProvider: () async => temp);
    const settings = AppearanceSettings(pageZoom: 1.4);
    await store.save(settings);
    final loaded = await store.load();
    expect(loaded.pageZoom, 1.4);
  });

  test('missing pageZoom field on disk yields 1.0', () async {
    final temp = await Directory.systemTemp.createTemp(
      'curio_appearance_nozoom_',
    );
    addTearDown(() => temp.delete(recursive: true));

    final file = File('${temp.path}/curio-appearance.json');
    await file.writeAsString('{"themeProfile":"aurora","themeMode":"system"}');

    final store = AppearanceSettingsStore(directoryProvider: () async => temp);
    final loaded = await store.load();
    expect(loaded.pageZoom, 1.0);
  });

  test('out-of-range pageZoom value clamps to maximum 2.0', () async {
    final temp = await Directory.systemTemp.createTemp(
      'curio_appearance_clamp_',
    );
    addTearDown(() => temp.delete(recursive: true));

    final file = File('${temp.path}/curio-appearance.json');
    await file.writeAsString(
      '{"themeProfile":"aurora","themeMode":"system","pageZoom":5.0}',
    );

    final store = AppearanceSettingsStore(directoryProvider: () async => temp);
    final loaded = await store.load();
    expect(loaded.pageZoom, 2.0);
  });

  test('invalid appearance file falls back to defaults', () async {
    final temp = await Directory.systemTemp.createTemp(
      'curio_appearance_invalid_',
    );
    addTearDown(() => temp.delete(recursive: true));

    final file = File('${temp.path}/curio-appearance.json');
    await file.writeAsString('');

    final store = AppearanceSettingsStore(directoryProvider: () async => temp);
    final loaded = await store.load();
    final archived = temp.listSync().where(
      (entity) => entity.path.contains('curio-appearance.json.invalid-'),
    );

    expect(loaded.themeMode, ThemeMode.system);
    expect(loaded.themeProfile, CurioThemeProfile.aurora);
    expect(loaded.pageZoom, 1.0);
    expect(archived, isNotEmpty);
  });

  test(
    'copyWith pageZoom produces new instance with updated zoom and unchanged other fields',
    () {
      const original = AppearanceSettings(
        themeMode: ThemeMode.dark,
        themeProfile: CurioThemeProfile.slate,
        pageZoom: 1.0,
      );
      final updated = original.copyWith(pageZoom: 0.75);
      expect(updated.pageZoom, 0.75);
      expect(updated.themeMode, ThemeMode.dark);
      expect(updated.themeProfile, CurioThemeProfile.slate);
    },
  );
}
