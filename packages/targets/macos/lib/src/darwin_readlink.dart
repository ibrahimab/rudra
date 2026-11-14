import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

// Begin with a modest allocation and grow only when the native
// result could have been truncated.
const int _initial_target_capacity_bytes = 256;

// A bounded allocation prevents unexpectedly large native memory
// requests. Reaching this limit is an explicit failure, not success.
const int _maximum_target_capacity_bytes = 65536;

/// Reads the stored destination of a macOS symbolic link.
///
/// Uses Darwin's native readlink() operation. The final symbolic
/// link is never followed, and its destination is not resolved
/// or checked for existence.
///
/// The returned destination may be absolute or relative. Its
/// spelling, separators, and relative components are preserved.
///
/// Native readlink() returns bytes without a NUL terminator.
/// The reader therefore uses the returned byte count, not
/// C-string termination, to construct the result.
///
/// The reader grows its buffer when the result fills the
/// entire allocation. It never returns a potentially truncated
/// destination.
///
/// Limitations:
/// - Requires macOS.
/// - Performs synchronous native I/O.
/// - Intermediate path components may contain symbolic links.
/// - Concurrent replacement of the entry is possible.
/// - Targets must be representable as valid UTF-8.
/// - Targets exceeding the configured allocation limit fail.
/// - Reading a target does not establish session-root containment.
///
/// This class performs no filesystem modifications.
///
/// Example:
/// ```dart
/// final reader = DarwinReadLink();
///
/// final destination = reader.read_target(
///   '/tmp/example-link',
/// );
///
/// print(destination);
/// ```
final class DarwinReadLink {
  /// Initializes the native readlink and errno bindings.
  ///
  /// Throws [UnsupportedError] outside macOS.
  ///
  /// Missing native symbols cause initialization to fail.
  /// They are not silently interpreted as empty link targets.
  ///
  /// Construction performs no filesystem operations.
  DarwinReadLink() {
    if (!Platform.isMacOS) {
      throw UnsupportedError('DarwinReadLink requires macOS.');
    }

    final library = DynamicLibrary.process();

    _native_readlink = library.lookupFunction<_ReadlinkNative, _ReadlinkDart>(
      'readlink',
    );

    _native_errno = library.lookupFunction<_ErrnoNative, _ErrnoDart>('__error');
  }

  late final _ReadlinkDart _native_readlink;
  late final _ErrnoDart _native_errno;

  /// Reads the raw stored destination of one symbolic link.
  ///
  /// [path] must be an absolute macOS path without an embedded
  /// NUL character or trailing separator, except for `/`.
  ///
  /// Returns a UTF-8-decoded destination without resolving it.
  /// Relative paths such as `../cache` remain relative.
  ///
  /// Throws [ArgumentError] when the input path is invalid.
  ///
  /// Throws [FileSystemException] when:
  /// - The native readlink operation fails.
  /// - The entry is not a symbolic link.
  /// - The target exceeds the supported buffer limit.
  /// - The returned target is empty or contains a NUL byte.
  /// - The target cannot be decoded as strict UTF-8.
  ///
  /// Native failures preserve errno in [OSError]. Failures
  /// validating returned bytes have no synthetic errno.
  ///
  /// No native buffer survives this method call.
  ///
  /// This operation does not inspect, resolve, or follow the
  /// stored destination and does not modify filesystem content.
  ///
  /// Example:
  /// ```dart
  /// final target = DarwinReadLink().read_target(
  ///   '/tmp/cache-shortcut',
  /// );
  ///
  /// print(target);
  /// ```
  String read_target(String path) {
    if (path.isEmpty ||
        !path.startsWith('/') ||
        path.contains('\u0000') ||
        (path.length > 1 && path.endsWith('/'))) {
      throw ArgumentError.value(
        path,
        'path',
        'Expected an absolute macOS symbolic-link path.',
      );
    }

    final native_path = path.toNativeUtf8(allocator: calloc);

    try {
      var buffer_capacity = _initial_target_capacity_bytes;

      while (true) {
        final native_buffer = calloc<Uint8>(buffer_capacity);

        try {
          final bytes_read = _native_readlink(
            native_path,
            native_buffer,
            buffer_capacity,
          );

          if (bytes_read < 0) {
            // Capture errno immediately after readlink fails.
            final error_number = _native_errno().value;

            throw FileSystemException(
              'Native readlink failed.',
              path,
              OSError('readlink', error_number),
            );
          }

          if (bytes_read > buffer_capacity) {
            // A conforming readlink must never return more bytes
            // than the supplied buffer can hold.
            throw FileSystemException(
              'Invalid native readlink byte count.',
              path,
            );
          }

          if (bytes_read == buffer_capacity) {
            // When the count equals the allocation size, the
            // result might have been truncated. Retry using
            // a larger buffer rather than returning bad data.
            if (buffer_capacity == _maximum_target_capacity_bytes) {
              throw FileSystemException(
                'Symbolic-link destination exceeds the '
                'supported allocation limit.',
                path,
              );
            }

            buffer_capacity *= 2;
            continue;
          }

          if (bytes_read == 0) {
            throw FileSystemException(
              'Symbolic-link destination is empty.',
              path,
            );
          }

          // Copy the returned bytes while native memory is
          // valid. readlink does not NUL-terminate its output.
          final target_bytes = List<int>.from(
            native_buffer.asTypedList(bytes_read),
            growable: false,
          );

          if (target_bytes.contains(0)) {
            throw FileSystemException(
              'Symbolic-link destination contains a NUL byte.',
              path,
            );
          }

          try {
            // Do not replace malformed bytes: that could
            // fabricate a destination identifying another
            // filesystem object.
            return utf8.decode(target_bytes, allowMalformed: false);
          } on FormatException {
            throw FileSystemException(
              'Symbolic-link destination is not valid UTF-8.',
              path,
            );
          }
        } finally {
          calloc.free(native_buffer);
        }
      }
    } finally {
      calloc.free(native_path);
    }
  }
}

/// Native signature of POSIX readlink().
///
/// ssize_t is represented by IntPtr and size_t by Size,
/// matching their pointer-width representations.
typedef _ReadlinkNative = IntPtr Function(Pointer<Utf8>, Pointer<Uint8>, Size);

/// Dart-callable signature of the native readlink function.
typedef _ReadlinkDart = int Function(Pointer<Utf8>, Pointer<Uint8>, int);

/// Native signature of Darwin's thread-local errno accessor.
typedef _ErrnoNative = Pointer<Int32> Function();

/// Dart-callable signature of the errno accessor.
typedef _ErrnoDart = Pointer<Int32> Function();
