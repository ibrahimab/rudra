import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

// Native macOS open flags from sys/fcntl.h.
const int _open_read_only = 0x00000000;
const int _open_no_follow = 0x00000100;
const int _open_directory_only = 0x00100000;
const int _open_close_on_exec = 0x01000000;

const int _directory_open_flags = _open_read_only |
    _open_no_follow |
    _open_directory_only |
    _open_close_on_exec;

// Darwin's 64-bit dirent structure uses a 1024-byte name array.
// The name begins after two 64-bit fields, two 16-bit fields,
// and one 8-bit field.
const int _directory_name_capacity = 1024;
const int _directory_name_offset_bytes = 21;

/// Darwin's 64-bit directory entry representation.
///
/// This structure follows the 64-bit inode layout declared by
/// macOS in sys/dirent.h.
///
/// The native memory belongs to the DIR stream. Its contents
/// must be copied before another readdir call or closedir.
///
/// The structure is never allocated or freed directly by Rudra.
final class _DarwinDirent extends Struct {
  @Uint64()
  external int d_ino;

  @Uint64()
  external int d_seekoff;

  @Uint16()
  external int d_reclen;

  @Uint16()
  external int d_namlen;

  @Uint8()
  external int d_type;

  @Array(_directory_name_capacity)
  external Array<Uint8> d_name;
}

typedef _OpenNative = Int32 Function(
  Pointer<Utf8>,
  Int32,
);
typedef _OpenDart = int Function(
  Pointer<Utf8>,
  int,
);

typedef _FdOpenDirNative = Pointer<Void> Function(Int32);
typedef _FdOpenDirDart = Pointer<Void> Function(int);

typedef _ReadDirNative = Pointer<_DarwinDirent> Function(
  Pointer<Void>,
);
typedef _ReadDirDart = Pointer<_DarwinDirent> Function(
  Pointer<Void>,
);

typedef _CloseDirNative = Int32 Function(Pointer<Void>);
typedef _CloseDirDart = int Function(Pointer<Void>);

typedef _CloseNative = Int32 Function(Int32);
typedef _CloseDart = int Function(int);

typedef _ErrnoNative = Pointer<Int32> Function();
typedef _ErrnoDart = Pointer<Int32> Function();

/// Creates a native filesystem exception from an observed errno.
///
/// The supplied errno must have been captured immediately after
/// the failing native call. Diagnostic messages are not used
/// for programmatic error classification.
FileSystemException _native_failure(
  String operation,
  String path,
  int error_number,
) {
  return FileSystemException(
    'Native $operation failed.',
    path,
    OSError(operation, error_number),
  );
}

/// Opens macOS directories for read-only, descriptor-based inspection.
///
/// The final path component is protected by O_NOFOLLOW.
/// O_DIRECTORY requires the opened object to be a directory.
///
/// Opening a descriptor does not establish session-root
/// containment. Intermediate path components may contain links.
///
/// The caller owns the returned [DarwinDirectoryCursor] and must
/// close it, including when iteration fails or is cancelled.
///
/// No filesystem contents are modified.
///
/// Example:
/// ```dart
/// final reader = DarwinDirectoryReader();
/// final cursor = reader.open('/tmp');
///
/// try {
///   String? name;
///
///   while ((name = cursor.next_name()) != null) {
///     print(name);
///   }
/// } finally {
///   cursor.close();
/// }
/// ```
final class DarwinDirectoryReader {
  /// Resolves the native macOS directory functions.
  ///
  /// Requires the macOS ARM64 or x64 ABI.
  ///
  /// A missing required native symbol causes initialization
  /// to fail rather than silently switching to an unverified ABI.
  ///
  /// Construction performs no filesystem traversal.
  DarwinDirectoryReader() {
    if (!Platform.isMacOS) {
      throw UnsupportedError(
        'DarwinDirectoryReader requires macOS.',
      );
    }

    final abi = Abi.current();

    if (abi != Abi.macosArm64 && abi != Abi.macosX64) {
      throw UnsupportedError(
        'Unsupported macOS native ABI: $abi',
      );
    }

    final library = DynamicLibrary.process();

    // Intel macOS uses the versioned 64-bit inode symbols.
    // ARM64 macOS uses the native unsuffixed implementations.
    final fdopendir_symbol =
        abi == Abi.macosX64 ? 'fdopendir\$INODE64' : 'fdopendir';

    final readdir_symbol = abi == Abi.macosX64 ? 'readdir\$INODE64' : 'readdir';

    _native_open = library.lookupFunction<_OpenNative, _OpenDart>('open');

    _native_fdopendir = library
        .lookupFunction<_FdOpenDirNative, _FdOpenDirDart>(fdopendir_symbol);

    _native_readdir =
        library.lookupFunction<_ReadDirNative, _ReadDirDart>(readdir_symbol);

    _native_closedir =
        library.lookupFunction<_CloseDirNative, _CloseDirDart>('closedir');

    _native_close = library.lookupFunction<_CloseNative, _CloseDart>('close');

    _native_errno = library.lookupFunction<_ErrnoNative, _ErrnoDart>('__error');
  }

