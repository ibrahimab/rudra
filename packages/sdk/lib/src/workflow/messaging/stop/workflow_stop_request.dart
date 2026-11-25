import 'package:rudra_communication/rudra_communication.dart';

import 'workflow_stop_response.dart';

/// Requests termination of a specific workflow through communication.
///
/// The workflow identifier binds the operation to the intended
/// workflow rather than whichever workflow happens to be active
/// when the request is processed.
///
/// Example:
/// ```dart
/// final request = WorkflowStopRequest(
///   workflow_id: 'workflow-001',
///   idempotency_key: 'operation-002',
/// );
/// ```
final class WorkflowStopRequest implements Request<WorkflowStopResponse> {
  /// Creates a workflow termination request.
  ///
  /// [workflow_id] identifies the intended workflow.
  /// [idempotency_key] identifies the logical operation across retries.
  ///
  /// Throws [ArgumentError] if either identifier is blank.
  WorkflowStopRequest({
    required this.workflow_id,
    required this.idempotency_key,
  }) {
    if (workflow_id.trim().isEmpty) {
      throw ArgumentError.value(
        workflow_id,
        'workflow_id',
        'Workflow identifier must not be blank.',
      );
    }

    if (idempotency_key.trim().isEmpty) {
      throw ArgumentError.value(
        idempotency_key,
        'idempotency_key',
        'Idempotency key must not be blank.',
      );
    }
  }

  /// Identifier of the workflow intended to be stopped.
  final String workflow_id;

  /// Durable identity of the logical application operation.
  ///
  /// Retries must preserve both this key and the original
  /// workflow identifier.
  final String idempotency_key;
}
