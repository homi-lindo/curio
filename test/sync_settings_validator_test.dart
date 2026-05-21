import 'package:flutter_test/flutter_test.dart';
import 'package:lume/services/sync_settings_validator.dart';

void main() {
  test('normalizes server origins with release-safe default scheme', () {
    const releaseValidator = SyncSettingsValidator(allowInsecureHttp: false);
    const debugValidator = SyncSettingsValidator(allowInsecureHttp: true);

    expect(
      releaseValidator.normalizeServerUrl(' sync.example/ '),
      'https://sync.example',
    );
    expect(
      debugValidator.normalizeServerUrl('127.0.0.1:8787/'),
      'http://127.0.0.1:8787',
    );
    expect(
      releaseValidator.normalizeServerUrl('https://sync.example/'),
      'https://sync.example',
    );
  });

  test('allows local offline sync settings without token', () {
    const validator = SyncSettingsValidator(allowInsecureHttp: false);

    expect(validator.normalizeServerUrl(' '), isEmpty);
    expect(
      () => validator.validate(serverUrl: '', authToken: ''),
      returnsNormally,
    );
  });

  test('rejects unsafe or ambiguous remote sync settings', () {
    const validator = SyncSettingsValidator(allowInsecureHttp: false);

    expect(
      () => validator.validate(
        serverUrl: 'http://sync.example',
        authToken: '0123456789abcdef',
      ),
      throwsArgumentError,
    );
    expect(
      () => validator.validate(
        serverUrl: 'https://user:pass@sync.example',
        authToken: '0123456789abcdef',
      ),
      throwsArgumentError,
    );
    expect(
      () => validator.validate(
        serverUrl: 'https://sync.example/path?x=1',
        authToken: '0123456789abcdef',
      ),
      throwsArgumentError,
    );
    expect(
      () => validator.validate(
        serverUrl: 'https://sync.example',
        authToken: 'short',
      ),
      throwsArgumentError,
    );
  });

  test('accepts a remote origin with a strong token', () {
    const validator = SyncSettingsValidator(allowInsecureHttp: false);

    expect(
      () => validator.validate(
        serverUrl: 'https://sync.example',
        authToken: '0123456789abcdef',
      ),
      returnsNormally,
    );
  });
}
