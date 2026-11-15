import '../event_submission_receipt.dart';
import 'workflow_processing_models.dart';

/// Durable processing states of an accepted submission.
enum WorkflowSubmissionState {
  /// Accepted but not yet resolved.
  pending,

  /// Successfully processed and committed.
  completed,

  /// Definitively refused by a business rule.
  rejected,
}

/// Stable reasons for refusing an accepted workflow command.
///
/// These codes form part of the persisted submission contract.
/// Once introduced, their names must remain stable.
enum WorkflowRejectionCode {
  /// The trusted OS user already owns an unfinished workflow.
  ownership_conflict,
}

/// Queryable resolution of a previously accepted submission.
///
/// This represents submission processing, not the workflow's
/// event-sourced lifecycle state.
final class WorkflowSubmissionResolution {
  /// Creates an immutable view of submission processing.
  const WorkflowSubmissionResolution({
    required this.receipt,
    required this.state,
    this.rejection_code,
    this.rejected_at_unix_ms,
  });

  /// Original accepted submission receipt.
  final EventSubmissionReceipt receipt;

  /// Current durable processing state.
  final WorkflowSubmissionState state;

  /// Business rejection reason, if rejected.
  final WorkflowRejectionCode? rejection_code;

  /// UTC rejection timestamp in Unix milliseconds.
  final int? rejected_at_unix_ms;
}

/// Read-only access to authoritative submission resolution.
///
/// Frontends can query by receipt after reconnecting and
/// do not need to have observed a transient notification.
abstract interface class WorkflowSubmissionStatusReader {
  /// Finds a submission's resolution within the trusted scope.
  ///
  /// Returns null when no matching submission is accessible.
  Future<WorkflowSubmissionResolution?> status_for(
    EventSubmissionReceipt receipt,
  );
}

/// Durable persistence boundary for business rejections.
///
/// Implementations must atomically change an eligible pending
/// submission into a rejected submission with its reason.
///
/// A stale or completed submission must never be overwritten.
abstract interface class WorkflowSubmissionRejector {
  /// Persists the confirmed rejection of a pending command.
  Future<void> reject({
    required PendingWorkflowCommand submission,
    required WorkflowRejectionCode code,
  });
}

/// Indicates a submission was durably rejected.
///
/// This exception is raised only after rejection persistence
/// succeeds. It is not used for transient infrastructure errors.
final class WorkflowSubmissionRejectedException implements Exception {
  /// Creates a typed rejection notification.
  const WorkflowSubmissionRejectedException({
    required this.receipt,
    required this.code,
  });

  /// Accepted request that was rejected.
  final EventSubmissionReceipt receipt;

  /// Persisted business rejection reason.
  final WorkflowRejectionCode code;

  @override
  String toString() =>
      'WorkflowSubmissionRejectedException(${code.name}): '
      '${receipt.event_id}';
}
