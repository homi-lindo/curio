import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lume/services/action_error_describer.dart';
import 'package:lume/services/local_sync_sidecar.dart';

void main() {
  const describer = ActionErrorDescriber();

  test('describes validation and sidecar errors without wrapping noise', () {
    expect(describer.describe(ArgumentError('token curto')), 'token curto');
    expect(
      describer.describe(const LocalSyncSidecarException('sidecar parado')),
      'sidecar parado',
    );
  });

  test('describes network and storage failures by category', () {
    expect(
      describer.describe(TimeoutException('slow')),
      'tempo limite excedido',
    );
    expect(
      describer.describe(const SocketException('refused')),
      'servidor indisponível',
    );
    expect(
      describer.describe(const FileSystemException('full disk', 'secret-path')),
      'armazenamento local indisponível',
    );
  });

  test('describes sync http status without leaking response bodies', () {
    expect(
      describer.describe(const HttpException('sync server 401: bad token')),
      'sync recusado: token inválido',
    );
    expect(
      describer.describe(const HttpException('sync server 413: too large')),
      'sync recusado: dados muito grandes',
    );
    expect(
      describer.describe(const HttpException('sync server 500: stack trace')),
      'sync server indisponível (500)',
    );
  });
}
