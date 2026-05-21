// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $TaskRowsTable extends TaskRows with TableInfo<$TaskRowsTable, TaskRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TaskRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dueAtUtcMeta = const VerificationMeta(
    'dueAtUtc',
  );
  @override
  late final GeneratedColumn<DateTime> dueAtUtc = GeneratedColumn<DateTime>(
    'due_at_utc',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _completedAtUtcMeta = const VerificationMeta(
    'completedAtUtc',
  );
  @override
  late final GeneratedColumn<DateTime> completedAtUtc =
      GeneratedColumn<DateTime>(
        'completed_at_utc',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _reminderEnabledMeta = const VerificationMeta(
    'reminderEnabled',
  );
  @override
  late final GeneratedColumn<bool> reminderEnabled = GeneratedColumn<bool>(
    'reminder_enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("reminder_enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _sourceNoteIdMeta = const VerificationMeta(
    'sourceNoteId',
  );
  @override
  late final GeneratedColumn<String> sourceNoteId = GeneratedColumn<String>(
    'source_note_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtUtcMeta = const VerificationMeta(
    'createdAtUtc',
  );
  @override
  late final GeneratedColumn<DateTime> createdAtUtc = GeneratedColumn<DateTime>(
    'created_at_utc',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtUtcMeta = const VerificationMeta(
    'updatedAtUtc',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAtUtc = GeneratedColumn<DateTime>(
    'updated_at_utc',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    description,
    status,
    dueAtUtc,
    completedAtUtc,
    reminderEnabled,
    sourceNoteId,
    createdAtUtc,
    updatedAtUtc,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'task_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<TaskRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('due_at_utc')) {
      context.handle(
        _dueAtUtcMeta,
        dueAtUtc.isAcceptableOrUnknown(data['due_at_utc']!, _dueAtUtcMeta),
      );
    }
    if (data.containsKey('completed_at_utc')) {
      context.handle(
        _completedAtUtcMeta,
        completedAtUtc.isAcceptableOrUnknown(
          data['completed_at_utc']!,
          _completedAtUtcMeta,
        ),
      );
    }
    if (data.containsKey('reminder_enabled')) {
      context.handle(
        _reminderEnabledMeta,
        reminderEnabled.isAcceptableOrUnknown(
          data['reminder_enabled']!,
          _reminderEnabledMeta,
        ),
      );
    }
    if (data.containsKey('source_note_id')) {
      context.handle(
        _sourceNoteIdMeta,
        sourceNoteId.isAcceptableOrUnknown(
          data['source_note_id']!,
          _sourceNoteIdMeta,
        ),
      );
    }
    if (data.containsKey('created_at_utc')) {
      context.handle(
        _createdAtUtcMeta,
        createdAtUtc.isAcceptableOrUnknown(
          data['created_at_utc']!,
          _createdAtUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtUtcMeta);
    }
    if (data.containsKey('updated_at_utc')) {
      context.handle(
        _updatedAtUtcMeta,
        updatedAtUtc.isAcceptableOrUnknown(
          data['updated_at_utc']!,
          _updatedAtUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtUtcMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TaskRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TaskRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      dueAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}due_at_utc'],
      ),
      completedAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}completed_at_utc'],
      ),
      reminderEnabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}reminder_enabled'],
      )!,
      sourceNoteId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_note_id'],
      ),
      createdAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at_utc'],
      )!,
      updatedAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at_utc'],
      )!,
    );
  }

  @override
  $TaskRowsTable createAlias(String alias) {
    return $TaskRowsTable(attachedDatabase, alias);
  }
}

class TaskRow extends DataClass implements Insertable<TaskRow> {
  final String id;
  final String title;
  final String description;
  final String status;
  final DateTime? dueAtUtc;
  final DateTime? completedAtUtc;
  final bool reminderEnabled;
  final String? sourceNoteId;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;
  const TaskRow({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    this.dueAtUtc,
    this.completedAtUtc,
    required this.reminderEnabled,
    this.sourceNoteId,
    required this.createdAtUtc,
    required this.updatedAtUtc,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    map['description'] = Variable<String>(description);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || dueAtUtc != null) {
      map['due_at_utc'] = Variable<DateTime>(dueAtUtc);
    }
    if (!nullToAbsent || completedAtUtc != null) {
      map['completed_at_utc'] = Variable<DateTime>(completedAtUtc);
    }
    map['reminder_enabled'] = Variable<bool>(reminderEnabled);
    if (!nullToAbsent || sourceNoteId != null) {
      map['source_note_id'] = Variable<String>(sourceNoteId);
    }
    map['created_at_utc'] = Variable<DateTime>(createdAtUtc);
    map['updated_at_utc'] = Variable<DateTime>(updatedAtUtc);
    return map;
  }

