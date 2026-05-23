import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../theme/curio_theme.dart';
import 'recoverable_store_file.dart';

final class AppearanceSettings {
  const AppearanceSettings({
    this.themeProfile = CurioThemeProfile.aurora,
    this.themeMode = ThemeMode.system,
    this.pageZoom = 1.0,
  });

  factory AppearanceSettings.fromJson(Map<String, Object?> json) {
    return AppearanceSettings(
      themeProfile: _parseThemeProfile(json['themeProfile']),
      themeMode: _parseThemeMode(json['themeMode']),
      pageZoom: _parsePageZoom(json['pageZoom']),
    );
  }

  final CurioThemeProfile themeProfile;
  final ThemeMode themeMode;
  final double pageZoom;

  AppearanceSettings copyWith({
    CurioThemeProfile? themeProfile,
    ThemeMode? themeMode,
    double? pageZoom,
  }) {
    return AppearanceSettings(
      themeProfile: themeProfile ?? this.themeProfile,
      themeMode: themeMode ?? this.themeMode,
      pageZoom: pageZoom ?? this.pageZoom,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'themeProfile': themeProfile.name,
      'themeMode': themeMode.name,
      'pageZoom': pageZoom,
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

    try {
      final raw = await settingsFile.readAsString();
      if (raw.trim().isEmpty) {
        await preserveInvalidStoreFile(settingsFile);
        return const AppearanceSettings();
      }

      final json = Map<String, Object?>.from(
        jsonDecode(raw) as Map<dynamic, dynamic>,
      );
      return AppearanceSettings.fromJson(json);
    } on Object catch (error) {
      if (!isRecoverableStoreFormatError(error)) {
        rethrow;
      }
      await preserveInvalidStoreFile(settingsFile);
      return const AppearanceSettings();
    }
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

double _parsePageZoom(Object? value) {
  if (value is num) {
    final clamped = value.toDouble().clamp(0.2, 2.0);
    return clamped;
  }
  return 1.0;
}
