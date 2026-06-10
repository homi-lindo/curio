import 'package:lume_core/domain/app_snapshot.dart';

import '../services/id_generator.dart';
import '../ui/task_view_helpers.dart';
import 'app_state_controller.dart';

/// Lógica de domínio da lista de tarefas, fora do widget. Segunda fatia da
/// migração do `_CurioAppState` (receita em docs/refatoracao-estado.md):
/// herdeira do mixin `_TaskActions`, agora um objeto puro que opera sobre o
/// [AppStateController] (snapshot/save/log) sem conhecer `BuildContext`,
/// diálogos ou SnackBars.
///
/// As entradas que antes vinham de diálogos/pickers (título da tarefa, data
/// escolhida) chegam aqui como **parâmetros**: a coleta na UI continua no host
/// e na view; o controller só transforma snapshot. O `deviceId` do tombstone de
/// exclusão também é parâmetro, porque o host o carrega de forma assíncrona
/// depois de montar o estado e pode trocá-lo em runtime.
final class TasksController {
  TasksController(this._appState);

  final AppStateController _appState;

  /// Insere ou atualiza [task] preservando a ordem (novas tarefas vão para o
  /// topo; edições mantêm a posição). Sem snapshot ainda não há o que mudar.
  Future<void> _upsert(TaskItem task) async {
    final snapshot = _appState.snapshot;
    if (snapshot == null) {
      return;
    }
    final exists = snapshot.tasks.any((candidate) => candidate.id == task.id);
    final nextTasks = exists
        ? snapshot.tasks
              .map((candidate) => candidate.id == task.id ? task : candidate)
              .toList()
        : <TaskItem>[task, ...snapshot.tasks];
    await _appState.save(snapshot.copyWith(tasks: nextTasks));
  }

  /// Cria uma tarefa aberta com [title] (já validado/trimado pela camada de UI).
  Future<void> create(String title) async {
    final now = DateTime.now().toUtc();
    await _upsert(
      TaskItem(
        id: newId('task'),
        title: title,
        status: TaskStatus.open,
        createdAtUtc: now,
        updatedAtUtc: now,
      ),
    );
    _appState.log('tarefa criada');
  }

  /// Cria uma tarefa a partir de [note], copiando título e um resumo do corpo e
  /// preservando o vínculo [TaskItem.sourceNoteId] para a sincronização.
  Future<void> createFromNote(NoteItem note) async {
    final now = DateTime.now().toUtc();
    await _upsert(
      TaskItem(
        id: newId('task'),
        title: note.title,
        description: noteTaskDescription(note),
        status: TaskStatus.open,
        sourceNoteId: note.id,
        createdAtUtc: now,
        updatedAtUtc: now,
      ),
    );
    _appState.log('tarefa criada a partir da nota');
  }

  /// Alterna o estado de conclusão: ao concluir, grava `completedAtUtc`; ao
  /// reabrir, limpa-o. `updatedAtUtc` avança nos dois sentidos.
  Future<void> toggleDone(TaskItem task) async {
    final now = DateTime.now().toUtc();
    final next = task.isDone
        ? task.copyWith(
            status: TaskStatus.open,
            updatedAtUtc: now,
            clearCompletedAt: true,
          )
        : task.copyWith(
            status: TaskStatus.done,
            completedAtUtc: now,
            updatedAtUtc: now,
          );
    await _upsert(next);
  }

  /// Renomeia [task] para [title] (já validado/trimado pela camada de UI).
  Future<void> rename(TaskItem task, String title) async {
    await _upsert(
      task.copyWith(title: title, updatedAtUtc: DateTime.now().toUtc()),
    );
    _appState.log('tarefa renomeada');
  }

  /// Define a data/hora de [task]. [dueLocal] é a data **local** escolhida nos
  /// pickers da UI; a conversão para UTC fica aqui.
  Future<void> setDue(TaskItem task, DateTime dueLocal) async {
    final dueUtc = dueLocal.toUtc();
    await _upsert(
      task.copyWith(dueAtUtc: dueUtc, updatedAtUtc: DateTime.now().toUtc()),
    );
    _appState.log('data da tarefa: ${formatLocalDateTime(dueUtc)}');
  }

  /// Remove a data/hora de [task].
  Future<void> clearDue(TaskItem task) async {
    await _upsert(
      task.copyWith(clearDueAt: true, updatedAtUtc: DateTime.now().toUtc()),
    );
    _appState.log('data da tarefa removida');
  }

  /// Exclui [task] e deixa um tombstone ([DeletedRecord]) com [deviceId] para
  /// que a exclusão replique em vez de ser ressuscitada por um snapshot mais
  /// antigo de outro dispositivo. A confirmação fica na UI.
  Future<void> delete(TaskItem task, {required String deviceId}) async {
    final snapshot = _appState.snapshot;
    if (snapshot == null) {
      return;
    }

    final now = DateTime.now().toUtc();
    final next = _withDeletedRecord(
      snapshot.copyWith(
        tasks: snapshot.tasks
            .where((candidate) => candidate.id != task.id)
            .toList(),
      ),
      DeletedRecord(
        recordType: SyncRecordType.task,
        recordId: task.id,
        deletedAtUtc: now,
        deviceId: deviceId,
      ),
    );
    await _appState.save(next);
    _appState.log('tarefa excluída');
  }

  /// Faz upsert do tombstone, substituindo qualquer registro com a mesma chave
  /// (espelha o `_withDeletedRecord` do host, mantido idêntico).
  AppSnapshot _withDeletedRecord(AppSnapshot snapshot, DeletedRecord record) {
    return snapshot.copyWith(
      deletedRecords: <DeletedRecord>[
        record,
        ...snapshot.deletedRecords.where(
          (candidate) => candidate.key != record.key,
        ),
      ],
    );
  }
}
