import 'dart:math' as math;

import 'package:flutter/foundation.dart';

enum CalendarOAuthProvider { google, microsoft }

final class CalendarOAuthScopes {
  const CalendarOAuthScopes._();

  static const googleCalendarEvents =
      'https://www.googleapis.com/auth/calendar.events';

  static const microsoftUserRead = 'User.Read';
  static const microsoftCalendarsReadWrite = 'Calendars.ReadWrite';
  static const microsoftOfflineAccess = 'offline_access';
}

final class CalendarOAuthClientConfig {
  const CalendarOAuthClientConfig({
    required this.provider,
    required this.name,
    required this.platformLabel,
    required this.clientId,
    required this.redirectUri,
    required this.scopes,
    required this.registrationGuide,
  });

  final CalendarOAuthProvider provider;
  final String name;
  final String platformLabel;
  final String clientId;
  final String redirectUri;
  final List<String> scopes;
  final String registrationGuide;

  bool get isConfigured => clientId.trim().isNotEmpty;

  String get providerId {
    return switch (provider) {
      CalendarOAuthProvider.google => 'google',
      CalendarOAuthProvider.microsoft => 'microsoft',
    };
  }

  String get maskedClientId => maskOAuthClientId(clientId);

  String get readinessLabel {
    if (!isConfigured) {
      return 'aguardando Client ID público';
    }
    return 'pronto para autorização do usuário';
  }
}

final class CalendarOAuthRuntimeConfig {
  const CalendarOAuthRuntimeConfig({
    required this.google,
    required this.microsoft,
  });

  final CalendarOAuthClientConfig google;
  final CalendarOAuthClientConfig microsoft;

  int get configuredCount {
    return <CalendarOAuthClientConfig>[
      google,
      microsoft,
    ].where((client) => client.isConfigured).length;
  }

  bool get hasAnyConfigured => configuredCount > 0;
}

final class CalendarOAuthBuildConfig {
  const CalendarOAuthBuildConfig({
    required this.googleWindowsClientId,
    required this.googleAndroidClientId,
    required this.microsoftClientId,
    required this.microsoftTenant,
  });

  const CalendarOAuthBuildConfig.fromEnvironment()
    : this(
        googleWindowsClientId: const String.fromEnvironment(
          'CURIO_GOOGLE_WINDOWS_CLIENT_ID',
        ),
        googleAndroidClientId: const String.fromEnvironment(
          'CURIO_GOOGLE_ANDROID_CLIENT_ID',
        ),
        microsoftClientId: const String.fromEnvironment(
          'CURIO_MICROSOFT_CLIENT_ID',
        ),
        microsoftTenant: const String.fromEnvironment(
          'CURIO_MICROSOFT_TENANT',
          defaultValue: 'common',
        ),
      );

  final String googleWindowsClientId;
  final String googleAndroidClientId;
  final String microsoftClientId;
  final String microsoftTenant;

  CalendarOAuthRuntimeConfig forPlatform(TargetPlatform platform) {
    final googlePlatform = platform == TargetPlatform.android
        ? 'Android'
        : 'Windows/Desktop';
    final googleClientId = platform == TargetPlatform.android
        ? googleAndroidClientId
        : googleWindowsClientId;

    return CalendarOAuthRuntimeConfig(
      google: CalendarOAuthClientConfig(
        provider: CalendarOAuthProvider.google,
        name: 'Google Calendar',
        platformLabel: googlePlatform,
        clientId: googleClientId,
        redirectUri: platform == TargetPlatform.android
            ? 'app.lume.personal'
            : 'http://127.0.0.1:<porta-local>/oauth/google',
        scopes: const <String>[CalendarOAuthScopes.googleCalendarEvents],
        registrationGuide: 'docs/calendar-app-registration.md#google-cloud',
      ),
      microsoft: CalendarOAuthClientConfig(
        provider: CalendarOAuthProvider.microsoft,
        name: 'Outlook / Microsoft 365',
        platformLabel: 'Windows/Android',
        clientId: microsoftClientId,
        redirectUri: _microsoftNativeRedirectUri(microsoftTenant),
        scopes: const <String>[
          CalendarOAuthScopes.microsoftUserRead,
          CalendarOAuthScopes.microsoftCalendarsReadWrite,
          CalendarOAuthScopes.microsoftOfflineAccess,
        ],
        registrationGuide:
            'docs/calendar-app-registration.md#microsoft-entra--outlook',
      ),
    );
  }
}

String maskOAuthClientId(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return 'não configurado';
  }

  final prefixLength = math.min(8, trimmed.length);
  final suffixLength = trimmed.length > 16 ? 6 : math.min(3, trimmed.length);
  final prefix = trimmed.substring(0, prefixLength);
  final suffix = trimmed.substring(trimmed.length - suffixLength);
  return '$prefix...$suffix';
}

String _microsoftNativeRedirectUri(String tenant) {
  final normalized = tenant.trim().isEmpty ? 'common' : tenant.trim();
  return 'https://login.microsoftonline.com/$normalized/oauth2/nativeclient';
}
