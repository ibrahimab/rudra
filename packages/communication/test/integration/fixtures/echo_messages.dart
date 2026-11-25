import 'package:rudra_communication/rudra_communication.dart';

/// Synthetic request used to verify cross-process messaging.
///
/// Example:
/// ```dart
/// const request = EchoRequest('Hello');
/// ```
final class EchoRequest implements Request<EchoResponse> {
  /// Creates a request containing [value].
  const EchoRequest(this.value);

  /// Application data transmitted to the remote handler.
  final String value;
}

/// Synthetic response returned by a remote request handler.
///
/// Example:
/// ```dart
/// const response = EchoResponse('Hello');
/// ```
final class EchoResponse implements Response {
  /// Creates a response containing [value].
  const EchoResponse(this.value);

  /// Application result returned to the requesting peer.
  final String value;
}

/// Encodes and reconstructs synthetic echo requests.
final class EchoRequestCodec implements MessageCodec<EchoRequest> {
  /// Creates the request codec.
  const EchoRequestCodec();

  /// Stable request wire identifier shared by both processes.
  @override
  String get type_id => 'example.native.echo.request.v1';

  /// Returns the value carried by [message].
  @override
  Object? encode(EchoRequest message) => message.value;

  /// Reconstructs a request from [payload].
  ///
  /// Throws [FormatException] for an incompatible payload.
  @override
  EchoRequest decode(Object? payload) {
    if (payload is! String) {
      throw const FormatException('Invalid echo request.');
    }

    return EchoRequest(payload);
  }
}

/// Encodes and reconstructs synthetic echo responses.
final class EchoResponseCodec implements MessageCodec<EchoResponse> {
  /// Creates the response codec.
  const EchoResponseCodec();

  /// Stable response wire identifier shared by both processes.
  @override
  String get type_id => 'example.native.echo.response.v1';

  /// Returns the value carried by [message].
  @override
  Object? encode(EchoResponse message) => message.value;

  /// Reconstructs a response from [payload].
  ///
  /// Throws [FormatException] for an incompatible payload.
  @override
  EchoResponse decode(Object? payload) {
    if (payload is! String) {
      throw const FormatException('Invalid echo response.');
    }

    return EchoResponse(payload);
  }
}

/// Creates application codec registration for the native fixture.
///
/// Returns an independent mutable registry whose configuration
/// will be frozen by communication before execution.
MessageCodecRegistry create_echo_codecs() {
  return MessageCodecRegistry()
    ..register_request<EchoResponse, EchoRequest>(const EchoRequestCodec())
    ..register_response<EchoResponse>(const EchoResponseCodec());
}
