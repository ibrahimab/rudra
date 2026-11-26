import 'dart:io';

import 'package:rudra_platform_macos/rudra_platform_macos.dart';
import 'package:rudra_sdk/rudra_sdk.dart';

import 'darwin_flock.dart';
import 'macos_host_ownership_lease.dart';

/// Establishes one live host per effective macOS user using a Darwin lock.
///
/// Example:
/// ```dart
/// final lease = await const MacOsHostOwnershipProvider().acquire();
/// try {
///   await run_owned_application();
/// } finally {
///   await lease.release();
/// }
/// ```
final class MacOsHostOwnershipProvider implements HostOwnershipProvider {
  /// Uses the native per-user directory by default.
  ///
  /// [runtime_directory] supplies a private, canonical directory for isolated
  /// composition. Construction does not acquire native resources.
  const MacOsHostOwnershipProvider({this.runtime_directory});

  /// Optional isolated directory for the ownership lock.
  final String? runtime_directory;

  /// Acquires the retained lock in the effective user's private directory.
  ///
  /// Throws [HostAlreadyOwnedException] when another instance holds it, or
  /// [FileSystemException] for an unsafe directory, lock or native failure.
  @override
  Future<HostOwnershipLease> acquire() async {
    final uid = await macos_effective_uid();
    final directory = await require_macos_private_directory(
      runtime_directory ?? MacOsResourceLayout.user_runtime(uid),
      uid,
    );
    final path = '${directory.path}/${MacOsResourceLayout.lock_filename}';

    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      final metadata = await macos_resource_stat(path);
      if (metadata.uid != uid ||
          metadata.mode != 0x8180 || // Regular file with mode 0600.
          metadata.links != 1) {
        throw FileSystemException('Invalid Rudra ownership lock.', path);
      }
    }

    // Darwin acquires an exclusive, nonblocking lock at open and also
    // rejects a symbolic link in the final path component.
    final native = DarwinFlock();
    final descriptor = native.try_acquire(path);
    if (descriptor == null) {
      throw HostAlreadyOwnedException(os_user_id: macos_user_id(uid));
    }

    return MacOsHostOwnershipLease(
      native: native,
      descriptor: descriptor,
      path: path,
    );
  }
}
