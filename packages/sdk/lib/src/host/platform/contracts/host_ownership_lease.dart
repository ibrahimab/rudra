/// Represents exclusive ownership of a host persistence scope.
///
/// Retains the underlying platform ownership resource until
/// explicitly released. The resource remains acquired throughout
/// application execution and persistence disposal.
///
/// A lease represents runtime ownership, independently of any
/// established workflow or its domain lifecycle.
///
/// Example:
/// ```dart
/// final lease = await provider.acquire(
///   scope_directory: '/workspace/rudra',
/// );
///
/// try {
///   await run_application();
/// } finally {
///   await lease.release();
/// }
/// ```
abstract interface class HostOwnershipLease {
  /// Releases the acquired ownership resource.
  ///
  /// Returns after the underlying ownership mechanism has been
  /// released. Repeated calls after successful release have no
  /// additional effect.
  ///
  /// Platform-specific resource disposal failures propagate
  /// to the caller.
  Future<void> release();
}
