// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rudra_database.dart';

// ignore_for_file: type=lint
class $WorkflowSubmissionsTable extends WorkflowSubmissions
    with TableInfo<$WorkflowSubmissionsTable, WorkflowSubmission> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WorkflowSubmissionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sequenceMeta = const VerificationMeta(
    'sequence',
  );
  @override
  late final GeneratedColumn<int> sequence = GeneratedColumn<int>(
    'sequence',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _event_idMeta = const VerificationMeta(
    'event_id',
  );
  @override
  late final GeneratedColumn<String> event_id = GeneratedColumn<String>(
    'event_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _correlation_idMeta = const VerificationMeta(
    'correlation_id',
  );
  @override
  late final GeneratedColumn<String> correlation_id = GeneratedColumn<String>(
    'correlation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _scope_idMeta = const VerificationMeta(
    'scope_id',
  );
  @override
  late final GeneratedColumn<String> scope_id = GeneratedColumn<String>(
    'scope_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idempotency_keyMeta = const VerificationMeta(
    'idempotency_key',
  );
  @override
  late final GeneratedColumn<String> idempotency_key = GeneratedColumn<String>(
    'idempotency_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _event_typeMeta = const VerificationMeta(
    'event_type',
  );
  @override
  late final GeneratedColumn<String> event_type = GeneratedColumn<String>(
    'event_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payload_jsonMeta = const VerificationMeta(
    'payload_json',
  );
  @override
  late final GeneratedColumn<String> payload_json = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _processing_stateMeta = const VerificationMeta(
    'processing_state',
  );
  @override
  late final GeneratedColumn<String> processing_state = GeneratedColumn<String>(
    'processing_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
  );
  static const VerificationMeta _accepted_at_unix_msMeta =
      const VerificationMeta('accepted_at_unix_ms');
  @override
  late final GeneratedColumn<int> accepted_at_unix_ms = GeneratedColumn<int>(
    'accepted_at_unix_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    sequence,
    event_id,
    correlation_id,
    scope_id,
    idempotency_key,
    event_type,
    payload_json,
    processing_state,
    accepted_at_unix_ms,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'workflow_submissions';
  @override
  VerificationContext validateIntegrity(
    Insertable<WorkflowSubmission> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('sequence')) {
      context.handle(
        _sequenceMeta,
        sequence.isAcceptableOrUnknown(data['sequence']!, _sequenceMeta),
      );
    }
    if (data.containsKey('event_id')) {
      context.handle(
        _event_idMeta,
        event_id.isAcceptableOrUnknown(data['event_id']!, _event_idMeta),
      );
    } else if (isInserting) {
      context.missing(_event_idMeta);
    }
    if (data.containsKey('correlation_id')) {
      context.handle(
        _correlation_idMeta,
        correlation_id.isAcceptableOrUnknown(
          data['correlation_id']!,
          _correlation_idMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_correlation_idMeta);
    }
    if (data.containsKey('scope_id')) {
      context.handle(
        _scope_idMeta,
        scope_id.isAcceptableOrUnknown(data['scope_id']!, _scope_idMeta),
      );
    } else if (isInserting) {
      context.missing(_scope_idMeta);
    }
    if (data.containsKey('idempotency_key')) {
      context.handle(
        _idempotency_keyMeta,
        idempotency_key.isAcceptableOrUnknown(
          data['idempotency_key']!,
          _idempotency_keyMeta,
        ),
      );
    }
    if (data.containsKey('event_type')) {
      context.handle(
        _event_typeMeta,
        event_type.isAcceptableOrUnknown(data['event_type']!, _event_typeMeta),
      );
    } else if (isInserting) {
      context.missing(_event_typeMeta);
    }
    if (data.containsKey('payload_json')) {
      context.handle(
        _payload_jsonMeta,
        payload_json.isAcceptableOrUnknown(
          data['payload_json']!,
          _payload_jsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payload_jsonMeta);
    }
    if (data.containsKey('processing_state')) {
      context.handle(
        _processing_stateMeta,
        processing_state.isAcceptableOrUnknown(
          data['processing_state']!,
          _processing_stateMeta,
        ),
      );
    }
    if (data.containsKey('accepted_at_unix_ms')) {
      context.handle(
        _accepted_at_unix_msMeta,
        accepted_at_unix_ms.isAcceptableOrUnknown(
          data['accepted_at_unix_ms']!,
          _accepted_at_unix_msMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_accepted_at_unix_msMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sequence};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {scope_id, idempotency_key},
  ];
  @override
  WorkflowSubmission map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WorkflowSubmission(
      sequence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sequence'],
      )!,
      event_id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_id'],
      )!,
      correlation_id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}correlation_id'],
      )!,
      scope_id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scope_id'],
      )!,
      idempotency_key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}idempotency_key'],
      ),
      event_type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_type'],
      )!,
      payload_json: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      )!,
      processing_state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}processing_state'],
      )!,
      accepted_at_unix_ms: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}accepted_at_unix_ms'],
      )!,
    );
  }

  @override
  $WorkflowSubmissionsTable createAlias(String alias) {
    return $WorkflowSubmissionsTable(attachedDatabase, alias);
  }

  @override
  bool get isStrict => true;
}

