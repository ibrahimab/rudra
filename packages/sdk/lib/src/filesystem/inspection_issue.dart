import 'package:rudra_target_contracts/rudra_target_contracts.dart';

/// An immutable description of a filesystem inspection issue.
///
/// InspectionIssue is a data model, not an exception.
///
/// It represents an unsuccessful filesystem observation using
/// platform-independent types defined by Rudra's target contracts.
///
/// SDK services may include issues in their response models when
/// an inspection partially succeeds or cannot be completed.
///
/// Consumers must use [code] and [operation] to classify issues.
/// The [message] is diagnostic information and must not be parsed
/// to determine application behavior.
///
/// Unlike [TargetInspectionException], this model does not retain
/// native exception objects or platform-specific causes.
///
/// This allows CLI, Flutter, and future consumers to exchange
/// inspection results without depending on native error types.
///
/// Invariants:
/// - Every issue has a typed error code.
/// - Every issue identifies the failed operation.
/// - Every issue identifies the affected target path.
/// - Diagnostic messages must not be blank.
/// - Instances are immutable.
/// - Constructing an issue performs no filesystem operations.
///
/// Example:
/// ```dart
/// final issue = InspectionIssue(
///   code: TargetInspectionErrorCode.permissionDenied,
///   operation: TargetInspectionOperation.inspect,
///   path: TargetPath('/Users/example/private'),
///   message: 'Permission denied.',
/// );
///
/// if (issue.code ==
///     TargetInspectionErrorCode.permissionDenied) {
///   print('The requested entry is inaccessible.');
/// }
/// ```
final class InspectionIssue {
  /// Creates an immutable inspection issue.
  ///
  /// [code] identifies the failure category.
  ///
  /// [operation] identifies the operation that failed.
  ///
  /// [path] identifies the affected filesystem location using
  /// the target platform's native path syntax.
  ///
  /// [message] provides human-readable diagnostic information.
  ///
  /// Throws [ArgumentError] when [message] is empty or contains
  /// only whitespace.
  ///
  /// This constructor performs no filesystem operations.
  InspectionIssue({
    required this.code,
    required this.operation,
    required this.path,
    required String message,
  }) : message = _require_non_blank(message);

  /// Creates an issue from a target inspection exception.
  ///
  /// Preserves the exception's typed error category, operation,
  /// target path, and diagnostic message.
  ///
  /// The original native [TargetInspectionException.cause]
  /// is deliberately excluded.
  ///
  /// This conversion does not modify the original exception.
  ///
  /// Example:
  /// ```dart
  /// final exception = TargetInspectionException(
  ///   code: TargetInspectionErrorCode.notFound,
  ///   operation: TargetInspectionOperation.inspect,
  ///   path: TargetPath('/tmp/missing'),
  ///   message: 'Entry not found.',
  /// );
  ///
  /// final issue = InspectionIssue.from_target_exception(
  ///   exception,
  /// );
  /// ```
  factory InspectionIssue.from_target_exception(
    TargetInspectionException exception,
  ) {
    return InspectionIssue(
      code: exception.code,
      operation: exception.operation,
      path: exception.path,
      message: exception.message,
    );
  }

  /// Platform-independent classification of the failure.
  ///
  /// Consumers should branch on this value rather than [message].
  final TargetInspectionErrorCode code;

  /// The filesystem operation that produced the issue.
  final TargetInspectionOperation operation;

  /// The affected target-native filesystem path.
  ///
  /// This value preserves the target's path syntax.
  /// It must not be interpreted using the frontend host's
  /// filesystem rules.
  final TargetPath path;

  /// Human-readable diagnostic information.
  ///
  /// This field is intended for presentation and diagnostics.
  ///
  /// It must not be used as a machine-readable error category.
  final String message;

  /// Validates that a diagnostic message contains visible text.
  ///
  /// The original message is preserved without trimming it.
  ///
  /// Throws [ArgumentError] if [value] is blank.
  static String _require_non_blank(String value) {
    if (value.trim().isEmpty) {
      throw ArgumentError.value(
        value,
        'message',
        'An inspection issue message must not be blank.',
      );
    }

    return value;
  }
}
