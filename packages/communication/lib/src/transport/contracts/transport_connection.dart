import 'dart:typed_data';

/// Represents an authenticated bidirectional transport connection.
///
/// Exposes the operating-system identity established by the native
/// transport and an ordered stream of incoming bytes.
///
/// Stream events represent transport chunks rather than application
/// messages. Higher-level protocols define message boundaries.
///
/// Example:
/// ```dart
/// await for (final bytes in connection.incoming) {
///   await connection.send(bytes);
/// }
/// ```
abstract interface class TransportConnection {
  /// Trusted operating-system identity of the remote peer.
  String get os_user_id;

  /// Single-subscription stream of incoming transport bytes.
  ///
  /// Completes when the connection closes.
  /// Transport failures may be delivered as stream errors.
  Stream<Uint8List> get incoming;

  /// Sends the supplied [bytes] through the connection.
  ///
  /// Returns after the transport accepts the buffered bytes.
  /// Completion does not establish remote application processing.
  ///
  /// Calls must be serialized by the connection consumer.
  /// Transport failures propagate to the caller.
  Future<void> send(Uint8List bytes);

  /// Terminates both directions of the connection.
  ///
  /// Pending reads must terminate and the underlying transport
  /// resource must be released.
  ///
  /// Repeated calls have no additional effect.
  Future<void> close();
}
