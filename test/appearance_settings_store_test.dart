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
}
