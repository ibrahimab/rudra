import 'dart:io';

import 'package:rudra_sdk/rudra_sdk.dart';

import 'darwin_flock.dart';
import 'macos_host_ownership_lease.dart';

/// Establishes exclusive host ownership on macOS.
///
/// Maps each canonical persistence directory to a stable
/// lock file protected by Darwin's kernel-managed locking
/// mechanism.
///
/// The provider establishes ownership without opening or
/// initializing workflow persistence.
///
/// Example:
/// ```dart
/// final provider = MacOsHostOwnershipProvider();
///
/// final lease = await provider.acquire(
///   scope_directory: '/workspace/rudra',
/// );
///
/// await lease.release();
/// ```
final class MacOsHostOwnershipProvider implements HostOwnershipProvider {
  /// Creates a native host ownership provider.
  ///
  /// Native resources are acquired only when [acquire] is invoked.
  const MacOsHostOwnershipProvider();

  /// Stable filename identifying the host ownership resource.
  static const String lock_filename = 'rudra-host.lock';

  /// Permission mask covering group and other access bits.
  static const int _shared_permission_mask = 0x003f;

  /// Acquires exclusive ownership of [scope_directory].
  ///
  /// The directory must be an existing, canonical absolute path
  /// reserved for trusted host persistence.
  ///
  /// Returns a lease retaining the acquired native descriptor.
  ///
  /// Throws [HostAlreadyOwnedException] for competing ownership,
  /// [UnsupportedError] outside macOS or [FileSystemException]
  /// for invalid storage and native acquisition failures.
  @override
  Future<HostOwnershipLease> acquire({required String scope_directory}) async {
    if (!Platform.isMacOS) {
      throw UnsupportedError('macOS host ownership requires macOS.');
    }

    final directory = Directory(scope_directory);
    final metadata = await directory.stat();

    if (metadata.type != FileSystemEntityType.directory) {
      throw FileSystemException(
        'Host ownership requires an existing directory.',
        scope_directory,
      );
    }

    // The development ownership mechanism requires a private
    // directory rather than a shared writable lock location.
    if ((metadata.mode & _shared_permission_mask) != 0) {
      throw FileSystemException(
        'Host ownership requires a private directory.',
        scope_directory,
      );
    }

    final lock_file = File.fromUri(directory.uri.resolve(lock_filename));

    final existing_type = await FileSystemEntity.type(
      lock_file.path,
      followLinks: false,
    );

    // Reject unexpected existing entries. Native O_NOFOLLOW
    // additionally prevents following a final symbolic link
    // during the actual acquisition operation.
    if (existing_type != FileSystemEntityType.notFound &&
        existing_type != FileSystemEntityType.file) {
      throw FileSystemException('Invalid host lock file.', lock_file.path);
    }

    final native = DarwinFlock();
    final descriptor = native.try_acquire(lock_file.path);

    if (descriptor == null) {
      throw HostAlreadyOwnedException(scope_directory: scope_directory);
    }

    return MacOsHostOwnershipLease(
      native: native,
      descriptor: descriptor,
      path: lock_file.path,
    );
  }
}
