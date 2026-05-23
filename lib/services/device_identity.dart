import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'recoverable_store_file.dart';

final class DeviceIdentityStore {
  DeviceIdentityStore({
    Future<Directory> Function()? directoryProvider,
    String Function()? idFactory,
  }) : _directoryProvider =
           directoryProvider ?? (() => getApplicationSupportDirectory()),
       _idFactory = idFactory ?? _randomDeviceId;

  final Future<Directory> Function() _directoryProvider;
  final String Function() _idFactory;

  Future<File> get file async {
    final directory = await _directoryProvider();
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return File(p.join(directory.path, 'lume-device.json'));
  }

  Future<String> load() async {
    final identityFile = await file;
    if (await identityFile.exists()) {
      try {
        final raw = await identityFile.readAsString();
        if (raw.trim().isNotEmpty) {
          final json = jsonDecode(raw) as Map<String, Object?>;
          final deviceId = json['deviceId'] as String?;
          if (deviceId != null && deviceId.isNotEmpty) {
            return deviceId;
          }
        }
      } on Object catch (error) {
        if (!isRecoverableStoreFormatError(error)) {
          rethrow;
        }
      }
      await preserveInvalidStoreFile(identityFile);
    }

    final deviceId = _idFactory();
    await identityFile.writeAsString(
      jsonEncode(<String, Object?>{
        'deviceId': deviceId,
        'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
      }),
    );
    return deviceId;
  }
}

String _randomDeviceId() {
  final random = Random.secure();
  final bytes = List<int>.generate(8, (_) => random.nextInt(256));
  final suffix = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return 'lume-${Platform.operatingSystem}-$suffix';
}
