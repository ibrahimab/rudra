import 'package:rudra_platform_macos/rudra_platform_macos.dart';
import 'package:rudra_sdk/rudra_sdk.dart';

/// Provides the effective operating-system identity of the macOS host.
///
/// ### Example
///
/// ```dart
/// final os_user_id = await const MacOsHostIdentity().resolve();
/// print(os_user_id); // For example, macos-uid:501.
/// ```
final class MacOsHostIdentity implements HostIdentityProvider {
  /// Creates a provider without resolving identity until [resolve].
  const MacOsHostIdentity();

  /// Returns the trusted identity in the `macos-uid:<uid>` namespace.
  ///
  /// Resolving identity can fail if the native identity binding is unavailable.
  @override
  Future<String> resolve() async => macos_user_id(macos_effective_uid());
}
