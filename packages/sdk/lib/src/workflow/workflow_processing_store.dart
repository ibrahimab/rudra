import 'event_submission_receipt.dart';
import 'events/workflow_event.dart';
import 'states/workflow_state.dart';
import 'workflow_identity.dart';

/// A pending command loaded from durable persistence.
///
/// The identity is proposed by trusted processing infrastructure.
/// It is not authoritative until the transaction commits.
final class PendingWorkflowCommand {
  /// Creates an immutable pending command snapshot.
  PendingWorkflowCommand({
    required this.receipt,
    required this.command,
    required this.identity,
    Iterable<WorkflowEvent> committed_events = const [],
  }) : committed_events = List.unmodifiable(committed_events);

  /// Original durable submission receipt.
  final EventSubmissionReceipt receipt;

  /// Reconstructed typed command.
  final WorkflowCommandEvent command;

  /// Proposed workflow identity from a trusted boundary.
  final WorkflowIdentity identity;

  /// Previously committed events, in workflow-version order.
  final List<WorkflowEvent> committed_events;
}

/// A validated proposal for atomic durable commitment.
///
/// The appended events contain the command and its outcomes,
/// but exclude previously committed workflow events.
final class WorkflowProcessingPlan {
  /// Creates an immutable processing plan.
  WorkflowProcessingPlan({
    required this.submission,
    required this.previous_state,
    required this.resulting_state,
    required Iterable<WorkflowEvent> events_to_append,
  }) : events_to_append = List.unmodifiable(events_to_append);

  /// Pending submission being processed.
  final PendingWorkflowCommand submission;

  /// State reconstructed before processing the command.
  final WorkflowState previous_state;

  /// State produced by applying the proposed new events.
  final WorkflowState resulting_state;

  /// Events to persist in the authoritative journal.
  final List<WorkflowEvent> events_to_append;
}

/// Transactional persistence boundary for workflow processing.
///
/// Implementations must commit the journal append, workflow
/// ownership projection, and submission completion atomically.
///
/// The commit must reject stale submissions, version conflicts,
/// and conflicting unfinished-workflow ownership.
///
/// A failed transaction must leave the submission recoverable.
abstract interface class WorkflowProcessingStore {
  /// Returns the next pending command or null if none exists.
  ///
  /// The store must derive owner identity from trusted context.
  Future<PendingWorkflowCommand?> next_pending();

  /// Atomically commits a validated processing plan.
  ///
  /// Successful completion means all associated database
  /// changes were committed, not merely queued.
  Future<void> commit(WorkflowProcessingPlan plan);
}
