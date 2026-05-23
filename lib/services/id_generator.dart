import 'package:uuid/uuid.dart';

const _uuid = Uuid();

String newId(String prefix) {
  return '$prefix-${_uuid.v4()}';
}
