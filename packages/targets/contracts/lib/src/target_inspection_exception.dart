import 'target_inspection_error_code.dart';
import 'target_inspection_operation.dart';
import 'target_path.dart';

/// Represents a typed failure during target filesystem inspection.
///
/// This exception is independent of platform-specific filesystem
/// exception classes.
///
/// The [code] identifies the category of failure.
/// The [operation] identifies which inspection operation failed.
/// The [path] identifies the filesystem path involved.
/// The [message] provides diagnostic context.
///
/// The optional [cause] preserves the original failure for
/// diagnostics without requiring the SDK to import a platform API.
///
/// Callers must use [code] for programmatic classification rather
/// than parsing [message] or [toString].
///
/// The SDK determines whether a failure terminates an inspection
/// workflow or permits partial results to be retained.
///
/// Example:
/// ```dart
/// final error = TargetInspectionException(
///   code: TargetInspectionErrorCode.permissionDenied,
///   operation: TargetInspectionOperation.listDirectory,
///   path: TargetPath('/Users/example/private'),
///   message: 'Directory enumeration was denied.',
/// );
///
/// print(error.code);
/// // TargetInspectionErrorCode.permissionDenied
/// ```
final class TargetInspectionException implements Exception {
  /// Creates a typed filesystem inspection failure.
  ///
  /// The [message] must contain at least one non-whitespace character.
  ///
  /// [cause] may contain the original platform-specific exception.
  /// It is retained for diagnostics and is not interpreted by this
  /// contract.
  ///
  /// Throws [ArgumentError] if [message] is blank.
  ///
  /// Example:
  /// ```dart
  /// final error = TargetInspectionException(
  ///   code: TargetInspectionErrorCode.notFound,
  ///   operation: TargetInspectionOperation.inspect,
  ///   path: TargetPath('/tmp/missing'),
  ///   message: 'The filesystem entry was not found.',
  /// );
  /// ```
  TargetInspectionException({
    required this.code,
    required this.operation,
    required this.path,
    required this.message,
    this.cause,
  }) {
    if (message.trim().isEmpty) {
      throw ArgumentError.value(
        message,
        'message',
        'An inspection error message must not be blank.',
      );
    }
  }

  /// Platform-independent classification of the failure.
  final TargetInspectionErrorCode code;

  /// The inspection operation that failed.
  final TargetInspectionOperation operation;

  /// The target-native path associated with the failure.
  ///
  /// This is the attempted operation's path, which may no longer
  /// exist or may have been rejected by the target platform.
  final TargetPath path;

  /// Human-readable diagnostic description of the failure.
  ///
  /// Consumers must not rely on this text for programmatic
  /// decisions.
  final String message;

  /// Optional original error that caused the inspection failure.
  ///
  /// This may be platform-specific and should only be used for
  /// diagnostics. It must not be required for error classification.
  ///
  /// Its string representation is deliberately excluded from
  /// [toString] to avoid unintentionally exposing native details.
  final Object? cause;

  /// Returns a readable representation of the inspection failure.
  ///
  /// The representation includes the operation, error code, path,
  /// and message, but excludes the original [cause].
  ///
  /// This output is intended for diagnostics, not for machine
  /// parsing or serialization.
  ///
  /// Example:
  /// ```dart
  /// final error = TargetInspectionException(
  ///   code: TargetInspectionErrorCode.notFound,
  ///   operation: TargetInspectionOperation.inspect,
  ///   path: TargetPath('/tmp/missing'),
  ///   message: 'Entry not found.',
  /// );
  ///
  /// print(error.toString().contains('notFound'));
  /// // true
  /// ```
  @override
  String toString() {
    return 'TargetInspectionException('
        'operation: ${operation.name}, '
        'code: ${code.name}, '
        'path: ${path.value}, '
        'message: $message'
        ')';
  }
}
