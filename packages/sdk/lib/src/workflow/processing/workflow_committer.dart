import 'workflow_processing_models.dart';

/// Atomic persistence boundary for validated workflow changes.
///
/// Implementations must commit the following together:
///
/// - New authoritative workflow events.
/// - Unfinished-workflow ownership changes.
/// - Completion of the accepted submission.
///
/// The transaction must reject stale submissions, version
/// conflicts, and conflicting workflow ownership.
///
/// Failure must not partially commit a workflow.
abstract interface class WorkflowCommitter {
  /// Atomically commits a validated processing proposal.
  ///
  /// Returns only after the transaction has committed.
  Future<void> commit(WorkflowProcessingPlan plan);
}
