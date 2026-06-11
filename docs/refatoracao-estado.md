# Refatoração do estado: do god-file aos controllers

`lib/main.dart` concentrava todo o estado do app num único `_CurioAppState`
(~70 campos), com as views recebendo dados e callbacks por parâmetro (a
`SyncView` chegou a 50 parâmetros). Este documento registra a direção da
migração e a receita para continuar, fatia por fatia, sem big-bang.

## O que já foi feito

`lib/state/app_state_controller.dart` é a fatia fundadora: um
`ChangeNotifier` dono do **snapshot em memória**, da **fila de escrita**
(diff + fallback de replace) e da **trilha de atividade** (memória + arquivo).
O `_CurioAppState` delega para ele:

- `_snapshot` virou um par getter/setter sobre `AppStateController.snapshot`
  (o contrato dos mixins de ação não mudou);
- `_saveSnapshot` chama `controller.save` (publica síncrono, persiste
  enfileirado) e mantém só os timers de alarme, que são do widget;
- `_log` chama `controller.log`;
- um listener único no controller dispara `setState` enquanto as views ainda
  forem prop-driven.

Invariantes preservados (não os quebre nas próximas fatias):

1. **Publicação síncrona**: `snapshot` muda antes de qualquer `await` no
   caminho de save — quem leu no mesmo microtask nunca observa rollback.
2. **Caminho quente do editor**: cada tecla usa `publishSilently` (sem
   notify); rebuild por tecla é desperdício. A notificação chega no flush do
   debounce ou na próxima ação.
3. **Escrita serializada e por diff**: tudo passa pela `SnapshotWriteQueue`;
   `prime(loaded)` no boot habilita o diff.

### Fatia Tarefas (feita)

`lib/state/tasks_controller.dart` absorveu a lógica do mixin `_TaskActions`
(aposentado): criar, criar-da-nota, alternar feito, renomear, definir/limpar
data e excluir com tombstone. Entradas de diálogo/picker viram parâmetros; o
host mantém só a cola de UI (prompts, confirmação, navegação de aba) e o
`_taskFilter`, que é estado de exibição. Coberta por
`test/tasks_controller_test.dart` contra o banco real — coisa que o mixin
nunca permitiu.

Nota honesta: a `TasksView` continua prop-driven nesta fatia. Ligar a view
direto no controller só traz ganho real quando o listener-ponte global
morrer; faça essa ligação quando a view for tocada por outra razão, ou na
varredura final.

## Receita para as próximas fatias (view a view)

Ordem sugerida, da mais simples para a mais arriscada:
Quadro → Agenda → Hoje → Notas → Sync.

Para cada domínio (exemplo com Tarefas):

1. **Criar o controller de feature** em `lib/state/` (ex.:
   `tasks_controller.dart`), recebendo o `AppStateController` no construtor.
   Mover para ele os métodos do mixin correspondente
   (`main_task_actions.dart`), trocando `_snapshot`/`_saveSnapshot`/`_log`
   por `appState.snapshot`/`appState.save`/`appState.log`. Diálogos e
   SnackBars **não** entram no controller — ficam na view ou num callback.
2. **Ligar a view direto no controller**: dentro da página, envolver com
   `ListenableBuilder(listenable: appState, ...)` e ler
   `appState.snapshot.tasks` em vez de receber `tasks` por parâmetro. Os
   callbacks chamam `tasksController.toggleDone(task)` etc.
3. **Apagar do `_CurioAppState`**: o mixin da feature, os parâmetros que a
   view não recebe mais e o repasse no `build`. O `flutter analyze` aponta o
   que sobrou.
4. **Rodar a suíte** (`flutter test`) e o fluxo de integração da view.

Quando a última view migrar, o listener-ponte
(`_appState.addListener(() => _applyState(() {}))`) e o `setState` herdado
podem morrer, e o `build` do app vira uma casca de navegação.

## O que NÃO fazer

- Não adotar um framework de estado novo no meio da migração — o
  `ChangeNotifier` resolve nesta escala; reavaliar só quando a migração
  terminar.
- Não mover `TextEditingController`s para os controllers de feature; eles são
  da view.
- Não fazer o controller conhecer `BuildContext`.
