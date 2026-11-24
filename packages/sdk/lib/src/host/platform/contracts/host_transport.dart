import 'host_listener.dart';

/// Establishes a native communication endpoint for a Rudra host.
///
/// Platform implementations select the appropriate local
/// transport and authenticate remote operating-system identities.
///
/// Endpoint preparation requires previously acquired exclusive
/// host ownership of the supplied persistence scope.
///
/// Example:
/// ```dart
/// final listener = await transport.listen(
///   scope_directory: '/workspace/rudra',
///   os_user_id: trusted_owner,
/// );
///
/// await listener.close();
/// ```
abstract interface class HostTransport {
  /// Opens a local listener within the exclusively owned scope.
  ///
  /// [scope_directory] identifies the canonical persistence scope.
  /// [os_user_id] identifies the trusted operating-system owner.
  ///
  /// Returns a listener accepting only authorized peers.
  /// Configuration, authentication infrastructure and endpoint
  /// initialization failures propagate to the caller.
  Future<HostListener> listen({
    required String scope_directory,
    required String os_user_id,
  });
}
