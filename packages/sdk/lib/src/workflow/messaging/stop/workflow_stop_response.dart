import 'package:rudra_communication/rudra_communication.dart';

import '../../application/outcomes/workflow_operation_outcome.dart';

/// Application response to a workflow termination request.
///
/// Describes the requested operation independently of any
/// subsequently established workflow.
///
/// Example:
/// ```dart
/// final response = WorkflowStopResponse(
///   outcome: WorkflowOperationResolved(
///     resolution: resolution,
///   ),
/// );
/// ```
final class WorkflowStopResponse implements Response {
  /// Creates a Stop response containing [outcome].
  const WorkflowStopResponse({required this.outcome});

  /// Durable submission resolution or idempotency conflict
  /// associated with the requested termination operation.
  final WorkflowOperationOutcome outcome;
}
