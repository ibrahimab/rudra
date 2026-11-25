import 'package:rudra_target_contracts/rudra_target_contracts.dart';

import '../../workflow_identity.dart';

/// Serializes the immutable identity of an established workflow.
///
/// Preserves the original workflow, owner and filesystem bindings
/// independently of the platform performing serialization.
///
/// A reconstructed identity is a domain reference, not evidence
/// of authentication or authorization.
///
/// Example:
/// ```dart
/// const codec = WorkflowIdentityCodec();
///
/// final restored = codec.decode(codec.encode(identity));
///
/// print(restored.workflow_id);
/// ```
final class WorkflowIdentityCodec {
  /// Creates the stateless workflow identity codec.
  const WorkflowIdentityCodec();

  /// Converts [identity] into its structured representation.
  ///
  /// Returns the original identifiers and target-native root path.
  Map<String, Object?> encode(WorkflowIdentity identity) {
    return {
      'workflow_id': identity.workflow_id,
      'os_user_id': identity.os_user_id,
      'target_id': identity.target_id,
      'root': identity.root.value,
    };
  }

  /// Reconstructs a workflow identity from [payload].
  ///
  /// Returns a validated identity preserving the original bindings.
  ///
  /// Throws [FormatException] for malformed representations,
  /// unexpected fields or invalid domain identity values.
  WorkflowIdentity decode(Object? payload) {
    if (payload is! Map<String, Object?> || payload.length != 4) {
      throw const FormatException('Invalid workflow identity payload.');
    }

    final workflow_id = payload['workflow_id'];
    final os_user_id = payload['os_user_id'];
    final target_id = payload['target_id'];
    final root = payload['root'];

    if (workflow_id is! String ||
        os_user_id is! String ||
        target_id is! String ||
        root is! String) {
      throw const FormatException('Invalid workflow identity fields.');
    }

    try {
      return WorkflowIdentity(
        workflow_id: workflow_id,
        os_user_id: os_user_id,
        target_id: target_id,
        root: TargetPath(root),
      );
    } on ArgumentError {
      throw const FormatException('Invalid workflow identity values.');
    }
  }
}
