import 'dart:async';
import 'dart:io';

import 'local_sync_sidecar.dart';

final class ActionErrorDescriber {
  const ActionErrorDescriber();

  String describe(Object error) {
    if (error is ArgumentError) {
      final message = error.message;
      return message == null ? 'entrada inválida' : message.toString();
    }
    if (error is FormatException) {
      return 'resposta inválida';
    }
    if (error is TimeoutException) {
      return 'tempo limite excedido';
    }
    if (error is LocalSyncSidecarException) {
      return error.message;
    }
    if (error is SocketException) {
      return 'servidor indisponível';
    }
    if (error is HandshakeException) {
      return 'falha TLS/HTTPS';
    }
    if (error is FileSystemException) {
      return 'armazenamento local indisponível';
    }
    if (error is HttpException) {
      return _describeHttpException(error);
    }

    return 'operação não concluída (${error.runtimeType})';
  }

  String _describeHttpException(HttpException error) {
    final status = RegExp(r'^sync server (\d{3})').firstMatch(error.message);
    final statusCode = status == null ? null : int.tryParse(status.group(1)!);
    if (statusCode == null) {
      return error.message;
    }
    if (statusCode == HttpStatus.unauthorized ||
        statusCode == HttpStatus.forbidden) {
      return 'sync recusado: token inválido';
    }
    if (statusCode == HttpStatus.requestEntityTooLarge) {
      return 'sync recusado: dados muito grandes';
    }
    if (statusCode == HttpStatus.tooManyRequests) {
      return 'sync limitado: tente novamente';
    }
    if (statusCode >= HttpStatus.internalServerError) {
      return 'sync server indisponível ($statusCode)';
    }
    return 'sync server $statusCode';
  }
}
