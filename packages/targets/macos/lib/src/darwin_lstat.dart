import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// An immutable observation obtained from Darwin's native `lstat`.
///
/// The values describe the filesystem entry itself, without following
/// a symbolic link in the final path component.
///
/// This is a private adapter implementation detail. It is not a
/// persistent filesystem identity or a cleanup authorization token.
///
/// The reported block count is not guaranteed recoverable storage.
final class DarwinStatSnapshot {
  /// Creates a Dart-owned copy of the required native fields.
  const DarwinStatSnapshot({
    required this.mode,
    required this.device_id,
    required this.inode,
    required this.logical_size_bytes,
    required this.allocated_blocks,
  });

  /// Native POSIX mode including file type and permission bits.
  final int mode;

  /// Native device identifier, scoped to the inspected host.
  final int device_id;

  /// Native inode identifier for the observed filesystem entry.
  final int inode;

  /// Native apparent size, without recursive aggregation.
  final int logical_size_bytes;

  /// Native allocation count in 512-byte units.
  ///
  /// This is not necessarily the number of blocks exclusively
  /// owned by the entry or recoverable through deletion.
  final int allocated_blocks;
}

/// The 64-bit Darwin representation of a POSIX timespec.
///
/// This type is used solely to preserve the native struct layout.
/// Timestamp conversion is deferred to the metadata implementation.
final class _DarwinTimespec extends Struct {
  @Int64()
  external int tv_sec;

  @Int64()
  external int tv_nsec;
}

/// Darwin's 64-bit `struct stat` representation.
///
/// Field ordering and widths follow Apple's `sys/stat.h`.
///
/// This layout targets 64-bit macOS processes on supported Darwin
/// architectures. It must be validated against native fixtures
/// before being relied upon for production inspection.
///
/// Never use this structure for Linux or Windows.
final class _DarwinStat extends Struct {
  @Int32()
  external int st_dev;

  @Uint16()
  external int st_mode;

  @Uint16()
  external int st_nlink;

  @Uint64()
  external int st_ino;

  @Uint32()
  external int st_uid;

  @Uint32()
  external int st_gid;

  @Int32()
  external int st_rdev;

  external _DarwinTimespec st_atimespec;
  external _DarwinTimespec st_mtimespec;
  external _DarwinTimespec st_ctimespec;
  external _DarwinTimespec st_birthtimespec;

  @Int64()
  external int st_size;

  @Int64()
  external int st_blocks;

  @Int32()
  external int st_blksize;

  @Uint32()
  external int st_flags;

  @Uint32()
  external int st_gen;

  @Int32()
  external int st_lspare;

  @Array(2)
  external Array<Int64> st_qspare;
}

typedef _LstatNative = Int32 Function(
  Pointer<Utf8>,
  Pointer<_DarwinStat>,
);

typedef _LstatDart = int Function(
  Pointer<Utf8>,
  Pointer<_DarwinStat>,
);

typedef _ErrnoNative = Pointer<Int32> Function();
typedef _ErrnoDart = Pointer<Int32> Function();

/// Provides read-only native filesystem inspection on macOS.
///
/// Uses `lstat` rather than `stat`, preserving the identity and type
/// of symbolic links in the final path component.
///
/// A successful call returns a Dart-owned snapshot. Native memory
/// is freed before the method returns.
///
/// Errors are preserved as [FileSystemException] with their native
/// [OSError] codes. Platform-independent error translation occurs
/// in MacOsTargetInspector.
///
/// Limitations:
/// - Requires a 64-bit macOS Dart VM.
/// - Calls native functions synchronously.
/// - Intermediate symbolic links may still be traversed.
/// - Does not establish containment inside a session root.
/// - Does not provide race-safe authorization for future deletion.
/// - Rejects trailing separators other than the root path to avoid
///   unintentionally following a final symbolic link.
///
/// Example:
/// ```dart
/// final native = DarwinLStat();
/// final result = native.inspect('/tmp/example.txt');
///
/// print(result.logical_size_bytes);
/// ```
final class DarwinLStat {
  /// Initializes the Darwin native function bindings.
  ///
  /// Throws [UnsupportedError] outside macOS.
  ///
  /// Fails during initialization when a required native symbol
  /// cannot be resolved. Such failure must not silently produce
  /// incomplete filesystem observations.
  DarwinLStat() {
    if (!Platform.isMacOS) {
      throw UnsupportedError(
        'DarwinLStat requires macOS.',
      );
    }

    final library = DynamicLibrary.process();

    _lstat = _lookup_lstat(library);
    _errno = library.lookupFunction<_ErrnoNative, _ErrnoDart>('__error');
  }

  late final _LstatDart _lstat;
  late final _ErrnoDart _errno;

  /// Inspects one filesystem entry without following its final link.
  ///
  /// [path] must be an absolute macOS path without a NUL character.
  /// A trailing slash is rejected except for `/`.
  ///
  /// Throws [ArgumentError] for invalid input.
  ///
  /// Throws [FileSystemException] if native `lstat` fails. The
  /// original native errno is retained in the exception's OSError.
  ///
  /// This operation performs no filesystem modification.
  ///
  /// Example:
  /// ```dart
  /// final result = DarwinLStat().inspect('/tmp');
  ///
  /// print(result.inode);
  /// ```
  DarwinStatSnapshot inspect(String path) {
    if (path.isEmpty ||
        !path.startsWith('/') ||
        path.contains('\u0000') ||
        (path.length > 1 && path.endsWith('/'))) {
      throw ArgumentError.value(
        path,
        'path',
        'Expected an absolute macOS path without NUL or a trailing slash.',
      );
    }

    final native_stat = calloc<_DarwinStat>();

    try {
      final native_path = path.toNativeUtf8(
        allocator: calloc,
      );

      try {
        final result = _lstat(native_path, native_stat);

        if (result != 0) {
          // Capture errno immediately after the failed native call.
          final error_number = _errno().value;

          throw FileSystemException(
            'Native lstat failed.',
            path,
            OSError('lstat', error_number),
          );
        }

        final stat = native_stat.ref;

        return DarwinStatSnapshot(
          mode: stat.st_mode,
          device_id: stat.st_dev,
          inode: stat.st_ino,
          logical_size_bytes: stat.st_size,
          allocated_blocks: stat.st_blocks,
        );
      } finally {
        calloc.free(native_path);
      }
    } finally {
      calloc.free(native_stat);
    }
  }

  /// Resolves the Darwin native `lstat` symbol.
  ///
  /// The 64-bit inode variant is preferred. Modern macOS toolchains
  /// may also expose the unsuffixed symbol.
  ///
  /// Both variants must be validated against the expected 64-bit
  /// struct layout by the native integration tests.
  static _LstatDart _lookup_lstat(
    DynamicLibrary library,
  ) {
    try {
      return library.lookupFunction<_LstatNative, _LstatDart>('lstat\$INODE64');
    } on ArgumentError {
      return library.lookupFunction<_LstatNative, _LstatDart>('lstat');
    }
  }
}
