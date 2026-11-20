import '../event_submission_receipt.dart';
import '../events/workflow_event.dart';
import '../states/workflow_snapshot.dart';

/// A pending command reconstructed from the durable submission inbox.
///
/// [command] represents the accepted user or application request.
/// [committed_events] contains previously committed domain outcomes
/// in workflow-version order.
///
/// Submission commands are not part of the authoritative workflow
/// journal and must not appear in [committed_events].
///
/// [scope_id] comes from trusted submission persistence. It is
/// not automatically an authenticated operating-system identity.
///
/// This object does not reserve the submission for processing.
final class PendingWorkflowCommand {
  /// Creates an immutable pending command snapshot.
  ///
  /// [receipt] identifies the accepted submission.
  /// [scope_id] identifies its durable processing scope.
  /// [command] contains the decoded typed command.
  /// [committed_events] contains prior domain outcomes, if any.
  ///
  /// The outcome collection is defensively copied.
  ///
  /// Throws [ArgumentError] for a blank submission scope.
  PendingWorkflowCommand({
    required this.receipt,
    required this.scope_id,
    required this.command,
    Iterable<WorkflowOutcomeEvent> committed_events = const [],
  }) : committed_events = List.unmodifiable(committed_events) {
    if (scope_id.trim().isEmpty) {
      throw ArgumentError.value(
        scope_id,
        'scope_id',
        'Submission scope must not be blank.',
      );
    }
  }

  /// Receipt identifying the accepted durable submission.
  final EventSubmissionReceipt receipt;

  /// Trusted processing scope associated with this submission.
  final String scope_id;

  /// Submitted command expressing the requested operation.
  final WorkflowCommandEvent command;

  /// Previously committed workflow outcomes in version order.
  ///
  /// An empty collection indicates that no current workflow
  /// history was supplied for this processing operation.
  ///
  /// The processor must distinguish this from an integrity
  /// failure, which must propagate rather than become absence.
  final List<WorkflowOutcomeEvent> committed_events;
}

/// A validated domain-change proposal awaiting atomic commitment.
///
/// The processor validates the submitted command, computes
/// proposed outcomes through a registered SDK behavior, and
/// applies them through the authoritative workflow state machine.
///
/// [previous_state] is null before workflow establishment.
/// [resulting_state] is the proposed immutable workflow snapshot.
///
/// [events_to_append] contains only domain outcomes. Submitted
/// commands remain in the durable inbox and do not increment
/// workflow versions.
///
/// This plan is not authoritative until the persistence committer
/// independently validates and atomically commits the proposal.
///
/// The committer must recheck submission eligibility, trusted
/// ownership, prior journal state, identity, expected version,
/// and the proposed outcomes inside its transaction.
final class WorkflowProcessingPlan {
  /// Creates an immutable workflow processing proposal.
  ///
  /// [submission] identifies the command being processed.
  /// [previous_state] is the last validated committed snapshot.
  /// [resulting_state] is the validated proposed next snapshot.
  /// [events_to_append] contains the proposed domain outcomes.
  ///
  /// The supplied outcome collection is defensively copied.
  ///
  /// Construction does not commit or publish domain state.
  WorkflowProcessingPlan({
    required this.submission,
    required this.previous_state,
    required this.resulting_state,
    required Iterable<WorkflowOutcomeEvent> events_to_append,
  }) : events_to_append = List.unmodifiable(events_to_append);

  /// Accepted command whose processing produced this proposal.
  final PendingWorkflowCommand submission;

  /// Prior committed workflow state, or null before establishment.
  final WorkflowSnapshot? previous_state;

  /// Proposed resulting immutable workflow state.
  final WorkflowSnapshot resulting_state;

  /// Domain outcomes to append to the authoritative journal.
  ///
  /// Each committed outcome advances the workflow-local version
  /// exactly once. Commands are never included in this collection.
  final List<WorkflowOutcomeEvent> events_to_append;
}
