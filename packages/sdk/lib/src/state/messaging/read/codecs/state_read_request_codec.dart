import 'package:rudra_communication/rudra_communication.dart';

import '../state_read_request.dart';

/// Serializes requests for composite Rudra application state.
///
/// The request representation contains no application arguments.
/// Trusted request scope is established independently by the host.
final class StateReadRequestCodec implements MessageCodec<StateReadRequest> {
  /// Creates the stateless State Read request codec.
  const StateReadRequestCodec();

  /// Stable wire identifier of the version 1 State Read request.
  @override
  String get type_id => 'rudra.state.read.request.v1';

  /// Converts [message] into its structured representation.
  ///
  /// Returns an empty application payload.
  @override
  Map<String, Object?> encode(StateReadRequest message) {
    return {};
  }

  /// Reconstructs a State Read request from [payload].
  ///
  /// Returns the stateless request represented by an empty map.
  ///
  /// Throws [FormatException] for malformed representations
  /// or unexpected application arguments.
  @override
  StateReadRequest decode(Object? payload) {
    if (payload is! Map<String, Object?> || payload.isNotEmpty) {
      throw const FormatException(
        'Invalid application state read request payload.',
      );
    }

    return const StateReadRequest();
  }
}
