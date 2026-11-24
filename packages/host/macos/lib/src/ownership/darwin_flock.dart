import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Open a native file descriptor for reading and writing.
const int _o_rdwr = 0x0002;

/// Reject lock contention without blocking the calling process.
const int _o_nonblock = 0x0004;

/// Acquire an exclusive lock atomically during open.
const int _o_exlock = 0x0020;

/// Reject symbolic links in the final path component.
const int _o_nofollow = 0x0100;

/// Create the lock file when it does not already exist.
const int _o_creat = 0x0200;

/// Prevent descriptor inheritance across process execution.
const int _o_cloexec = 0x01000000;

/// Owner-only read and write permissions, equivalent to POSIX 0600.
const int _owner_read_write = 0x0180;

/// Darwin EWOULDBLOCK, indicating nonblocking lock contention.
const int _e_would_block = 35;

/// C ABI for open with a variadic file-creation mode.
typedef _OpenNative = Int Function(Pointer<Utf8>, Int, VarArgs<(Int,)>);

/// Dart binding for native file opening and creation.
typedef _OpenDart = int Function(Pointer<Utf8>, int, int);

/// C ABI for closing a native file descriptor.
typedef _CloseNative = Int Function(Int);

/// Dart binding for native descriptor disposal.
typedef _CloseDart = int Function(int);

/// C ABI for retrieving the thread-local errno location.
typedef _ErrnoNative = Pointer<Int32> Function();

/// Dart binding for retrieving native error information.
typedef _ErrnoDart = Pointer<Int32> Function();

/// Provides exclusive file ownership using Darwin locking semantics.
///
/// Acquires an exclusive kernel-managed lock atomically while
/// opening the designated lock file.
///
/// The returned descriptor retains ownership until closed or
/// until the owning process terminates. The lock file itself
/// remains available for subsequent acquisitions.
///
/// Example:
/// ```dart
/// final native = DarwinFlock();
/// final descriptor = native.try_acquire(
///   '/workspace/rudra/rudra-host.lock',
/// );
///
/// if (descriptor != null) {
///   native.release(
///     descriptor: descriptor,
///     path: '/workspace/rudra/rudra-host.lock',
///   );
/// }
/// ```
final class DarwinFlock {
  /// Initializes the native Darwin locking bindings.
  ///
  /// Throws [UnsupportedError] outside macOS.
  /// Native symbol-resolution failures propagate to the caller.
  DarwinFlock() {
    if (!Platform.isMacOS) {
      throw UnsupportedError('DarwinFlock requires macOS.');
    }

    final library = DynamicLibrary.process();

    _open = library.lookupFunction<_OpenNative, _OpenDart>('open');

    _close = library.lookupFunction<_CloseNative, _CloseDart>('close');

    _errno = library.lookupFunction<_ErrnoNative, _ErrnoDart>('__error');
  }

  /// Native file opening and atomic lock acquisition.
  late final _OpenDart _open;

  /// Native descriptor disposal.
  late final _CloseDart _close;

  /// Native thread-local error retrieval.
  late final _ErrnoDart _errno;

  /// Attempts exclusive ownership of the lock file at [path].
  ///
  /// [path] must be absolute and must not contain NUL characters.
  ///
  /// Returns an acquired native descriptor, or null when another
  /// owner holds the lock.
  ///
  /// Throws [ArgumentError] for invalid paths and
  /// [FileSystemException] for other native failures.
  ///
  /// The caller assumes responsibility for closing a successfully
  /// acquired descriptor through [release].
  int? try_acquire(String path) {
    if (!path.startsWith('/') || path.contains('\u0000')) {
      throw ArgumentError.value(
        path,
        'path',
        'Expected an absolute native lock path.',
      );
    }

    final native_path = path.toNativeUtf8(allocator: calloc);

    try {
      // Acquire ownership during open rather than performing a
      // separate existence check followed by lock acquisition.
      //
      // O_CLOEXEC prevents future child executables from
      // unintentionally retaining the host's ownership resource.
      final descriptor = _open(
        native_path,
        _o_rdwr | _o_nonblock | _o_exlock | _o_nofollow | _o_creat | _o_cloexec,
        _owner_read_write,
      );

      if (descriptor >= 0) {
        return descriptor;
      }

      // Capture errno before another native operation can
      // overwrite the failure information.
      final error_number = _errno().value;

      if (error_number == _e_would_block) {
        return null;
      }

      throw FileSystemException(
        'Unable to acquire native host ownership.',
        path,
        OSError('open', error_number),
      );
    } finally {
      calloc.free(native_path);
    }
  }

  /// Releases the acquired native [descriptor].
  ///
  /// [path] identifies the associated lock file for diagnostics.
  ///
  /// Throws [FileSystemException] if native descriptor disposal
  /// fails. The lock file is retained for subsequent acquisitions.
  void release({required int descriptor, required String path}) {
    // Closing the descriptor releases its associated flock
    // ownership without unlinking the underlying file.
    if (_close(descriptor) != 0) {
      final error_number = _errno().value;

      throw FileSystemException(
        'Unable to release native host ownership.',
        path,
        OSError('close', error_number),
      );
    }
  }
}
