import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

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
  Timer? _systemLoop;

  bool get isPlaying => _player != null || _systemLoop != null;

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

    final playedOnce = await _playSystemOnce(windowsAttention);
    _systemLoop = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_playSystemOnce(windowsAttention));
    });
    return AlarmPlaybackResult(
      started: playedOnce,
      usedCustomAudio: false,
      message: playedOnce
          ? 'alarme contínuo com áudio do sistema'
          : 'alarme contínuo iniciado sem áudio audível confirmado',
    );
  }

  Future<void> stop() async {
    final timer = _systemLoop;
    _systemLoop = null;
    timer?.cancel();

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
      final player = AudioPlayer();
      await player.setReleaseMode(ReleaseMode.loop);
      await player.play(DeviceFileSource(path), volume: 1);
      _player = player;
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

  Future<bool> _playSystemOnce(WindowsAttentionService windowsAttention) async {
    if (Platform.isWindows) {
      return windowsAttention.playAlarmFallback();
    }

    try {
      await SystemSound.play(SystemSoundType.alert);
      return true;
    } on Object {
      return false;
    }
  }
}
