import '../event_submission_receipt.dart';
import '../events/workflow_event.dart';
import '../states/workflow_state.dart';

/// A pending command reconstructed from the durable inbox.
///
/// The scope originates from trusted submission persistence.
/// It must not be treated as an authenticated OS-user identity.
///
/// This snapshot does not reserve the submission for processing.
final class PendingWorkflowCommand {
  /// Creates an immutable pending command snapshot.
  PendingWorkflowCommand({
    required this.receipt,
    required this.scope_id,
    required this.command,
    Iterable<WorkflowEvent> committed_events = const [],
  }) : committed_events = List.unmodifiable(committed_events) {
    if (scope_id.trim().isEmpty) {
      throw ArgumentError.value(scope_id, 'scope_id');
    }
  }

  /// Receipt identifying the accepted submission.
  final EventSubmissionReceipt receipt;

  /// Trusted scope associated with the submission.
  final String scope_id;

  /// Reconstructed typed command.
  final WorkflowCommandEvent command;

  /// Previously committed events in workflow-version order.
  final List<WorkflowEvent> committed_events;
}

/// A validated proposal awaiting atomic persistence.
///
/// The processor creates this plan after applying every
/// proposed event through the workflow state machine.
///
/// The persistence boundary must still verify expected
/// versions, ownership, and the submission's pending status.
final class WorkflowProcessingPlan {
  /// Creates an immutable processing proposal.
  WorkflowProcessingPlan({
    required this.submission,
    required this.previous_state,
    required this.resulting_state,
    required Iterable<WorkflowEvent> events_to_append,
  }) : events_to_append = List.unmodifiable(events_to_append);

  /// Submission being processed.
  final PendingWorkflowCommand submission;

  /// State before the proposed transitions.
  final WorkflowState previous_state;

  /// State resulting from the proposed transitions.
  final WorkflowState resulting_state;

  /// New events to append to the authoritative journal.
  final List<WorkflowEvent> events_to_append;
}
