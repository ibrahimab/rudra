import 'host_ownership_lease.dart';

/// Acquires exclusive ownership of a host persistence scope.
///
/// Platform implementations establish ownership through an
/// operating-system mechanism that coordinates independent
/// processes and releases ownership upon process termination.
///
/// Acquisition must reject competing owners without waiting for
/// the existing owner to terminate.
///
/// Example:
/// ```dart
/// final lease = await provider.acquire(
///   scope_directory: '/workspace/rudra',
/// );
///
/// await lease.release();
/// ```
abstract interface class HostOwnershipProvider {
  /// Acquires ownership of the configured persistence scope.
  ///
  /// [scope_directory] identifies an existing canonical absolute
  /// directory containing the host's persistence resources.
  ///
  /// Returns an acquired [HostOwnershipLease].
  ///
  /// Throws [HostAlreadyOwnedException] when another instance
  /// owns the same scope. Configuration, permission and native
  /// resource failures propagate independently of contention.
  Future<HostOwnershipLease> acquire({required String scope_directory});
}

/// Indicates that a persistence scope already has a host owner.
///
/// Represents an expected operational conflict rather than a
/// workflow lifecycle conflict or an internal application failure.
///
/// Example:
/// ```dart
/// try {
///   await provider.acquire(scope_directory: directory);
/// } on HostAlreadyOwnedException catch (error) {
///   print(error.scope_directory);
/// }
/// ```
final class HostAlreadyOwnedException implements Exception {
  /// Creates an ownership conflict for [scope_directory].
  const HostAlreadyOwnedException({required this.scope_directory});

  /// Canonical persistence scope whose ownership was rejected.
  final String scope_directory;

  /// Returns a diagnostic describing the occupied scope.
  @override
  String toString() => 'HostAlreadyOwnedException(scope: $scope_directory)';
}
