import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'alarm_settings_store.dart';
import 'windows_attention_service.dart';

final class AlarmPlaybackResult {
  const AlarmPlaybackResult({
    required this.started,
    required this.usedCustomAudio,
    required this.message,
  });

  final bool started;
  final bool usedCustomAudio;
  final String message;
}

final class AlarmPlaybackService {
  AudioPlayer? _player;
  StreamSubscription<void>? _completeSubscription;
  Timer? _loopWatchdog;
  Timer? _fallbackLoop;
  int _loopGeneration = 0;

  bool get isPlaying => _player != null || _fallbackLoop != null;

  Future<AlarmPlaybackResult> start(
    AlarmSettings settings, {
    WindowsAttentionService windowsAttention = const WindowsAttentionService(),
  }) async {
    await stop();

    if (settings.soundSource == AlarmSoundSource.custom &&
        settings.customAudioPath.trim().isNotEmpty) {
      final customResult = await _startCustomLoop(settings.customAudioPath);
      if (customResult.started) {
        return customResult;
      }
    }

    return _startSystemLoop(windowsAttention);
  }

  Future<void> stop() async {
    _loopGeneration++;
    _fallbackLoop?.cancel();
    _fallbackLoop = null;
    _loopWatchdog?.cancel();
    _loopWatchdog = null;
    await _completeSubscription?.cancel();
    _completeSubscription = null;

    final player = _player;
    _player = null;
    if (player != null) {
      await player.stop();
      await player.dispose();
    }
  }

  Future<AlarmPlaybackResult> _startCustomLoop(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      return const AlarmPlaybackResult(
        started: false,
        usedCustomAudio: true,
        message: 'áudio personalizado não encontrado',
      );
    }

    try {
      await _startLoopingDeviceFile(path);
      return const AlarmPlaybackResult(
        started: true,
        usedCustomAudio: true,
        message: 'alarme contínuo com áudio personalizado',
      );
    } on Object {
      return const AlarmPlaybackResult(
        started: false,
        usedCustomAudio: true,
        message: 'áudio personalizado falhou; usando sistema',
      );
    }
  }

  Future<AlarmPlaybackResult> _startSystemLoop(
    WindowsAttentionService windowsAttention,
  ) async {
    try {
      final file = await _defaultSystemAlarmFile();
      await _startLoopingDeviceFile(file.path);
      return const AlarmPlaybackResult(
        started: true,
        usedCustomAudio: false,
        message: 'alarme contínuo com áudio padrão',
      );
    } on Object {
      final fallback = Platform.isWindows
          ? _startWindowsFallbackLoop(windowsAttention)
          : false;
      return AlarmPlaybackResult(
        started: fallback,
        usedCustomAudio: false,
        message: fallback
            ? 'áudio contínuo indisponível; fallback do sistema em loop'
            : 'áudio contínuo indisponível',
      );
    }
  }

  Future<void> _startLoopingDeviceFile(String path) async {
    final player = AudioPlayer();
    final source = DeviceFileSource(path);
    final generation = ++_loopGeneration;
    _player = player;

    try {
      await player.setReleaseMode(ReleaseMode.loop);
      _completeSubscription = player.onPlayerComplete.listen((_) {
        unawaited(_restartLoopIfNeeded(player, source, generation));
      });
      _loopWatchdog = Timer.periodic(const Duration(seconds: 2), (_) {
        if (!_isCurrentLoop(player, generation)) {
          return;
        }
        if (player.state != PlayerState.playing) {
          unawaited(_restartLoopIfNeeded(player, source, generation));
        }
      });
      await player.play(source, volume: 1);
    } on Object {
      if (_player == player) {
        _player = null;
      }
      _loopWatchdog?.cancel();
      _loopWatchdog = null;
      await _completeSubscription?.cancel();
      _completeSubscription = null;
      await player.dispose();
      rethrow;
    }
  }

  Future<void> _restartLoopIfNeeded(
    AudioPlayer player,
    Source source,
    int generation,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!_isCurrentLoop(player, generation) ||
        player.state == PlayerState.playing) {
      return;
    }

    try {
      await player.seek(Duration.zero);
      if (_isCurrentLoop(player, generation)) {
        await player.resume();
      }
    } on Object {
      if (!_isCurrentLoop(player, generation)) {
        return;
      }
      try {
        await player.stop();
        if (_isCurrentLoop(player, generation)) {
          await player.play(source, volume: 1);
        }
      } on Object {
        // The next watchdog tick will try again while the alarm remains active.
      }
    }
  }

  bool _isCurrentLoop(AudioPlayer player, int generation) {
    return _player == player && _loopGeneration == generation;
  }

  bool _startWindowsFallbackLoop(WindowsAttentionService windowsAttention) {
    final firstPlay = windowsAttention.playAlarmFallback();
    if (!firstPlay) {
      return false;
    }
    _fallbackLoop?.cancel();
    _fallbackLoop = Timer.periodic(const Duration(milliseconds: 900), (_) {
      windowsAttention.playAlarmFallback();
    });
    return true;
  }

  Future<File> _defaultSystemAlarmFile() async {
    final directory = await getTemporaryDirectory();
    final file = File(
      '${directory.path}${Platform.pathSeparator}curio-alarm.wav',
    );
    final bytes = generateDefaultAlarmWav();
    if (!await file.exists() || await file.length() != bytes.length) {
      await file.writeAsBytes(bytes, flush: true);
    }
    return file;
  }
}

