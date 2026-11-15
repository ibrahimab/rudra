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
  static const VerificationMeta _rejection_codeMeta = const VerificationMeta(
    'rejection_code',
  );
  @override
  late final GeneratedColumn<String> rejection_code = GeneratedColumn<String>(
    'rejection_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rejected_at_unix_msMeta =
      const VerificationMeta('rejected_at_unix_ms');
  @override
  late final GeneratedColumn<int> rejected_at_unix_ms = GeneratedColumn<int>(
    'rejected_at_unix_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _quarantine_codeMeta = const VerificationMeta(
    'quarantine_code',
  );
  @override
  late final GeneratedColumn<String> quarantine_code = GeneratedColumn<String>(
    'quarantine_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _quarantine_diagnosticMeta =
      const VerificationMeta('quarantine_diagnostic');
  @override
  late final GeneratedColumn<String> quarantine_diagnostic =
      GeneratedColumn<String>(
        'quarantine_diagnostic',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _quarantined_at_unix_msMeta =
      const VerificationMeta('quarantined_at_unix_ms');
  @override
  late final GeneratedColumn<int> quarantined_at_unix_ms = GeneratedColumn<int>(
    'quarantined_at_unix_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
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
    rejection_code,
    rejected_at_unix_ms,
    quarantine_code,
    quarantine_diagnostic,
    quarantined_at_unix_ms,
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
    if (data.containsKey('rejection_code')) {
      context.handle(
        _rejection_codeMeta,
        rejection_code.isAcceptableOrUnknown(
          data['rejection_code']!,
          _rejection_codeMeta,
        ),
      );
    }
    if (data.containsKey('rejected_at_unix_ms')) {
      context.handle(
        _rejected_at_unix_msMeta,
        rejected_at_unix_ms.isAcceptableOrUnknown(
          data['rejected_at_unix_ms']!,
          _rejected_at_unix_msMeta,
        ),
      );
    }
    if (data.containsKey('quarantine_code')) {
      context.handle(
        _quarantine_codeMeta,
        quarantine_code.isAcceptableOrUnknown(
          data['quarantine_code']!,
          _quarantine_codeMeta,
        ),
      );
    }
    if (data.containsKey('quarantine_diagnostic')) {
      context.handle(
        _quarantine_diagnosticMeta,
        quarantine_diagnostic.isAcceptableOrUnknown(
          data['quarantine_diagnostic']!,
          _quarantine_diagnosticMeta,
        ),
      );
    }
    if (data.containsKey('quarantined_at_unix_ms')) {
      context.handle(
        _quarantined_at_unix_msMeta,
        quarantined_at_unix_ms.isAcceptableOrUnknown(
          data['quarantined_at_unix_ms']!,
          _quarantined_at_unix_msMeta,
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
      rejection_code: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rejection_code'],
      ),
      rejected_at_unix_ms: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rejected_at_unix_ms'],
      ),
      quarantine_code: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}quarantine_code'],
      ),
      quarantine_diagnostic: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}quarantine_diagnostic'],
      ),
      quarantined_at_unix_ms: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}quarantined_at_unix_ms'],
      ),
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

  /// Stable reason recorded for a rejected submission.
  ///
  /// Null for pending and successfully completed commands.
  final String? rejection_code;

  /// UTC Unix timestamp when a business rejection was committed.
  ///
  /// Null for submissions that have not been rejected.
  final int? rejected_at_unix_ms;

  /// Stable reason for quarantining an unreadable submission.
  ///
  /// Null unless processing_state is 'quarantined'.
  final String? quarantine_code;

  /// Diagnostic recorded by the decoding boundary.
  ///
  /// The original payload remains in payload_json.
  /// This column must not be used to duplicate raw payloads.
  final String? quarantine_diagnostic;

  /// UTC Unix timestamp when quarantine was committed.
  ///
  /// Null unless processing_state is 'quarantined'.
  final int? quarantined_at_unix_ms;

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
    this.rejection_code,
    this.rejected_at_unix_ms,
    this.quarantine_code,
    this.quarantine_diagnostic,
    this.quarantined_at_unix_ms,
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
    if (!nullToAbsent || rejection_code != null) {
      map['rejection_code'] = Variable<String>(rejection_code);
    }
    if (!nullToAbsent || rejected_at_unix_ms != null) {
      map['rejected_at_unix_ms'] = Variable<int>(rejected_at_unix_ms);
    }
    if (!nullToAbsent || quarantine_code != null) {
      map['quarantine_code'] = Variable<String>(quarantine_code);
    }
    if (!nullToAbsent || quarantine_diagnostic != null) {
      map['quarantine_diagnostic'] = Variable<String>(quarantine_diagnostic);
    }
    if (!nullToAbsent || quarantined_at_unix_ms != null) {
      map['quarantined_at_unix_ms'] = Variable<int>(quarantined_at_unix_ms);
    }
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
      rejection_code: rejection_code == null && nullToAbsent
          ? const Value.absent()
          : Value(rejection_code),
      rejected_at_unix_ms: rejected_at_unix_ms == null && nullToAbsent
          ? const Value.absent()
          : Value(rejected_at_unix_ms),
      quarantine_code: quarantine_code == null && nullToAbsent
          ? const Value.absent()
          : Value(quarantine_code),
      quarantine_diagnostic: quarantine_diagnostic == null && nullToAbsent
          ? const Value.absent()
          : Value(quarantine_diagnostic),
      quarantined_at_unix_ms: quarantined_at_unix_ms == null && nullToAbsent
          ? const Value.absent()
          : Value(quarantined_at_unix_ms),
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
      rejection_code: serializer.fromJson<String?>(json['rejection_code']),
      rejected_at_unix_ms: serializer.fromJson<int?>(
        json['rejected_at_unix_ms'],
      ),
      quarantine_code: serializer.fromJson<String?>(json['quarantine_code']),
      quarantine_diagnostic: serializer.fromJson<String?>(
        json['quarantine_diagnostic'],
      ),
      quarantined_at_unix_ms: serializer.fromJson<int?>(
        json['quarantined_at_unix_ms'],
      ),
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
      'rejection_code': serializer.toJson<String?>(rejection_code),
      'rejected_at_unix_ms': serializer.toJson<int?>(rejected_at_unix_ms),
      'quarantine_code': serializer.toJson<String?>(quarantine_code),
      'quarantine_diagnostic': serializer.toJson<String?>(
        quarantine_diagnostic,
      ),
      'quarantined_at_unix_ms': serializer.toJson<int?>(quarantined_at_unix_ms),
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
    Value<String?> rejection_code = const Value.absent(),
    Value<int?> rejected_at_unix_ms = const Value.absent(),
    Value<String?> quarantine_code = const Value.absent(),
    Value<String?> quarantine_diagnostic = const Value.absent(),
    Value<int?> quarantined_at_unix_ms = const Value.absent(),
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
    rejection_code: rejection_code.present
        ? rejection_code.value
        : this.rejection_code,
    rejected_at_unix_ms: rejected_at_unix_ms.present
        ? rejected_at_unix_ms.value
        : this.rejected_at_unix_ms,
    quarantine_code: quarantine_code.present
        ? quarantine_code.value
        : this.quarantine_code,
    quarantine_diagnostic: quarantine_diagnostic.present
        ? quarantine_diagnostic.value
        : this.quarantine_diagnostic,
    quarantined_at_unix_ms: quarantined_at_unix_ms.present
        ? quarantined_at_unix_ms.value
        : this.quarantined_at_unix_ms,
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
      rejection_code: data.rejection_code.present
          ? data.rejection_code.value
          : this.rejection_code,
      rejected_at_unix_ms: data.rejected_at_unix_ms.present
          ? data.rejected_at_unix_ms.value
          : this.rejected_at_unix_ms,
      quarantine_code: data.quarantine_code.present
          ? data.quarantine_code.value
          : this.quarantine_code,
      quarantine_diagnostic: data.quarantine_diagnostic.present
          ? data.quarantine_diagnostic.value
          : this.quarantine_diagnostic,
      quarantined_at_unix_ms: data.quarantined_at_unix_ms.present
          ? data.quarantined_at_unix_ms.value
          : this.quarantined_at_unix_ms,
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
          ..write('rejection_code: $rejection_code, ')
          ..write('rejected_at_unix_ms: $rejected_at_unix_ms, ')
          ..write('quarantine_code: $quarantine_code, ')
          ..write('quarantine_diagnostic: $quarantine_diagnostic, ')
          ..write('quarantined_at_unix_ms: $quarantined_at_unix_ms, ')
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
    rejection_code,
    rejected_at_unix_ms,
    quarantine_code,
    quarantine_diagnostic,
    quarantined_at_unix_ms,
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
          other.rejection_code == this.rejection_code &&
          other.rejected_at_unix_ms == this.rejected_at_unix_ms &&
          other.quarantine_code == this.quarantine_code &&
          other.quarantine_diagnostic == this.quarantine_diagnostic &&
          other.quarantined_at_unix_ms == this.quarantined_at_unix_ms &&
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
  final Value<String?> rejection_code;
  final Value<int?> rejected_at_unix_ms;
  final Value<String?> quarantine_code;
  final Value<String?> quarantine_diagnostic;
  final Value<int?> quarantined_at_unix_ms;
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
    this.rejection_code = const Value.absent(),
    this.rejected_at_unix_ms = const Value.absent(),
    this.quarantine_code = const Value.absent(),
    this.quarantine_diagnostic = const Value.absent(),
    this.quarantined_at_unix_ms = const Value.absent(),
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
    this.rejection_code = const Value.absent(),
    this.rejected_at_unix_ms = const Value.absent(),
    this.quarantine_code = const Value.absent(),
    this.quarantine_diagnostic = const Value.absent(),
    this.quarantined_at_unix_ms = const Value.absent(),
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
    Expression<String>? rejection_code,
    Expression<int>? rejected_at_unix_ms,
    Expression<String>? quarantine_code,
    Expression<String>? quarantine_diagnostic,
    Expression<int>? quarantined_at_unix_ms,
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
      if (rejection_code != null) 'rejection_code': rejection_code,
      if (rejected_at_unix_ms != null)
        'rejected_at_unix_ms': rejected_at_unix_ms,
      if (quarantine_code != null) 'quarantine_code': quarantine_code,
      if (quarantine_diagnostic != null)
        'quarantine_diagnostic': quarantine_diagnostic,
      if (quarantined_at_unix_ms != null)
        'quarantined_at_unix_ms': quarantined_at_unix_ms,
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
    Value<String?>? rejection_code,
    Value<int?>? rejected_at_unix_ms,
    Value<String?>? quarantine_code,
    Value<String?>? quarantine_diagnostic,
    Value<int?>? quarantined_at_unix_ms,
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
      rejection_code: rejection_code ?? this.rejection_code,
      rejected_at_unix_ms: rejected_at_unix_ms ?? this.rejected_at_unix_ms,
      quarantine_code: quarantine_code ?? this.quarantine_code,
      quarantine_diagnostic:
          quarantine_diagnostic ?? this.quarantine_diagnostic,
      quarantined_at_unix_ms:
          quarantined_at_unix_ms ?? this.quarantined_at_unix_ms,
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
    if (rejection_code.present) {
      map['rejection_code'] = Variable<String>(rejection_code.value);
    }
    if (rejected_at_unix_ms.present) {
      map['rejected_at_unix_ms'] = Variable<int>(rejected_at_unix_ms.value);
    }
    if (quarantine_code.present) {
      map['quarantine_code'] = Variable<String>(quarantine_code.value);
    }
    if (quarantine_diagnostic.present) {
      map['quarantine_diagnostic'] = Variable<String>(
        quarantine_diagnostic.value,
      );
    }
    if (quarantined_at_unix_ms.present) {
      map['quarantined_at_unix_ms'] = Variable<int>(
        quarantined_at_unix_ms.value,
      );
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
          ..write('rejection_code: $rejection_code, ')
          ..write('rejected_at_unix_ms: $rejected_at_unix_ms, ')
          ..write('quarantine_code: $quarantine_code, ')
          ..write('quarantine_diagnostic: $quarantine_diagnostic, ')
          ..write('quarantined_at_unix_ms: $quarantined_at_unix_ms, ')
          ..write('accepted_at_unix_ms: $accepted_at_unix_ms')
          ..write(')'))
        .toString();
  }
}

