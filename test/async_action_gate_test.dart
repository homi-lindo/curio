import 'package:flutter_test/flutter_test.dart';
import 'package:lume/services/async_action_gate.dart';

void main() {
  test('async action gate rejects concurrent entries until released', () {
    final gate = AsyncActionGate();

    expect(gate.tryEnter(), isTrue);
    expect(gate.isRunning, isTrue);
    expect(gate.tryEnter(), isFalse);

    gate.leave();

    expect(gate.isRunning, isFalse);
    expect(gate.tryEnter(), isTrue);
  });
}
