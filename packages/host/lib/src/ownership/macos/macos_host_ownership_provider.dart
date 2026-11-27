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

  /// Stable filename retained across host acquisitions.
  static const _lock_filename = 'rudra.lock';

  /// Exclusive directory access for the effective owner.
  static const _private_directory_permissions =
      DarwinMode.owner_read_write | DarwinMode.owner_execute;

  /// Acquires the retained lock in the effective user's private directory.
  ///
  /// Throws [HostAlreadyOwnedException] when another instance holds it, or
  /// [FileSystemException] for an unsafe directory, lock or native failure.
  @override
  Future<HostOwnershipLease> acquire() async {
    final uid = macos_effective_uid();
    final directory =
        runtime_directory ?? MacOsResourceLayout.user_runtime(uid);
    final native_metadata = DarwinLStat();
    final runtime = native_metadata.inspect_security(directory);
    if (runtime.has_extended_acl ||
        runtime.metadata.uid != uid ||
        runtime.metadata.type != DarwinFileType.directory ||
        runtime.metadata.permissions != _private_directory_permissions ||
        await Directory(directory).resolveSymbolicLinks() != directory) {
      throw FileSystemException(
        'Rudra requires a canonical, user-owned 0700 lock directory.',
        directory,
      );
    }

    final path = '$directory/$_lock_filename';
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      final lock = native_metadata.inspect_security(path);
      if (lock.has_extended_acl ||
          lock.metadata.uid != uid ||
          lock.metadata.type != DarwinFileType.regular_file ||
          lock.metadata.permissions != DarwinMode.owner_read_write ||
          lock.metadata.links != 1) {
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
