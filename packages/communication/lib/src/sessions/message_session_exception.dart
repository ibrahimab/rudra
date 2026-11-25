/// Identifies failures encountered during message session execution.
///
/// Session failures are independent of application rejection outcomes
/// and malformed communication protocol data.
///
/// Example:
/// ```dart
/// final code = MessageSessionErrorCode.request_timeout;
/// ```
enum MessageSessionErrorCode {
  /// The session has terminated and cannot execute further requests.
  session_closed,

  /// The configured local execution capacity has been exhausted.
  capacity_exceeded,

  /// An outgoing request exceeded its configured deadline.
  request_timeout,

  /// The remote peer has no handler for the requested operation.
  handler_unavailable,

  /// The remote application handler failed unexpectedly.
  handler_failed,
}

/// Reports a message session execution failure.
///
/// The failure describes communication execution rather than the
/// outcome of the remote application operation.
///
/// Example:
/// ```dart
/// throw const MessageSessionException(
///   MessageSessionErrorCode.session_closed,
/// );
/// ```
final class MessageSessionException implements Exception {
  /// Creates a session failure identified by [code].
  const MessageSessionException(this.code);

  /// Machine-readable classification of the session failure.
  final MessageSessionErrorCode code;

  /// Returns a diagnostic representation of the failure.
  @override
  String toString() => 'MessageSessionException(${code.name})';
}