class $WorkflowEventsTable extends WorkflowEvents
    with TableInfo<$WorkflowEventsTable, WorkflowEvent> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WorkflowEventsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _workflow_idMeta = const VerificationMeta(
    'workflow_id',
  );
  @override
  late final GeneratedColumn<String> workflow_id = GeneratedColumn<String>(
    'workflow_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
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
  static const VerificationMeta _causation_idMeta = const VerificationMeta(
    'causation_id',
  );
  @override
  late final GeneratedColumn<String> causation_id = GeneratedColumn<String>(
    'causation_id',
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
  static const VerificationMeta _recorded_at_unix_msMeta =
      const VerificationMeta('recorded_at_unix_ms');
  @override
  late final GeneratedColumn<int> recorded_at_unix_ms = GeneratedColumn<int>(
    'recorded_at_unix_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    sequence,
    event_id,
    workflow_id,
    version,
    correlation_id,
    causation_id,
    event_type,
    payload_json,
    recorded_at_unix_ms,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'workflow_events';
  @override
  VerificationContext validateIntegrity(
    Insertable<WorkflowEvent> instance, {
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
    if (data.containsKey('workflow_id')) {
      context.handle(
        _workflow_idMeta,
        workflow_id.isAcceptableOrUnknown(
          data['workflow_id']!,
          _workflow_idMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_workflow_idMeta);
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    } else if (isInserting) {
      context.missing(_versionMeta);
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
    if (data.containsKey('causation_id')) {
      context.handle(
        _causation_idMeta,
        causation_id.isAcceptableOrUnknown(
          data['causation_id']!,
          _causation_idMeta,
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
    if (data.containsKey('recorded_at_unix_ms')) {
      context.handle(
        _recorded_at_unix_msMeta,
        recorded_at_unix_ms.isAcceptableOrUnknown(
          data['recorded_at_unix_ms']!,
          _recorded_at_unix_msMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_recorded_at_unix_msMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sequence};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {workflow_id, version},
  ];
  @override
  WorkflowEvent map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WorkflowEvent(
      sequence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sequence'],
      )!,
      event_id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_id'],
      )!,
      workflow_id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}workflow_id'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      correlation_id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}correlation_id'],
      )!,
      causation_id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}causation_id'],
      ),
      event_type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_type'],
      )!,
      payload_json: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      )!,
      recorded_at_unix_ms: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}recorded_at_unix_ms'],
      )!,
    );
  }

  @override
  $WorkflowEventsTable createAlias(String alias) {
    return $WorkflowEventsTable(attachedDatabase, alias);
  }

  @override
  bool get isStrict => true;
}

