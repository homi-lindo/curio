import 'package:flutter_test/flutter_test.dart';
import 'package:lume_core/sync/serial_task_queue.dart';

void main() {
  test('executa tarefas em ordem, sem sobreposição', () async {
    final queue = SerialTaskQueue();
    final events = <String>[];

    final first = queue.run(() async {
      events.add('a:início');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      events.add('a:fim');
      return 1;
    });
    final second = queue.run(() async {
      events.add('b:início');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      events.add('b:fim');
      return 2;
    });

    expect(await first, 1);
    expect(await second, 2);
    expect(events, <String>['a:início', 'a:fim', 'b:início', 'b:fim']);
  });

  test('erro de uma tarefa não derruba a fila', () async {
    final queue = SerialTaskQueue();

    final failing = queue.run<int>(() async => throw StateError('boom'));
    final following = queue.run(() async => 42);

    await expectLater(failing, throwsStateError);
    expect(await following, 42);
  });

  test('o resultado preserva o valor de retorno da tarefa', () async {
    final queue = SerialTaskQueue();
    final value = await queue.run(() async => 'ok');
    expect(value, 'ok');
  });
}
