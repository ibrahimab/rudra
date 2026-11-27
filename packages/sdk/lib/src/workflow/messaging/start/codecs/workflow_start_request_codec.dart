import 'package:rudra_communication/rudra_communication.dart';
import 'package:rudra_target_contracts/rudra_target_contracts.dart';

import '../workflow_start_request.dart';

/// Serializes workflow establishment requests.
///
/// Preserves the target-native path and durable idempotency key.
///
/// Example:
/// ```dart
/// const codec = WorkflowStartRequestCodec();
/// final decoded = codec.decode(codec.encode(request));
/// ```
final class WorkflowStartRequestCodec
    implements MessageCodec<WorkflowStartRequest> {
  /// Creates the stateless Start request codec.
  const WorkflowStartRequestCodec();

  /// Stable wire identifier of the version 2 Start request.
  @override
  String get type_id => 'rudra.workflow.start.request.v2';

  /// Converts [message] into its structured application payload.
  ///
  /// Returns the requested root and idempotency key.
  @override
  Map<String, Object?> encode(WorkflowStartRequest message) {
    return {
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
    if (payload is! Map<String, Object?> || payload.length != 2) {
      throw const FormatException('Invalid workflow Start request payload.');
    }

    final root = payload['root'];
    final idempotency_key = payload['idempotency_key'];

    if (root is! String || idempotency_key is! String) {
      throw const FormatException('Invalid workflow Start request fields.');
    }

    try {
      return WorkflowStartRequest(
        root: TargetPath(root),
        idempotency_key: idempotency_key,
      );
    } on ArgumentError {
      throw const FormatException('Invalid workflow Start request values.');
    }
  }
}