  TaskRowsCompanion toCompanion(bool nullToAbsent) {
    return TaskRowsCompanion(
      id: Value(id),
      title: Value(title),
      description: Value(description),
      status: Value(status),
      dueAtUtc: dueAtUtc == null && nullToAbsent
          ? const Value.absent()
          : Value(dueAtUtc),
      completedAtUtc: completedAtUtc == null && nullToAbsent
          ? const Value.absent()
          : Value(completedAtUtc),
      reminderEnabled: Value(reminderEnabled),
      sourceNoteId: sourceNoteId == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceNoteId),
      createdAtUtc: Value(createdAtUtc),
      updatedAtUtc: Value(updatedAtUtc),
    );
  }

  factory TaskRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TaskRow(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      description: serializer.fromJson<String>(json['description']),
      status: serializer.fromJson<String>(json['status']),
      dueAtUtc: serializer.fromJson<DateTime?>(json['dueAtUtc']),
      completedAtUtc: serializer.fromJson<DateTime?>(json['completedAtUtc']),
      reminderEnabled: serializer.fromJson<bool>(json['reminderEnabled']),
      sourceNoteId: serializer.fromJson<String?>(json['sourceNoteId']),
      createdAtUtc: serializer.fromJson<DateTime>(json['createdAtUtc']),
      updatedAtUtc: serializer.fromJson<DateTime>(json['updatedAtUtc']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'description': serializer.toJson<String>(description),
      'status': serializer.toJson<String>(status),
      'dueAtUtc': serializer.toJson<DateTime?>(dueAtUtc),
      'completedAtUtc': serializer.toJson<DateTime?>(completedAtUtc),
      'reminderEnabled': serializer.toJson<bool>(reminderEnabled),
      'sourceNoteId': serializer.toJson<String?>(sourceNoteId),
      'createdAtUtc': serializer.toJson<DateTime>(createdAtUtc),
      'updatedAtUtc': serializer.toJson<DateTime>(updatedAtUtc),
    };
  }

  TaskRow copyWith({
    String? id,
    String? title,
    String? description,
    String? status,
    Value<DateTime?> dueAtUtc = const Value.absent(),
    Value<DateTime?> completedAtUtc = const Value.absent(),
    bool? reminderEnabled,
    Value<String?> sourceNoteId = const Value.absent(),
    DateTime? createdAtUtc,
    DateTime? updatedAtUtc,
  }) => TaskRow(
    id: id ?? this.id,
    title: title ?? this.title,
    description: description ?? this.description,
    status: status ?? this.status,
    dueAtUtc: dueAtUtc.present ? dueAtUtc.value : this.dueAtUtc,
    completedAtUtc: completedAtUtc.present
        ? completedAtUtc.value
        : this.completedAtUtc,
    reminderEnabled: reminderEnabled ?? this.reminderEnabled,
    sourceNoteId: sourceNoteId.present ? sourceNoteId.value : this.sourceNoteId,
    createdAtUtc: createdAtUtc ?? this.createdAtUtc,
    updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
  );
  TaskRow copyWithCompanion(TaskRowsCompanion data) {
    return TaskRow(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      description: data.description.present
          ? data.description.value
          : this.description,
      status: data.status.present ? data.status.value : this.status,
      dueAtUtc: data.dueAtUtc.present ? data.dueAtUtc.value : this.dueAtUtc,
      completedAtUtc: data.completedAtUtc.present
          ? data.completedAtUtc.value
          : this.completedAtUtc,
      reminderEnabled: data.reminderEnabled.present
          ? data.reminderEnabled.value
          : this.reminderEnabled,
      sourceNoteId: data.sourceNoteId.present
          ? data.sourceNoteId.value
          : this.sourceNoteId,
      createdAtUtc: data.createdAtUtc.present
          ? data.createdAtUtc.value
          : this.createdAtUtc,
      updatedAtUtc: data.updatedAtUtc.present
          ? data.updatedAtUtc.value
          : this.updatedAtUtc,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TaskRow(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('status: $status, ')
          ..write('dueAtUtc: $dueAtUtc, ')
          ..write('completedAtUtc: $completedAtUtc, ')
          ..write('reminderEnabled: $reminderEnabled, ')
          ..write('sourceNoteId: $sourceNoteId, ')
          ..write('createdAtUtc: $createdAtUtc, ')
          ..write('updatedAtUtc: $updatedAtUtc')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    description,
    status,
    dueAtUtc,
    completedAtUtc,
    reminderEnabled,
    sourceNoteId,
    createdAtUtc,
    updatedAtUtc,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TaskRow &&
          other.id == this.id &&
          other.title == this.title &&
          other.description == this.description &&
          other.status == this.status &&
          other.dueAtUtc == this.dueAtUtc &&
          other.completedAtUtc == this.completedAtUtc &&
          other.reminderEnabled == this.reminderEnabled &&
          other.sourceNoteId == this.sourceNoteId &&
          other.createdAtUtc == this.createdAtUtc &&
          other.updatedAtUtc == this.updatedAtUtc);
}

class TaskRowsCompanion extends UpdateCompanion<TaskRow> {
  final Value<String> id;
  final Value<String> title;
  final Value<String> description;
  final Value<String> status;
  final Value<DateTime?> dueAtUtc;
  final Value<DateTime?> completedAtUtc;
  final Value<bool> reminderEnabled;
  final Value<String?> sourceNoteId;
  final Value<DateTime> createdAtUtc;
  final Value<DateTime> updatedAtUtc;
  final Value<int> rowid;
  const TaskRowsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.description = const Value.absent(),
    this.status = const Value.absent(),
    this.dueAtUtc = const Value.absent(),
    this.completedAtUtc = const Value.absent(),
    this.reminderEnabled = const Value.absent(),
    this.sourceNoteId = const Value.absent(),
    this.createdAtUtc = const Value.absent(),
    this.updatedAtUtc = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TaskRowsCompanion.insert({
    required String id,
    required String title,
    this.description = const Value.absent(),
    required String status,
    this.dueAtUtc = const Value.absent(),
    this.completedAtUtc = const Value.absent(),
    this.reminderEnabled = const Value.absent(),
    this.sourceNoteId = const Value.absent(),
    required DateTime createdAtUtc,
    required DateTime updatedAtUtc,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       title = Value(title),
       status = Value(status),
       createdAtUtc = Value(createdAtUtc),
       updatedAtUtc = Value(updatedAtUtc);
  static Insertable<TaskRow> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? description,
    Expression<String>? status,
    Expression<DateTime>? dueAtUtc,
    Expression<DateTime>? completedAtUtc,
    Expression<bool>? reminderEnabled,
    Expression<String>? sourceNoteId,
    Expression<DateTime>? createdAtUtc,
    Expression<DateTime>? updatedAtUtc,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (status != null) 'status': status,
      if (dueAtUtc != null) 'due_at_utc': dueAtUtc,
      if (completedAtUtc != null) 'completed_at_utc': completedAtUtc,
      if (reminderEnabled != null) 'reminder_enabled': reminderEnabled,
      if (sourceNoteId != null) 'source_note_id': sourceNoteId,
      if (createdAtUtc != null) 'created_at_utc': createdAtUtc,
      if (updatedAtUtc != null) 'updated_at_utc': updatedAtUtc,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TaskRowsCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<String>? description,
    Value<String>? status,
    Value<DateTime?>? dueAtUtc,
    Value<DateTime?>? completedAtUtc,
    Value<bool>? reminderEnabled,
    Value<String?>? sourceNoteId,
    Value<DateTime>? createdAtUtc,
    Value<DateTime>? updatedAtUtc,
    Value<int>? rowid,
  }) {
    return TaskRowsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      status: status ?? this.status,
      dueAtUtc: dueAtUtc ?? this.dueAtUtc,
      completedAtUtc: completedAtUtc ?? this.completedAtUtc,
      reminderEnabled: reminderEnabled ?? this.reminderEnabled,
      sourceNoteId: sourceNoteId ?? this.sourceNoteId,
      createdAtUtc: createdAtUtc ?? this.createdAtUtc,
      updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (dueAtUtc.present) {
      map['due_at_utc'] = Variable<DateTime>(dueAtUtc.value);
    }
    if (completedAtUtc.present) {
      map['completed_at_utc'] = Variable<DateTime>(completedAtUtc.value);
    }
    if (reminderEnabled.present) {
      map['reminder_enabled'] = Variable<bool>(reminderEnabled.value);
    }
    if (sourceNoteId.present) {
      map['source_note_id'] = Variable<String>(sourceNoteId.value);
    }
    if (createdAtUtc.present) {
      map['created_at_utc'] = Variable<DateTime>(createdAtUtc.value);
    }
    if (updatedAtUtc.present) {
      map['updated_at_utc'] = Variable<DateTime>(updatedAtUtc.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TaskRowsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('status: $status, ')
          ..write('dueAtUtc: $dueAtUtc, ')
          ..write('completedAtUtc: $completedAtUtc, ')
          ..write('reminderEnabled: $reminderEnabled, ')
          ..write('sourceNoteId: $sourceNoteId, ')
          ..write('createdAtUtc: $createdAtUtc, ')
          ..write('updatedAtUtc: $updatedAtUtc, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $NoteRowsTable extends NoteRows with TableInfo<$NoteRowsTable, NoteRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NoteRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtUtcMeta = const VerificationMeta(
    'createdAtUtc',
  );
  @override
  late final GeneratedColumn<DateTime> createdAtUtc = GeneratedColumn<DateTime>(
    'created_at_utc',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtUtcMeta = const VerificationMeta(
    'updatedAtUtc',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAtUtc = GeneratedColumn<DateTime>(
    'updated_at_utc',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    body,
    createdAtUtc,
    updatedAtUtc,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'note_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<NoteRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    if (data.containsKey('created_at_utc')) {
      context.handle(
        _createdAtUtcMeta,
        createdAtUtc.isAcceptableOrUnknown(
          data['created_at_utc']!,
          _createdAtUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtUtcMeta);
    }
    if (data.containsKey('updated_at_utc')) {
      context.handle(
        _updatedAtUtcMeta,
        updatedAtUtc.isAcceptableOrUnknown(
          data['updated_at_utc']!,
          _updatedAtUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtUtcMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  NoteRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NoteRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
      createdAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at_utc'],
      )!,
      updatedAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at_utc'],
      )!,
    );
  }

  @override
  $NoteRowsTable createAlias(String alias) {
    return $NoteRowsTable(attachedDatabase, alias);
  }
}

class NoteRow extends DataClass implements Insertable<NoteRow> {
  final String id;
  final String title;
  final String body;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;
  const NoteRow({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAtUtc,
    required this.updatedAtUtc,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    map['body'] = Variable<String>(body);
    map['created_at_utc'] = Variable<DateTime>(createdAtUtc);
    map['updated_at_utc'] = Variable<DateTime>(updatedAtUtc);
    return map;
  }

  NoteRowsCompanion toCompanion(bool nullToAbsent) {
    return NoteRowsCompanion(
      id: Value(id),
      title: Value(title),
      body: Value(body),
      createdAtUtc: Value(createdAtUtc),
      updatedAtUtc: Value(updatedAtUtc),
    );
  }

  factory NoteRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NoteRow(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      body: serializer.fromJson<String>(json['body']),
      createdAtUtc: serializer.fromJson<DateTime>(json['createdAtUtc']),
      updatedAtUtc: serializer.fromJson<DateTime>(json['updatedAtUtc']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'body': serializer.toJson<String>(body),
      'createdAtUtc': serializer.toJson<DateTime>(createdAtUtc),
      'updatedAtUtc': serializer.toJson<DateTime>(updatedAtUtc),
    };
  }

  NoteRow copyWith({
    String? id,
    String? title,
    String? body,
    DateTime? createdAtUtc,
    DateTime? updatedAtUtc,
  }) => NoteRow(
    id: id ?? this.id,
    title: title ?? this.title,
    body: body ?? this.body,
    createdAtUtc: createdAtUtc ?? this.createdAtUtc,
    updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
  );
  NoteRow copyWithCompanion(NoteRowsCompanion data) {
    return NoteRow(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      body: data.body.present ? data.body.value : this.body,
      createdAtUtc: data.createdAtUtc.present
          ? data.createdAtUtc.value
          : this.createdAtUtc,
      updatedAtUtc: data.updatedAtUtc.present
          ? data.updatedAtUtc.value
          : this.updatedAtUtc,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NoteRow(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('body: $body, ')
          ..write('createdAtUtc: $createdAtUtc, ')
          ..write('updatedAtUtc: $updatedAtUtc')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, title, body, createdAtUtc, updatedAtUtc);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NoteRow &&
          other.id == this.id &&
          other.title == this.title &&
          other.body == this.body &&
          other.createdAtUtc == this.createdAtUtc &&
          other.updatedAtUtc == this.updatedAtUtc);
}

class NoteRowsCompanion extends UpdateCompanion<NoteRow> {
  final Value<String> id;
  final Value<String> title;
  final Value<String> body;
  final Value<DateTime> createdAtUtc;
  final Value<DateTime> updatedAtUtc;
  final Value<int> rowid;
  const NoteRowsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.body = const Value.absent(),
    this.createdAtUtc = const Value.absent(),
    this.updatedAtUtc = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NoteRowsCompanion.insert({
    required String id,
    required String title,
    required String body,
    required DateTime createdAtUtc,
    required DateTime updatedAtUtc,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       title = Value(title),
       body = Value(body),
       createdAtUtc = Value(createdAtUtc),
       updatedAtUtc = Value(updatedAtUtc);
  static Insertable<NoteRow> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? body,
    Expression<DateTime>? createdAtUtc,
    Expression<DateTime>? updatedAtUtc,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (body != null) 'body': body,
      if (createdAtUtc != null) 'created_at_utc': createdAtUtc,
      if (updatedAtUtc != null) 'updated_at_utc': updatedAtUtc,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NoteRowsCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<String>? body,
    Value<DateTime>? createdAtUtc,
    Value<DateTime>? updatedAtUtc,
    Value<int>? rowid,
  }) {
    return NoteRowsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      createdAtUtc: createdAtUtc ?? this.createdAtUtc,
      updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (createdAtUtc.present) {
      map['created_at_utc'] = Variable<DateTime>(createdAtUtc.value);
    }
    if (updatedAtUtc.present) {
      map['updated_at_utc'] = Variable<DateTime>(updatedAtUtc.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NoteRowsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('body: $body, ')
          ..write('createdAtUtc: $createdAtUtc, ')
          ..write('updatedAtUtc: $updatedAtUtc, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ScheduledNotificationRowsTable extends ScheduledNotificationRows
    with TableInfo<$ScheduledNotificationRowsTable, ScheduledNotificationRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ScheduledNotificationRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _reminderIntentIdMeta = const VerificationMeta(
    'reminderIntentId',
  );
  @override
  late final GeneratedColumn<String> reminderIntentId = GeneratedColumn<String>(
    'reminder_intent_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ownerTypeMeta = const VerificationMeta(
    'ownerType',
  );
  @override
  late final GeneratedColumn<String> ownerType = GeneratedColumn<String>(
    'owner_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _occurrenceKeyMeta = const VerificationMeta(
    'occurrenceKey',
  );
  @override
  late final GeneratedColumn<String> occurrenceKey = GeneratedColumn<String>(
    'occurrence_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _scheduledForUtcMeta = const VerificationMeta(
    'scheduledForUtc',
  );
  @override
  late final GeneratedColumn<DateTime> scheduledForUtc =
      GeneratedColumn<DateTime>(
        'scheduled_for_utc',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _scheduledTimeZoneMeta = const VerificationMeta(
    'scheduledTimeZone',
  );
  @override
  late final GeneratedColumn<String> scheduledTimeZone =
      GeneratedColumn<String>(
        'scheduled_time_zone',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant(''),
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    deviceId,
    reminderIntentId,
    ownerId,
    ownerType,
    occurrenceKey,
    scheduledForUtc,
    payload,
    scheduledTimeZone,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'scheduled_notification_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<ScheduledNotificationRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('reminder_intent_id')) {
      context.handle(
        _reminderIntentIdMeta,
        reminderIntentId.isAcceptableOrUnknown(
          data['reminder_intent_id']!,
          _reminderIntentIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_reminderIntentIdMeta);
    }
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerIdMeta);
    }
    if (data.containsKey('owner_type')) {
      context.handle(
        _ownerTypeMeta,
        ownerType.isAcceptableOrUnknown(data['owner_type']!, _ownerTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_ownerTypeMeta);
    }
    if (data.containsKey('occurrence_key')) {
      context.handle(
        _occurrenceKeyMeta,
        occurrenceKey.isAcceptableOrUnknown(
          data['occurrence_key']!,
          _occurrenceKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_occurrenceKeyMeta);
    }
    if (data.containsKey('scheduled_for_utc')) {
      context.handle(
        _scheduledForUtcMeta,
        scheduledForUtc.isAcceptableOrUnknown(
          data['scheduled_for_utc']!,
          _scheduledForUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_scheduledForUtcMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('scheduled_time_zone')) {
      context.handle(
        _scheduledTimeZoneMeta,
        scheduledTimeZone.isAcceptableOrUnknown(
          data['scheduled_time_zone']!,
          _scheduledTimeZoneMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ScheduledNotificationRow map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ScheduledNotificationRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      reminderIntentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reminder_intent_id'],
      )!,
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      )!,
      ownerType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_type'],
      )!,
      occurrenceKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}occurrence_key'],
      )!,
      scheduledForUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}scheduled_for_utc'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      scheduledTimeZone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scheduled_time_zone'],
      )!,
    );
  }

  @override
  $ScheduledNotificationRowsTable createAlias(String alias) {
    return $ScheduledNotificationRowsTable(attachedDatabase, alias);
  }
}

class ScheduledNotificationRow extends DataClass
    implements Insertable<ScheduledNotificationRow> {
  final int id;
  final String deviceId;
  final String reminderIntentId;
  final String ownerId;
  final String ownerType;
  final String occurrenceKey;
  final DateTime scheduledForUtc;
  final String payload;
  final String scheduledTimeZone;
  const ScheduledNotificationRow({
    required this.id,
    required this.deviceId,
    required this.reminderIntentId,
    required this.ownerId,
    required this.ownerType,
    required this.occurrenceKey,
    required this.scheduledForUtc,
    required this.payload,
    required this.scheduledTimeZone,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['device_id'] = Variable<String>(deviceId);
    map['reminder_intent_id'] = Variable<String>(reminderIntentId);
    map['owner_id'] = Variable<String>(ownerId);
    map['owner_type'] = Variable<String>(ownerType);
    map['occurrence_key'] = Variable<String>(occurrenceKey);
    map['scheduled_for_utc'] = Variable<DateTime>(scheduledForUtc);
    map['payload'] = Variable<String>(payload);
    map['scheduled_time_zone'] = Variable<String>(scheduledTimeZone);
    return map;
  }

  ScheduledNotificationRowsCompanion toCompanion(bool nullToAbsent) {
    return ScheduledNotificationRowsCompanion(
      id: Value(id),
      deviceId: Value(deviceId),
      reminderIntentId: Value(reminderIntentId),
      ownerId: Value(ownerId),
      ownerType: Value(ownerType),
      occurrenceKey: Value(occurrenceKey),
      scheduledForUtc: Value(scheduledForUtc),
      payload: Value(payload),
      scheduledTimeZone: Value(scheduledTimeZone),
    );
  }

  factory ScheduledNotificationRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ScheduledNotificationRow(
      id: serializer.fromJson<int>(json['id']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      reminderIntentId: serializer.fromJson<String>(json['reminderIntentId']),
      ownerId: serializer.fromJson<String>(json['ownerId']),
      ownerType: serializer.fromJson<String>(json['ownerType']),
      occurrenceKey: serializer.fromJson<String>(json['occurrenceKey']),
      scheduledForUtc: serializer.fromJson<DateTime>(json['scheduledForUtc']),
      payload: serializer.fromJson<String>(json['payload']),
      scheduledTimeZone: serializer.fromJson<String>(json['scheduledTimeZone']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'deviceId': serializer.toJson<String>(deviceId),
      'reminderIntentId': serializer.toJson<String>(reminderIntentId),
      'ownerId': serializer.toJson<String>(ownerId),
      'ownerType': serializer.toJson<String>(ownerType),
      'occurrenceKey': serializer.toJson<String>(occurrenceKey),
      'scheduledForUtc': serializer.toJson<DateTime>(scheduledForUtc),
      'payload': serializer.toJson<String>(payload),
      'scheduledTimeZone': serializer.toJson<String>(scheduledTimeZone),
    };
  }

  ScheduledNotificationRow copyWith({
    int? id,
    String? deviceId,
    String? reminderIntentId,
    String? ownerId,
    String? ownerType,
    String? occurrenceKey,
    DateTime? scheduledForUtc,
    String? payload,
    String? scheduledTimeZone,
  }) => ScheduledNotificationRow(
    id: id ?? this.id,
    deviceId: deviceId ?? this.deviceId,
    reminderIntentId: reminderIntentId ?? this.reminderIntentId,
    ownerId: ownerId ?? this.ownerId,
    ownerType: ownerType ?? this.ownerType,
    occurrenceKey: occurrenceKey ?? this.occurrenceKey,
    scheduledForUtc: scheduledForUtc ?? this.scheduledForUtc,
    payload: payload ?? this.payload,
    scheduledTimeZone: scheduledTimeZone ?? this.scheduledTimeZone,
  );
  ScheduledNotificationRow copyWithCompanion(
    ScheduledNotificationRowsCompanion data,
  ) {
    return ScheduledNotificationRow(
      id: data.id.present ? data.id.value : this.id,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      reminderIntentId: data.reminderIntentId.present
          ? data.reminderIntentId.value
          : this.reminderIntentId,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      ownerType: data.ownerType.present ? data.ownerType.value : this.ownerType,
      occurrenceKey: data.occurrenceKey.present
          ? data.occurrenceKey.value
          : this.occurrenceKey,
      scheduledForUtc: data.scheduledForUtc.present
          ? data.scheduledForUtc.value
          : this.scheduledForUtc,
      payload: data.payload.present ? data.payload.value : this.payload,
      scheduledTimeZone: data.scheduledTimeZone.present
          ? data.scheduledTimeZone.value
          : this.scheduledTimeZone,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ScheduledNotificationRow(')
          ..write('id: $id, ')
          ..write('deviceId: $deviceId, ')
          ..write('reminderIntentId: $reminderIntentId, ')
          ..write('ownerId: $ownerId, ')
          ..write('ownerType: $ownerType, ')
          ..write('occurrenceKey: $occurrenceKey, ')
          ..write('scheduledForUtc: $scheduledForUtc, ')
          ..write('payload: $payload, ')
          ..write('scheduledTimeZone: $scheduledTimeZone')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    deviceId,
    reminderIntentId,
    ownerId,
    ownerType,
    occurrenceKey,
    scheduledForUtc,
    payload,
    scheduledTimeZone,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ScheduledNotificationRow &&
          other.id == this.id &&
          other.deviceId == this.deviceId &&
          other.reminderIntentId == this.reminderIntentId &&
          other.ownerId == this.ownerId &&
          other.ownerType == this.ownerType &&
          other.occurrenceKey == this.occurrenceKey &&
          other.scheduledForUtc == this.scheduledForUtc &&
          other.payload == this.payload &&
          other.scheduledTimeZone == this.scheduledTimeZone);
}

class ScheduledNotificationRowsCompanion
    extends UpdateCompanion<ScheduledNotificationRow> {
  final Value<int> id;
  final Value<String> deviceId;
  final Value<String> reminderIntentId;
  final Value<String> ownerId;
  final Value<String> ownerType;
  final Value<String> occurrenceKey;
  final Value<DateTime> scheduledForUtc;
  final Value<String> payload;
  final Value<String> scheduledTimeZone;
  const ScheduledNotificationRowsCompanion({
    this.id = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.reminderIntentId = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.ownerType = const Value.absent(),
    this.occurrenceKey = const Value.absent(),
    this.scheduledForUtc = const Value.absent(),
    this.payload = const Value.absent(),
    this.scheduledTimeZone = const Value.absent(),
  });
  ScheduledNotificationRowsCompanion.insert({
    this.id = const Value.absent(),
    required String deviceId,
    required String reminderIntentId,
    required String ownerId,
    required String ownerType,
    required String occurrenceKey,
    required DateTime scheduledForUtc,
    required String payload,
    this.scheduledTimeZone = const Value.absent(),
  }) : deviceId = Value(deviceId),
       reminderIntentId = Value(reminderIntentId),
       ownerId = Value(ownerId),
       ownerType = Value(ownerType),
       occurrenceKey = Value(occurrenceKey),
       scheduledForUtc = Value(scheduledForUtc),
       payload = Value(payload);
  static Insertable<ScheduledNotificationRow> custom({
    Expression<int>? id,
    Expression<String>? deviceId,
    Expression<String>? reminderIntentId,
    Expression<String>? ownerId,
    Expression<String>? ownerType,
    Expression<String>? occurrenceKey,
    Expression<DateTime>? scheduledForUtc,
    Expression<String>? payload,
    Expression<String>? scheduledTimeZone,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (deviceId != null) 'device_id': deviceId,
      if (reminderIntentId != null) 'reminder_intent_id': reminderIntentId,
      if (ownerId != null) 'owner_id': ownerId,
      if (ownerType != null) 'owner_type': ownerType,
      if (occurrenceKey != null) 'occurrence_key': occurrenceKey,
      if (scheduledForUtc != null) 'scheduled_for_utc': scheduledForUtc,
      if (payload != null) 'payload': payload,
      if (scheduledTimeZone != null) 'scheduled_time_zone': scheduledTimeZone,
    });
  }

  ScheduledNotificationRowsCompanion copyWith({
    Value<int>? id,
    Value<String>? deviceId,
    Value<String>? reminderIntentId,
    Value<String>? ownerId,
    Value<String>? ownerType,
    Value<String>? occurrenceKey,
    Value<DateTime>? scheduledForUtc,
    Value<String>? payload,
    Value<String>? scheduledTimeZone,
  }) {
    return ScheduledNotificationRowsCompanion(
      id: id ?? this.id,
      deviceId: deviceId ?? this.deviceId,
      reminderIntentId: reminderIntentId ?? this.reminderIntentId,
      ownerId: ownerId ?? this.ownerId,
      ownerType: ownerType ?? this.ownerType,
      occurrenceKey: occurrenceKey ?? this.occurrenceKey,
      scheduledForUtc: scheduledForUtc ?? this.scheduledForUtc,
      payload: payload ?? this.payload,
      scheduledTimeZone: scheduledTimeZone ?? this.scheduledTimeZone,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (reminderIntentId.present) {
      map['reminder_intent_id'] = Variable<String>(reminderIntentId.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (ownerType.present) {
      map['owner_type'] = Variable<String>(ownerType.value);
    }
    if (occurrenceKey.present) {
      map['occurrence_key'] = Variable<String>(occurrenceKey.value);
    }
    if (scheduledForUtc.present) {
      map['scheduled_for_utc'] = Variable<DateTime>(scheduledForUtc.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (scheduledTimeZone.present) {
      map['scheduled_time_zone'] = Variable<String>(scheduledTimeZone.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ScheduledNotificationRowsCompanion(')
          ..write('id: $id, ')
          ..write('deviceId: $deviceId, ')
          ..write('reminderIntentId: $reminderIntentId, ')
          ..write('ownerId: $ownerId, ')
          ..write('ownerType: $ownerType, ')
          ..write('occurrenceKey: $occurrenceKey, ')
          ..write('scheduledForUtc: $scheduledForUtc, ')
          ..write('payload: $payload, ')
          ..write('scheduledTimeZone: $scheduledTimeZone')
          ..write(')'))
        .toString();
  }
}

class $DeletedRecordRowsTable extends DeletedRecordRows
    with TableInfo<$DeletedRecordRowsTable, DeletedRecordRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DeletedRecordRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _recordTypeMeta = const VerificationMeta(
    'recordType',
  );
  @override
  late final GeneratedColumn<String> recordType = GeneratedColumn<String>(
    'record_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _recordIdMeta = const VerificationMeta(
    'recordId',
  );
  @override
  late final GeneratedColumn<String> recordId = GeneratedColumn<String>(
    'record_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtUtcMeta = const VerificationMeta(
    'deletedAtUtc',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAtUtc = GeneratedColumn<DateTime>(
    'deleted_at_utc',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    recordType,
    recordId,
    deletedAtUtc,
    deviceId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'deleted_record_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<DeletedRecordRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('record_type')) {
      context.handle(
        _recordTypeMeta,
        recordType.isAcceptableOrUnknown(data['record_type']!, _recordTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_recordTypeMeta);
    }
    if (data.containsKey('record_id')) {
      context.handle(
        _recordIdMeta,
        recordId.isAcceptableOrUnknown(data['record_id']!, _recordIdMeta),
      );
    } else if (isInserting) {
      context.missing(_recordIdMeta);
    }
    if (data.containsKey('deleted_at_utc')) {
      context.handle(
        _deletedAtUtcMeta,
        deletedAtUtc.isAcceptableOrUnknown(
          data['deleted_at_utc']!,
          _deletedAtUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_deletedAtUtcMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {recordType, recordId};
  @override
  DeletedRecordRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DeletedRecordRow(
      recordType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}record_type'],
      )!,
      recordId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}record_id'],
      )!,
      deletedAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at_utc'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
    );
  }

  @override
  $DeletedRecordRowsTable createAlias(String alias) {
    return $DeletedRecordRowsTable(attachedDatabase, alias);
  }
}

class DeletedRecordRow extends DataClass
    implements Insertable<DeletedRecordRow> {
  final String recordType;
  final String recordId;
  final DateTime deletedAtUtc;
  final String deviceId;
  const DeletedRecordRow({
    required this.recordType,
    required this.recordId,
    required this.deletedAtUtc,
    required this.deviceId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['record_type'] = Variable<String>(recordType);
    map['record_id'] = Variable<String>(recordId);
    map['deleted_at_utc'] = Variable<DateTime>(deletedAtUtc);
    map['device_id'] = Variable<String>(deviceId);
    return map;
  }

  DeletedRecordRowsCompanion toCompanion(bool nullToAbsent) {
    return DeletedRecordRowsCompanion(
      recordType: Value(recordType),
      recordId: Value(recordId),
      deletedAtUtc: Value(deletedAtUtc),
      deviceId: Value(deviceId),
    );
  }

  factory DeletedRecordRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DeletedRecordRow(
      recordType: serializer.fromJson<String>(json['recordType']),
      recordId: serializer.fromJson<String>(json['recordId']),
      deletedAtUtc: serializer.fromJson<DateTime>(json['deletedAtUtc']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'recordType': serializer.toJson<String>(recordType),
      'recordId': serializer.toJson<String>(recordId),
      'deletedAtUtc': serializer.toJson<DateTime>(deletedAtUtc),
      'deviceId': serializer.toJson<String>(deviceId),
    };
  }

  DeletedRecordRow copyWith({
    String? recordType,
    String? recordId,
    DateTime? deletedAtUtc,
    String? deviceId,
  }) => DeletedRecordRow(
    recordType: recordType ?? this.recordType,
    recordId: recordId ?? this.recordId,
    deletedAtUtc: deletedAtUtc ?? this.deletedAtUtc,
    deviceId: deviceId ?? this.deviceId,
  );
  DeletedRecordRow copyWithCompanion(DeletedRecordRowsCompanion data) {
    return DeletedRecordRow(
      recordType: data.recordType.present
          ? data.recordType.value
          : this.recordType,
      recordId: data.recordId.present ? data.recordId.value : this.recordId,
      deletedAtUtc: data.deletedAtUtc.present
          ? data.deletedAtUtc.value
          : this.deletedAtUtc,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DeletedRecordRow(')
          ..write('recordType: $recordType, ')
          ..write('recordId: $recordId, ')
          ..write('deletedAtUtc: $deletedAtUtc, ')
          ..write('deviceId: $deviceId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(recordType, recordId, deletedAtUtc, deviceId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DeletedRecordRow &&
          other.recordType == this.recordType &&
          other.recordId == this.recordId &&
          other.deletedAtUtc == this.deletedAtUtc &&
          other.deviceId == this.deviceId);
}

class DeletedRecordRowsCompanion extends UpdateCompanion<DeletedRecordRow> {
  final Value<String> recordType;
  final Value<String> recordId;
  final Value<DateTime> deletedAtUtc;
  final Value<String> deviceId;
  final Value<int> rowid;
  const DeletedRecordRowsCompanion({
    this.recordType = const Value.absent(),
    this.recordId = const Value.absent(),
    this.deletedAtUtc = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DeletedRecordRowsCompanion.insert({
    required String recordType,
    required String recordId,
    required DateTime deletedAtUtc,
    required String deviceId,
    this.rowid = const Value.absent(),
  }) : recordType = Value(recordType),
       recordId = Value(recordId),
       deletedAtUtc = Value(deletedAtUtc),
       deviceId = Value(deviceId);
  static Insertable<DeletedRecordRow> custom({
    Expression<String>? recordType,
    Expression<String>? recordId,
    Expression<DateTime>? deletedAtUtc,
    Expression<String>? deviceId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (recordType != null) 'record_type': recordType,
      if (recordId != null) 'record_id': recordId,
      if (deletedAtUtc != null) 'deleted_at_utc': deletedAtUtc,
      if (deviceId != null) 'device_id': deviceId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DeletedRecordRowsCompanion copyWith({
    Value<String>? recordType,
    Value<String>? recordId,
    Value<DateTime>? deletedAtUtc,
    Value<String>? deviceId,
    Value<int>? rowid,
  }) {
    return DeletedRecordRowsCompanion(
      recordType: recordType ?? this.recordType,
      recordId: recordId ?? this.recordId,
      deletedAtUtc: deletedAtUtc ?? this.deletedAtUtc,
      deviceId: deviceId ?? this.deviceId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (recordType.present) {
      map['record_type'] = Variable<String>(recordType.value);
    }
    if (recordId.present) {
      map['record_id'] = Variable<String>(recordId.value);
    }
    if (deletedAtUtc.present) {
      map['deleted_at_utc'] = Variable<DateTime>(deletedAtUtc.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DeletedRecordRowsCompanion(')
          ..write('recordType: $recordType, ')
          ..write('recordId: $recordId, ')
          ..write('deletedAtUtc: $deletedAtUtc, ')
          ..write('deviceId: $deviceId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $TaskRowsTable taskRows = $TaskRowsTable(this);
  late final $NoteRowsTable noteRows = $NoteRowsTable(this);
  late final $ScheduledNotificationRowsTable scheduledNotificationRows =
      $ScheduledNotificationRowsTable(this);
  late final $DeletedRecordRowsTable deletedRecordRows =
      $DeletedRecordRowsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    taskRows,
    noteRows,
    scheduledNotificationRows,
    deletedRecordRows,
  ];
}

typedef $$TaskRowsTableCreateCompanionBuilder =
    TaskRowsCompanion Function({
      required String id,
      required String title,
      Value<String> description,
      required String status,
      Value<DateTime?> dueAtUtc,
      Value<DateTime?> completedAtUtc,
      Value<bool> reminderEnabled,
      Value<String?> sourceNoteId,
      required DateTime createdAtUtc,
      required DateTime updatedAtUtc,
      Value<int> rowid,
    });
typedef $$TaskRowsTableUpdateCompanionBuilder =
    TaskRowsCompanion Function({
      Value<String> id,
      Value<String> title,
      Value<String> description,
      Value<String> status,
      Value<DateTime?> dueAtUtc,
      Value<DateTime?> completedAtUtc,
      Value<bool> reminderEnabled,
      Value<String?> sourceNoteId,
      Value<DateTime> createdAtUtc,
      Value<DateTime> updatedAtUtc,
      Value<int> rowid,
    });

class $$TaskRowsTableFilterComposer
    extends Composer<_$AppDatabase, $TaskRowsTable> {
  $$TaskRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get dueAtUtc => $composableBuilder(
    column: $table.dueAtUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get completedAtUtc => $composableBuilder(
    column: $table.completedAtUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get reminderEnabled => $composableBuilder(
    column: $table.reminderEnabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceNoteId => $composableBuilder(
    column: $table.sourceNoteId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAtUtc => $composableBuilder(
    column: $table.createdAtUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAtUtc => $composableBuilder(
    column: $table.updatedAtUtc,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TaskRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $TaskRowsTable> {
  $$TaskRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get dueAtUtc => $composableBuilder(
    column: $table.dueAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get completedAtUtc => $composableBuilder(
    column: $table.completedAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get reminderEnabled => $composableBuilder(
    column: $table.reminderEnabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceNoteId => $composableBuilder(
    column: $table.sourceNoteId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAtUtc => $composableBuilder(
    column: $table.createdAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAtUtc => $composableBuilder(
    column: $table.updatedAtUtc,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TaskRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TaskRowsTable> {
  $$TaskRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<DateTime> get dueAtUtc =>
      $composableBuilder(column: $table.dueAtUtc, builder: (column) => column);

  GeneratedColumn<DateTime> get completedAtUtc => $composableBuilder(
    column: $table.completedAtUtc,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get reminderEnabled => $composableBuilder(
    column: $table.reminderEnabled,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceNoteId => $composableBuilder(
    column: $table.sourceNoteId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAtUtc => $composableBuilder(
    column: $table.createdAtUtc,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAtUtc => $composableBuilder(
    column: $table.updatedAtUtc,
    builder: (column) => column,
  );
}

class $$TaskRowsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TaskRowsTable,
          TaskRow,
          $$TaskRowsTableFilterComposer,
          $$TaskRowsTableOrderingComposer,
          $$TaskRowsTableAnnotationComposer,
          $$TaskRowsTableCreateCompanionBuilder,
          $$TaskRowsTableUpdateCompanionBuilder,
          (TaskRow, BaseReferences<_$AppDatabase, $TaskRowsTable, TaskRow>),
          TaskRow,
          PrefetchHooks Function()
        > {
  $$TaskRowsTableTableManager(_$AppDatabase db, $TaskRowsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TaskRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TaskRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TaskRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> description = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<DateTime?> dueAtUtc = const Value.absent(),
                Value<DateTime?> completedAtUtc = const Value.absent(),
                Value<bool> reminderEnabled = const Value.absent(),
                Value<String?> sourceNoteId = const Value.absent(),
                Value<DateTime> createdAtUtc = const Value.absent(),
                Value<DateTime> updatedAtUtc = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TaskRowsCompanion(
                id: id,
                title: title,
                description: description,
                status: status,
                dueAtUtc: dueAtUtc,
                completedAtUtc: completedAtUtc,
                reminderEnabled: reminderEnabled,
                sourceNoteId: sourceNoteId,
                createdAtUtc: createdAtUtc,
                updatedAtUtc: updatedAtUtc,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String title,
                Value<String> description = const Value.absent(),
                required String status,
                Value<DateTime?> dueAtUtc = const Value.absent(),
                Value<DateTime?> completedAtUtc = const Value.absent(),
                Value<bool> reminderEnabled = const Value.absent(),
                Value<String?> sourceNoteId = const Value.absent(),
                required DateTime createdAtUtc,
                required DateTime updatedAtUtc,
                Value<int> rowid = const Value.absent(),
              }) => TaskRowsCompanion.insert(
                id: id,
                title: title,
                description: description,
                status: status,
                dueAtUtc: dueAtUtc,
                completedAtUtc: completedAtUtc,
                reminderEnabled: reminderEnabled,
                sourceNoteId: sourceNoteId,
                createdAtUtc: createdAtUtc,
                updatedAtUtc: updatedAtUtc,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TaskRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TaskRowsTable,
      TaskRow,
      $$TaskRowsTableFilterComposer,
      $$TaskRowsTableOrderingComposer,
      $$TaskRowsTableAnnotationComposer,
      $$TaskRowsTableCreateCompanionBuilder,
      $$TaskRowsTableUpdateCompanionBuilder,
      (TaskRow, BaseReferences<_$AppDatabase, $TaskRowsTable, TaskRow>),
      TaskRow,
      PrefetchHooks Function()
    >;
typedef $$NoteRowsTableCreateCompanionBuilder =
    NoteRowsCompanion Function({
      required String id,
      required String title,
      required String body,
      required DateTime createdAtUtc,
      required DateTime updatedAtUtc,
      Value<int> rowid,
    });
typedef $$NoteRowsTableUpdateCompanionBuilder =
    NoteRowsCompanion Function({
      Value<String> id,
      Value<String> title,
      Value<String> body,
      Value<DateTime> createdAtUtc,
      Value<DateTime> updatedAtUtc,
      Value<int> rowid,
    });

class $$NoteRowsTableFilterComposer
    extends Composer<_$AppDatabase, $NoteRowsTable> {
  $$NoteRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAtUtc => $composableBuilder(
    column: $table.createdAtUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAtUtc => $composableBuilder(
    column: $table.updatedAtUtc,
    builder: (column) => ColumnFilters(column),
  );
}

class $$NoteRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $NoteRowsTable> {
  $$NoteRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAtUtc => $composableBuilder(
    column: $table.createdAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAtUtc => $composableBuilder(
    column: $table.updatedAtUtc,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NoteRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $NoteRowsTable> {
  $$NoteRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAtUtc => $composableBuilder(
    column: $table.createdAtUtc,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAtUtc => $composableBuilder(
    column: $table.updatedAtUtc,
    builder: (column) => column,
  );
}

class $$NoteRowsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $NoteRowsTable,
          NoteRow,
          $$NoteRowsTableFilterComposer,
          $$NoteRowsTableOrderingComposer,
          $$NoteRowsTableAnnotationComposer,
          $$NoteRowsTableCreateCompanionBuilder,
          $$NoteRowsTableUpdateCompanionBuilder,
          (NoteRow, BaseReferences<_$AppDatabase, $NoteRowsTable, NoteRow>),
          NoteRow,
          PrefetchHooks Function()
        > {
  $$NoteRowsTableTableManager(_$AppDatabase db, $NoteRowsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NoteRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NoteRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$NoteRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<DateTime> createdAtUtc = const Value.absent(),
                Value<DateTime> updatedAtUtc = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NoteRowsCompanion(
                id: id,
                title: title,
                body: body,
                createdAtUtc: createdAtUtc,
                updatedAtUtc: updatedAtUtc,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String title,
                required String body,
                required DateTime createdAtUtc,
                required DateTime updatedAtUtc,
                Value<int> rowid = const Value.absent(),
              }) => NoteRowsCompanion.insert(
                id: id,
                title: title,
                body: body,
                createdAtUtc: createdAtUtc,
                updatedAtUtc: updatedAtUtc,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$NoteRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $NoteRowsTable,
      NoteRow,
      $$NoteRowsTableFilterComposer,
      $$NoteRowsTableOrderingComposer,
      $$NoteRowsTableAnnotationComposer,
      $$NoteRowsTableCreateCompanionBuilder,
      $$NoteRowsTableUpdateCompanionBuilder,
      (NoteRow, BaseReferences<_$AppDatabase, $NoteRowsTable, NoteRow>),
      NoteRow,
      PrefetchHooks Function()
    >;
typedef $$ScheduledNotificationRowsTableCreateCompanionBuilder =
    ScheduledNotificationRowsCompanion Function({
      Value<int> id,
      required String deviceId,
      required String reminderIntentId,
      required String ownerId,
      required String ownerType,
      required String occurrenceKey,
      required DateTime scheduledForUtc,
      required String payload,
      Value<String> scheduledTimeZone,
    });
typedef $$ScheduledNotificationRowsTableUpdateCompanionBuilder =
    ScheduledNotificationRowsCompanion Function({
      Value<int> id,
      Value<String> deviceId,
      Value<String> reminderIntentId,
      Value<String> ownerId,
      Value<String> ownerType,
      Value<String> occurrenceKey,
      Value<DateTime> scheduledForUtc,
      Value<String> payload,
      Value<String> scheduledTimeZone,
    });

class $$ScheduledNotificationRowsTableFilterComposer
    extends Composer<_$AppDatabase, $ScheduledNotificationRowsTable> {
  $$ScheduledNotificationRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reminderIntentId => $composableBuilder(
    column: $table.reminderIntentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ownerType => $composableBuilder(
    column: $table.ownerType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get occurrenceKey => $composableBuilder(
    column: $table.occurrenceKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get scheduledForUtc => $composableBuilder(
    column: $table.scheduledForUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scheduledTimeZone => $composableBuilder(
    column: $table.scheduledTimeZone,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ScheduledNotificationRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $ScheduledNotificationRowsTable> {
  $$ScheduledNotificationRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reminderIntentId => $composableBuilder(
    column: $table.reminderIntentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ownerType => $composableBuilder(
    column: $table.ownerType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get occurrenceKey => $composableBuilder(
    column: $table.occurrenceKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get scheduledForUtc => $composableBuilder(
    column: $table.scheduledForUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scheduledTimeZone => $composableBuilder(
    column: $table.scheduledTimeZone,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ScheduledNotificationRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ScheduledNotificationRowsTable> {
  $$ScheduledNotificationRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get reminderIntentId => $composableBuilder(
    column: $table.reminderIntentId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);

  GeneratedColumn<String> get ownerType =>
      $composableBuilder(column: $table.ownerType, builder: (column) => column);

  GeneratedColumn<String> get occurrenceKey => $composableBuilder(
    column: $table.occurrenceKey,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get scheduledForUtc => $composableBuilder(
    column: $table.scheduledForUtc,
    builder: (column) => column,
  );

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<String> get scheduledTimeZone => $composableBuilder(
    column: $table.scheduledTimeZone,
    builder: (column) => column,
  );
}

class $$ScheduledNotificationRowsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ScheduledNotificationRowsTable,
          ScheduledNotificationRow,
          $$ScheduledNotificationRowsTableFilterComposer,
          $$ScheduledNotificationRowsTableOrderingComposer,
          $$ScheduledNotificationRowsTableAnnotationComposer,
          $$ScheduledNotificationRowsTableCreateCompanionBuilder,
          $$ScheduledNotificationRowsTableUpdateCompanionBuilder,
          (
            ScheduledNotificationRow,
            BaseReferences<
              _$AppDatabase,
              $ScheduledNotificationRowsTable,
              ScheduledNotificationRow
            >,
          ),
          ScheduledNotificationRow,
          PrefetchHooks Function()
        > {
  $$ScheduledNotificationRowsTableTableManager(
    _$AppDatabase db,
    $ScheduledNotificationRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ScheduledNotificationRowsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$ScheduledNotificationRowsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ScheduledNotificationRowsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<String> reminderIntentId = const Value.absent(),
                Value<String> ownerId = const Value.absent(),
                Value<String> ownerType = const Value.absent(),
                Value<String> occurrenceKey = const Value.absent(),
                Value<DateTime> scheduledForUtc = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<String> scheduledTimeZone = const Value.absent(),
              }) => ScheduledNotificationRowsCompanion(
                id: id,
                deviceId: deviceId,
                reminderIntentId: reminderIntentId,
                ownerId: ownerId,
                ownerType: ownerType,
                occurrenceKey: occurrenceKey,
                scheduledForUtc: scheduledForUtc,
                payload: payload,
                scheduledTimeZone: scheduledTimeZone,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String deviceId,
                required String reminderIntentId,
                required String ownerId,
                required String ownerType,
                required String occurrenceKey,
                required DateTime scheduledForUtc,
                required String payload,
                Value<String> scheduledTimeZone = const Value.absent(),
              }) => ScheduledNotificationRowsCompanion.insert(
                id: id,
                deviceId: deviceId,
                reminderIntentId: reminderIntentId,
                ownerId: ownerId,
                ownerType: ownerType,
                occurrenceKey: occurrenceKey,
                scheduledForUtc: scheduledForUtc,
                payload: payload,
                scheduledTimeZone: scheduledTimeZone,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ScheduledNotificationRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ScheduledNotificationRowsTable,
      ScheduledNotificationRow,
      $$ScheduledNotificationRowsTableFilterComposer,
      $$ScheduledNotificationRowsTableOrderingComposer,
      $$ScheduledNotificationRowsTableAnnotationComposer,
      $$ScheduledNotificationRowsTableCreateCompanionBuilder,
      $$ScheduledNotificationRowsTableUpdateCompanionBuilder,
      (
        ScheduledNotificationRow,
        BaseReferences<
          _$AppDatabase,
          $ScheduledNotificationRowsTable,
          ScheduledNotificationRow
        >,
      ),
      ScheduledNotificationRow,
      PrefetchHooks Function()
    >;
typedef $$DeletedRecordRowsTableCreateCompanionBuilder =
    DeletedRecordRowsCompanion Function({
      required String recordType,
      required String recordId,
      required DateTime deletedAtUtc,
      required String deviceId,
      Value<int> rowid,
    });
typedef $$DeletedRecordRowsTableUpdateCompanionBuilder =
    DeletedRecordRowsCompanion Function({
      Value<String> recordType,
      Value<String> recordId,
      Value<DateTime> deletedAtUtc,
      Value<String> deviceId,
      Value<int> rowid,
    });

class $$DeletedRecordRowsTableFilterComposer
    extends Composer<_$AppDatabase, $DeletedRecordRowsTable> {
  $$DeletedRecordRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get recordType => $composableBuilder(
    column: $table.recordType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recordId => $composableBuilder(
    column: $table.recordId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAtUtc => $composableBuilder(
    column: $table.deletedAtUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DeletedRecordRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $DeletedRecordRowsTable> {
  $$DeletedRecordRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get recordType => $composableBuilder(
    column: $table.recordType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recordId => $composableBuilder(
    column: $table.recordId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAtUtc => $composableBuilder(
    column: $table.deletedAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DeletedRecordRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $DeletedRecordRowsTable> {
  $$DeletedRecordRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get recordType => $composableBuilder(
    column: $table.recordType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get recordId =>
      $composableBuilder(column: $table.recordId, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAtUtc => $composableBuilder(
    column: $table.deletedAtUtc,
    builder: (column) => column,
  );

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);
}

class $$DeletedRecordRowsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DeletedRecordRowsTable,
          DeletedRecordRow,
          $$DeletedRecordRowsTableFilterComposer,
          $$DeletedRecordRowsTableOrderingComposer,
          $$DeletedRecordRowsTableAnnotationComposer,
          $$DeletedRecordRowsTableCreateCompanionBuilder,
          $$DeletedRecordRowsTableUpdateCompanionBuilder,
          (
            DeletedRecordRow,
            BaseReferences<
              _$AppDatabase,
              $DeletedRecordRowsTable,
              DeletedRecordRow
            >,
          ),
          DeletedRecordRow,
          PrefetchHooks Function()
        > {
  $$DeletedRecordRowsTableTableManager(
    _$AppDatabase db,
    $DeletedRecordRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DeletedRecordRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DeletedRecordRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DeletedRecordRowsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> recordType = const Value.absent(),
                Value<String> recordId = const Value.absent(),
                Value<DateTime> deletedAtUtc = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DeletedRecordRowsCompanion(
                recordType: recordType,
                recordId: recordId,
                deletedAtUtc: deletedAtUtc,
                deviceId: deviceId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String recordType,
                required String recordId,
                required DateTime deletedAtUtc,
                required String deviceId,
                Value<int> rowid = const Value.absent(),
              }) => DeletedRecordRowsCompanion.insert(
                recordType: recordType,
                recordId: recordId,
                deletedAtUtc: deletedAtUtc,
                deviceId: deviceId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DeletedRecordRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DeletedRecordRowsTable,
      DeletedRecordRow,
      $$DeletedRecordRowsTableFilterComposer,
      $$DeletedRecordRowsTableOrderingComposer,
      $$DeletedRecordRowsTableAnnotationComposer,
      $$DeletedRecordRowsTableCreateCompanionBuilder,
      $$DeletedRecordRowsTableUpdateCompanionBuilder,
      (
        DeletedRecordRow,
        BaseReferences<
          _$AppDatabase,
          $DeletedRecordRowsTable,
          DeletedRecordRow
        >,
      ),
      DeletedRecordRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$TaskRowsTableTableManager get taskRows =>
      $$TaskRowsTableTableManager(_db, _db.taskRows);
  $$NoteRowsTableTableManager get noteRows =>
      $$NoteRowsTableTableManager(_db, _db.noteRows);
  $$ScheduledNotificationRowsTableTableManager get scheduledNotificationRows =>
      $$ScheduledNotificationRowsTableTableManager(
        _db,
        _db.scheduledNotificationRows,
      );
  $$DeletedRecordRowsTableTableManager get deletedRecordRows =>
      $$DeletedRecordRowsTableTableManager(_db, _db.deletedRecordRows);
}
