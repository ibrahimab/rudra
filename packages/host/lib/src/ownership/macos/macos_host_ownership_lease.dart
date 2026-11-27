import 'package:rudra_sdk/rudra_sdk.dart';

import 'darwin_flock.dart';

/// Retains an acquired macOS host ownership resource.
///
/// Owns the native descriptor associated with an exclusive
/// Darwin file lock throughout the host execution lifecycle.
///
/// Example:
/// ```dart
/// final lease = MacOsHostOwnershipLease(
///   native: native,
///   descriptor: acquired_descriptor,
///   path: lock_path,
/// );
///
/// await lease.release();
/// ```
final class MacOsHostOwnershipLease implements HostOwnershipLease {
  /// Takes ownership of an acquired native descriptor.
  ///
  /// [native] supplies the native disposal operation.
  /// [descriptor] identifies the successfully acquired resource.
  /// [path] supplies its associated filesystem location.
  ///
  /// The caller transfers responsibility for descriptor disposal
  /// to this lease.
  MacOsHostOwnershipLease({
    required DarwinFlock native,
    required int descriptor,
    required String path,
  }) : _native = native,
       _descriptor = descriptor,
       _path = path;

  /// Native implementation responsible for resource disposal.
  final DarwinFlock _native;

  /// Acquired native file descriptor.
  final int _descriptor;

  /// Lock file location retained for diagnostics.
  final String _path;

  /// Records whether descriptor disposal has been attempted.
  bool _release_attempted = false;

  /// Releases the retained native ownership resource.
  ///
  /// Returns after closing the acquired descriptor.
  /// Repeated calls do not attempt to close the descriptor again.
  ///
  /// Native disposal failures propagate to the caller.
  @override
  Future<void> release() async {
    if (_release_attempted) {
      return;
    }

    // Native descriptor numbers can be reused after closure.
    // Never risk closing an unrelated resource through a
    // repeated disposal attempt.
    _release_attempted = true;

    _native.release(descriptor: _descriptor, path: _path);
  }
}