class WorkflowEvent extends DataClass implements Insertable<WorkflowEvent> {
  /// Database-local event sequence.
  final int sequence;

  /// Stable identity of the committed event.
  final String event_id;

  /// Workflow receiving this event.
  final String workflow_id;

  /// Version resulting from this event.
  final int version;

  /// Correlation identifier shared with its original request.
  final String correlation_id;

  /// Event responsible for causing this event, if known.
  final String? causation_id;

  /// Stable domain event type.
  final String event_type;

  /// Versioned event representation.
  final String payload_json;

  /// UTC commit timestamp in Unix milliseconds.
  final int recorded_at_unix_ms;
  const WorkflowEvent({
    required this.sequence,
    required this.event_id,
    required this.workflow_id,
    required this.version,
    required this.correlation_id,
    this.causation_id,
    required this.event_type,
    required this.payload_json,
    required this.recorded_at_unix_ms,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['sequence'] = Variable<int>(sequence);
    map['event_id'] = Variable<String>(event_id);
    map['workflow_id'] = Variable<String>(workflow_id);
    map['version'] = Variable<int>(version);
    map['correlation_id'] = Variable<String>(correlation_id);
    if (!nullToAbsent || causation_id != null) {
      map['causation_id'] = Variable<String>(causation_id);
    }
    map['event_type'] = Variable<String>(event_type);
    map['payload_json'] = Variable<String>(payload_json);
    map['recorded_at_unix_ms'] = Variable<int>(recorded_at_unix_ms);
    return map;
  }

  WorkflowEventsCompanion toCompanion(bool nullToAbsent) {
    return WorkflowEventsCompanion(
      sequence: Value(sequence),
      event_id: Value(event_id),
      workflow_id: Value(workflow_id),
      version: Value(version),
      correlation_id: Value(correlation_id),
      causation_id: causation_id == null && nullToAbsent
          ? const Value.absent()
          : Value(causation_id),
      event_type: Value(event_type),
      payload_json: Value(payload_json),
      recorded_at_unix_ms: Value(recorded_at_unix_ms),
    );
  }

  factory WorkflowEvent.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WorkflowEvent(
      sequence: serializer.fromJson<int>(json['sequence']),
      event_id: serializer.fromJson<String>(json['event_id']),
      workflow_id: serializer.fromJson<String>(json['workflow_id']),
      version: serializer.fromJson<int>(json['version']),
      correlation_id: serializer.fromJson<String>(json['correlation_id']),
      causation_id: serializer.fromJson<String?>(json['causation_id']),
      event_type: serializer.fromJson<String>(json['event_type']),
      payload_json: serializer.fromJson<String>(json['payload_json']),
      recorded_at_unix_ms: serializer.fromJson<int>(
        json['recorded_at_unix_ms'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sequence': serializer.toJson<int>(sequence),
      'event_id': serializer.toJson<String>(event_id),
      'workflow_id': serializer.toJson<String>(workflow_id),
      'version': serializer.toJson<int>(version),
      'correlation_id': serializer.toJson<String>(correlation_id),
      'causation_id': serializer.toJson<String?>(causation_id),
      'event_type': serializer.toJson<String>(event_type),
      'payload_json': serializer.toJson<String>(payload_json),
      'recorded_at_unix_ms': serializer.toJson<int>(recorded_at_unix_ms),
    };
  }

  WorkflowEvent copyWith({
    int? sequence,
    String? event_id,
    String? workflow_id,
    int? version,
    String? correlation_id,
    Value<String?> causation_id = const Value.absent(),
    String? event_type,
    String? payload_json,
    int? recorded_at_unix_ms,
  }) => WorkflowEvent(
    sequence: sequence ?? this.sequence,
    event_id: event_id ?? this.event_id,
    workflow_id: workflow_id ?? this.workflow_id,
    version: version ?? this.version,
    correlation_id: correlation_id ?? this.correlation_id,
    causation_id: causation_id.present ? causation_id.value : this.causation_id,
    event_type: event_type ?? this.event_type,
    payload_json: payload_json ?? this.payload_json,
    recorded_at_unix_ms: recorded_at_unix_ms ?? this.recorded_at_unix_ms,
  );
  WorkflowEvent copyWithCompanion(WorkflowEventsCompanion data) {
    return WorkflowEvent(
      sequence: data.sequence.present ? data.sequence.value : this.sequence,
      event_id: data.event_id.present ? data.event_id.value : this.event_id,
      workflow_id: data.workflow_id.present
          ? data.workflow_id.value
          : this.workflow_id,
      version: data.version.present ? data.version.value : this.version,
      correlation_id: data.correlation_id.present
          ? data.correlation_id.value
          : this.correlation_id,
      causation_id: data.causation_id.present
          ? data.causation_id.value
          : this.causation_id,
      event_type: data.event_type.present
          ? data.event_type.value
          : this.event_type,
      payload_json: data.payload_json.present
          ? data.payload_json.value
          : this.payload_json,
      recorded_at_unix_ms: data.recorded_at_unix_ms.present
          ? data.recorded_at_unix_ms.value
          : this.recorded_at_unix_ms,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WorkflowEvent(')
          ..write('sequence: $sequence, ')
          ..write('event_id: $event_id, ')
          ..write('workflow_id: $workflow_id, ')
          ..write('version: $version, ')
          ..write('correlation_id: $correlation_id, ')
          ..write('causation_id: $causation_id, ')
          ..write('event_type: $event_type, ')
          ..write('payload_json: $payload_json, ')
          ..write('recorded_at_unix_ms: $recorded_at_unix_ms')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    sequence,
    event_id,
    workflow_id,
    version,
    correlation_id,
    causation_id,
    event_type,
    payload_json,
    recorded_at_unix_ms,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WorkflowEvent &&
          other.sequence == this.sequence &&
          other.event_id == this.event_id &&
          other.workflow_id == this.workflow_id &&
          other.version == this.version &&
          other.correlation_id == this.correlation_id &&
          other.causation_id == this.causation_id &&
          other.event_type == this.event_type &&
          other.payload_json == this.payload_json &&
          other.recorded_at_unix_ms == this.recorded_at_unix_ms);
}

class WorkflowEventsCompanion extends UpdateCompanion<WorkflowEvent> {
  final Value<int> sequence;
  final Value<String> event_id;
  final Value<String> workflow_id;
  final Value<int> version;
  final Value<String> correlation_id;
  final Value<String?> causation_id;
  final Value<String> event_type;
  final Value<String> payload_json;
  final Value<int> recorded_at_unix_ms;
  const WorkflowEventsCompanion({
    this.sequence = const Value.absent(),
    this.event_id = const Value.absent(),
    this.workflow_id = const Value.absent(),
    this.version = const Value.absent(),
    this.correlation_id = const Value.absent(),
    this.causation_id = const Value.absent(),
    this.event_type = const Value.absent(),
    this.payload_json = const Value.absent(),
    this.recorded_at_unix_ms = const Value.absent(),
  });
  WorkflowEventsCompanion.insert({
    this.sequence = const Value.absent(),
    required String event_id,
    required String workflow_id,
    required int version,
    required String correlation_id,
    this.causation_id = const Value.absent(),
    required String event_type,
    required String payload_json,
    required int recorded_at_unix_ms,
  }) : event_id = Value(event_id),
       workflow_id = Value(workflow_id),
       version = Value(version),
       correlation_id = Value(correlation_id),
       event_type = Value(event_type),
       payload_json = Value(payload_json),
       recorded_at_unix_ms = Value(recorded_at_unix_ms);
  static Insertable<WorkflowEvent> custom({
    Expression<int>? sequence,
    Expression<String>? event_id,
    Expression<String>? workflow_id,
    Expression<int>? version,
    Expression<String>? correlation_id,
    Expression<String>? causation_id,
    Expression<String>? event_type,
    Expression<String>? payload_json,
    Expression<int>? recorded_at_unix_ms,
  }) {
    return RawValuesInsertable({
      if (sequence != null) 'sequence': sequence,
      if (event_id != null) 'event_id': event_id,
      if (workflow_id != null) 'workflow_id': workflow_id,
      if (version != null) 'version': version,
      if (correlation_id != null) 'correlation_id': correlation_id,
      if (causation_id != null) 'causation_id': causation_id,
      if (event_type != null) 'event_type': event_type,
      if (payload_json != null) 'payload_json': payload_json,
      if (recorded_at_unix_ms != null)
        'recorded_at_unix_ms': recorded_at_unix_ms,
    });
  }

  WorkflowEventsCompanion copyWith({
    Value<int>? sequence,
    Value<String>? event_id,
    Value<String>? workflow_id,
    Value<int>? version,
    Value<String>? correlation_id,
    Value<String?>? causation_id,
    Value<String>? event_type,
    Value<String>? payload_json,
    Value<int>? recorded_at_unix_ms,
  }) {
    return WorkflowEventsCompanion(
      sequence: sequence ?? this.sequence,
      event_id: event_id ?? this.event_id,
      workflow_id: workflow_id ?? this.workflow_id,
      version: version ?? this.version,
      correlation_id: correlation_id ?? this.correlation_id,
      causation_id: causation_id ?? this.causation_id,
      event_type: event_type ?? this.event_type,
      payload_json: payload_json ?? this.payload_json,
      recorded_at_unix_ms: recorded_at_unix_ms ?? this.recorded_at_unix_ms,
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
    if (workflow_id.present) {
      map['workflow_id'] = Variable<String>(workflow_id.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (correlation_id.present) {
      map['correlation_id'] = Variable<String>(correlation_id.value);
    }
    if (causation_id.present) {
      map['causation_id'] = Variable<String>(causation_id.value);
    }
    if (event_type.present) {
      map['event_type'] = Variable<String>(event_type.value);
    }
    if (payload_json.present) {
      map['payload_json'] = Variable<String>(payload_json.value);
    }
    if (recorded_at_unix_ms.present) {
      map['recorded_at_unix_ms'] = Variable<int>(recorded_at_unix_ms.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WorkflowEventsCompanion(')
          ..write('sequence: $sequence, ')
          ..write('event_id: $event_id, ')
          ..write('workflow_id: $workflow_id, ')
          ..write('version: $version, ')
          ..write('correlation_id: $correlation_id, ')
          ..write('causation_id: $causation_id, ')
          ..write('event_type: $event_type, ')
          ..write('payload_json: $payload_json, ')
          ..write('recorded_at_unix_ms: $recorded_at_unix_ms')
          ..write(')'))
        .toString();
  }
}

class $UnfinishedWorkflowsTable extends UnfinishedWorkflows
    with TableInfo<$UnfinishedWorkflowsTable, UnfinishedWorkflow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UnfinishedWorkflowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _os_user_idMeta = const VerificationMeta(
    'os_user_id',
  );
  @override
  late final GeneratedColumn<String> os_user_id = GeneratedColumn<String>(
    'os_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _workflow_idMeta = const VerificationMeta(
    'workflow_id',
  );
  @override
  late final GeneratedColumn<String> workflow_id = GeneratedColumn<String>(
    'workflow_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _target_idMeta = const VerificationMeta(
    'target_id',
  );
  @override
  late final GeneratedColumn<String> target_id = GeneratedColumn<String>(
    'target_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _root_pathMeta = const VerificationMeta(
    'root_path',
  );
  @override
  late final GeneratedColumn<String> root_path = GeneratedColumn<String>(
    'root_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    os_user_id,
    workflow_id,
    target_id,
    root_path,
    version,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'unfinished_workflows';
  @override
  VerificationContext validateIntegrity(
    Insertable<UnfinishedWorkflow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('os_user_id')) {
      context.handle(
        _os_user_idMeta,
        os_user_id.isAcceptableOrUnknown(data['os_user_id']!, _os_user_idMeta),
      );
    } else if (isInserting) {
      context.missing(_os_user_idMeta);
    }
    if (data.containsKey('workflow_id')) {
      context.handle(
        _workflow_idMeta,
        workflow_id.isAcceptableOrUnknown(
          data['workflow_id']!,
          _workflow_idMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_workflow_idMeta);
    }
    if (data.containsKey('target_id')) {
      context.handle(
        _target_idMeta,
        target_id.isAcceptableOrUnknown(data['target_id']!, _target_idMeta),
      );
    } else if (isInserting) {
      context.missing(_target_idMeta);
    }
    if (data.containsKey('root_path')) {
      context.handle(
        _root_pathMeta,
        root_path.isAcceptableOrUnknown(data['root_path']!, _root_pathMeta),
      );
    } else if (isInserting) {
      context.missing(_root_pathMeta);
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    } else if (isInserting) {
      context.missing(_versionMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {os_user_id};
  @override
  UnfinishedWorkflow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return UnfinishedWorkflow(
      os_user_id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}os_user_id'],
      )!,
      workflow_id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}workflow_id'],
      )!,
      target_id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_id'],
      )!,
      root_path: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}root_path'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
    );
  }

  @override
  $UnfinishedWorkflowsTable createAlias(String alias) {
    return $UnfinishedWorkflowsTable(attachedDatabase, alias);
  }

  @override
  bool get isStrict => true;
}

class UnfinishedWorkflow extends DataClass
    implements Insertable<UnfinishedWorkflow> {
  /// Trusted operating-system user identity.
  final String os_user_id;

  /// Unique identity of the unfinished workflow.
  final String workflow_id;

  /// Immutable configured filesystem target.
  final String target_id;

  /// Original target-native inspection root.
  final String root_path;

  /// Last committed workflow event version.
  final int version;
  const UnfinishedWorkflow({
    required this.os_user_id,
    required this.workflow_id,
    required this.target_id,
    required this.root_path,
    required this.version,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['os_user_id'] = Variable<String>(os_user_id);
    map['workflow_id'] = Variable<String>(workflow_id);
    map['target_id'] = Variable<String>(target_id);
    map['root_path'] = Variable<String>(root_path);
    map['version'] = Variable<int>(version);
    return map;
  }

  UnfinishedWorkflowsCompanion toCompanion(bool nullToAbsent) {
    return UnfinishedWorkflowsCompanion(
      os_user_id: Value(os_user_id),
      workflow_id: Value(workflow_id),
      target_id: Value(target_id),
      root_path: Value(root_path),
      version: Value(version),
    );
  }

  factory UnfinishedWorkflow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return UnfinishedWorkflow(
      os_user_id: serializer.fromJson<String>(json['os_user_id']),
      workflow_id: serializer.fromJson<String>(json['workflow_id']),
      target_id: serializer.fromJson<String>(json['target_id']),
      root_path: serializer.fromJson<String>(json['root_path']),
      version: serializer.fromJson<int>(json['version']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'os_user_id': serializer.toJson<String>(os_user_id),
      'workflow_id': serializer.toJson<String>(workflow_id),
      'target_id': serializer.toJson<String>(target_id),
      'root_path': serializer.toJson<String>(root_path),
      'version': serializer.toJson<int>(version),
    };
  }

  UnfinishedWorkflow copyWith({
    String? os_user_id,
    String? workflow_id,
    String? target_id,
    String? root_path,
    int? version,
  }) => UnfinishedWorkflow(
    os_user_id: os_user_id ?? this.os_user_id,
    workflow_id: workflow_id ?? this.workflow_id,
    target_id: target_id ?? this.target_id,
    root_path: root_path ?? this.root_path,
    version: version ?? this.version,
  );
  UnfinishedWorkflow copyWithCompanion(UnfinishedWorkflowsCompanion data) {
    return UnfinishedWorkflow(
      os_user_id: data.os_user_id.present
          ? data.os_user_id.value
          : this.os_user_id,
      workflow_id: data.workflow_id.present
          ? data.workflow_id.value
          : this.workflow_id,
      target_id: data.target_id.present ? data.target_id.value : this.target_id,
      root_path: data.root_path.present ? data.root_path.value : this.root_path,
      version: data.version.present ? data.version.value : this.version,
    );
  }

  @override
  String toString() {
    return (StringBuffer('UnfinishedWorkflow(')
          ..write('os_user_id: $os_user_id, ')
          ..write('workflow_id: $workflow_id, ')
          ..write('target_id: $target_id, ')
          ..write('root_path: $root_path, ')
          ..write('version: $version')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(os_user_id, workflow_id, target_id, root_path, version);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UnfinishedWorkflow &&
          other.os_user_id == this.os_user_id &&
          other.workflow_id == this.workflow_id &&
          other.target_id == this.target_id &&
          other.root_path == this.root_path &&
          other.version == this.version);
}

class UnfinishedWorkflowsCompanion extends UpdateCompanion<UnfinishedWorkflow> {
  final Value<String> os_user_id;
  final Value<String> workflow_id;
  final Value<String> target_id;
  final Value<String> root_path;
  final Value<int> version;
  final Value<int> rowid;
  const UnfinishedWorkflowsCompanion({
    this.os_user_id = const Value.absent(),
    this.workflow_id = const Value.absent(),
    this.target_id = const Value.absent(),
    this.root_path = const Value.absent(),
    this.version = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  UnfinishedWorkflowsCompanion.insert({
    required String os_user_id,
    required String workflow_id,
    required String target_id,
    required String root_path,
    required int version,
    this.rowid = const Value.absent(),
  }) : os_user_id = Value(os_user_id),
       workflow_id = Value(workflow_id),
       target_id = Value(target_id),
       root_path = Value(root_path),
       version = Value(version);
  static Insertable<UnfinishedWorkflow> custom({
    Expression<String>? os_user_id,
    Expression<String>? workflow_id,
    Expression<String>? target_id,
    Expression<String>? root_path,
    Expression<int>? version,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (os_user_id != null) 'os_user_id': os_user_id,
      if (workflow_id != null) 'workflow_id': workflow_id,
      if (target_id != null) 'target_id': target_id,
      if (root_path != null) 'root_path': root_path,
      if (version != null) 'version': version,
      if (rowid != null) 'rowid': rowid,
    });
  }

  UnfinishedWorkflowsCompanion copyWith({
    Value<String>? os_user_id,
    Value<String>? workflow_id,
    Value<String>? target_id,
    Value<String>? root_path,
    Value<int>? version,
    Value<int>? rowid,
  }) {
    return UnfinishedWorkflowsCompanion(
      os_user_id: os_user_id ?? this.os_user_id,
      workflow_id: workflow_id ?? this.workflow_id,
      target_id: target_id ?? this.target_id,
      root_path: root_path ?? this.root_path,
      version: version ?? this.version,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (os_user_id.present) {
      map['os_user_id'] = Variable<String>(os_user_id.value);
    }
    if (workflow_id.present) {
      map['workflow_id'] = Variable<String>(workflow_id.value);
    }
    if (target_id.present) {
      map['target_id'] = Variable<String>(target_id.value);
    }
    if (root_path.present) {
      map['root_path'] = Variable<String>(root_path.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UnfinishedWorkflowsCompanion(')
          ..write('os_user_id: $os_user_id, ')
          ..write('workflow_id: $workflow_id, ')
          ..write('target_id: $target_id, ')
          ..write('root_path: $root_path, ')
          ..write('version: $version, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$RudraDatabase extends GeneratedDatabase {
  _$RudraDatabase(QueryExecutor e) : super(e);
  $RudraDatabaseManager get managers => $RudraDatabaseManager(this);
  late final $WorkflowSubmissionsTable workflowSubmissions =
      $WorkflowSubmissionsTable(this);
  late final $WorkflowEventsTable workflowEvents = $WorkflowEventsTable(this);
  late final $UnfinishedWorkflowsTable unfinishedWorkflows =
      $UnfinishedWorkflowsTable(this);
  late final Index workflowEventsStartedOwnerIdx = Index(
    'workflow_events_started_owner_idx',
    'CREATE INDEX workflow_events_started_owner_idx ON workflow_events (CASE WHEN json_valid(payload_json) THEN json_extract(payload_json, \'\$.os_user_id\') END, workflow_id) WHERE event_type = \'workflow.started\'',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    workflowSubmissions,
    workflowEvents,
    unfinishedWorkflows,
    workflowEventsStartedOwnerIdx,
  ];
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
      Value<String?> rejection_code,
      Value<int?> rejected_at_unix_ms,
      Value<String?> quarantine_code,
      Value<String?> quarantine_diagnostic,
      Value<int?> quarantined_at_unix_ms,
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
      Value<String?> rejection_code,
      Value<int?> rejected_at_unix_ms,
      Value<String?> quarantine_code,
      Value<String?> quarantine_diagnostic,
      Value<int?> quarantined_at_unix_ms,
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

  ColumnFilters<String> get rejection_code => $composableBuilder(
    column: $table.rejection_code,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rejected_at_unix_ms => $composableBuilder(
    column: $table.rejected_at_unix_ms,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get quarantine_code => $composableBuilder(
    column: $table.quarantine_code,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get quarantine_diagnostic => $composableBuilder(
    column: $table.quarantine_diagnostic,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get quarantined_at_unix_ms => $composableBuilder(
    column: $table.quarantined_at_unix_ms,
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

  ColumnOrderings<String> get rejection_code => $composableBuilder(
    column: $table.rejection_code,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rejected_at_unix_ms => $composableBuilder(
    column: $table.rejected_at_unix_ms,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get quarantine_code => $composableBuilder(
    column: $table.quarantine_code,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get quarantine_diagnostic => $composableBuilder(
    column: $table.quarantine_diagnostic,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get quarantined_at_unix_ms => $composableBuilder(
    column: $table.quarantined_at_unix_ms,
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

  GeneratedColumn<String> get rejection_code => $composableBuilder(
    column: $table.rejection_code,
    builder: (column) => column,
  );

  GeneratedColumn<int> get rejected_at_unix_ms => $composableBuilder(
    column: $table.rejected_at_unix_ms,
    builder: (column) => column,
  );

  GeneratedColumn<String> get quarantine_code => $composableBuilder(
    column: $table.quarantine_code,
    builder: (column) => column,
  );

  GeneratedColumn<String> get quarantine_diagnostic => $composableBuilder(
    column: $table.quarantine_diagnostic,
    builder: (column) => column,
  );

  GeneratedColumn<int> get quarantined_at_unix_ms => $composableBuilder(
    column: $table.quarantined_at_unix_ms,
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
                Value<String?> rejection_code = const Value.absent(),
                Value<int?> rejected_at_unix_ms = const Value.absent(),
                Value<String?> quarantine_code = const Value.absent(),
                Value<String?> quarantine_diagnostic = const Value.absent(),
                Value<int?> quarantined_at_unix_ms = const Value.absent(),
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
                rejection_code: rejection_code,
                rejected_at_unix_ms: rejected_at_unix_ms,
                quarantine_code: quarantine_code,
                quarantine_diagnostic: quarantine_diagnostic,
                quarantined_at_unix_ms: quarantined_at_unix_ms,
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
                Value<String?> rejection_code = const Value.absent(),
                Value<int?> rejected_at_unix_ms = const Value.absent(),
                Value<String?> quarantine_code = const Value.absent(),
                Value<String?> quarantine_diagnostic = const Value.absent(),
                Value<int?> quarantined_at_unix_ms = const Value.absent(),
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
                rejection_code: rejection_code,
                rejected_at_unix_ms: rejected_at_unix_ms,
                quarantine_code: quarantine_code,
                quarantine_diagnostic: quarantine_diagnostic,
                quarantined_at_unix_ms: quarantined_at_unix_ms,
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
typedef $$WorkflowEventsTableCreateCompanionBuilder =
    WorkflowEventsCompanion Function({
      Value<int> sequence,
      required String event_id,
      required String workflow_id,
      required int version,
      required String correlation_id,
      Value<String?> causation_id,
      required String event_type,
      required String payload_json,
      required int recorded_at_unix_ms,
    });
typedef $$WorkflowEventsTableUpdateCompanionBuilder =
    WorkflowEventsCompanion Function({
      Value<int> sequence,
      Value<String> event_id,
      Value<String> workflow_id,
      Value<int> version,
      Value<String> correlation_id,
      Value<String?> causation_id,
      Value<String> event_type,
      Value<String> payload_json,
      Value<int> recorded_at_unix_ms,
    });

class $$WorkflowEventsTableFilterComposer
    extends Composer<_$RudraDatabase, $WorkflowEventsTable> {
  $$WorkflowEventsTableFilterComposer({
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

  ColumnFilters<String> get workflow_id => $composableBuilder(
    column: $table.workflow_id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get correlation_id => $composableBuilder(
    column: $table.correlation_id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get causation_id => $composableBuilder(
    column: $table.causation_id,
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

  ColumnFilters<int> get recorded_at_unix_ms => $composableBuilder(
    column: $table.recorded_at_unix_ms,
    builder: (column) => ColumnFilters(column),
  );
}

class $$WorkflowEventsTableOrderingComposer
    extends Composer<_$RudraDatabase, $WorkflowEventsTable> {
  $$WorkflowEventsTableOrderingComposer({
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

  ColumnOrderings<String> get workflow_id => $composableBuilder(
    column: $table.workflow_id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get correlation_id => $composableBuilder(
    column: $table.correlation_id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get causation_id => $composableBuilder(
    column: $table.causation_id,
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

  ColumnOrderings<int> get recorded_at_unix_ms => $composableBuilder(
    column: $table.recorded_at_unix_ms,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$WorkflowEventsTableAnnotationComposer
    extends Composer<_$RudraDatabase, $WorkflowEventsTable> {
  $$WorkflowEventsTableAnnotationComposer({
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

  GeneratedColumn<String> get workflow_id => $composableBuilder(
    column: $table.workflow_id,
    builder: (column) => column,
  );

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<String> get correlation_id => $composableBuilder(
    column: $table.correlation_id,
    builder: (column) => column,
  );

  GeneratedColumn<String> get causation_id => $composableBuilder(
    column: $table.causation_id,
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

  GeneratedColumn<int> get recorded_at_unix_ms => $composableBuilder(
    column: $table.recorded_at_unix_ms,
    builder: (column) => column,
  );
}

class $$WorkflowEventsTableTableManager
    extends
        RootTableManager<
          _$RudraDatabase,
          $WorkflowEventsTable,
          WorkflowEvent,
          $$WorkflowEventsTableFilterComposer,
          $$WorkflowEventsTableOrderingComposer,
          $$WorkflowEventsTableAnnotationComposer,
          $$WorkflowEventsTableCreateCompanionBuilder,
          $$WorkflowEventsTableUpdateCompanionBuilder,
          (
            WorkflowEvent,
            BaseReferences<
              _$RudraDatabase,
              $WorkflowEventsTable,
              WorkflowEvent
            >,
          ),
          WorkflowEvent,
          PrefetchHooks Function()
        > {
  $$WorkflowEventsTableTableManager(
    _$RudraDatabase db,
    $WorkflowEventsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WorkflowEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WorkflowEventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WorkflowEventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> sequence = const Value.absent(),
                Value<String> event_id = const Value.absent(),
                Value<String> workflow_id = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<String> correlation_id = const Value.absent(),
                Value<String?> causation_id = const Value.absent(),
                Value<String> event_type = const Value.absent(),
                Value<String> payload_json = const Value.absent(),
                Value<int> recorded_at_unix_ms = const Value.absent(),
              }) => WorkflowEventsCompanion(
                sequence: sequence,
                event_id: event_id,
                workflow_id: workflow_id,
                version: version,
                correlation_id: correlation_id,
                causation_id: causation_id,
                event_type: event_type,
                payload_json: payload_json,
                recorded_at_unix_ms: recorded_at_unix_ms,
              ),
          createCompanionCallback:
              ({
                Value<int> sequence = const Value.absent(),
                required String event_id,
                required String workflow_id,
                required int version,
                required String correlation_id,
                Value<String?> causation_id = const Value.absent(),
                required String event_type,
                required String payload_json,
                required int recorded_at_unix_ms,
              }) => WorkflowEventsCompanion.insert(
                sequence: sequence,
                event_id: event_id,
                workflow_id: workflow_id,
                version: version,
                correlation_id: correlation_id,
                causation_id: causation_id,
                event_type: event_type,
                payload_json: payload_json,
                recorded_at_unix_ms: recorded_at_unix_ms,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$WorkflowEventsTable, WorkflowEvent>(table),
                  BaseReferences<
                    _$RudraDatabase,
                    $WorkflowEventsTable,
                    WorkflowEvent
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$WorkflowEventsTableProcessedTableManager =
    ProcessedTableManager<
      _$RudraDatabase,
      $WorkflowEventsTable,
      WorkflowEvent,
      $$WorkflowEventsTableFilterComposer,
      $$WorkflowEventsTableOrderingComposer,
      $$WorkflowEventsTableAnnotationComposer,
      $$WorkflowEventsTableCreateCompanionBuilder,
      $$WorkflowEventsTableUpdateCompanionBuilder,
      (
        WorkflowEvent,
        BaseReferences<_$RudraDatabase, $WorkflowEventsTable, WorkflowEvent>,
      ),
      WorkflowEvent,
      PrefetchHooks Function()
    >;
typedef $$UnfinishedWorkflowsTableCreateCompanionBuilder =
    UnfinishedWorkflowsCompanion Function({
      required String os_user_id,
      required String workflow_id,
      required String target_id,
      required String root_path,
      required int version,
      Value<int> rowid,
    });
typedef $$UnfinishedWorkflowsTableUpdateCompanionBuilder =
    UnfinishedWorkflowsCompanion Function({
      Value<String> os_user_id,
      Value<String> workflow_id,
      Value<String> target_id,
      Value<String> root_path,
      Value<int> version,
      Value<int> rowid,
    });

class $$UnfinishedWorkflowsTableFilterComposer
    extends Composer<_$RudraDatabase, $UnfinishedWorkflowsTable> {
  $$UnfinishedWorkflowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get os_user_id => $composableBuilder(
    column: $table.os_user_id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get workflow_id => $composableBuilder(
    column: $table.workflow_id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get target_id => $composableBuilder(
    column: $table.target_id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get root_path => $composableBuilder(
    column: $table.root_path,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );
}

class $$UnfinishedWorkflowsTableOrderingComposer
    extends Composer<_$RudraDatabase, $UnfinishedWorkflowsTable> {
  $$UnfinishedWorkflowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get os_user_id => $composableBuilder(
    column: $table.os_user_id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get workflow_id => $composableBuilder(
    column: $table.workflow_id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get target_id => $composableBuilder(
    column: $table.target_id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get root_path => $composableBuilder(
    column: $table.root_path,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$UnfinishedWorkflowsTableAnnotationComposer
    extends Composer<_$RudraDatabase, $UnfinishedWorkflowsTable> {
  $$UnfinishedWorkflowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get os_user_id => $composableBuilder(
    column: $table.os_user_id,
    builder: (column) => column,
  );

  GeneratedColumn<String> get workflow_id => $composableBuilder(
    column: $table.workflow_id,
    builder: (column) => column,
  );

  GeneratedColumn<String> get target_id =>
      $composableBuilder(column: $table.target_id, builder: (column) => column);

  GeneratedColumn<String> get root_path =>
      $composableBuilder(column: $table.root_path, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);
}

class $$UnfinishedWorkflowsTableTableManager
    extends
        RootTableManager<
          _$RudraDatabase,
          $UnfinishedWorkflowsTable,
          UnfinishedWorkflow,
          $$UnfinishedWorkflowsTableFilterComposer,
          $$UnfinishedWorkflowsTableOrderingComposer,
          $$UnfinishedWorkflowsTableAnnotationComposer,
          $$UnfinishedWorkflowsTableCreateCompanionBuilder,
          $$UnfinishedWorkflowsTableUpdateCompanionBuilder,
          (
            UnfinishedWorkflow,
            BaseReferences<
              _$RudraDatabase,
              $UnfinishedWorkflowsTable,
              UnfinishedWorkflow
            >,
          ),
          UnfinishedWorkflow,
          PrefetchHooks Function()
        > {
  $$UnfinishedWorkflowsTableTableManager(
    _$RudraDatabase db,
    $UnfinishedWorkflowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UnfinishedWorkflowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UnfinishedWorkflowsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$UnfinishedWorkflowsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> os_user_id = const Value.absent(),
                Value<String> workflow_id = const Value.absent(),
                Value<String> target_id = const Value.absent(),
                Value<String> root_path = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => UnfinishedWorkflowsCompanion(
                os_user_id: os_user_id,
                workflow_id: workflow_id,
                target_id: target_id,
                root_path: root_path,
                version: version,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String os_user_id,
                required String workflow_id,
                required String target_id,
                required String root_path,
                required int version,
                Value<int> rowid = const Value.absent(),
              }) => UnfinishedWorkflowsCompanion.insert(
                os_user_id: os_user_id,
                workflow_id: workflow_id,
                target_id: target_id,
                root_path: root_path,
                version: version,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$UnfinishedWorkflowsTable, UnfinishedWorkflow>(
                    table,
                  ),
                  BaseReferences<
                    _$RudraDatabase,
                    $UnfinishedWorkflowsTable,
                    UnfinishedWorkflow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$UnfinishedWorkflowsTableProcessedTableManager =
    ProcessedTableManager<
      _$RudraDatabase,
      $UnfinishedWorkflowsTable,
      UnfinishedWorkflow,
      $$UnfinishedWorkflowsTableFilterComposer,
      $$UnfinishedWorkflowsTableOrderingComposer,
      $$UnfinishedWorkflowsTableAnnotationComposer,
      $$UnfinishedWorkflowsTableCreateCompanionBuilder,
      $$UnfinishedWorkflowsTableUpdateCompanionBuilder,
      (
        UnfinishedWorkflow,
        BaseReferences<
          _$RudraDatabase,
          $UnfinishedWorkflowsTable,
          UnfinishedWorkflow
        >,
      ),
      UnfinishedWorkflow,
      PrefetchHooks Function()
    >;

class $RudraDatabaseManager {
  final _$RudraDatabase _db;
  $RudraDatabaseManager(this._db);
  $$WorkflowSubmissionsTableTableManager get workflowSubmissions =>
      $$WorkflowSubmissionsTableTableManager(_db, _db.workflowSubmissions);
  $$WorkflowEventsTableTableManager get workflowEvents =>
      $$WorkflowEventsTableTableManager(_db, _db.workflowEvents);
  $$UnfinishedWorkflowsTableTableManager get unfinishedWorkflows =>
      $$UnfinishedWorkflowsTableTableManager(_db, _db.unfinishedWorkflows);
}
