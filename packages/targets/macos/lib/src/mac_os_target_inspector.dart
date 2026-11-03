import 'dart:io';

import 'package:rudra_target_contracts/rudra_target_contracts.dart';

import 'darwin_lstat.dart';

// Darwin file-type constants from sys/stat.h.
const int _file_type_mask = 0xF000;
const int _regular_file_type = 0x8000;
const int _directory_type = 0x4000;
const int _symbolic_link_type = 0xA000;
const int _fifo_type = 0x1000;
const int _character_device_type = 0x2000;
const int _block_device_type = 0x6000;
const int _socket_type = 0xC000;
const int _whiteout_type = 0xE000;

// Darwin st_mode uses the low 12 bits for POSIX permissions
// and special permission flags, excluding the file type.
const int _posix_permission_mask = 0x0FFF;

// Darwin st_blocks counts allocation in 512-byte units,
// independent of the filesystem's physical block size.
const int _darwin_allocation_block_bytes = 512;

// Prevent signed 64-bit overflow when converting block counts
// to byte counts. An unrepresentable observation remains unknown.
const int _maximum_signed_int64 = 0x7FFFFFFFFFFFFFFF;

// Darwin errno constants from sys/errno.h.
const int _errno_operation_not_permitted = 1;
const int _errno_not_found = 2;
const int _errno_permission_denied = 13;
const int _errno_not_directory = 20;
const int _errno_invalid_argument = 22;
const int _errno_symbolic_link_loop = 62;
const int _errno_name_too_long = 63;

/// Performs read-only filesystem inspection on macOS.
///
/// Uses Darwin's native `lstat` operation to examine filesystem
/// entries without following symbolic links in their final path
/// component.
///
/// This is an incremental implementation. Block 3A.2 provides
/// [inspect] only. The remaining TargetInspector operations will
/// be added in subsequent implementation blocks.
///
/// No filesystem modifications are performed.
///
/// Important limitations:
/// - Requires a 64-bit macOS Dart runtime.
/// - Intermediate symbolic links may still be followed.
/// - Inspection does not establish session-root containment.
/// - Observations are not atomic filesystem snapshots.
/// - Native `lstat` is synchronous and may block the calling isolate.
/// - No metadata observation authorizes cleanup or deletion.
///
/// This class must not be registered as a complete TargetInspector
/// until all required interface operations are implemented.
///
/// Example:
/// ```dart
/// final inspector = MacOsTargetInspector();
///
/// final entry = await inspector.inspect(
///   TargetPath('/tmp/example.txt'),
/// );
///
/// print(entry.kind);
/// ```
final class MacOsTargetInspector {
  /// Creates a macOS filesystem inspector.
  ///
  /// Initializes the private Darwin native inspection bridge.
  ///
  /// Throws [UnsupportedError] when constructed outside macOS.
  ///
  /// Native symbol resolution failures are propagated rather than
  /// interpreted as missing filesystem capabilities.
  ///
  /// Construction does not inspect or modify filesystem content.
  MacOsTargetInspector() : _native = DarwinLStat();

  final DarwinLStat _native;