  late final _OpenDart _native_open;
  late final _FdOpenDirDart _native_fdopendir;
  late final _ReadDirDart _native_readdir;
  late final _CloseDirDart _native_closedir;
  late final _CloseDart _native_close;
  late final _ErrnoDart _native_errno;

  /// Opens an absolute directory path without following a final link.
  ///
  /// [path] must be absolute, contain no NUL bytes, and must
  /// not have a trailing slash except when it is `/`.
  ///
  /// Returns an owned cursor positioned before the first entry.
  ///
  /// Throws [ArgumentError] for invalid input paths.
  /// Throws [FileSystemException] for native open failures,
  /// preserving the original errno.
  ///
  /// When fdopendir fails, the previously opened descriptor is
  /// closed before propagating the failure.
  ///
  /// This method performs synchronous native I/O.
  ///
  /// Example:
  /// ```dart
  /// final cursor = DarwinDirectoryReader().open('/tmp');
  /// try {
  ///   print(cursor.next_name());
  /// } finally {
  ///   cursor.close();
  /// }
  /// ```
  DarwinDirectoryCursor open(String path) {
    if (path.isEmpty ||
        !path.startsWith('/') ||
        path.contains('\u0000') ||
        (path.length > 1 && path.endsWith('/'))) {
      throw ArgumentError.value(
        path,
        'path',
        'Expected an absolute macOS directory path.',
      );
    }

    final native_path = path.toNativeUtf8(
      allocator: calloc,
    );

    try {
      final descriptor = _native_open(
        native_path,
        _directory_open_flags,
      );

      if (descriptor < 0) {
        final error_number = _native_errno().value;
        throw _native_failure('open', path, error_number);
      }

      // fdopendir takes ownership only on success.
      final directory = _native_fdopendir(descriptor);

      if (directory == nullptr) {
        final error_number = _native_errno().value;

        // Preserve the original fdopendir failure.
        // The descriptor is still caller-owned here.
        _native_close(descriptor);

        throw _native_failure(
          'fdopendir',
          path,
          error_number,
        );
      }

      return DarwinDirectoryCursor._(
        path: path,
        directory: directory,
        read_dir: _native_readdir,
        close_dir: _native_closedir,
        errno: _native_errno,
      );
    } finally {
      calloc.free(native_path);
    }
  }
}

/// Owns one open native macOS directory stream.
///
/// Each call to [next_name] returns one immediate child name.
/// It does not inspect child metadata or follow symbolic links.
///
/// A null result indicates normal end-of-directory only when
/// the native readdir call completed without errno.
///
/// A native error throws [FileSystemException] instead of
/// returning null, preserving incomplete-enumeration semantics.
///
/// Directory names that cannot be represented as strict UTF-8
/// cause an explicit failure. They are never silently replaced.
///
/// This cursor is synchronous and not safe for concurrent reads.
/// Its owner must call [close], including after errors.
///
/// Example:
/// ```dart
/// final cursor = DarwinDirectoryReader().open('/tmp');
///
/// try {
///   final name = cursor.next_name();
///   print(name);
/// } finally {
///   cursor.close();
/// }
/// ```
final class DarwinDirectoryCursor {
  DarwinDirectoryCursor._({
    required this.path,
    required Pointer<Void> directory,
    required _ReadDirDart read_dir,
    required _CloseDirDart close_dir,
    required _ErrnoDart errno,
  })  : _directory = directory,
        _read_dir = read_dir,
        _close_dir = close_dir,
        _errno = errno;

