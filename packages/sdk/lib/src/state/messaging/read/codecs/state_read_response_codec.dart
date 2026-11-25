import 'package:rudra_communication/rudra_communication.dart';

import '../../../../workflow/workflow_runtime.dart';

import '../../serialization/rudra_state_codec.dart';

import '../state_read_response.dart';

/// Serializes responses containing composite Rudra application state.
///
/// Delegates domain-state representation and concrete slice
/// reconstruction to the owned application state codec.
final class StateReadResponseCodec implements MessageCodec<StateReadResponse> {
  /// Creates a State Read response codec using [runtime].
  ///
  /// The runtime provides the immutable workflow configuration
  /// required to serialize and reconstruct application state.
  ///
  /// Throws [StateError] when required slice serialization
  /// capabilities are missing.
  StateReadResponseCodec({required WorkflowRuntime runtime})
    : _state_codec = RudraStateCodec(runtime: runtime);

  /// Owned serializer for composite application state.
  final RudraStateCodec _state_codec;

  /// Stable wire identifier of the version 1 State Read response.
  @override
  String get type_id => 'rudra.state.read.response.v1';

  /// Converts [message] into its structured state representation.
  ///
  /// Returns the serialized composite application state.
  ///
  /// Domain serialization failures propagate.
  @override
  Map<String, Object?> encode(StateReadResponse message) {
    return _state_codec.encode(message.state);
  }

  /// Reconstructs a State Read response from [payload].
  ///
  /// Returns a response containing concrete reconstructed
  /// application state.
  ///
  /// Throws [FormatException] for malformed or unsupported
  /// application-state representations.
  ///
  /// Feature-owned codec contract violations propagate.
  @override
  StateReadResponse decode(Object? payload) {
    return StateReadResponse(state: _state_codec.decode(payload));
  }
}
