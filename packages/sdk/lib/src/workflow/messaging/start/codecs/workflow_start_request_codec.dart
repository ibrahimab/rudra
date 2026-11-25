import 'package:rudra_communication/rudra_communication.dart';
import 'package:rudra_target_contracts/rudra_target_contracts.dart';

import '../workflow_start_request.dart';

/// Serializes workflow establishment requests.
///
/// Preserves the requested target, target-native path and
/// durable idempotency key without normalization.
final class WorkflowStartRequestCodec
    implements MessageCodec<WorkflowStartRequest> {
  /// Creates the stateless Start request codec.
  const WorkflowStartRequestCodec();

  /// Stable wire identifier of the version 1 Start request.
  @override
  String get type_id => 'rudra.workflow.start.request.v1';

  /// Converts [message] into its structured application payload.
  ///
  /// Returns the requested target, root and idempotency key.
  @override
  Map<String, Object?> encode(WorkflowStartRequest message) {
    return {
      'target_id': message.target_id,
      'root': message.root.value,
      'idempotency_key': message.idempotency_key,
    };
  }

  /// Reconstructs a workflow establishment request from [payload].
  ///
  /// Returns a validated request preserving its original values.
  ///
  /// Throws [FormatException] for malformed representations,
  /// unexpected fields or invalid application values.
  @override
  WorkflowStartRequest decode(Object? payload) {
    if (payload is! Map<String, Object?> || payload.length != 3) {
      throw const FormatException('Invalid workflow Start request payload.');
    }

    final target_id = payload['target_id'];
    final root = payload['root'];
    final idempotency_key = payload['idempotency_key'];

    if (target_id is! String || root is! String || idempotency_key is! String) {
      throw const FormatException('Invalid workflow Start request fields.');
    }

    try {
      return WorkflowStartRequest(
        target_id: target_id,
        root: TargetPath(root),
        idempotency_key: idempotency_key,
      );
    } on ArgumentError {
      throw const FormatException('Invalid workflow Start request values.');
    }
  }
}