@visibleForTesting
Uint8List generateDefaultAlarmWav({
  int sampleRate = 44100,
  Duration duration = const Duration(seconds: 8),
}) {
  final sampleCount = (sampleRate * duration.inMilliseconds / 1000).round();
  const channels = 1;
  const bitsPerSample = 16;
  const bytesPerSample = bitsPerSample ~/ 8;
  final dataSize = sampleCount * channels * bytesPerSample;
  final bytes = Uint8List(44 + dataSize);
  final data = ByteData.sublistView(bytes);

  _writeAscii(bytes, 0, 'RIFF');
  data.setUint32(4, 36 + dataSize, Endian.little);
  _writeAscii(bytes, 8, 'WAVE');
  _writeAscii(bytes, 12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, channels, Endian.little);
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * channels * bytesPerSample, Endian.little);
  data.setUint16(32, channels * bytesPerSample, Endian.little);
  data.setUint16(34, bitsPerSample, Endian.little);
  _writeAscii(bytes, 36, 'data');
  data.setUint32(40, dataSize, Endian.little);

  for (var i = 0; i < sampleCount; i++) {
    final t = i / sampleRate;
    final cycle = t % 1.6;
    final frequency = switch (cycle) {
      < 0.32 => 880.0,
      < 0.42 => 0.0,
      < 0.74 => 660.0,
      < 0.88 => 0.0,
      < 1.20 => 1040.0,
      _ => 0.0,
    };
    final fade = _edgeFade(cycle);
    final sample = frequency == 0
        ? 0
        : (math.sin(2 * math.pi * frequency * t) * 32767 * 0.38 * fade).round();
    data.setInt16(44 + i * bytesPerSample, sample, Endian.little);
  }

  return bytes;
}

double _edgeFade(double cycle) {
  const fadeSeconds = 0.018;
  final nearestEdge = <double>[
    cycle,
    (0.32 - cycle).abs(),
    (0.42 - cycle).abs(),
    (0.74 - cycle).abs(),
    (0.88 - cycle).abs(),
    (1.20 - cycle).abs(),
    (1.60 - cycle).abs(),
  ].reduce(math.min);
  return (nearestEdge / fadeSeconds).clamp(0, 1).toDouble();
}

void _writeAscii(Uint8List bytes, int offset, String value) {
  for (var i = 0; i < value.length; i++) {
    bytes[offset + i] = value.codeUnitAt(i);
  }
}
