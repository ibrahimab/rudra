/// Stable reasons for rejecting workflow command validation.
///
/// Business rejections can be translated into durable submission
/// resolutions by the application processor.
///
/// Identity and request-binding mismatches instead indicate an
/// invalid processing proposal and must fail closed.
enum WorkflowCommandValidationErrorCode {
  /// A new workflow was requested while one remains unfinished.
  workflow_already_active,

  /// A command requires a current unfinished workflow.
  workflow_not_active,

  /// A command targets a different established workflow.
  workflow_id_mismatch,

  /// A proposed identity changes the requested filesystem target.
  target_mismatch,

  /// A proposed identity changes the requested inspection root.
  root_mismatch,

  /// A supplied identity conflicts with committed workflow identity.
  identity_mismatch,
}

/// Indicates that a workflow command violates a domain invariant.
///
/// Command validation occurs before proposing authoritative
/// domain outcomes. A rejected validation does not alter the
/// current snapshot, submit events, or modify persistence.
///
/// [code] allows the application processor to distinguish
/// recognized business rejections from integrity failures.
///
/// Example:
/// ```dart
/// try {
///   behavior.validate_submission(
///     command,
///     previous: snapshot,
///     identity: identity,
///   );
/// } on WorkflowCommandValidationException catch (error) {
///   print(error.code);
/// }
/// ```
final class WorkflowCommandValidationException implements Exception {
  /// Creates a classified command-validation failure.
  ///
  /// [code] identifies the violated invariant.
  /// [message] supplies a human-readable diagnostic.
  const WorkflowCommandValidationException({
    required this.code,
    required this.message,
  });

  /// Machine-readable reason for the validation failure.
  final WorkflowCommandValidationErrorCode code;

  /// Human-readable explanation without serialized command payloads.
  final String message;

  /// Formats the stable command-validation code and diagnostic message.
  @override
  String toString() {
    return 'WorkflowCommandValidationException('
        'code: ${code.name}): $message';
  }
}
