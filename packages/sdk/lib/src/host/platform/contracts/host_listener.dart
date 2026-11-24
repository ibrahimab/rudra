import 'host_connection.dart';

/// Accepts authenticated connections within a host execution scope.
///
/// Retains the native listener and its outstanding connections
/// until the host releases the listener.
///
/// Example:
/// ```dart
/// final listener = await transport.listen(
///   scope_directory: directory,
///   os_user_id: trusted_owner,
/// );
///
/// final subscription = listener.connections.listen(handle_connection);
/// await listener.close();
/// await subscription.cancel();
/// ```
abstract interface class HostListener {
  /// Single-subscription stream of authorized connections.
  ///
  /// Rejected peers must never be exposed through this stream.
  /// Listener-level failures are delivered as stream errors.
  Stream<HostConnection> get connections;

  /// Stops accepting connections and closes outstanding sessions.
  ///
  /// Returns after releasing the native listener, its connections
  /// and any transport-owned endpoint resources.
  ///
  /// Closing must be supported before or after stream subscription.
  /// Repeated calls must be safe.
  ///
  /// Resource disposal failures propagate to the caller.
  Future<void> close();
}
