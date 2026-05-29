import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lume/sync/http_sync_adapter.dart';
import 'package:lume_core/domain/app_snapshot.dart';
import 'package:lume_core/sync/sync_pairing.dart';
import 'package:lume_sync_server/cert_fingerprint.dart';

// Self-signed fixture (CN=curio-sync-test) generated once with openssl, used to
// exercise certificate pinning end-to-end without generating a cert at runtime.
const _certPem = '''
-----BEGIN CERTIFICATE-----
MIIC4zCCAcugAwIBAgIUd2shKSH8PfCtOIGPK9RR2YLLg2wwDQYJKoZIhvcNAQEL
BQAwGjEYMBYGA1UEAwwPY3VyaW8tc3luYy10ZXN0MB4XDTI2MDUyOTAwMzQxMFoX
DTM2MDUyNjAwMzQxMFowGjEYMBYGA1UEAwwPY3VyaW8tc3luYy10ZXN0MIIBIjAN
BgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA5TuM6EA2hqa6Tl2YdQ7XlXGcI79D
38mkTvkCihJ40OykI0jA345TV1Y0vuFB6cHSLnkK9CEzkqtMgC9+A8o+hzbvrvvq
H79hYRYE7OlrQrH5CL85ACHg3MjFzG7qFPKKf3q0yTRuv+La82WC1EgN5vvxo3SR
8VUsUblXHFmiQRL1t75gI7b0CzL2GeZUQYSbujCPEBx/TkmE1tOSk/M6pzOtsyyV
C6WKFsSuLNznoD3y22PD/KwVH+s2Q8bl5zAwyeRRO1tpgUMlGH9jPDguMZGfBXk2
FheaJl3obfmn5TH67gw1he/FdRbU2hvOiZxtXKc0Q5SrzBQQ/ixzPbPKeQIDAQAB
oyEwHzAdBgNVHQ4EFgQUe6Dl37QGlbZS2sz21X8wrVFmU1YwDQYJKoZIhvcNAQEL
BQADggEBAMvl8S1rTz6F1XfaCNdEMPY4Yj9weasCD4cqZyDrN2d3vTFmoCVeFwFv
KkrCK53sIquwT9EPJE8WsZTrg1Cch4dqupuTJ2RruVLGxcu9p05rLOp8Sfv0Cm5B
5+bq1K1zmQQivJkB0QEDacjzwWjW0FbknKbna2k5EXi0ughblIG3tHTLYDvDWR89
Gx61lFPQUtW+SIOMnuE5Tj9NPbVMhHV/Q33cVnmXjPbEvN7jaORw6uBtU8Of8g2+
GYBDU1F4vsiAKZvrCiC/dRGML7YTymDF5Xwf+K4j9h/GtIKzF3AlG+B9vdbnnoFp
/YU3J29AYAehCQGSv2wlSnVRk7DsttA=
-----END CERTIFICATE-----
''';

const _keyPem = '''
-----BEGIN PRIVATE KEY-----
MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQDlO4zoQDaGprpO
XZh1DteVcZwjv0PfyaRO+QKKEnjQ7KQjSMDfjlNXVjS+4UHpwdIueQr0ITOSq0yA
L34Dyj6HNu+u++ofv2FhFgTs6WtCsfkIvzkAIeDcyMXMbuoU8op/erTJNG6/4trz
ZYLUSA3m+/GjdJHxVSxRuVccWaJBEvW3vmAjtvQLMvYZ5lRBhJu6MI8QHH9OSYTW
05KT8zqnM62zLJULpYoWxK4s3OegPfLbY8P8rBUf6zZDxuXnMDDJ5FE7W2mBQyUY
f2M8OC4xkZ8FeTYWF5omXeht+aflMfruDDWF78V1FtTaG86JnG1cpzRDlKvMFBD+
LHM9s8p5AgMBAAECggEABF4WwzNmATlwAfTlO2W6/yKZAlKvQmD0e89hbawIbUKf
pfnJjaOH5vls1oOIM/dOFTXtMCrpxqOeONsEIE0G1UtbVGQsWR/WWnkxmCn3sd+e
NRJ0+DxXrR0414+ixMoSOszltj0E1yxwANna8kclLKokN88NcMxZ+dH5h5Vq8qkW
kyobdxFdW5OWc71XvDX1PJWTQ7KG06+VuCUqngIqPQq5p5lgCrFpThMelwrN7lSC
SCZIOqvQ13WWGZz18owTsb7AJeVYl3snjEBIj+UAOpfUKY2dMO6DNDXlxfwmIQsL
9+4kngXFrIr6Fw9zqFNOguuA5FmBJV4y9O2SxS+MAQKBgQD+9gUGgSOdXIv7CYwa
H7boo0iakjDPfSkzdhFbyyhC8Duxf5GqeuB6xKtIWUS8z79bNQHXyvLDVQSs0T8x
qWknhGGa/AujUF+Kdf97C4xQWI4IOIXLt38nXZBQ6KE5pQXL+Ceg4v8Hl+vsfHVu
wWCV1YwKZ02sL9ajM3fsUzZEuQKBgQDmKrC/OFeoxSWtKHM12ZArqn1gWBp10kWd
1kH9RmCUpfWnzddm7fXazfrrMTUDFOFsMAoY1FzjOym8l8M/5D9mqOv6C1cxCojG
W3YJOuANfstCUqs7pmmtIoMa5MNtUqgUp42KWgK1dkBfitkSVK3MIw3OucC/Djpa
+O5EeJJTwQKBgG+wDBGGXrifgv6MdyA2hmSwqqxzoAg0tujBLud8Pn3cSPn/fSsm
OtHs929xE4h2pUfqF42VbPUeeDbQTxONN/BEsJE5GkwHeGLqP+mB7IyBzm5RfGL6
VixDc2XOElpzLO/mHE4BQmDsL0BgYP0Mnyfj7T3ddQwZxLenY0BWT26ZAoGBANYL
73D1IbhHF2GwE2yJ1qR1GcHGTV0y3iEJxzaWA21Z5VlXeTE0rQX9tpKQoV8rRPQK
vOkYXQXI2GiVrjM1vaxn/YP8lep6hHYLSnsM8J48QyR7otiHSxGC3e/dvMxnKP6E
T4HRcWF2BimUA4kjjLkiBE4yusgyoBxIEbVFd7dBAoGBAKGTQ1g7LzmF2UWmx5OK
xhVu9RgVSi6eFr6in0665rUOn8J2gboGkbWthkapbtwgB/cOvxgqwUvIvCFqHTG/
IO3odaopZsCXAqc6Wu0Yx/tGIiOddbmZYFyV0JeLK4+LKKXUp8LlMK9KUSMfjRe9
upgfvACWzsWrKOUoyseDiU9w
-----END PRIVATE KEY-----
''';

