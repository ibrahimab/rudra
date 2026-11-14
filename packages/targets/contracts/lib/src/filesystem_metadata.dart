import 'filesystem_permissions.dart';
import 'filesystem_identity.dart';

/// Describes available metadata for a single filesystem entry.
///
/// All fields are optional because target platforms and filesystems
/// provide different levels of metadata support.
///
/// Size fields describe the individual entry, not recursively
/// aggregated directory sizes.
///
/// Logical size and allocated size are independent observations.
/// Neither represents guaranteed recoverable disk space.
///
/// Timestamps are normalized to UTC when this object is constructed.
///
/// Unknown values are represented by null, never fabricated values.
///
/// Example:
/// ```dart
/// final metadata = FilesystemMetadata(
///   logical_size_bytes: 1024,
///   allocated_size_bytes: 4096,
///   modified_at: DateTime.utc(2026, 11, 3),
/// );
///
/// print(metadata.logical_size_bytes);
/// // 1024
/// ```
final class FilesystemMetadata {
  /// Creates immutable filesystem metadata.
  ///
  /// Both size values must be nonnegative when provided.
  ///
  /// Timestamps are converted to UTC without changing the instant
  /// they represent.
  ///
  /// Throws [ArgumentError] for negative size values.
  FilesystemMetadata({
    this.logical_size_bytes,
    this.allocated_size_bytes,
    DateTime? created_at,
    DateTime? modified_at,
    DateTime? accessed_at,
    this.identity,
    this.permissions,
  }) : created_at = created_at?.toUtc(),
       modified_at = modified_at?.toUtc(),
       accessed_at = accessed_at?.toUtc() {
    if (logical_size_bytes != null && logical_size_bytes! < 0) {
      throw ArgumentError.value(
        logical_size_bytes,
        'logical_size_bytes',
        'Logical size must not be negative.',
      );
    }

    if (allocated_size_bytes != null && allocated_size_bytes! < 0) {
      throw ArgumentError.value(
        allocated_size_bytes,
        'allocated_size_bytes',
        'Allocated size must not be negative.',
      );
    }
  }

  /// The apparent size of this entry in bytes.
  ///
  /// Null means unavailable.
  final int? logical_size_bytes;

  /// Filesystem-reported allocated size in bytes.
  ///
  /// This does not represent guaranteed recoverable disk space.
  final int? allocated_size_bytes;

  /// The entry's creation or birth time, if available.
  ///
  /// Stored in UTC.
  final DateTime? created_at;

  /// The last modification time, if available.
  ///
  /// Stored in UTC.
  final DateTime? modified_at;

  /// The last access time, if available.
  ///
  /// Stored in UTC.
  final DateTime? accessed_at;

  /// The identity of the observed filesystem entry, when available.
  ///
  /// Multiple paths may share an identity when they refer to the same
  /// underlying filesystem object.
  ///
  /// For symbolic links, this identifies the symbolic link itself,
  /// not its destination.
  ///
  /// Null means no reliable identity was provided.
  ///
  /// An identity must not be used as a permanent authorization key
  /// or as a guarantee of recoverable storage.
  final FilesystemIdentity? identity;

  /// Available permission information for this entry.
  ///
  /// Null means no permission observations were provided.
  final FilesystemPermissions? permissions;
}
