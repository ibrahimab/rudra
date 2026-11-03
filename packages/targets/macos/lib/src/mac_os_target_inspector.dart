import 'dart:io';

import 'package:rudra_target_contracts/rudra_target_contracts.dart';

import 'darwin_directory_reader.dart';
import 'darwin_lstat.dart';
import 'darwin_readlink.dart';

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
/// This is an incremental implementation providing [inspect],
/// [list_directory], and [read_symbolic_link].
///
/// Capability discovery will be added in a subsequent block.
/// Until then, this class is not a complete TargetInspector.
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

  // Lazily initialize directory bindings only when enumeration
  // is first requested. Existing inspect() behavior is unchanged.
  late final DarwinDirectoryReader _directory_reader = DarwinDirectoryReader();

  // Resolve native readlink bindings only when a symbolic-link
  // destination is requested. Inspection and enumeration do not
  // depend on this additional native reader.
  late final DarwinReadLink _symbolic_link_reader = DarwinReadLink();

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

  /// Lazily enumerates immediate children of a macOS directory.
  ///
  /// The returned stream is single-subscription. No directory
  /// descriptor is opened until a listener subscribes.
  ///
  /// Enumeration:
  /// - Is non-recursive and unordered.
  /// - Does not inspect child metadata.
  /// - Does not follow the final directory symbolic link.
  /// - Omits synthetic "." and ".." entries.
  /// - Preserves the requested parent path spelling.
  /// - Performs no filesystem modifications.
  ///
  /// A native directory cursor is closed after normal completion,
  /// failure, or cancellation. Cancellation cannot interrupt an
  /// individual synchronous native readdir call.
  ///
  /// Each emitted path is an observation, not a stable reference
  /// to a filesystem object. Concurrent directory renames or
  /// replacements can make emitted paths stale immediately.
  ///
  /// Failures produce a [TargetInspectionException] stream error
  /// using [TargetInspectionOperation.listDirectory].
  ///
  /// Already emitted entries remain partial observations if
  /// enumeration subsequently fails.
  ///
  /// This operation does not establish session-root containment.
  /// Intermediate symbolic links may still be traversed by macOS.
  ///
  /// Example:
  /// ```dart
  /// final inspector = MacOsTargetInspector();
  ///
  /// await for (final child in inspector.list_directory(
  ///   TargetPath('/tmp'),
  /// )) {
  ///   print(child.value);
  /// }
  /// ```
  Stream<TargetPath> list_directory(TargetPath path) async* {
    DarwinDirectoryCursor? cursor;

    TargetInspectionException? failure;
    StackTrace? failure_stack;

    try {
      try {
        // Native open is intentionally deferred until subscription.
        // O_DIRECTORY and O_NOFOLLOW protect the final component.
        final active_cursor = _directory_reader.open(path.value);
        cursor = active_cursor;

        while (true) {
          final child_name = active_cursor.next_name();

          if (child_name == null) {
            break;
          }

          // Avoid introducing a double separator under filesystem
          // root while preserving the caller's original spelling.
          final child_path =
              path.value == '/' ? '/$child_name' : '${path.value}/$child_name';

          // Yielding permits backpressure and cancellation.
          yield TargetPath(child_path);
        }
      } on ArgumentError catch (error, stack) {
        failure = TargetInspectionException(
          code: TargetInspectionErrorCode.invalidPath,
          operation: TargetInspectionOperation.listDirectory,
          path: path,
          message: 'Invalid absolute macOS directory path.',
          cause: error,
        );

        failure_stack = stack;
      } on FileSystemException catch (error, stack) {
        failure = _directory_failure(
          error,
          path,
          during_open: cursor == null,
        );

        failure_stack = stack;
      }
    } finally {
      if (cursor != null) {
        try {
          cursor.close();
        } on FileSystemException catch (error, stack) {
          // Closing can fail too. Do not discard an earlier
          // enumeration error in favor of a cleanup failure.
          failure ??= _directory_failure(
            error,
            path,
            during_open: false,
          );

          failure_stack ??= stack;
        }
      }
    }

    // Emit the terminal failure after releasing native resources.
    // A successful enumeration reaches this point without error.
    if (failure != null) {
      Error.throwWithStackTrace(
        failure,
        failure_stack!,
      );
    }
  }

  /// Reads the stored destination of a macOS symbolic link.
  ///
  /// [path] must be an absolute macOS path without a trailing
  /// separator, except for the filesystem root.
  ///
  /// The returned [TargetPath] contains the destination exactly
  /// as stored and decoded by the native reader. It may be
  /// absolute or relative.
  ///
  /// This operation:
  /// - Does not resolve the destination.
  /// - Does not require the destination to exist.
  /// - Does not follow the final symbolic link.
  /// - Does not modify filesystem contents.
  ///
  /// Native readlink() is used directly rather than performing
  /// a separate inspection first. This avoids introducing an
  /// unnecessary check/use race.
  ///
  /// A non-symbolic-link entry produces
  /// [TargetInspectionErrorCode.notSymbolicLink].
  ///
  /// Invalid input paths produce
  /// [TargetInspectionErrorCode.invalidPath].
  ///
  /// Other native failures use the existing Darwin errno
  /// translation. Unknown failures become
  /// [TargetInspectionErrorCode.ioFailure].
  ///
  /// Every failure uses
  /// [TargetInspectionOperation.readSymbolicLink] and preserves
  /// the original requested [TargetPath].
  ///
  /// Native exceptions are retained as diagnostic causes.
  ///
  /// This operation is asynchronous at the contract boundary,
  /// but native readlink() executes synchronously and may
  /// briefly block the calling isolate.
  ///
  /// Intermediate symbolic links may still be traversed.
  /// This operation does not establish session-root containment
  /// or authorize any future cleanup operation.
  ///
  /// Example:
  /// ```dart
  /// final inspector = MacOsTargetInspector();
  ///
  /// final destination = await inspector.read_symbolic_link(
  ///   TargetPath('/tmp/cache-link'),
  /// );
  ///
  /// print(destination.value);
  /// ```
  Future<TargetPath> read_symbolic_link(TargetPath path) async {
    late final String destination;

    try {
      // readlink() observes the final symbolic link without
      // following its stored destination.
      destination = _symbolic_link_reader.read_target(
        path.value,
      );
    } on ArgumentError catch (error) {
      throw TargetInspectionException(
        code: TargetInspectionErrorCode.invalidPath,
        operation: TargetInspectionOperation.readSymbolicLink,
        path: path,
        message: 'Invalid absolute macOS symbolic-link path.',
        cause: error,
      );
    } on FileSystemException catch (error) {
      final error_number = error.osError?.errorCode;

      // For readlink(), EINVAL identifies an entry that is not
      // a symbolic link. This differs from the generic inspect()
      // interpretation of EINVAL as invalidPath.
      final code = error_number == _errno_invalid_argument
          ? TargetInspectionErrorCode.notSymbolicLink
          : _translate_errno(error_number);

      throw TargetInspectionException(
        code: code,
        operation: TargetInspectionOperation.readSymbolicLink,
        path: path,
        message: 'macOS could not read the symbolic-link destination.',
        cause: error,
      );
    }

    // Relative destinations are valid contract values.
    // TargetPath deliberately does not canonicalize or resolve them.
    return TargetPath(destination);
  }

  /// Converts a native directory failure into a contract error.
  ///
  /// Uses the existing Darwin errno translation shared with
  /// inspect(), without relying on diagnostic message parsing.
  ///
  /// When open() reports ELOOP, a read-only lstat observation
  /// distinguishes a final symbolic link from an intermediate
  /// symbolic-link cycle where possible.
  ///
  /// A final symbolic link maps to notDirectory, as required
  /// by TargetInspector. A path-resolution cycle maps to
  /// symbolicLinkLoop.
  ///
  /// The additional lstat is observational and may itself race
  /// with concurrent filesystem changes. It never authorizes
  /// traversal or cleanup.
  ///
  /// The original native error remains the diagnostic cause.
  TargetInspectionException _directory_failure(
    FileSystemException error,
    TargetPath path, {
    required bool during_open,
  }) {
    final error_number = error.osError?.errorCode;
    var code = _translate_errno(error_number);

    if (during_open && error_number == _errno_symbolic_link_loop) {
      try {
        final observation = _native.inspect(path.value);

        if ((observation.mode & _file_type_mask) == _symbolic_link_type) {
          code = TargetInspectionErrorCode.notDirectory;
        }
      } on FileSystemException {
        // Preserve the original open failure classification
        // when another read-only observation is unavailable.
      } on ArgumentError {
        // An invalid follow-up observation must not replace
        // the original native failure.
      }
    }

    return TargetInspectionException(
      code: code,
      operation: TargetInspectionOperation.listDirectory,
      path: path,
      message: 'macOS could not enumerate the requested directory.',
      cause: error,
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
