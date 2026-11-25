import '../../../workflow/messaging/serialization/workflows_state_codec.dart';
import '../../../workflow/workflow_runtime.dart';

import '../../rudra_state.dart';

/// Serializes Rudra's immutable composite application state.
///
/// Delegates each domain-state representation to its owning
/// serialization capability.
///
/// Reconstructed state retains concrete SDK domain types.
/// Invalid domain representations fail without returning
/// partially reconstructed application state.
///
/// Example:
/// ```dart
/// final codec = RudraStateCodec(
///   runtime: WorkflowRuntime.standard(),
/// );
///
/// final payload = codec.encode(state);
/// final restored = codec.decode(payload);
///
/// print(restored.workflows.current_workflow?.version);
/// ```
final class RudraStateCodec {
  /// Creates an application state codec using [runtime].
  ///
  /// The runtime provides the workflow configuration consumed
  /// by the owned workflow state serializer.
  ///
  /// Throws [StateError] when the supplied configuration lacks
  /// required workflow slice codecs.
  RudraStateCodec({required WorkflowRuntime runtime})
    : _workflows_codec = WorkflowsStateCodec(runtime: runtime);

  /// Owned serializer for the workflow domain-state collection.
  final WorkflowsStateCodec _workflows_codec;

  /// Converts [state] into its structured application representation.
  ///
  /// Returns the serialized domain-state collections.
  ///
  /// Domain serialization failures propagate.
  Map<String, Object?> encode(RudraState state) {
    return {'workflows': _workflows_codec.encode(state.workflows)};
  }

  /// Reconstructs composite application state from [payload].
  ///
  /// Returns an immutable [RudraState] containing its decoded
  /// domain-state collections.
  ///
  /// Throws [FormatException] for malformed or unsupported
  /// application-state representations.
  ///
  /// Feature-owned codec contract violations propagate.
  RudraState decode(Object? payload) {
    if (payload is! Map<String, Object?> ||
        payload.length != 1 ||
        !payload.containsKey('workflows')) {
      throw const FormatException('Invalid Rudra application state payload.');
    }

    return RudraState(workflows: _workflows_codec.decode(payload['workflows']));
  }
}
