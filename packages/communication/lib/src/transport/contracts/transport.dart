import 'transport_listener.dart';

/// Establishes authenticated local communication endpoints.
///
/// Implementations provide native communication mechanisms
/// behind a portable connection and listener contract.
///
/// Endpoint preparation requires exclusive ownership of the
/// supplied communication scope by the caller.
///
/// Example:
/// ```dart
/// final listener = await transport.listen(
///   scope_directory: '/private/tmp/example',
///   os_user_id: trusted_owner,
/// );
///
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
  ///
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
}
