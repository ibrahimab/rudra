import '../event_submission_receipt.dart';
import 'workflow_processing_models.dart';
import 'workflow_quarantine.dart';

/// Durable processing states of an accepted submission.
enum WorkflowSubmissionState {
  /// Accepted but not yet resolved.
  pending,

  /// Successfully processed and committed.
  completed,

  /// Definitively refused by a business rule.
  rejected,

  /// Preserved for investigation because the command could not
  /// be interpreted safely by the registered serializers.
  quarantined,
}

/// Stable reasons for refusing an accepted workflow command.
///
/// These identifiers are persisted with submission resolutions.
enum WorkflowRejectionCode {
  /// The trusted OS user already owns an unfinished workflow.
  ownership_conflict,

  /// A stop request has no established active workflow.
  workflow_not_active,

  /// A stop request targets a different active workflow.
  workflow_id_mismatch,
}

/// Identifies the last journal outcome committed by one submission.
///
/// The persistence adapter resolves this reference through the journal's
/// causation identity, rather than inferring it from the current projection.
/// [sequence] is database-global; [version] is workflow-local.
final class WorkflowCommittedOutcome {
  /// Creates a validated reference to a committed outcome.
  ///
  /// [workflow_id] identifies the affected workflow. [event_type] is its
  /// registered outcome identifier. [version] and [sequence] must be positive.
  /// Invalid values throw [ArgumentError].
  WorkflowCommittedOutcome({
    required this.workflow_id,
    required this.event_type,
    required this.version,
    required this.sequence,
  }) {
    if (workflow_id.trim().isEmpty ||
        event_type.trim().isEmpty ||
        version <= 0 ||
        sequence <= 0) {
      throw ArgumentError('Invalid committed workflow outcome reference.');
    }
  }

  /// Immutable identifier of the workflow affected by the submission.
  final String workflow_id;

  /// Registered identifier of its final committed domain outcome.
  final String event_type;

  /// Workflow-local version of the final outcome.
  final int version;

  /// Database-global journal sequence of the final outcome.
  final int sequence;
}

/// Queryable resolution of a previously accepted submission.
///
/// This represents submission processing, not the workflow's
/// event-sourced lifecycle state. A completed resolution references the
/// submission's own committed journal outcome; it never supplies a substitute
/// current-workflow snapshot.
final class WorkflowSubmissionResolution {
  /// Creates an immutable view of submission processing.
  ///
  /// [receipt] identifies the accepted request and [state] its durable
  /// processing condition. [committed_outcome] identifies confirmed journal
  /// evidence for a completed request. [rejection_code] and
  /// [rejected_at_unix_ms] describe an expected business rejection.
  /// [quarantine_code], [quarantine_diagnostic] and
  /// [quarantined_at_unix_ms] describe a preserved unreadable submission.
  const WorkflowSubmissionResolution({
    required this.receipt,
    required this.state,
    this.committed_outcome,
    this.rejection_code,
    this.rejected_at_unix_ms,
    this.quarantine_code,
    this.quarantine_diagnostic,
    this.quarantined_at_unix_ms,
  });

  /// Original accepted submission receipt.
  final EventSubmissionReceipt receipt;

  /// Current durable processing state.
  final WorkflowSubmissionState state;

  /// Journal outcome linked to a successfully completed submission.
  ///
  /// Must be supplied by a trustworthy persistence adapter for completion.
  /// A missing value is an integrity failure for confirmed SDK operations.
  final WorkflowCommittedOutcome? committed_outcome;

  /// Business rejection reason, if rejected.
  final WorkflowRejectionCode? rejection_code;

  /// UTC rejection timestamp in Unix milliseconds.
  final int? rejected_at_unix_ms;

  /// Reason the submission was quarantined.
  final WorkflowQuarantineCode? quarantine_code;

  /// Diagnostic recorded when quarantine was committed.
  ///
  /// This must not contain the original serialized payload.
  final String? quarantine_diagnostic;

  /// UTC quarantine timestamp in Unix milliseconds.
  final int? quarantined_at_unix_ms;
}

/// Read-only access to authoritative submission resolution.
///
/// Frontends can query by receipt after reconnecting and
/// do not need to have observed a transient notification.
abstract interface class WorkflowSubmissionStatusReader {
  /// Finds a submission's resolution within the trusted scope.
  ///
  /// [receipt] contains the original event and correlation identifiers.
  /// Returns null when no matching submission is accessible. Completed
  /// results must include a causally linked [WorkflowCommittedOutcome].
  /// Read and journal-integrity failures propagate.
  Future<WorkflowSubmissionResolution?> status_for(
    EventSubmissionReceipt receipt,
  );
}

/// Durable persistence boundary for business rejections.
///
/// Implementations must atomically change an eligible pending
/// submission into a rejected submission with its reason.
/// A stale or completed submission must never be overwritten.
abstract interface class WorkflowSubmissionRejector {
  /// Persists the confirmed rejection of a pending [submission].
  ///
  /// [code] classifies the business conflict. The operation completes only
  /// after the rejection is durable; persistence failures propagate.
  Future<void> reject({
    required PendingWorkflowCommand submission,
    required WorkflowRejectionCode code,
  });
}
