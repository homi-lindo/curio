import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lume/services/calendar_oauth_config.dart';

void main() {
  test('runtime config selects platform-specific Google client', () {
    const config = CalendarOAuthBuildConfig(
      googleWindowsClientId: 'windows-client.apps.googleusercontent.com',
      googleAndroidClientId: 'android-client.apps.googleusercontent.com',
      microsoftClientId: '00000000-0000-0000-0000-000000000000',
      microsoftTenant: 'common',
    );

    final windows = config.forPlatform(TargetPlatform.windows);
    final android = config.forPlatform(TargetPlatform.android);

    expect(windows.google.clientId, startsWith('windows-client'));
    expect(windows.google.platformLabel, 'Windows/Desktop');
    expect(android.google.clientId, startsWith('android-client'));
    expect(android.google.platformLabel, 'Android');
    expect(windows.microsoft.redirectUri, contains('/common/'));
    expect(windows.configuredCount, 2);
  });

  test('runtime config reports missing public client IDs', () {
    const config = CalendarOAuthBuildConfig(
      googleWindowsClientId: '',
      googleAndroidClientId: '',
      microsoftClientId: '',
      microsoftTenant: '',
    );

    final runtime = config.forPlatform(TargetPlatform.windows);

    expect(runtime.hasAnyConfigured, isFalse);
    expect(runtime.google.readinessLabel, contains('aguardando'));
    expect(runtime.microsoft.maskedClientId, 'não configurado');
  });

  test('masks client IDs without hiding their provider identity', () {
    expect(
      maskOAuthClientId('1234567890abcdef.apps.googleusercontent.com'),
      '12345678...nt.com',
    );
    expect(maskOAuthClientId('abc'), 'abc...abc');
    expect(maskOAuthClientId(''), 'não configurado');
  });
}
