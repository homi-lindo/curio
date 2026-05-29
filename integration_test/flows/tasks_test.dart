// Tarefas view integration tests.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../harness/pump_app.dart';

void main() => tasksTests();

void tasksTests() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Tarefas', () {
    Future<void> openTasks(WidgetTester tester) async {
      await tester.tap(find.text('Tarefas').first, warnIfMissed: false);
      await tester.pumpAndSettle();
    }

    testWidgets('navega para Tarefas e mostra estado vazio', (tester) async {
      final harness = await pumpApp(tester);
      addTearDown(harness.dispose);

      await openTasks(tester);

      expect(find.text('Lista de tarefas'), findsOneWidget);
      expect(find.text('Nova tarefa'), findsOneWidget);
      // Sem tarefas no seed: estado vazio do filtro "Abertas".
      expect(find.textContaining('Nenhuma tarefa aberta'), findsWidgets);
    });

    testWidgets('cria uma tarefa e ela aparece na lista', (tester) async {
      final harness = await pumpApp(tester);
      addTearDown(harness.dispose);

      await openTasks(tester);

      await tester.tap(find.text('Nova tarefa'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Comprar pão');
      await tester.tap(find.text('Criar'));
      await tester.pumpAndSettle();

      expect(find.text('Comprar pão'), findsOneWidget);
      // Um checkbox por tarefa.
      expect(find.byType(Checkbox), findsOneWidget);
    });

    testWidgets('concluir a tarefa move para o filtro Feitas', (tester) async {
      final harness = await pumpApp(tester);
      addTearDown(harness.dispose);

      await openTasks(tester);

      await tester.tap(find.text('Nova tarefa'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Pagar conta');
      await tester.tap(find.text('Criar'));
      await tester.pumpAndSettle();

      // Marca como feita.
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();

      // No filtro "Abertas" some.
      expect(find.text('Pagar conta'), findsNothing);

      // No filtro "Feitas" reaparece.
      await tester.tap(find.text('Feitas'));
      await tester.pumpAndSettle();
      expect(find.text('Pagar conta'), findsOneWidget);
    });
  });
}
