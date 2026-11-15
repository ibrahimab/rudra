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

/// Complete committed history belonging to one workflow.
///
/// The journal may represent an active, terminal, or
/// inconsistent workflow. Its lifecycle is determined only
/// by replaying events through the SDK state machine.
final class WorkflowHistoryJournal {
  /// Creates an immutable journal snapshot.
  WorkflowHistoryJournal({
    required this.workflow_id,
    required Iterable<WorkflowJournalEntry> journal,
  }) : journal = List<WorkflowJournalEntry>.unmodifiable(journal);

  /// Workflow identifier associated with the journal.
  final String workflow_id;

  /// Committed events in ascending workflow-version order.
  final List<WorkflowJournalEntry> journal;
}

/// Consistent persisted evidence for workflow restoration.
///
/// [projected] identifies the workflow currently reserved for
/// the requested OS user, if one exists.
///
/// [other_histories] contains journal histories not associated
/// with that projection. The SDK checks these histories to
/// detect active workflows whose ownership projection is
/// missing, incorrect, or duplicated.
///
/// All data must originate from one consistent persistence
/// snapshot. This contract is intended for trusted application
/// composition, not direct frontend access.
///
/// The store does not determine lifecycle state.
final class WorkflowRestorationEvidence {
  /// Creates immutable restoration evidence.
  WorkflowRestorationEvidence({
    required this.projected,
    required Iterable<WorkflowHistoryJournal> other_histories,
  }) : other_histories = List<WorkflowHistoryJournal>.unmodifiable(
         other_histories,
       );

  /// User's projected unfinished workflow, if present.
  final WorkflowHistorySnapshot? projected;

  /// Other committed histories requiring integrity inspection.
  final List<WorkflowHistoryJournal> other_histories;
}

/// Read-only persistence contract for workflow restoration.
///
/// A trusted persistence implementation returns all relevant
/// journal evidence from one consistent snapshot.
///
/// The SDK determines lifecycle state and detects an active
/// workflow missing its expected ownership projection.
///
/// Implementations must not process commands, commit events,
/// repair projections, or perform filesystem operations.
///
/// The identity is supplied by trusted application composition.
/// Submission scopes are not authenticated OS-user identities.
abstract interface class WorkflowHistoryStore {
  /// Loads consistent restoration evidence for [os_user_id].
  ///
  /// Returns an evidence object even when no unfinished
  /// workflow projection is present.
  ///
  /// Other histories must not be omitted merely because
  /// their current ownership projection is absent.
  Future<WorkflowRestorationEvidence> load_restoration_evidence({
    required String os_user_id,
  });
}
