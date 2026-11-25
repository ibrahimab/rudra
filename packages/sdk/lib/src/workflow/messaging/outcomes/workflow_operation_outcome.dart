import '../../processing/workflow_submission_resolution.dart';

/// Application outcome of a workflow operation.
///
/// Distinguishes operations with a durable submission resolution
/// from conflicting attempts to reuse an idempotency key.
///
/// Operation outcomes remain independent of communication
/// delivery and the currently established workflow.
sealed class WorkflowOperationOutcome {
  /// Creates a workflow operation outcome.
  const WorkflowOperationOutcome();
}

/// Represents an operation associated with a durable submission.
///
/// The submission may still be pending or may have reached
/// a completed, rejected or quarantined processing state.
///
/// Example:
/// ```dart
/// final outcome = WorkflowOperationResolved(
///   resolution: resolution,
/// );
///
/// print(outcome.resolution.state);
/// ```
final class WorkflowOperationResolved extends WorkflowOperationOutcome {
  /// Creates an outcome containing the supplied [resolution].
  const WorkflowOperationResolved({required this.resolution});

  /// Durable processing resolution of the accepted submission.
  ///
  /// Completion describes the original operation rather than
  /// the current lifecycle or state of the affected workflow.
  final WorkflowSubmissionResolution resolution;
}

/// Represents conflicting reuse of a durable idempotency key.
///
/// The supplied key belongs to a different logical operation.
/// The original submission remains unchanged and no new
/// submission receipt is established.
final class WorkflowOperationIdempotencyConflict
    extends WorkflowOperationOutcome {
  /// Creates an idempotency conflict outcome.
  const WorkflowOperationIdempotencyConflict();
}
