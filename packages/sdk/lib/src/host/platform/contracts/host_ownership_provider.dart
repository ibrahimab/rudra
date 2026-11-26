import 'host_ownership_lease.dart';

/// Acquires exclusive host ownership for the trusted operating-system user.
///
/// Example:
/// ```dart
/// final lease = await ownership_provider.acquire();
/// try {
///   await run_owned_application();
/// } finally {
///   await lease.release();
/// }
/// ```
abstract interface class HostOwnershipProvider {
  /// Returns an acquired [HostOwnershipLease] for the configured user.
  ///
  /// Throws [HostAlreadyOwnedException] without waiting for a competing
  /// instance to exit. The operating system releases ownership at process
  /// termination. Configuration and permission failures propagate separately.
  Future<HostOwnershipLease> acquire();
}

/// Indicates another Rudra host is running for the same operating-system user.
///
/// Example:
/// ```dart
/// try {
///   final lease = await ownership_provider.acquire();
///   await lease.release();
/// } on HostAlreadyOwnedException catch (error) {
///   print(error.os_user_id);
/// }
/// ```
final class HostAlreadyOwnedException implements Exception {
  /// Creates an ownership conflict for the trusted [os_user_id].
  const HostAlreadyOwnedException({required this.os_user_id});

  /// Trusted operating-system identity whose host ownership is occupied.
  final String os_user_id;

  @override
  String toString() => 'HostAlreadyOwnedException(user: $os_user_id)';
}
