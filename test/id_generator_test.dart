import 'package:flutter_test/flutter_test.dart';
import 'package:lume/services/id_generator.dart';

void main() {
  test('newId preserves the given prefix', () {
    final id = newId('note');
    expect(id, startsWith('note-'));
  });

  test('newId generates unique values across 1000 calls', () {
    const prefix = 'item';
    final ids = <String>{};
    for (var i = 0; i < 1000; i++) {
      ids.add(newId(prefix));
    }
    expect(ids.length, 1000);
  });

  test('newId with different prefixes produces correct prefix in each', () {
    for (final prefix in ['note', 'task', 'notif']) {
      final id = newId(prefix);
      expect(id, startsWith('$prefix-'));
    }
  });
}
