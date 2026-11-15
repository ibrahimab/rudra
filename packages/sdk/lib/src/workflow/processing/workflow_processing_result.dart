import '../event_submission_receipt.dart';
import 'workflow_processing_models.dart';
import 'workflow_submission_resolution.dart';

/// Result of attempting to process one pending workflow command.
///
/// Normal processing outcomes are represented as values.
/// Unexpected processing or persistence failures still throw.
///
/// This is an immediate operation result, not the durable
/// submission status queried by frontends after reconnection.
sealed class WorkflowProcessingResult {
  /// Creates a processing result.
  const WorkflowProcessingResult();
}

/// No pending command was available for processing.
final class WorkflowProcessingIdle extends WorkflowProcessingResult {
  /// Creates an idle processing result.
  const WorkflowProcessingIdle();
}

/// A workflow processing plan was successfully committed.
final class WorkflowProcessingCommitted extends WorkflowProcessingResult {
  /// Creates a result after authoritative commitment succeeds.
  const WorkflowProcessingCommitted({required this.plan});

  /// Validated plan whose changes were committed.
  final WorkflowProcessingPlan plan;
}

/// A business rejection was successfully persisted.
final class WorkflowProcessingRejected extends WorkflowProcessingResult {
  /// Creates a result after rejection persistence succeeds.
  const WorkflowProcessingRejected({required this.receipt, required this.code});

  /// Original accepted command's receipt.
  final EventSubmissionReceipt receipt;

  /// Durable business rejection classification.
  final WorkflowRejectionCode code;
}
