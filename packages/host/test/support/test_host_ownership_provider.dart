import 'package:rudra_sdk/rudra_sdk.dart';

/// Provides deterministic ownership for host composition tests.
///
/// Records acquisitions and releases while enforcing one
/// active lease per fixture instance.
///
/// Example:
/// ```dart
/// final provider = TestHostOwnershipProvider();
/// final lease = await provider.acquire();
///
/// await lease.release();
/// ```
final class TestHostOwnershipProvider implements HostOwnershipProvider {
  /// Creates an initially unowned test fixture.
  TestHostOwnershipProvider();

  /// Whether the fixture currently retains an acquired lease.
  bool is_owned = false;

  /// Number of successful acquisitions.
  int acquire_count = 0;

  /// Number of successfully released ownership resources.
  int release_count = 0;

  /// Acquires synthetic ownership for the fixture user.
  ///
  /// Returns a controlled lease or throws
  /// [HostAlreadyOwnedException] for an occupied fixture.
  @override
  Future<HostOwnershipLease> acquire() async {
    if (is_owned) {
      throw const HostAlreadyOwnedException(os_user_id: 'test-owner');
    }

    is_owned = true;
    acquire_count++;

    return _TestHostOwnershipLease(() {
      is_owned = false;
      release_count++;
    });
  }
}

/// Represents a controlled ownership resource in composition tests.
///
/// Example:
/// ```dart
/// final lease = _TestHostOwnershipLease(() {});
/// await lease.release();
/// ```
final class _TestHostOwnershipLease implements HostOwnershipLease {
  /// Creates a lease with its injected disposal callback.
  _TestHostOwnershipLease(this._on_release);

  /// Callback recording successful ownership disposal.
  final void Function() _on_release;

  /// Whether this synthetic resource has been released.
  bool _released = false;

  /// Releases the synthetic resource exactly once.
  @override
  Future<void> release() async {
    if (_released) {
      return;
    }

    _released = true;
    _on_release();
  }
}
