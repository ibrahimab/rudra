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
    this.quarantine_code,
    this.quarantine_diagnostic,
    this.quarantined_at_unix_ms,
  });

  /// Original accepted submission receipt.
  final EventSubmissionReceipt receipt;

  /// Current durable processing state.
  final WorkflowSubmissionState state;

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
