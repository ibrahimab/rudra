/// Provides the trusted operating-system identity of a Rudra host.
///
/// Platform implementations resolve identity through authoritative
/// operating-system mechanisms. The resolved identity establishes
/// the ownership scope used by host-side application composition.
///
/// Implementations are responsible for defining a stable identity
/// namespace appropriate to their operating system.
///
/// Example:
/// ```dart
/// Future<String> resolve_owner(
///   HostIdentityProvider provider,
/// ) async {
///   return await provider.resolve();
/// }
/// ```
abstract interface class HostIdentityProvider {
  /// Resolves the trusted identity of the current host process.
  ///
  /// Returns a stable, nonblank operating-system user identifier
  /// within the platform implementation's identity namespace.
  ///
  /// Throws an implementation-specific exception when identity
  /// cannot be established or verified.
  Future<String> resolve();
}