  /// Inspects one filesystem entry without following its final link.
  ///
  /// [path] must contain an absolute macOS/POSIX path.
  ///
  /// Paths ending in `/`, other than the root path itself, are
  /// rejected by the current native bridge. This prevents a
  /// trailing separator from changing final-link resolution.
  ///
  /// The original path spelling is preserved in the result.
  /// No canonicalization or home-directory expansion occurs.
  ///
  /// Returns a [FilesystemEntry] describing the observed type
  /// and currently supported metadata.
  ///
  /// Logical size is the native `st_size` value for the individual
  /// entry, not a recursive directory size. A negative value is
  /// represented as null rather than fabricated as zero.
  ///
  /// Allocated size is derived from native 512-byte block counts.
  /// It does not represent exclusively owned or recoverable storage.
  ///
  /// Filesystem identity combines the native device and inode
  /// identifiers. It is meaningful only within the same live
  /// macOS target identity namespace. Identity reuse is possible.
  ///
  /// POSIX permission bits are reported without inferring effective
  /// access. Effective access fields remain null.
  ///
  /// Modification and access timestamps are converted from native
  /// Darwin timespec values into UTC DateTime observations.
  ///
  /// Native nanosecond precision is reduced to microseconds.
  /// Invalid or unrepresentable timestamps remain null.
  ///
  /// Access timestamps may be stale when filesystem access-time
  /// updates are disabled or deferred.
  ///
  /// Creation time remains null because native birthtime may
  /// silently fall back to inode status-change time on filesystems
  /// that do not support true creation timestamps.
  ///
  /// Completes with [TargetInspectionException] when inspection
  /// fails. The operation is always
  /// [TargetInspectionOperation.inspect].
  ///
  /// Recognized native failures are mapped to specific error codes.
  /// Unclassified native failures become
  /// [TargetInspectionErrorCode.ioFailure].
  ///
  /// The original native exception is preserved as the cause.
  ///
  /// This operation performs no filesystem mutation.
  ///
  /// Example:
  /// ```dart
  /// final inspector = MacOsTargetInspector();
  ///
  /// final entry = await inspector.inspect(
  ///   TargetPath('/tmp/example.txt'),
  /// );
  ///
  /// print(entry.metadata.logical_size_bytes);
  /// ```
  Future<FilesystemEntry> inspect(TargetPath path) async {
    late final DarwinStatSnapshot snapshot;

    try {
      snapshot = _native.inspect(path.value);
    } on ArgumentError catch (error) {
      throw TargetInspectionException(
        code: TargetInspectionErrorCode.invalidPath,
        operation: TargetInspectionOperation.inspect,
        path: path,
        message: 'Invalid absolute macOS inspection path.',
        cause: error,
      );
    } on FileSystemException catch (error) {
      throw TargetInspectionException(
        code: _translate_errno(error.osError?.errorCode),
        operation: TargetInspectionOperation.inspect,
        path: path,
        message: 'macOS could not inspect the filesystem entry.',
        cause: error,
      );
    }

    final kind = _entry_kind(snapshot.mode, path);

    // st_blocks is signed. Negative or unrepresentable values
    // must not become fabricated allocated-size observations.
    final allocated_blocks = snapshot.allocated_blocks;

    final allocated_size_bytes = allocated_blocks >= 0 &&
            allocated_blocks <=
                _maximum_signed_int64 ~/ _darwin_allocation_block_bytes
        ? allocated_blocks * _darwin_allocation_block_bytes
        : null;

    // An inode of zero is treated conservatively as an
    // unavailable identity. Device numbers are scoped to the
    // current macOS target and may be reused over time.
    final identity = snapshot.inode > 0
        ? FilesystemIdentity(
            filesystem_id: 'darwin-dev:${snapshot.device_id}',
            entry_id: snapshot.inode.toString(),
          )
        : null;

    // POSIX mode records permission and special bits.
    // No effective-access checks have been performed.
    final permissions = FilesystemPermissions(
      posix_mode: snapshot.mode & _posix_permission_mask,
    );

    return FilesystemEntry(
      path: path,
      kind: kind,
      metadata: FilesystemMetadata(
        logical_size_bytes: snapshot.logical_size_bytes >= 0
            ? snapshot.logical_size_bytes
            : null,
        allocated_size_bytes: allocated_size_bytes,
        identity: identity,
        permissions: permissions,
        modified_at: snapshot.modification_time.to_utc_datetime(),
        accessed_at: snapshot.access_time.to_utc_datetime(),
      ),
    );
  }

  /// Classifies the native file type without resolving the entry.
  ///
  /// Only known Darwin file-type values are accepted.
  ///
  /// Special files are represented by [FilesystemEntryKind.other].
  /// An unrecognized type is an inspection failure, not an
  /// automatically accepted special entry.
  ///
  /// This prevents corrupted or incompatible native metadata
  /// from being interpreted as a successfully identified entry.
  static FilesystemEntryKind _entry_kind(
    int mode,
    TargetPath path,
  ) {
    final file_type = mode & _file_type_mask;

    switch (file_type) {
      case _regular_file_type:
        return FilesystemEntryKind.regularFile;

      case _directory_type:
        return FilesystemEntryKind.directory;

      case _symbolic_link_type:
        return FilesystemEntryKind.symbolicLink;

      case _fifo_type:
      case _character_device_type:
      case _block_device_type:
      case _socket_type:
      case _whiteout_type:
        return FilesystemEntryKind.other;

      default:
        throw TargetInspectionException(
          code: TargetInspectionErrorCode.ioFailure,
          operation: TargetInspectionOperation.inspect,
          path: path,
          message: 'Unrecognized Darwin filesystem entry type.',
        );
    }
  }

  /// Translates known Darwin errno values into Rudra error codes.
  ///
  /// This method never parses native exception messages.
  ///
  /// Unrecognized and unavailable errno values map to ioFailure,
  /// preserving the original exception separately as the cause.
  static TargetInspectionErrorCode _translate_errno(
    int? error_number,
  ) {
    switch (error_number) {
      case _errno_not_found:
        return TargetInspectionErrorCode.notFound;

      case _errno_operation_not_permitted:
      case _errno_permission_denied:
        return TargetInspectionErrorCode.permissionDenied;

      case _errno_not_directory:
        return TargetInspectionErrorCode.notDirectory;

      case _errno_invalid_argument:
      case _errno_name_too_long:
        return TargetInspectionErrorCode.invalidPath;

      case _errno_symbolic_link_loop:
        return TargetInspectionErrorCode.symbolicLinkLoop;

      default:
        return TargetInspectionErrorCode.ioFailure;
    }
  }
}
