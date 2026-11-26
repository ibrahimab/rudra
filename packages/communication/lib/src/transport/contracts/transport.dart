import 'transport_connection.dart';
import 'transport_listener.dart';

/// Establishes authenticated bidirectional communication endpoints.
///
/// Concrete implementations retain their endpoint configuration,
/// authentication requirements and native connectivity mechanisms.
///
/// Listener initialization requires exclusive ownership of the
/// configured endpoint. Outbound connectivity establishes an
/// authenticated connection to an existing endpoint.
///
/// Example:
/// ```dart
/// final listener = await transport.listen();
/// final connection = await transport.connect();
///
/// await connection.close();
/// await listener.close();
/// ```
abstract interface class Transport {
  /// Opens the configured authenticated listening endpoint.
  ///
  /// Returns a listener accepting only authorized peers.
  /// Successful initialization transfers ownership of the listener
  /// to the caller.
  ///
  /// Failed initialization must release communication resources
  /// acquired during the attempt before propagating the failure.
  ///
  /// Configuration, authentication infrastructure and endpoint
  /// initialization failures propagate to the caller.
  Future<TransportListener> listen();

  /// Establishes an authenticated connection to the configured endpoint.
  ///
  /// Returns a connection whose remote identity has been verified
  /// against the transport's trusted authentication configuration.
  ///
  /// Successful establishment transfers connection ownership to
  /// the caller.
  ///
  /// Failed establishment must release all connection resources
  /// acquired during the attempt.
  ///
  /// Connecting preserves ownership and integrity of the remote
  /// listening endpoint.
  ///
  /// Configuration, authentication and connection failures
  /// propagate to the caller.
  Future<TransportConnection> connect();
}
