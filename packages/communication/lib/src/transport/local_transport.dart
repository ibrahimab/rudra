import 'dart:io';

import 'contracts/transport.dart';
import 'contracts/transport_listener.dart';
import 'macos/unix/macos_unix_transport.dart';

/// Selects the native transport for local communication.
///
/// Encapsulates platform selection within the communication
/// subsystem and delegates endpoint establishment to the
/// appropriate native transport implementation.
///
/// Native resources are acquired only when [listen] is invoked.
///
/// Example:
/// ```dart
/// final transport = LocalTransport();
///
/// final listener = await transport.listen(
///   scope_directory: scope,
///   os_user_id: trusted_owner,
/// );
///
/// await listener.close();
/// ```
final class LocalTransport implements Transport {
  /// Creates a local transport without acquiring native resources.
  const LocalTransport();

  /// Establishes an authenticated local communication endpoint.
  ///
  /// [scope_directory] identifies the exclusively owned communication
  /// directory prepared by the caller.
  /// [os_user_id] identifies the trusted operating-system owner
  /// authorized to establish connections.
  ///
  /// Returns the listener created by the selected native transport.
  ///
  /// Throws [UnsupportedError] when the current operating system
  /// has no supported local transport implementation.
  /// Native initialization failures propagate to the caller.
  @override
  Future<TransportListener> listen({
    required String scope_directory,
    required String os_user_id,
  }) {
    final transport = _select_transport();

    return transport.listen(
      scope_directory: scope_directory,
      os_user_id: os_user_id,
    );
  }

  /// Selects the transport implementation for the current platform.
  ///
  /// Returns the native implementation without acquiring resources.
  ///
  /// Throws [UnsupportedError] when no implementation is available.
  Transport _select_transport() {
    if (Platform.isMacOS) {
      return const MacOsUnixTransport();
    }

    throw UnsupportedError(
      'Local communication is unavailable on this platform.',
    );
  }
}
