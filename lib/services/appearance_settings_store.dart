import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../theme/curio_theme.dart';

final class AppearanceSettings {
  const AppearanceSettings({
    this.themeProfile = CurioThemeProfile.aurora,
    this.themeMode = ThemeMode.system,
  });

  factory AppearanceSettings.fromJson(Map<String, Object?> json) {
    return AppearanceSettings(
      themeProfile: _parseThemeProfile(json['themeProfile']),
      themeMode: _parseThemeMode(json['themeMode']),
    );
  }

  final CurioThemeProfile themeProfile;
  final ThemeMode themeMode;

  AppearanceSettings copyWith({
    CurioThemeProfile? themeProfile,
    ThemeMode? themeMode,
  }) {
    return AppearanceSettings(
      themeProfile: themeProfile ?? this.themeProfile,
      themeMode: themeMode ?? this.themeMode,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'themeProfile': themeProfile.name,
      'themeMode': themeMode.name,
    };
  }
}

final class AppearanceSettingsStore {
  AppearanceSettingsStore({Future<Directory> Function()? directoryProvider})
    : _directoryProvider =
          directoryProvider ?? (() => getApplicationSupportDirectory());

  final Future<Directory> Function() _directoryProvider;

  Future<File> get file async {
    final directory = await _directoryProvider();
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return File(p.join(directory.path, 'curio-appearance.json'));
  }

  Future<AppearanceSettings> load() async {
    final settingsFile = await file;
    if (!await settingsFile.exists()) {
      return const AppearanceSettings();
    }

    final raw = await settingsFile.readAsString();
    final json = Map<String, Object?>.from(
      jsonDecode(raw) as Map<dynamic, dynamic>,
    );
    return AppearanceSettings.fromJson(json);
  }

  Future<void> save(AppearanceSettings settings) async {
    final settingsFile = await file;
    await settingsFile.writeAsString(jsonEncode(settings.toJson()));
  }
}

CurioThemeProfile _parseThemeProfile(Object? value) {
  final name = value as String?;
  return CurioThemeProfile.values.firstWhere(
    (profile) => profile.name == name,
    orElse: () => CurioThemeProfile.aurora,
  );
}

ThemeMode _parseThemeMode(Object? value) {
  final name = value as String?;
  return ThemeMode.values.firstWhere(
    (mode) => mode.name == name,
    orElse: () => ThemeMode.system,
  );
}
