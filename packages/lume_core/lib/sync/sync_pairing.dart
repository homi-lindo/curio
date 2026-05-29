import 'dart:convert';

/// A self-hosted sync pairing: everything a device needs to trust and reach a
/// server — its origin, the shared token, and the SHA-256 fingerprint of the
/// server's TLS certificate (lowercase hex, no separators).
///
/// The server prints a single pairing code; pasting it into the app fills the
/// origin, token and pinned fingerprint at once. Pinning the fingerprint lets a
/// self-signed certificate be trusted securely (SSH-style trust-on-pairing)
/// without a public CA — so HTTPS works plug-and-play for a self-hosted box.
final class SyncPairing {
  const SyncPairing({
    required this.serverUrl,
    required this.authToken,
    required this.certSha256,
  });

  /// Parses a pairing code produced by [encode]. Returns null when the input is
  /// not a well-formed pairing code, so callers can fall back to manual entry.
  static SyncPairing? tryParse(String input) {
    final trimmed = input.trim();
    if (!trimmed.startsWith(_prefix)) {
      return null;
    }
    try {
      final encoded = trimmed.substring(_prefix.length);
      final decoded = utf8.decode(base64Url.decode(base64.normalize(encoded)));
      final json = jsonDecode(decoded);
      if (json is! Map) {
        return null;
      }
      final serverUrl = (json['u'] as String? ?? '').trim();
      final authToken = (json['t'] as String? ?? '').trim();
      final certSha256 = normalizeFingerprint(json['f'] as String? ?? '');
      if (serverUrl.isEmpty || authToken.isEmpty) {
        return null;
      }
      return SyncPairing(
        serverUrl: serverUrl,
        authToken: authToken,
        certSha256: certSha256,
      );
    } on Object {
      return null;
    }
  }

  /// Normalizes a fingerprint to lowercase hex with no separators (`:`, spaces),
  /// so codes copied from tools like `openssl` (which use colons) still match.
  static String normalizeFingerprint(String value) {
    return value.replaceAll(RegExp(r'[^0-9a-fA-F]'), '').toLowerCase();
  }

  final String serverUrl;
  final String authToken;
  final String certSha256;

  String encode() {
    final json = jsonEncode(<String, String>{
      'u': serverUrl,
      't': authToken,
      'f': certSha256,
    });
    return '$_prefix${base64Url.encode(utf8.encode(json))}';
  }

  static const String _prefix = 'curio-pair.v1.';
}
