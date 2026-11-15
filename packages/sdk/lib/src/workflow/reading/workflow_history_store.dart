import '../workflow_identity.dart';

/// One committed event from the authoritative workflow journal.
///
/// Sequence is database-global and need not be contiguous
/// within a single workflow. Version is workflow-local and
/// must advance exactly once for every committed event.
///
/// The payload remains encoded until the SDK reader decodes
/// it using its configured WorkflowRuntime.
final class WorkflowJournalEntry {
  /// Creates an immutable committed journal entry.
  const WorkflowJournalEntry({
    required this.sequence,
    required this.event_id,
    required this.workflow_id,
    required this.version,
    required this.event_type,
    required this.payload_json,
  });

  /// Database-global insertion sequence.
  final int sequence;

  /// Unique persisted event identifier.
  final String event_id;

  /// Workflow owning this event.
  final String workflow_id;

  /// Workflow-local version produced by the event.
  final int version;

  /// Stable domain event type identifier.
  final String event_type;

  /// Versioned serialized event payload.
  final String payload_json;
}

/// Consistent persisted snapshot for one unfinished workflow.
///
/// The projection is used to locate the workflow and verify
/// its ownership. Its contents are not authoritative until
/// checked against the committed journal.
///
/// Implementations must read the projection and journal from
/// one consistent database snapshot.
///
/// Construction performs no validation or persistence I/O.
final class WorkflowHistorySnapshot {
  /// Creates an immutable history snapshot.
  WorkflowHistorySnapshot({
    required this.projected_identity,
    required this.projected_version,
    required Iterable<WorkflowJournalEntry> journal,
  }) : journal = List<WorkflowJournalEntry>.unmodifiable(journal);

  /// Identity and bindings recorded in the unfinished projection.
  final WorkflowIdentity projected_identity;

  /// Version recorded in the unfinished projection.
  final int projected_version;

  /// Committed events in ascending workflow-version order.
  final List<WorkflowJournalEntry> journal;
}

/// Read-only persistence contract for workflow restoration.
///
/// Implementations retrieve a consistent snapshot associated
/// with a trusted operating-system user identity.
///
/// The caller must obtain this identity through a trusted
/// platform or application composition boundary.
///
/// Submission scopes, terminal input, environment usernames,
/// and frontend-provided strings are not authentication.
///
/// Reading must never submit events, process commands, repair
/// projections, or modify workflow lifecycle state.
///
/// An absent unfinished workflow returns null.
abstract interface class WorkflowHistoryStore {
  /// Loads the unfinished workflow associated with [os_user_id].
  ///
  /// The returned journal must include all committed events,
  /// starting at workflow version one.
  ///
  /// Contradictory persisted data must not be silently repaired.
  Future<WorkflowHistorySnapshot?> load_unfinished({
    required String os_user_id,
  });
}
