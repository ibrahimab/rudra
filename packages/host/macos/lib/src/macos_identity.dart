import 'dart:io';

import 'package:rudra_sdk/rudra_sdk.dart';

/// Provides the effective operating-system user identity on macOS.
///
/// Resolves the numeric user identifier through the native macOS
/// identity utility and represents it within Rudra's macOS identity
/// namespace.
///
/// The resulting identity provides a consistent ownership identifier
/// for workflow restoration, submission and persistence composition.
///
/// Example:
/// ```dart
/// final provider = MacOsHostIdentity();
/// final os_user_id = await provider.resolve();
///
/// // Example result: macos-uid:501
/// print(os_user_id);
/// ```
final class MacOsHostIdentity implements HostIdentityProvider {
  /// Creates a native macOS host identity provider.
  ///
  /// Identity resolution is deferred until [resolve] is invoked.
  const MacOsHostIdentity();

  /// Resolves the effective macOS user identity of the host process.
  ///
  /// Returns the numeric effective UID prefixed with `macos-uid:`,
  /// preserving compatibility with existing Rudra workflow ownership
  /// identifiers.
  ///
  /// Throws [UnsupportedError] when invoked outside macOS,
  /// [ProcessException] when the native identity utility cannot
  /// be executed, or [StateError] when its result is unsuccessful
  /// or contains an invalid UID.
  @override
  Future<String> resolve() async {
    if (!Platform.isMacOS) {
      throw UnsupportedError('macOS host identity requires macOS.');
    }

    // Resolve the effective UID through the operating system rather
    // than trusting environment variables or frontend-supplied identity.
    final result = await Process.run('/usr/bin/id', ['-u']);

    if (result.exitCode != 0) {
      throw StateError('Unable to resolve the operating-system UID.');
    }

    final uid = int.tryParse((result.stdout as String).trim());

    // Reject malformed identities before constructing an identifier
    // that could subsequently be used as a persistence ownership key.
    if (uid == null || uid < 0) {
      throw StateError('Invalid operating-system UID.');
    }

    // Preserve the existing identity namespace so migrating workflow
    // ownership to the host does not change established owner identifiers.
    return 'macos-uid:$uid';
  }
}
