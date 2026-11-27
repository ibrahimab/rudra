import 'package:rudra_communication/rudra_communication.dart';
import 'package:rudra_target_contracts/rudra_target_contracts.dart';

import 'workflow_start_response.dart';

/// Requests establishment of a workflow through communication.
///
/// Identifies the intended inspection root. The host determines the
/// filesystem target and trusted submitting identity.
///
/// Example:
/// ```dart
/// final request = WorkflowStartRequest(
///   root: TargetPath('/workspace'),
///   idempotency_key: 'operation-001',
/// );
/// ```
final class WorkflowStartRequest implements Request<WorkflowStartResponse> {
  /// Creates a workflow establishment request.
  ///
  /// [root] identifies the intended original inspection root.
  /// [idempotency_key] identifies the logical operation across retries.
  ///
  /// Throws [ArgumentError] if the idempotency key is blank.
  WorkflowStartRequest({required this.root, required this.idempotency_key}) {
    if (idempotency_key.trim().isEmpty) {
      throw ArgumentError.value(
        idempotency_key,
        'idempotency_key',
        'Idempotency key must not be blank.',
      );
    }
  }

  /// Requested original inspection root in target-native syntax.
  final TargetPath root;

  /// Durable identity of the logical application operation.
  ///
  /// Retries of the same operation must preserve this key and
  /// the original request data.
  final String idempotency_key;
}