const _fingerprint =
    'f77bd79e1f371ba497f4fbf718db04eaee6fcaa151d6414545809ccb0745da39';

void main() {
  group('pairing code', () {
    test('round-trips origin, token and fingerprint', () {
      final pairing = SyncPairing(
        serverUrl: 'https://sync.example.test:8787',
        authToken: 'shared-secret-012345',
        certSha256: _fingerprint,
      );
      final decoded = SyncPairing.tryParse(pairing.encode());
      expect(decoded, isNotNull);
      expect(decoded!.serverUrl, 'https://sync.example.test:8787');
      expect(decoded.authToken, 'shared-secret-012345');
      expect(decoded.certSha256, _fingerprint);
    });

    test('rejects malformed input', () {
      expect(SyncPairing.tryParse('not a code'), isNull);
      expect(SyncPairing.tryParse('curio-pair.v1.@@@'), isNull);
    });

    test('normalizes fingerprints copied with colons/uppercase', () {
      expect(SyncPairing.normalizeFingerprint('F7:7B:D7:9E'), 'f77bd79e');
    });
  });

  test('server computes the certificate SHA-256 from PEM', () {
    expect(certificateSha256FromPem(_certPem), _fingerprint);
    expect(certificateSha256FromPem('no cert here'), isNull);
  });

  test('server pairing code composes into a code the app can parse', () {
    // Mirrors the server startup: fingerprint(cert) → SyncPairing → encode.
    final fingerprint = certificateSha256FromPem(_certPem);
    final code = SyncPairing(
      serverUrl: 'https://192.168.0.50:8787',
      authToken: 'shared-secret-012345',
      certSha256: fingerprint!,
    ).encode();

    final parsed = SyncPairing.tryParse(code);
    expect(parsed, isNotNull);
    expect(parsed!.serverUrl, 'https://192.168.0.50:8787');
    expect(parsed.authToken, 'shared-secret-012345');
    expect(parsed.certSha256, _fingerprint);
  });

  group('certificate pinning over TLS', () {
    late HttpServer server;
    late String baseUrl;

    setUp(() async {
      final context = SecurityContext()
        ..useCertificateChainBytes(utf8.encode(_certPem))
        ..usePrivateKeyBytes(utf8.encode(_keyPem));
      server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        context,
      );
      baseUrl = 'https://127.0.0.1:${server.port}';
      unawaited(() async {
        await for (final request in server) {
          await utf8.decodeStream(request);
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode(<String, Object?>{
              'snapshot': const AppSnapshot(
                tasks: <TaskItem>[],
                notes: <NoteItem>[],
                scheduledNotifications: [],
              ).toJson(),
            }),
          );
          await request.response.close();
        }
      }());
    });

    tearDown(() async {
      await server.close(force: true);
    });

    Future<void> sync(String pin) async {
      final adapter = HttpSyncAdapter(
        serverUrl: Uri.parse(baseUrl),
        authToken: 'shared-secret-012345',
        pinnedCertSha256: pin,
      );
      try {
        await adapter.synchronize(
          snapshot: const AppSnapshot(
            tasks: <TaskItem>[],
            notes: <NoteItem>[],
            scheduledNotifications: [],
          ),
          deviceId: 'lume-test',
        );
      } finally {
        adapter.dispose();
      }
    }

    test('accepts the self-signed cert when the pin matches', () async {
      await sync(_fingerprint); // must not throw
    });

    test('rejects when the pin does not match', () async {
      await expectLater(sync('0' * 64), throwsA(anything));
    });

    test('rejects a self-signed cert when no pin is set', () async {
      await expectLater(sync(''), throwsA(anything));
    });
  });
}
