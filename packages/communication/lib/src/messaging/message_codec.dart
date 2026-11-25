import 'message.dart';

/// Converts application messages of type [M] to and from structured
/// communication payloads.
///
/// Implementations own the serialized representation of one concrete
/// message type. Wire encoding, envelopes and transport framing are
/// maintained separately by communication.
///
/// Codec behavior and type identifiers must remain stable throughout
/// the lifetime of their registration.
///
/// Example:
/// ```dart
/// final class EchoResponseCodec
///     implements MessageCodec<EchoResponse> {
///   @override
///   String get type_id => 'example.echo.response.v1';
///
///   @override
///   Object? encode(EchoResponse message) => message.value;
///
///   @override
///   EchoResponse decode(Object? payload) {
///     if (payload is! String) {
///       throw const FormatException('Invalid echo payload.');
///     }
///
///     return EchoResponse(payload);
///   }
/// }
/// ```
abstract interface class MessageCodec<M extends Message> {
  /// Stable wire identifier of the represented message type.
  ///
  /// Identifiers must remain independent of Dart runtime type names
  /// and uniquely identify their registered payload representation.
  String get type_id;

  /// Converts [message] into its structured payload representation.
  ///
  /// Returns the payload consumed by the configured wire encoder.
  /// Implementations must produce values supported by that encoder
  /// without introducing transport or correlation metadata.
  Object? encode(M message);

  /// Reconstructs a message from the supplied [payload].
  ///
  /// Returns an instance of the registered concrete message type.
  /// Throws [FormatException] when the payload does not conform
  /// to the expected message representation.
  M decode(Object? payload);
}
