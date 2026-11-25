import 'transport_connection.dart';
import 'transport_listener.dart';

/// Establishes authenticated bidirectional communication endpoints.
///
/// Implementations provide native communication mechanisms behind
/// portable connection and listener contracts.
///
/// Listener initialization requires exclusive ownership of the
/// communication scope. Outbound connectivity requires trusted
/// endpoint configuration but does not acquire listener ownership.
///
/// Example:
/// ```dart
/// final listener = await transport.listen(
///   scope_directory: scope,
///   os_user_id: trusted_owner,
/// );
///
/// final connection = await transport.connect(
///   scope_directory: scope,
///   os_user_id: trusted_owner,
/// );
///
/// await connection.close();
/// await listener.close();
/// ```
abstract interface class Transport {
  /// Opens a local listener within an exclusively owned scope.
  ///
  /// [scope_directory] identifies the canonical directory
  /// reserved for the communication endpoint.
  ///
  /// [os_user_id] identifies the trusted operating-system owner
  /// authorized to establish connections.
  ///
  /// Returns a listener accepting only authorized peers.
  /// Successful initialization transfers ownership of the listener
  /// to the caller.
  ///
  /// Failed initialization must release any communication resources
  /// acquired during the attempt before propagating the failure.
  ///
  /// Configuration, authentication infrastructure and endpoint
  /// initialization failures propagate to the caller.
  Future<TransportListener> listen({
    required String scope_directory,
    required String os_user_id,
  });

  /// Establishes an authenticated connection to an existing endpoint.
  ///
  /// [scope_directory] identifies the trusted canonical communication
  /// directory containing the remote endpoint.
  ///
  /// [os_user_id] identifies the expected trusted remote peer.
  ///
  /// Returns a connection whose remote identity has been verified
  /// against the supplied trusted identity.
  ///
  /// Successful establishment transfers connection ownership to
  /// the caller.
  ///
  /// Failed establishment must release all connection resources
  /// acquired during the attempt.
  ///
  /// Connecting does not acquire listener ownership or create,
  /// replace, repair or remove the remote endpoint.
  ///
  /// Configuration, authentication and native connection failures
  /// propagate to the caller.
  Future<TransportConnection> connect({
    required String scope_directory,
    required String os_user_id,
  });
}
