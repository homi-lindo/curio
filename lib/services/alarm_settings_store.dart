import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'recoverable_store_file.dart';

const List<String> alarmAudioExtensions = <String>[
  'mp3',
  'wav',
  'm4a',
  'aac',
  'ogg',
  'flac',
  'wma',
];

const String alarmAudioExtensionsLabel = 'MP3, WAV, M4A, AAC, OGG, FLAC, WMA';

enum AlarmSoundSource { system, custom }

final class AlarmSettings {
  const AlarmSettings({
    this.soundSource = AlarmSoundSource.system,
    this.customAudioPath = '',
    this.customAudioName = '',
  });

  factory AlarmSettings.fromJson(Map<String, Object?> json) {
    return AlarmSettings(
      soundSource: _parseSoundSource(json['soundSource']),
      customAudioPath: json['customAudioPath'] as String? ?? '',
      customAudioName: json['customAudioName'] as String? ?? '',
    );
  }

  final AlarmSoundSource soundSource;
  final String customAudioPath;
  final String customAudioName;

  bool get hasCustomAudio =>
      customAudioPath.trim().isNotEmpty && customAudioName.trim().isNotEmpty;

  String get label {
    if (soundSource == AlarmSoundSource.custom && hasCustomAudio) {
      return customAudioName;
    }
    return 'Áudio do sistema';
  }

  AlarmSettings copyWith({
    AlarmSoundSource? soundSource,
    String? customAudioPath,
    String? customAudioName,
    bool clearCustomAudio = false,
  }) {
    return AlarmSettings(
      soundSource: soundSource ?? this.soundSource,
      customAudioPath: clearCustomAudio
          ? ''
          : customAudioPath ?? this.customAudioPath,
      customAudioName: clearCustomAudio
          ? ''
          : customAudioName ?? this.customAudioName,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'soundSource': soundSource.name,
      'customAudioPath': customAudioPath,
      'customAudioName': customAudioName,
    };
  }
}

final class AlarmSettingsStore {
  AlarmSettingsStore({Future<Directory> Function()? directoryProvider})
    : _directoryProvider =
          directoryProvider ?? (() => getApplicationSupportDirectory());

  final Future<Directory> Function() _directoryProvider;

  Future<File> get file async {
    final directory = await _directoryProvider();
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return File(p.join(directory.path, 'curio-alarm-settings.json'));
  }

  Future<Directory> get audioDirectory async {
    final directory = await _directoryProvider();
    final target = Directory(p.join(directory.path, 'alarm-audio'));
    if (!await target.exists()) {
      await target.create(recursive: true);
    }
    return target;
  }

  Future<AlarmSettings> load() async {
    final settingsFile = await file;
    if (!await settingsFile.exists()) {
      return const AlarmSettings();
    }

    try {
      final raw = await settingsFile.readAsString();
      if (raw.trim().isEmpty) {
        await preserveInvalidStoreFile(settingsFile);
        return const AlarmSettings();
      }

      final json = Map<String, Object?>.from(
        jsonDecode(raw) as Map<dynamic, dynamic>,
      );
      return AlarmSettings.fromJson(json);
    } on Object catch (error) {
      if (!isRecoverableStoreFormatError(error)) {
        rethrow;
      }
      await preserveInvalidStoreFile(settingsFile);
      return const AlarmSettings();
    }
  }

  Future<void> save(AlarmSettings settings) async {
    final settingsFile = await file;
    final tmp = File('${settingsFile.path}.tmp');
    await tmp.writeAsString(jsonEncode(settings.toJson()), flush: true);
    if (await settingsFile.exists()) {
      await settingsFile.delete();
    }
    await tmp.rename(settingsFile.path);
  }

  Future<AlarmSettings> installCustomAudio(
    String sourcePath, {
    AlarmSettings current = const AlarmSettings(),
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw const AlarmSettingsException('Arquivo de áudio não encontrado.');
    }

    final extension = p
        .extension(source.path)
        .replaceFirst('.', '')
        .toLowerCase();
    if (!alarmAudioExtensions.contains(extension)) {
      throw AlarmSettingsException(
        'Formato não suportado. Use $alarmAudioExtensionsLabel.',
      );
    }

    final directory = await audioDirectory;
    final sanitizedName = _sanitizeFileName(p.basename(source.path));
    final stamp = DateTime.now().toUtc().microsecondsSinceEpoch;
    final target = File(p.join(directory.path, '$stamp-$sanitizedName'));
    await source.copy(target.path);

    await _deletePreviousCustomAudio(
      current.customAudioPath,
      except: target.path,
    );

    final settings = current.copyWith(
      soundSource: AlarmSoundSource.custom,
      customAudioPath: target.path,
      customAudioName: p.basename(source.path),
    );
    await save(settings);
    return settings;
  }

  Future<AlarmSettings> clearCustomAudio(AlarmSettings current) async {
    await _deletePreviousCustomAudio(current.customAudioPath);
    final settings = current.copyWith(
      soundSource: AlarmSoundSource.system,
      clearCustomAudio: true,
    );
    await save(settings);
    return settings;
  }

  Future<void> _deletePreviousCustomAudio(String path, {String? except}) async {
    if (path.trim().isEmpty || path == except) {
      return;
    }

    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } on Object {
      // Old custom audio is disposable cache; failure must not block settings.
    }
  }
}

final class AlarmSettingsException implements Exception {
  const AlarmSettingsException(this.message);

  final String message;
}

AlarmSoundSource _parseSoundSource(Object? value) {
  final name = value as String?;
  return AlarmSoundSource.values.firstWhere(
    (source) => source.name == name,
    orElse: () => AlarmSoundSource.system,
  );
}

String _sanitizeFileName(String value) {
  final sanitized = value.replaceAll(RegExp(r'[^\w.\- ]+'), '_').trim();
  return sanitized.isEmpty ? 'audio' : sanitized;
}
