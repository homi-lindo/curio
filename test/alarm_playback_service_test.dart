import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lume/services/alarm_playback_service.dart';

void main() {
  test('default alarm wav is a loopable PCM file', () {
    final wav = generateDefaultAlarmWav();

    expect(ascii.decode(wav.sublist(0, 4)), 'RIFF');
    expect(ascii.decode(wav.sublist(8, 12)), 'WAVE');
    expect(ascii.decode(wav.sublist(12, 16)), 'fmt ');
    expect(ascii.decode(wav.sublist(36, 40)), 'data');
    expect(wav.length, greaterThan(44100));
  });
}