class WorkflowSubmission extends DataClass
    implements Insertable<WorkflowSubmission> {
  /// Monotonically increasing database-local submission position.
  final int sequence;

  /// Stable identity of the accepted event.
  final String event_id;

  /// Identifier shared with future processing outcomes.
  final String correlation_id;

  /// Trusted submission scope, not frontend-supplied authority.
  final String scope_id;

  /// Optional identity of a logical retry.
  final String? idempotency_key;

  /// Stable typed event identifier.
  final String event_type;

  /// Serialized immutable command payload.
  final String payload_json;

  /// Processing obligation, initially pending.
  final String processing_state;

  /// UTC acceptance timestamp in Unix milliseconds.
  final int accepted_at_unix_ms;
  const WorkflowSubmission({
    required this.sequence,
    required this.event_id,
    required this.correlation_id,
    required this.scope_id,
    this.idempotency_key,
    required this.event_type,
    required this.payload_json,
    required this.processing_state,
    required this.accepted_at_unix_ms,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['sequence'] = Variable<int>(sequence);
    map['event_id'] = Variable<String>(event_id);
    map['correlation_id'] = Variable<String>(correlation_id);
    map['scope_id'] = Variable<String>(scope_id);
    if (!nullToAbsent || idempotency_key != null) {
      map['idempotency_key'] = Variable<String>(idempotency_key);
    }
    map['event_type'] = Variable<String>(event_type);
    map['payload_json'] = Variable<String>(payload_json);
    map['processing_state'] = Variable<String>(processing_state);
    map['accepted_at_unix_ms'] = Variable<int>(accepted_at_unix_ms);
    return map;
  }

  WorkflowSubmissionsCompanion toCompanion(bool nullToAbsent) {
    return WorkflowSubmissionsCompanion(
      sequence: Value(sequence),
      event_id: Value(event_id),
      correlation_id: Value(correlation_id),
      scope_id: Value(scope_id),
      idempotency_key: idempotency_key == null && nullToAbsent
          ? const Value.absent()
          : Value(idempotency_key),
      event_type: Value(event_type),
      payload_json: Value(payload_json),
      processing_state: Value(processing_state),
      accepted_at_unix_ms: Value(accepted_at_unix_ms),
    );
  }

  factory WorkflowSubmission.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WorkflowSubmission(
      sequence: serializer.fromJson<int>(json['sequence']),
      event_id: serializer.fromJson<String>(json['event_id']),
      correlation_id: serializer.fromJson<String>(json['correlation_id']),
      scope_id: serializer.fromJson<String>(json['scope_id']),
      idempotency_key: serializer.fromJson<String?>(json['idempotency_key']),
      event_type: serializer.fromJson<String>(json['event_type']),
      payload_json: serializer.fromJson<String>(json['payload_json']),
      processing_state: serializer.fromJson<String>(json['processing_state']),
      accepted_at_unix_ms: serializer.fromJson<int>(
        json['accepted_at_unix_ms'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sequence': serializer.toJson<int>(sequence),
      'event_id': serializer.toJson<String>(event_id),
      'correlation_id': serializer.toJson<String>(correlation_id),
      'scope_id': serializer.toJson<String>(scope_id),
      'idempotency_key': serializer.toJson<String?>(idempotency_key),
      'event_type': serializer.toJson<String>(event_type),
      'payload_json': serializer.toJson<String>(payload_json),
      'processing_state': serializer.toJson<String>(processing_state),
      'accepted_at_unix_ms': serializer.toJson<int>(accepted_at_unix_ms),
    };
  }

  WorkflowSubmission copyWith({
    int? sequence,
    String? event_id,
    String? correlation_id,
    String? scope_id,
    Value<String?> idempotency_key = const Value.absent(),
    String? event_type,
    String? payload_json,
    String? processing_state,
    int? accepted_at_unix_ms,
  }) => WorkflowSubmission(
    sequence: sequence ?? this.sequence,
    event_id: event_id ?? this.event_id,
    correlation_id: correlation_id ?? this.correlation_id,
    scope_id: scope_id ?? this.scope_id,
    idempotency_key: idempotency_key.present
        ? idempotency_key.value
        : this.idempotency_key,
    event_type: event_type ?? this.event_type,
    payload_json: payload_json ?? this.payload_json,
    processing_state: processing_state ?? this.processing_state,
    accepted_at_unix_ms: accepted_at_unix_ms ?? this.accepted_at_unix_ms,
  );
  WorkflowSubmission copyWithCompanion(WorkflowSubmissionsCompanion data) {
    return WorkflowSubmission(
      sequence: data.sequence.present ? data.sequence.value : this.sequence,
      event_id: data.event_id.present ? data.event_id.value : this.event_id,
      correlation_id: data.correlation_id.present
          ? data.correlation_id.value
          : this.correlation_id,
      scope_id: data.scope_id.present ? data.scope_id.value : this.scope_id,
      idempotency_key: data.idempotency_key.present
          ? data.idempotency_key.value
          : this.idempotency_key,
      event_type: data.event_type.present
          ? data.event_type.value
          : this.event_type,
      payload_json: data.payload_json.present
          ? data.payload_json.value
          : this.payload_json,
      processing_state: data.processing_state.present
          ? data.processing_state.value
          : this.processing_state,
      accepted_at_unix_ms: data.accepted_at_unix_ms.present
          ? data.accepted_at_unix_ms.value
          : this.accepted_at_unix_ms,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WorkflowSubmission(')
          ..write('sequence: $sequence, ')
          ..write('event_id: $event_id, ')
          ..write('correlation_id: $correlation_id, ')
          ..write('scope_id: $scope_id, ')
          ..write('idempotency_key: $idempotency_key, ')
          ..write('event_type: $event_type, ')
          ..write('payload_json: $payload_json, ')
          ..write('processing_state: $processing_state, ')
          ..write('accepted_at_unix_ms: $accepted_at_unix_ms')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    sequence,
    event_id,
    correlation_id,
    scope_id,
    idempotency_key,
    event_type,
    payload_json,
    processing_state,
    accepted_at_unix_ms,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WorkflowSubmission &&
          other.sequence == this.sequence &&
          other.event_id == this.event_id &&
          other.correlation_id == this.correlation_id &&
          other.scope_id == this.scope_id &&
          other.idempotency_key == this.idempotency_key &&
          other.event_type == this.event_type &&
          other.payload_json == this.payload_json &&
          other.processing_state == this.processing_state &&
          other.accepted_at_unix_ms == this.accepted_at_unix_ms);
}

class WorkflowSubmissionsCompanion extends UpdateCompanion<WorkflowSubmission> {
  final Value<int> sequence;
  final Value<String> event_id;
  final Value<String> correlation_id;
  final Value<String> scope_id;
  final Value<String?> idempotency_key;
  final Value<String> event_type;
  final Value<String> payload_json;
  final Value<String> processing_state;
  final Value<int> accepted_at_unix_ms;
  const WorkflowSubmissionsCompanion({
    this.sequence = const Value.absent(),
    this.event_id = const Value.absent(),
    this.correlation_id = const Value.absent(),
    this.scope_id = const Value.absent(),
    this.idempotency_key = const Value.absent(),
    this.event_type = const Value.absent(),
    this.payload_json = const Value.absent(),
    this.processing_state = const Value.absent(),
    this.accepted_at_unix_ms = const Value.absent(),
  });
  WorkflowSubmissionsCompanion.insert({
    this.sequence = const Value.absent(),
    required String event_id,
    required String correlation_id,
    required String scope_id,
    this.idempotency_key = const Value.absent(),
    required String event_type,
    required String payload_json,
    this.processing_state = const Value.absent(),
    required int accepted_at_unix_ms,
  }) : event_id = Value(event_id),
       correlation_id = Value(correlation_id),
       scope_id = Value(scope_id),
       event_type = Value(event_type),
       payload_json = Value(payload_json),
       accepted_at_unix_ms = Value(accepted_at_unix_ms);
  static Insertable<WorkflowSubmission> custom({
    Expression<int>? sequence,
    Expression<String>? event_id,
    Expression<String>? correlation_id,
    Expression<String>? scope_id,
    Expression<String>? idempotency_key,
    Expression<String>? event_type,
    Expression<String>? payload_json,
    Expression<String>? processing_state,
    Expression<int>? accepted_at_unix_ms,
  }) {
    return RawValuesInsertable({
      if (sequence != null) 'sequence': sequence,
      if (event_id != null) 'event_id': event_id,
      if (correlation_id != null) 'correlation_id': correlation_id,
      if (scope_id != null) 'scope_id': scope_id,
      if (idempotency_key != null) 'idempotency_key': idempotency_key,
      if (event_type != null) 'event_type': event_type,
      if (payload_json != null) 'payload_json': payload_json,
      if (processing_state != null) 'processing_state': processing_state,
      if (accepted_at_unix_ms != null)
        'accepted_at_unix_ms': accepted_at_unix_ms,
    });
  }

  WorkflowSubmissionsCompanion copyWith({
    Value<int>? sequence,
    Value<String>? event_id,
    Value<String>? correlation_id,
    Value<String>? scope_id,
    Value<String?>? idempotency_key,
    Value<String>? event_type,
    Value<String>? payload_json,
    Value<String>? processing_state,
    Value<int>? accepted_at_unix_ms,
  }) {
    return WorkflowSubmissionsCompanion(
      sequence: sequence ?? this.sequence,
      event_id: event_id ?? this.event_id,
      correlation_id: correlation_id ?? this.correlation_id,
      scope_id: scope_id ?? this.scope_id,
      idempotency_key: idempotency_key ?? this.idempotency_key,
      event_type: event_type ?? this.event_type,
      payload_json: payload_json ?? this.payload_json,
      processing_state: processing_state ?? this.processing_state,
      accepted_at_unix_ms: accepted_at_unix_ms ?? this.accepted_at_unix_ms,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sequence.present) {
      map['sequence'] = Variable<int>(sequence.value);
    }
    if (event_id.present) {
      map['event_id'] = Variable<String>(event_id.value);
    }
    if (correlation_id.present) {
      map['correlation_id'] = Variable<String>(correlation_id.value);
    }
    if (scope_id.present) {
      map['scope_id'] = Variable<String>(scope_id.value);
    }
    if (idempotency_key.present) {
      map['idempotency_key'] = Variable<String>(idempotency_key.value);
    }
    if (event_type.present) {
      map['event_type'] = Variable<String>(event_type.value);
    }
    if (payload_json.present) {
      map['payload_json'] = Variable<String>(payload_json.value);
    }
    if (processing_state.present) {
      map['processing_state'] = Variable<String>(processing_state.value);
    }
    if (accepted_at_unix_ms.present) {
      map['accepted_at_unix_ms'] = Variable<int>(accepted_at_unix_ms.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WorkflowSubmissionsCompanion(')
          ..write('sequence: $sequence, ')
          ..write('event_id: $event_id, ')
          ..write('correlation_id: $correlation_id, ')
          ..write('scope_id: $scope_id, ')
          ..write('idempotency_key: $idempotency_key, ')
          ..write('event_type: $event_type, ')
          ..write('payload_json: $payload_json, ')
          ..write('processing_state: $processing_state, ')
          ..write('accepted_at_unix_ms: $accepted_at_unix_ms')
          ..write(')'))
        .toString();
  }
}

abstract class _$RudraDatabase extends GeneratedDatabase {
  _$RudraDatabase(QueryExecutor e) : super(e);
  $RudraDatabaseManager get managers => $RudraDatabaseManager(this);
  late final $WorkflowSubmissionsTable workflowSubmissions =
      $WorkflowSubmissionsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [workflowSubmissions];
}

typedef $$WorkflowSubmissionsTableCreateCompanionBuilder =
    WorkflowSubmissionsCompanion Function({
      Value<int> sequence,
      required String event_id,
      required String correlation_id,
      required String scope_id,
      Value<String?> idempotency_key,
      required String event_type,
      required String payload_json,
      Value<String> processing_state,
      required int accepted_at_unix_ms,
    });
typedef $$WorkflowSubmissionsTableUpdateCompanionBuilder =
    WorkflowSubmissionsCompanion Function({
      Value<int> sequence,
      Value<String> event_id,
      Value<String> correlation_id,
      Value<String> scope_id,
      Value<String?> idempotency_key,
      Value<String> event_type,
      Value<String> payload_json,
      Value<String> processing_state,
      Value<int> accepted_at_unix_ms,
    });

class $$WorkflowSubmissionsTableFilterComposer
    extends Composer<_$RudraDatabase, $WorkflowSubmissionsTable> {
  $$WorkflowSubmissionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get sequence => $composableBuilder(
    column: $table.sequence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get event_id => $composableBuilder(
    column: $table.event_id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get correlation_id => $composableBuilder(
    column: $table.correlation_id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scope_id => $composableBuilder(
    column: $table.scope_id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get idempotency_key => $composableBuilder(
    column: $table.idempotency_key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get event_type => $composableBuilder(
    column: $table.event_type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload_json => $composableBuilder(
    column: $table.payload_json,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get processing_state => $composableBuilder(
    column: $table.processing_state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get accepted_at_unix_ms => $composableBuilder(
    column: $table.accepted_at_unix_ms,
    builder: (column) => ColumnFilters(column),
  );
}

class $$WorkflowSubmissionsTableOrderingComposer
    extends Composer<_$RudraDatabase, $WorkflowSubmissionsTable> {
  $$WorkflowSubmissionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get sequence => $composableBuilder(
    column: $table.sequence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get event_id => $composableBuilder(
    column: $table.event_id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get correlation_id => $composableBuilder(
    column: $table.correlation_id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scope_id => $composableBuilder(
    column: $table.scope_id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get idempotency_key => $composableBuilder(
    column: $table.idempotency_key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get event_type => $composableBuilder(
    column: $table.event_type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload_json => $composableBuilder(
    column: $table.payload_json,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get processing_state => $composableBuilder(
    column: $table.processing_state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get accepted_at_unix_ms => $composableBuilder(
    column: $table.accepted_at_unix_ms,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$WorkflowSubmissionsTableAnnotationComposer
    extends Composer<_$RudraDatabase, $WorkflowSubmissionsTable> {
  $$WorkflowSubmissionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get sequence =>
      $composableBuilder(column: $table.sequence, builder: (column) => column);

  GeneratedColumn<String> get event_id =>
      $composableBuilder(column: $table.event_id, builder: (column) => column);

  GeneratedColumn<String> get correlation_id => $composableBuilder(
    column: $table.correlation_id,
    builder: (column) => column,
  );

  GeneratedColumn<String> get scope_id =>
      $composableBuilder(column: $table.scope_id, builder: (column) => column);

  GeneratedColumn<String> get idempotency_key => $composableBuilder(
    column: $table.idempotency_key,
    builder: (column) => column,
  );

  GeneratedColumn<String> get event_type => $composableBuilder(
    column: $table.event_type,
    builder: (column) => column,
  );

  GeneratedColumn<String> get payload_json => $composableBuilder(
    column: $table.payload_json,
    builder: (column) => column,
  );

  GeneratedColumn<String> get processing_state => $composableBuilder(
    column: $table.processing_state,
    builder: (column) => column,
  );

  GeneratedColumn<int> get accepted_at_unix_ms => $composableBuilder(
    column: $table.accepted_at_unix_ms,
    builder: (column) => column,
  );
}

class $$WorkflowSubmissionsTableTableManager
    extends
        RootTableManager<
          _$RudraDatabase,
          $WorkflowSubmissionsTable,
          WorkflowSubmission,
          $$WorkflowSubmissionsTableFilterComposer,
          $$WorkflowSubmissionsTableOrderingComposer,
          $$WorkflowSubmissionsTableAnnotationComposer,
          $$WorkflowSubmissionsTableCreateCompanionBuilder,
          $$WorkflowSubmissionsTableUpdateCompanionBuilder,
          (
            WorkflowSubmission,
            BaseReferences<
              _$RudraDatabase,
              $WorkflowSubmissionsTable,
              WorkflowSubmission
            >,
          ),
          WorkflowSubmission,
          PrefetchHooks Function()
        > {
  $$WorkflowSubmissionsTableTableManager(
    _$RudraDatabase db,
    $WorkflowSubmissionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WorkflowSubmissionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WorkflowSubmissionsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$WorkflowSubmissionsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> sequence = const Value.absent(),
                Value<String> event_id = const Value.absent(),
                Value<String> correlation_id = const Value.absent(),
                Value<String> scope_id = const Value.absent(),
                Value<String?> idempotency_key = const Value.absent(),
                Value<String> event_type = const Value.absent(),
                Value<String> payload_json = const Value.absent(),
                Value<String> processing_state = const Value.absent(),
                Value<int> accepted_at_unix_ms = const Value.absent(),
              }) => WorkflowSubmissionsCompanion(
                sequence: sequence,
                event_id: event_id,
                correlation_id: correlation_id,
                scope_id: scope_id,
                idempotency_key: idempotency_key,
                event_type: event_type,
                payload_json: payload_json,
                processing_state: processing_state,
                accepted_at_unix_ms: accepted_at_unix_ms,
              ),
          createCompanionCallback:
              ({
                Value<int> sequence = const Value.absent(),
                required String event_id,
                required String correlation_id,
                required String scope_id,
                Value<String?> idempotency_key = const Value.absent(),
                required String event_type,
                required String payload_json,
                Value<String> processing_state = const Value.absent(),
                required int accepted_at_unix_ms,
              }) => WorkflowSubmissionsCompanion.insert(
                sequence: sequence,
                event_id: event_id,
                correlation_id: correlation_id,
                scope_id: scope_id,
                idempotency_key: idempotency_key,
                event_type: event_type,
                payload_json: payload_json,
                processing_state: processing_state,
                accepted_at_unix_ms: accepted_at_unix_ms,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$WorkflowSubmissionsTable, WorkflowSubmission>(
                    table,
                  ),
                  BaseReferences<
                    _$RudraDatabase,
                    $WorkflowSubmissionsTable,
                    WorkflowSubmission
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$WorkflowSubmissionsTableProcessedTableManager =
    ProcessedTableManager<
      _$RudraDatabase,
      $WorkflowSubmissionsTable,
      WorkflowSubmission,
      $$WorkflowSubmissionsTableFilterComposer,
      $$WorkflowSubmissionsTableOrderingComposer,
      $$WorkflowSubmissionsTableAnnotationComposer,
      $$WorkflowSubmissionsTableCreateCompanionBuilder,
      $$WorkflowSubmissionsTableUpdateCompanionBuilder,
      (
        WorkflowSubmission,
        BaseReferences<
          _$RudraDatabase,
          $WorkflowSubmissionsTable,
          WorkflowSubmission
        >,
      ),
      WorkflowSubmission,
      PrefetchHooks Function()
    >;

class $RudraDatabaseManager {
  final _$RudraDatabase _db;
  $RudraDatabaseManager(this._db);
  $$WorkflowSubmissionsTableTableManager get workflowSubmissions =>
      $$WorkflowSubmissionsTableTableManager(_db, _db.workflowSubmissions);
}
