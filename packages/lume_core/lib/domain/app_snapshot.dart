import 'reminder.dart';

enum TaskStatus { open, done }

enum SyncRecordType { task, note }

final class TaskItem {
  const TaskItem({
    required this.id,
    required this.title,
    required this.status,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    this.description = '',
    this.dueAtUtc,
    this.completedAtUtc,
    this.reminderEnabled = false,
    this.sourceNoteId,
  });

  factory TaskItem.fromJson(Map<String, Object?> json) {
    return TaskItem(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String? ?? '',
      status: TaskStatus.values.byName(json['status'] as String),
      dueAtUtc: _optionalDate(json['dueAtUtc']),
      completedAtUtc: _optionalDate(json['completedAtUtc']),
      reminderEnabled: json['reminderEnabled'] as bool? ?? false,
      sourceNoteId: json['sourceNoteId'] as String?,
      createdAtUtc: DateTime.parse(json['createdAtUtc'] as String).toUtc(),
      updatedAtUtc: DateTime.parse(json['updatedAtUtc'] as String).toUtc(),
    );
  }

  final String id;
  final String title;
  final String description;
  final TaskStatus status;
  final DateTime? dueAtUtc;
  final DateTime? completedAtUtc;
  final bool reminderEnabled;
  final String? sourceNoteId;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;

  bool get isDone => status == TaskStatus.done;

  TaskItem copyWith({
    String? title,
    String? description,
    TaskStatus? status,
    DateTime? dueAtUtc,
    DateTime? completedAtUtc,
    bool? reminderEnabled,
    String? sourceNoteId,
    DateTime? updatedAtUtc,
    bool clearDueAt = false,
    bool clearCompletedAt = false,
    bool clearSourceNoteId = false,
  }) {
    return TaskItem(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      status: status ?? this.status,
      dueAtUtc: clearDueAt ? null : dueAtUtc ?? this.dueAtUtc,
      completedAtUtc: clearCompletedAt
          ? null
          : completedAtUtc ?? this.completedAtUtc,
      reminderEnabled: reminderEnabled ?? this.reminderEnabled,
      sourceNoteId: clearSourceNoteId
          ? null
          : sourceNoteId ?? this.sourceNoteId,
      createdAtUtc: createdAtUtc,
      updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'title': title,
      'description': description,
      'status': status.name,
      'dueAtUtc': dueAtUtc?.toUtc().toIso8601String(),
      'completedAtUtc': completedAtUtc?.toUtc().toIso8601String(),
      'reminderEnabled': reminderEnabled,
      'sourceNoteId': sourceNoteId,
      'createdAtUtc': createdAtUtc.toUtc().toIso8601String(),
      'updatedAtUtc': updatedAtUtc.toUtc().toIso8601String(),
    };
  }
}

final class NoteItem {
  const NoteItem({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAtUtc,
    required this.updatedAtUtc,
  });

  factory NoteItem.fromJson(Map<String, Object?> json) {
    return NoteItem(
      id: json['id'] as String,
      title: json['title'] as String,
      body: json['body'] as String,
      createdAtUtc: DateTime.parse(json['createdAtUtc'] as String).toUtc(),
      updatedAtUtc: DateTime.parse(json['updatedAtUtc'] as String).toUtc(),
    );
  }

  final String id;
  final String title;
  final String body;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;

  NoteItem copyWith({String? title, String? body, DateTime? updatedAtUtc}) {
    return NoteItem(
      id: id,
      title: title ?? this.title,
      body: body ?? this.body,
      createdAtUtc: createdAtUtc,
      updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'title': title,
      'body': body,
      'createdAtUtc': createdAtUtc.toUtc().toIso8601String(),
      'updatedAtUtc': updatedAtUtc.toUtc().toIso8601String(),
    };
  }
}

final class DeletedRecord {
  const DeletedRecord({
    required this.recordType,
    required this.recordId,
    required this.deletedAtUtc,
    required this.deviceId,
  });

  factory DeletedRecord.fromJson(Map<String, Object?> json) {
    return DeletedRecord(
      recordType: SyncRecordType.values.byName(json['recordType'] as String),
      recordId: json['recordId'] as String,
      deletedAtUtc: DateTime.parse(json['deletedAtUtc'] as String).toUtc(),
      deviceId: json['deviceId'] as String,
    );
  }

  final SyncRecordType recordType;
  final String recordId;
  final DateTime deletedAtUtc;
  final String deviceId;

  String get key => '${recordType.name}:$recordId';

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'recordType': recordType.name,
      'recordId': recordId,
      'deletedAtUtc': deletedAtUtc.toUtc().toIso8601String(),
      'deviceId': deviceId,
    };
  }
}

final class AppSnapshot {
  const AppSnapshot({
    required this.tasks,
    required this.notes,
    required this.scheduledNotifications,
    this.deletedRecords = const <DeletedRecord>[],
  });

  factory AppSnapshot.fromJson(Map<String, Object?> json) {
    return AppSnapshot(
      tasks: _listOfMaps(json['tasks']).map(TaskItem.fromJson).toList(),
      notes: _listOfMaps(json['notes']).map(NoteItem.fromJson).toList(),
      scheduledNotifications: _listOfMaps(
        json['scheduledNotifications'],
      ).map(ScheduledNotificationRecord.fromJson).toList(),
      deletedRecords: _listOfMaps(
        json['deletedRecords'],
      ).map(DeletedRecord.fromJson).toList(),
    );
  }

  factory AppSnapshot.seeded(DateTime nowUtc) {
    return AppSnapshot(
      tasks: const <TaskItem>[],
      notes: <NoteItem>[
        NoteItem(
          id: 'note-inbox',
          title: 'Entrada',
          body:
              '# Ideias soltas\n\n- Ajustar lembrete do pagamento\n- Separar pauta da semana\n\nCole qualquer texto aqui.',
          createdAtUtc: nowUtc,
          updatedAtUtc: nowUtc,
        ),
      ],
      scheduledNotifications: const <ScheduledNotificationRecord>[],
      deletedRecords: const <DeletedRecord>[],
    );
  }

  final List<TaskItem> tasks;
  final List<NoteItem> notes;
  final List<ScheduledNotificationRecord> scheduledNotifications;
  final List<DeletedRecord> deletedRecords;

  AppSnapshot copyWith({
    List<TaskItem>? tasks,
    List<NoteItem>? notes,
    List<ScheduledNotificationRecord>? scheduledNotifications,
    List<DeletedRecord>? deletedRecords,
  }) {
    return AppSnapshot(
      tasks: tasks ?? this.tasks,
      notes: notes ?? this.notes,
      scheduledNotifications:
          scheduledNotifications ?? this.scheduledNotifications,
      deletedRecords: deletedRecords ?? this.deletedRecords,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaVersion': 4,
      'tasks': tasks.map((task) => task.toJson()).toList(),
      'notes': notes.map((note) => note.toJson()).toList(),
      'scheduledNotifications': scheduledNotifications
          .map((record) => record.toJson())
          .toList(),
      'deletedRecords': deletedRecords
          .map((record) => record.toJson())
          .toList(),
    };
  }
}

DateTime? _optionalDate(Object? value) {
  if (value == null) {
    return null;
  }
  return DateTime.parse(value as String).toUtc();
}

List<Map<String, Object?>> _listOfMaps(Object? value) {
  if (value == null) {
    return const <Map<String, Object?>>[];
  }
  return (value as List<Object?>)
      .map((item) => Map<String, Object?>.from(item! as Map<dynamic, dynamic>))
      .toList();
}