  /// The original path used to open this directory.
  final String path;

  Pointer<Void> _directory;
  final _ReadDirDart _read_dir;
  final _CloseDirDart _close_dir;
  final _ErrnoDart _errno;

  /// Whether ownership of the native directory stream has ended.
  ///
  /// A failed close attempt also ends ownership from this cursor's
  /// perspective, preventing accidental repeated native closes.
  bool get is_closed => _directory == nullptr;

  /// Reads the next immediate child name from the directory.
  ///
  /// Returns null only at normal end-of-directory.
  /// The synthetic `.` and `..` entries are ignored.
  ///
  /// Throws [StateError] when the cursor has been closed.
  /// Throws [FileSystemException] for native enumeration errors
  /// or directory names that cannot be represented safely.
  ///
  /// Results are not sorted and are not an atomic snapshot.
  /// Entries may change while enumeration is in progress.
  ///
  /// This method does not recurse, inspect children, or modify
  /// the filesystem.
  ///
  /// Example:
  /// ```dart
  /// final cursor = DarwinDirectoryReader().open('/tmp');
  ///
  /// try {
  ///   while (true) {
  ///     final name = cursor.next_name();
  ///     if (name == null) break;
  ///     print(name);
  ///   }
  /// } finally {
  ///   cursor.close();
  /// }
  /// ```
  String? next_name() {
    if (is_closed) {
      throw StateError('Directory cursor is already closed.');
    }

    while (true) {
      // readdir uses NULL for both EOF and failure. Clearing
      // errno beforehand allows us to distinguish the two.
      _errno().value = 0;

      final native_entry = _read_dir(_directory);

      if (native_entry == nullptr) {
        final error_number = _errno().value;

        if (error_number != 0) {
          throw _native_failure(
            'readdir',
            path,
            error_number,
          );
        }

        return null;
      }

      // The entry memory is owned by libc and becomes invalid
      // after another read. Copy the name immediately.
      final entry = native_entry.ref;
      final name_length = entry.d_namlen;

      if (name_length <= 0 ||
          name_length >= _directory_name_capacity ||
          entry.d_reclen < _directory_name_offset_bytes + name_length + 1 ||
          entry.d_name[name_length] != 0) {
        throw FileSystemException(
          'Invalid native directory entry record.',
          path,
        );
      }

      final name_bytes = List<int>.generate(
        name_length,
        (index) => entry.d_name[index],
        growable: false,
      );

      if (name_bytes.contains(0)) {
        throw FileSystemException(
          'Directory entry contains an invalid NUL byte.',
          path,
        );
      }

      late final String name;

      try {
        name = utf8.decode(
          name_bytes,
          allowMalformed: false,
        );
      } on FormatException {
        throw FileSystemException(
          'Directory entry name is not valid UTF-8.',
          path,
        );
      }

      if (name == '.' || name == '..') {
        continue;
      }

      return name;
    }
  }

  /// Closes the native directory stream and its file descriptor.
  ///
  /// Safe to invoke repeatedly. Only the first call attempts
  /// native resource release.
  ///
  /// Throws [FileSystemException] when native closedir fails.
  ///
  /// The cursor is considered closed even after a native close
  /// failure. Callers must preserve that error as an incomplete
  /// enumeration outcome when applicable.
  ///
  /// Example:
  /// ```dart
  /// final cursor = DarwinDirectoryReader().open('/tmp');
  /// cursor.close();
  /// assert(cursor.is_closed);
  /// ```
  void close() {
    if (is_closed) {
      return;
    }

    final directory = _directory;
    _directory = nullptr;

    if (_close_dir(directory) != 0) {
      final error_number = _errno().value;

      throw _native_failure(
        'closedir',
        path,
        error_number,
      );
    }
  }
}
