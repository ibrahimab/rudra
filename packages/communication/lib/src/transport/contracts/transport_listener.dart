import 'transport_connection.dart';

/// Accepts authenticated connections within a communication scope.
///
/// Retains the native listener and its outstanding connections
/// until the owning consumer releases the listener.
///
/// Example:
/// ```dart
/// final listener = await transport.listen();
///
/// final subscription = listener.connections.listen(handle_connection);
/// await listener.close();
/// await subscription.cancel();
/// ```
abstract interface class TransportListener {
  /// Single-subscription stream of authorized connections.
  ///
  /// Rejected peers are excluded from this stream.
  /// Listener-level failures are delivered as stream errors.
  Stream<TransportConnection> get connections;

  /// Stops acceptance and closes outstanding connections.
  ///
  /// Returns after releasing native listener, connection and
  /// endpoint resources.
  ///
  /// Disposal is supported before or after stream subscription.
  /// Repeated calls must be safe.
  ///
  /// Resource disposal failures propagate to the caller.
  Future<void> close();
}
