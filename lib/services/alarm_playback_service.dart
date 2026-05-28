import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'alarm_settings_store.dart';
import 'windows_attention_service.dart';

const String defaultAlarmAssetPath =
    'assets/audio/curio_canto_praia_alarm_v1.wav';

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
  Timer? _nativeLoopWatchdog;
  void Function()? _nativeStop;
  int _loopGeneration = 0;

  bool get isPlaying =>
      _player != null || _fallbackLoop != null || _nativeStop != null;

  Future<AlarmPlaybackResult> start(
    AlarmSettings settings, {
    WindowsAttentionService windowsAttention = const WindowsAttentionService(),
  }) async {
    await stop();

    if (settings.soundSource == AlarmSoundSource.custom &&
        settings.customAudioPath.trim().isNotEmpty) {
      final customResult = await _startCustomLoop(
        settings.customAudioPath,
        windowsAttention,
      );
      if (customResult.started) {
        return customResult;
      }
    }

    return _startSystemLoop(windowsAttention);
  }

  Future<void> stop() async {
    _loopGeneration++;
    final nativeStop = _nativeStop;
    _nativeStop = null;
    nativeStop?.call();
    _nativeLoopWatchdog?.cancel();
    _nativeLoopWatchdog = null;
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

  Future<AlarmPlaybackResult> _startCustomLoop(
    String path,
    WindowsAttentionService windowsAttention,
  ) async {
    final file = File(path);
    if (!await file.exists()) {
      return const AlarmPlaybackResult(
        started: false,
        usedCustomAudio: true,
        message: 'áudio personalizado não encontrado',
      );
    }

    try {
      if (_canUseNativeWindowsWav(path) &&
          _startNativeWindowsWavLoop(path, windowsAttention)) {
        return const AlarmPlaybackResult(
          started: true,
          usedCustomAudio: true,
          message: 'alarme contínuo nativo com WAV personalizado rearmado',
        );
      }
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
      if (_startNativeWindowsWavLoop(file.path, windowsAttention)) {
        return const AlarmPlaybackResult(
          started: true,
          usedCustomAudio: false,
          message: 'alarme contínuo nativo do Windows rearmado',
        );
      }
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

  bool _startNativeWindowsWavLoop(
    String path,
    WindowsAttentionService windowsAttention,
  ) {
    if (!Platform.isWindows) {
      return false;
    }
    final started = windowsAttention.playWavLoop(path);
    if (!started) {
      return false;
    }
    _nativeStop = windowsAttention.stopLoopingSound;
    final replayInterval = _nativeReplayInterval(path);
    _nativeLoopWatchdog?.cancel();
    _nativeLoopWatchdog = Timer.periodic(replayInterval, (_) {
      if (_nativeStop == null) {
        return;
      }
      windowsAttention.playWavLoop(path);
    });
    return true;
  }

  bool _canUseNativeWindowsWav(String path) {
    return Platform.isWindows && path.toLowerCase().endsWith('.wav');
  }

  Duration _nativeReplayInterval(String path) {
    final duration = _readWavDuration(path);
    if (duration == null) {
      return const Duration(seconds: 5);
    }

    final replayMs = (duration.inMilliseconds * 0.95).round();
    return Duration(milliseconds: replayMs.clamp(800, 57000));
  }

  Duration? _readWavDuration(String path) {
    try {
      final bytes = File(path).readAsBytesSync();
      if (bytes.length < 44 ||
          _ascii(bytes, 0, 4) != 'RIFF' ||
          _ascii(bytes, 8, 12) != 'WAVE') {
        return null;
      }

      var offset = 12;
      int? byteRate;
      int? dataSize;
      while (offset + 8 <= bytes.length) {
        final chunkId = _ascii(bytes, offset, offset + 4);
        final chunkSize = _uint32(bytes, offset + 4);
        final chunkData = offset + 8;
        if (chunkData + chunkSize > bytes.length) {
          break;
        }

        if (chunkId == 'fmt ' && chunkSize >= 16) {
          byteRate = _uint32(bytes, chunkData + 8);
        } else if (chunkId == 'data') {
          dataSize = chunkSize;
          break;
        }

        offset = chunkData + chunkSize + (chunkSize.isOdd ? 1 : 0);
      }

      if (byteRate == null || byteRate <= 0 || dataSize == null) {
        return null;
      }

      return Duration(milliseconds: (dataSize * 1000 / byteRate).round());
    } on Object {
      return null;
    }
  }

  Future<File> _defaultSystemAlarmFile() async {
    final directory = await getTemporaryDirectory();
    final file = File(
      '${directory.path}${Platform.pathSeparator}curio-canto-praia-alarm-v1.wav',
    );
    final bytes = await loadDefaultAlarmWavBytes();
    if (!await file.exists() || await file.length() != bytes.length) {
      await file.writeAsBytes(bytes, flush: true);
    }
    return file;
  }
}

Future<Uint8List> loadDefaultAlarmWavBytes() async {
  try {
    final data = await rootBundle.load(defaultAlarmAssetPath);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } on Object {
    return generateDefaultAlarmWav();
  }
}

Uint8List generateDefaultAlarmWav({
  int sampleRate = 22050,
  Duration duration = const Duration(minutes: 1),
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
    final beat = t % 1.0;
    final breath = 0.78 + 0.22 * math.sin(2 * math.pi * t / 12);
    final pulse = 0.32 + 0.68 * math.pow(_pulseEnvelope(beat), 1.35);
    final shimmer = 0.5 + 0.5 * math.sin(2 * math.pi * t / 20);
    final pitchDrift = 1 + 0.006 * math.sin(2 * math.pi * t / 15);
    final primary =
        math.sin(2 * math.pi * 740 * pitchDrift * t) * (0.34 + 0.10 * shimmer);
    final secondary =
        math.sin(2 * math.pi * 880 * t + 0.18 * math.sin(2 * math.pi * t / 6)) *
        0.28;
    final floor = math.sin(2 * math.pi * 370 * t) * 0.12;
    final ping =
        math.sin(2 * math.pi * 1480 * t) *
        math.exp(-beat * 10) *
        (0.22 + 0.08 * shimmer);
    final overtone = math.sin(2 * math.pi * 1110 * t) * 0.08 * breath;
    final mixed = (primary + secondary + floor + ping + overtone) * pulse;
    final sample = (mixed * 32767 * 0.62).clamp(-32767, 32767).round();
    data.setInt16(44 + i * bytesPerSample, sample, Endian.little);
  }

  return bytes;
}

double _pulseEnvelope(double beat) {
  final first = math.exp(-beat * 4.5);
  final second = beat < 0.5 ? 0.0 : math.exp(-(beat - 0.5) * 5.2) * 0.58;
  return math.max(first, second);
}

void _writeAscii(Uint8List bytes, int offset, String value) {
  for (var i = 0; i < value.length; i++) {
    bytes[offset + i] = value.codeUnitAt(i);
  }
}

String _ascii(Uint8List bytes, int start, int end) {
  return String.fromCharCodes(bytes.sublist(start, end));
}

int _uint32(Uint8List bytes, int offset) {
  return bytes[offset] |
      (bytes[offset + 1] << 8) |
      (bytes[offset + 2] << 16) |
      (bytes[offset + 3] << 24);
}
