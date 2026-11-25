/// Identifies a failure while processing communication protocol data.
///
/// These categories allow session coordination to distinguish
/// protocol violations from transport and application failures.
///
/// Example:
/// ```dart
/// final code = ProtocolErrorCode.incomplete_frame;
/// ```
enum ProtocolErrorCode {
  /// The declared or outgoing frame length violates configured limits.
  invalid_frame_length,

  /// The incoming stream ended before a frame was complete.
  incomplete_frame,

  /// The wire representation could not be encoded or decoded.
  invalid_encoding,

  /// The envelope violates the protocol's structural requirements.
  invalid_envelope,

  /// The envelope declares an unsupported protocol version.
  unsupported_version,

  /// The message violates the session's correlation requirements.
  invalid_correlation,

  /// The message violates its registered application message contract.
  invalid_message,

  /// Incoming requests exceed the configured session capacity.
  capacity_exceeded,
}

/// Reports a violation of the communication protocol.
///
/// Protocol failures identify invalid communication data rather than
/// application rejections or native transport failures.
///
/// Diagnostic descriptions are intended for local use and must not
/// contain raw remote payloads or sensitive application data.
///
/// Example:
/// ```dart
/// throw const ProtocolException(
///   ProtocolErrorCode.incomplete_frame,
///   'Incoming frame ended prematurely.',
/// );
/// ```
final class ProtocolException implements Exception {
  /// Creates a protocol failure with the supplied [code] and [message].
  ///
  /// The message describes the failure for local diagnostics.
  const ProtocolException(this.code, this.message);

  /// Machine-readable classification of the protocol violation.
  final ProtocolErrorCode code;

  /// Local diagnostic description of the protocol violation.
  final String message;

  /// Returns a diagnostic representation of this failure.
  @override
  String toString() => 'ProtocolException(${code.name}): $message';
}
