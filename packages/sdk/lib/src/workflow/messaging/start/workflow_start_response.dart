import 'package:rudra_communication/rudra_communication.dart';

import '../outcomes/workflow_operation_outcome.dart';

/// Application response to a workflow establishment request.
///
/// Describes the requested operation independently of the
/// currently active workflow.
///
/// Example:
/// ```dart
/// final response = WorkflowStartResponse(
///   outcome: WorkflowOperationResolved(
///     resolution: resolution,
///   ),
/// );
/// ```
final class WorkflowStartResponse implements Response {
  /// Creates a Start response containing [outcome].
  const WorkflowStartResponse({required this.outcome});

  /// Durable submission resolution or idempotency conflict
  /// associated with the requested establishment operation.
  final WorkflowOperationOutcome outcome;
}
