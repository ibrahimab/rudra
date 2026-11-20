import '../events/workflow_event.dart';
import '../events/workflow_start_event.dart';
import '../events/workflow_started_event.dart';
import '../states/workflow_snapshot.dart';
import '../workflow_identity.dart';
import 'workflow_behavior.dart';
import 'workflow_command_validation_exception.dart';

/// Validates Start requests and proposes establishment outcomes.
///
/// An existing unfinished workflow cannot be replaced, and the original
/// target and root must match the trusted proposed workflow identity.
final class WorkflowStartBehavior
    extends WorkflowCommandBehavior<WorkflowStartEvent> {
  /// Constructs the stateless Start behavior.
  const WorkflowStartBehavior();

  /// Validates the Start request against previously committed state.
  ///
  /// Transactional ownership uniqueness remains the committer's duty.
  @override
  void validate_command(
    WorkflowStartEvent command, {
    required WorkflowSnapshot? previous,
    required WorkflowIdentity identity,
  }) {
    if (previous != null) {
      throw const WorkflowCommandValidationException(
        code: WorkflowCommandValidationErrorCode.workflow_already_active,
        message: 'An unfinished workflow already exists.',
      );
    }
    if (identity.target_id != command.target_id) {
      throw const WorkflowCommandValidationException(
        code: WorkflowCommandValidationErrorCode.target_mismatch,
        message: 'Proposed target differs from the accepted Start request.',
      );
    }
    if (identity.root.value != command.root.value) {
      throw const WorkflowCommandValidationException(
        code: WorkflowCommandValidationErrorCode.root_mismatch,
        message: 'Proposed root differs from the accepted Start request.',
      );
    }
  }

  /// Proposes the first established domain outcome without committing it.
  @override
  List<WorkflowOutcomeEvent> handle_command(
    WorkflowStartEvent command,
    WorkflowIdentity identity,
  ) => [WorkflowStartedEvent(identity: identity)];
}
