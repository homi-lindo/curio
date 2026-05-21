import 'package:flutter/foundation.dart';

final class SyncSettingsValidator {
  const SyncSettingsValidator({this.allowInsecureHttp = kDebugMode});

  final bool allowInsecureHttp;

  String normalizeServerUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '';
    }

    final hasScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+\-.]*://').hasMatch(trimmed);
    final normalized = hasScheme
        ? trimmed
        : '${allowInsecureHttp ? 'http' : 'https'}://$trimmed';
    return normalized.endsWith('/')
        ? normalized.substring(0, normalized.length - 1)
        : normalized;
  }

  void validate({required String serverUrl, required String authToken}) {
    if (serverUrl.isEmpty) {
      return;
    }

    final Uri uri;
    try {
      uri = Uri.parse(serverUrl);
    } on FormatException {
      throw ArgumentError('URL de sync inválida.');
    }
    if (uri.scheme == 'http' && !allowInsecureHttp) {
      throw ArgumentError(
        'HTTP só é permitido em builds de debug. Use HTTPS no app empacotado.',
      );
    }
    if (!uri.hasAuthority || uri.host.trim().isEmpty) {
      throw ArgumentError('Informe o host do servidor de sync.');
    }
    if (uri.userInfo.isNotEmpty) {
      throw ArgumentError('Não inclua usuário ou senha na URL de sync.');
    }
    if ((uri.path.isNotEmpty && uri.path != '/') ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw ArgumentError(
        'Informe apenas a origem do servidor, sem caminho, query ou fragmento.',
      );
    }
    if (authToken.length < minSyncTokenLength) {
      throw ArgumentError(
        'Use um token de sync com pelo menos $minSyncTokenLength caracteres.',
      );
    }
  }
}

const minSyncTokenLength = 16;
