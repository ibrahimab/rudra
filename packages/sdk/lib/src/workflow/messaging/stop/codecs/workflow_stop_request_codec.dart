import 'package:rudra_communication/rudra_communication.dart';

import '../workflow_stop_request.dart';

/// Serializes requests to terminate a specific workflow.
///
/// Preserves the intended workflow identity and durable
/// idempotency key without normalization.
final class WorkflowStopRequestCodec
    implements MessageCodec<WorkflowStopRequest> {
  /// Creates the stateless Stop request codec.
  const WorkflowStopRequestCodec();

  /// Stable wire identifier of the version 1 Stop request.
  @override
  String get type_id => 'rudra.workflow.stop.request.v1';

  /// Converts [message] into its structured application payload.
  ///
  /// Returns the intended workflow identifier and idempotency key.
  @override
  Map<String, Object?> encode(WorkflowStopRequest message) {
    return {
      'workflow_id': message.workflow_id,
      'idempotency_key': message.idempotency_key,
    };
  }

  /// Reconstructs a workflow termination request from [payload].
  ///
  /// Returns a validated request preserving both identifiers.
  ///
  /// Throws [FormatException] for malformed representations,
  /// unexpected fields or invalid identifiers.
  @override
  WorkflowStopRequest decode(Object? payload) {
    if (payload is! Map<String, Object?> || payload.length != 2) {
      throw const FormatException('Invalid workflow Stop request payload.');
    }

    final workflow_id = payload['workflow_id'];
    final idempotency_key = payload['idempotency_key'];

    if (workflow_id is! String || idempotency_key is! String) {
      throw const FormatException('Invalid workflow Stop request fields.');
    }

    try {
      return WorkflowStopRequest(
        workflow_id: workflow_id,
        idempotency_key: idempotency_key,
      );
    } on ArgumentError {
      throw const FormatException('Invalid workflow Stop request identifiers.');
    }
  }
}
