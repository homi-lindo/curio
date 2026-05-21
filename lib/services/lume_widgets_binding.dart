import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

final class LumeWidgetsBinding extends WidgetsFlutterBinding {
  static WidgetsBinding ensureInitialized() {
    try {
      return WidgetsBinding.instance;
    } on Object {
      LumeWidgetsBinding();
      return WidgetsBinding.instance;
    }
  }

  @override
  // The Windows MSIX replaces Flutter's compressed NOTICES.Z with plain text
  // so WACK does not flag it as an archive.
  // ignore: must_call_super
  void initLicenses() {
    LicenseRegistry.addLicense(_loadLicenses);
  }

  Stream<LicenseEntry> _loadLicenses() async* {
    final notices = defaultTargetPlatform == TargetPlatform.windows
        ? await rootBundle.loadString('NOTICES', cache: false)
        : await _loadCompressedNotices();
    yield LicenseEntryWithLineBreaks(<String>['third_party'], notices);
  }

  Future<String> _loadCompressedNotices() async {
    final noticeBytes = await rootBundle.load('NOTICES.Z');
    final uncompressed = gzip.decode(noticeBytes.buffer.asUint8List());
    return utf8.decode(uncompressed);
  }
}
