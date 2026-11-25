import 'package:rudra_communication/rudra_communication.dart';
import 'package:rudra_target_contracts/rudra_target_contracts.dart';

import 'workflow_start_response.dart';

/// Requests establishment of a workflow through communication.
///
/// Identifies the intended filesystem target and inspection root.
/// The host determines the trusted submitting identity independently
/// of the supplied application data.
///
/// Example:
/// ```dart
/// final request = WorkflowStartRequest(
///   target_id: 'local-macos',
///   root: TargetPath('/workspace'),
///   idempotency_key: 'operation-001',
/// );
/// ```
final class WorkflowStartRequest implements Request<WorkflowStartResponse> {
  /// Creates a workflow establishment request.
  ///
  /// [target_id] identifies the configured filesystem target.
  /// [root] identifies the intended original inspection root.
  /// [idempotency_key] identifies the logical operation across retries.
  ///
  /// Throws [ArgumentError] if the target identifier or idempotency
  /// key is blank.
  WorkflowStartRequest({
    required this.target_id,
    required this.root,
    required this.idempotency_key,
  }) {
    if (target_id.trim().isEmpty) {
      throw ArgumentError.value(
        target_id,
        'target_id',
        'Target identifier must not be blank.',
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

  /// Requested configured filesystem target.
  final String target_id;

  /// Requested original inspection root in target-native syntax.
  final TargetPath root;

  /// Durable identity of the logical application operation.
  ///
  /// Retries of the same operation must preserve this key and
  /// the original request data.
  final String idempotency_key;
}
