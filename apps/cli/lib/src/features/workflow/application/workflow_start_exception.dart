/// Indicates that an OS user already owns an active workflow.
///
/// This is an expected business conflict, not an internal
/// application failure.
///
/// The existing workflow is never replaced or terminated.
final class WorkflowAlreadyActiveException implements Exception {
  /// Creates a conflict with an optionally known workflow ID.
  const WorkflowAlreadyActiveException({this.workflow_id});

  /// Existing workflow identifier, when available.
  final String? workflow_id;

  @override
  String toString() {
    return 'WorkflowAlreadyActiveException('
        'workflow_id: $workflow_id)';
  }
}
