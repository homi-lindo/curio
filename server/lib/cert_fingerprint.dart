import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Lowercase-hex SHA-256 fingerprint of the first certificate in [pem]
/// (the DER bytes between the BEGIN/END CERTIFICATE markers). Returns null when
/// the input has no parseable certificate. This is the value a device pins.
String? certificateSha256FromPem(String pem) {
  final match = RegExp(
    r'-----BEGIN CERTIFICATE-----([A-Za-z0-9+/=\s]+?)-----END CERTIFICATE-----',
  ).firstMatch(pem);
  if (match == null) {
    return null;
  }
  final body = match.group(1)!.replaceAll(RegExp(r'\s'), '');
  if (body.isEmpty) {
    return null;
  }
  try {
    final der = base64.decode(body);
    return sha256.convert(der).toString().toLowerCase();
  } on FormatException {
    return null;
  }
}
