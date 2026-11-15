import 'package:drift/drift.dart';

/// Append-only history of committed workflow events.
///
/// Each event belongs to one workflow and occupies exactly
/// one workflow-local version.
///
/// Database sequence establishes global insertion order.
/// Workflow version establishes deterministic replay order.
///
/// The committed WorkflowStartedEvent records its trusted
/// OS-user identity in the dedicated os_user_id column.
///
/// An index on os_user_id and workflow_id enables efficient
/// owner-scoped history restoration without inspecting
/// serialized event payloads.
///
/// Ownership metadata is committed atomically with the
/// authoritative journal and unfinished-workflow projection.
///
/// The SDK remains responsible for validating ownership
/// against replayed domain events.
@TableIndex.sql('''
CREATE INDEX workflow_events_owner_idx
ON workflow_events (os_user_id, workflow_id)
''')
class WorkflowEvents extends Table {
  /// Database-local event sequence.
  IntColumn get sequence => integer().autoIncrement()();

  /// Stable identity of the committed event.
  TextColumn get event_id => text().unique()();

  /// Workflow receiving this event.
  TextColumn get workflow_id => text()();

  /// Trusted OS-user identity established at commit time.
  ///
  /// This is journal metadata, independent of serialized
  /// event payloads and the unfinished-workflow projection.
  ///
  /// Null for events without established ownership.
  TextColumn get os_user_id => text().nullable()();

  /// Version resulting from this event.
  IntColumn get version => integer()();

  /// Correlation identifier shared with its original request.
  TextColumn get correlation_id => text()();

  /// Event responsible for causing this event, if known.
  TextColumn get causation_id => text().nullable()();

  /// Stable domain event type.
  TextColumn get event_type => text()();

  /// Versioned event representation.
  TextColumn get payload_json => text()();

  /// UTC commit timestamp in Unix milliseconds.
  IntColumn get recorded_at_unix_ms => integer()();

  /// Prevents duplicate versions within a workflow.
  @override
  List<Set<Column>> get uniqueKeys => [
    {workflow_id, version},
  ];

  @override
  bool get isStrict => true;
}
