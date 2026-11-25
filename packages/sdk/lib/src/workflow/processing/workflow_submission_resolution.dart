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
///
/// Example:
/// ```dart
/// final outcome = WorkflowCommittedOutcome(
///   workflow_id: 'workflow-1',
///   event_type: WorkflowStartedEvent.type_id,
///   version: 1,
///   sequence: 42,
/// );
/// print(outcome.workflow_id);
/// ```
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
/// Represents submission processing independently of the workflow's
/// event-sourced lifecycle. A completed resolution references the
/// submission's own committed journal outcome.
///
/// Each processing state requires its corresponding resolution metadata
/// and excludes metadata belonging to other states.
///
/// Example:
/// ```dart
/// final resolution = WorkflowSubmissionResolution(
///   receipt: receipt,
///   state: WorkflowSubmissionState.pending,
/// );
///
/// print(resolution.state);
/// ```
final class WorkflowSubmissionResolution {
  /// Creates a validated immutable submission resolution.
  ///
  /// [receipt] identifies the original accepted command.
  /// [state] identifies its durable processing condition.
  ///
  /// Completed resolutions require [committed_outcome].
  /// Rejected resolutions require [rejection_code] and
  /// [rejected_at_unix_ms].
  /// Quarantined resolutions require [quarantine_code] and
  /// [quarantined_at_unix_ms], with an optional internal
  /// [quarantine_diagnostic].
  ///
  /// Pending resolutions contain no terminal resolution metadata.
  ///
  /// Throws [ArgumentError] when required metadata is missing
  /// or metadata contradicts the declared processing state.
  WorkflowSubmissionResolution({
    required this.receipt,
    required this.state,
    this.committed_outcome,
    this.rejection_code,
    this.rejected_at_unix_ms,
    this.quarantine_code,
    this.quarantine_diagnostic,
    this.quarantined_at_unix_ms,
  }) {
    final is_completed = state == WorkflowSubmissionState.completed;
    final is_rejected = state == WorkflowSubmissionState.rejected;
    final is_quarantined = state == WorkflowSubmissionState.quarantined;

    // Terminal metadata must belong exclusively to its declared state.
    if ((committed_outcome != null) != is_completed ||
        (rejection_code != null) != is_rejected ||
        (rejected_at_unix_ms != null) != is_rejected ||
        (quarantine_code != null) != is_quarantined ||
        (quarantined_at_unix_ms != null) != is_quarantined ||
        (!is_quarantined && quarantine_diagnostic != null)) {
      throw ArgumentError(
        'Resolution metadata contradicts its processing state.',
      );
    }
  }

  /// Original accepted submission receipt.
  final EventSubmissionReceipt receipt;

  /// Durable processing state of the accepted submission.
  final WorkflowSubmissionState state;

  /// Final committed journal outcome, present exclusively on completion.
  final WorkflowCommittedOutcome? committed_outcome;

  /// Business rejection classification, present exclusively on rejection.
  final WorkflowRejectionCode? rejection_code;

  /// UTC rejection timestamp in Unix milliseconds.
  final int? rejected_at_unix_ms;

  /// Quarantine classification, present exclusively on quarantine.
  final WorkflowQuarantineCode? quarantine_code;

  /// Optional internal diagnostic associated with quarantine.
  ///
  /// Must not contain the original serialized payload.
  /// Application messaging excludes this diagnostic from its
  /// serialized representation.
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
