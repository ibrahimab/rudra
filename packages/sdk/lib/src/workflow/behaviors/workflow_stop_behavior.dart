import '../events/workflow_ended_event.dart';
import '../events/workflow_event.dart';
import '../events/workflow_stop_event.dart';
import '../states/workflow_snapshot.dart';
import '../workflow_identity.dart';
import 'workflow_behavior.dart';
import 'workflow_command_validation_exception.dart';

/// Validates a Stop request and proposes a terminal domain outcome.
///
/// The request must target the established workflow and cannot alter its
/// trusted owner, configured target or original filesystem root.
final class WorkflowStopBehavior
    extends WorkflowCommandBehavior<WorkflowStopEvent> {
  /// Constructs the stateless Stop behavior.
  const WorkflowStopBehavior();

  /// Validates the exact workflow identity being stopped.
  @override
  void validate_command(
    WorkflowStopEvent command, {
    required WorkflowSnapshot? previous,
    required WorkflowIdentity identity,
  }) {
    if (previous == null || previous.is_terminal) {
      throw const WorkflowCommandValidationException(
        code: WorkflowCommandValidationErrorCode.workflow_not_active,
        message: 'No unfinished workflow exists.',
      );
    }

    final established = previous.identity;
    if (command.workflow_id != established.workflow_id) {
      throw const WorkflowCommandValidationException(
        code: WorkflowCommandValidationErrorCode.workflow_id_mismatch,
        message: 'Stop targets a different workflow.',
      );
    }
    if (identity.workflow_id != established.workflow_id ||
        identity.os_user_id != established.os_user_id ||
        identity.target_id != established.target_id ||
        identity.root.value != established.root.value) {
      throw const WorkflowCommandValidationException(
        code: WorkflowCommandValidationErrorCode.identity_mismatch,
        message: 'Processing identity differs from committed identity.',
      );
    }
  }

  /// Proposes the terminal outcome of the validated Stop request.
  @override
  List<WorkflowOutcomeEvent> handle_command(
    WorkflowStopEvent command,
    WorkflowIdentity identity,
  ) => [WorkflowEndedEvent(workflow_id: command.workflow_id)];
}
