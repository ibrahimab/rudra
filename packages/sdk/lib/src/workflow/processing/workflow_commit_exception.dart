/// Stable reasons why a workflow proposal cannot be committed.
enum WorkflowCommitErrorCode {
  /// The accepted submission is no longer pending or has changed.
  stale_submission,

  /// An OS user already owns an unfinished workflow.
  ownership_conflict,

  /// The processing proposal violates the commit contract.
  invalid_plan,
}

/// A typed failure of authoritative workflow commitment.
///
/// These failures do not imply that a partial transaction
/// was committed. The persistence adapter must roll back
/// all writes when commitment fails.
final class WorkflowCommitException implements Exception {
  /// Creates a classified commitment failure.
  const WorkflowCommitException({required this.code, required this.message});

  /// Stable machine-readable failure classification.
  final WorkflowCommitErrorCode code;

  /// Diagnostic explanation.
  final String message;

  @override
  String toString() => 'WorkflowCommitException(code: ${code.name}): $message';
}
