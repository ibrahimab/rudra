import '../events/workflow_ended_event.dart';
import '../events/workflow_event.dart';
import '../events/workflow_stop_event.dart';

import '../states/workflow_active_state.dart';
import '../states/workflow_snapshot.dart';
import '../states/workflow_stop_requested_state.dart';

import '../transitions/workflow_transition.dart';

import '../workflow_identity.dart';
import '../workflow_transition_exception.dart';

import 'workflow_behavior.dart';
import 'workflow_command_validation_exception.dart';

/// Validates Stop requests and proposes terminal outcomes.
///
/// A Stop request requires an established unfinished workflow.
/// The requested workflow ID must match the committed identity.
///
/// The identity supplied to processing must also match the
/// original committed workflow bindings. A mismatched identity
/// is an integrity failure rather than an ordinary user rejection.
///
/// Successful processing proposes [WorkflowEndedEvent].
/// Only committed outcome replay can establish the terminal state.
///
/// The legacy command transition remains during migration.
final class WorkflowStopBehavior
    extends WorkflowCommandBehavior<WorkflowStopEvent> {
  /// Creates the stateless workflow-stop behavior.
  const WorkflowStopBehavior();

  /// Legacy Active-to-StopRequested transition.
  ///
  /// Retained until the coordinated outcome-only engine cutover.
  @override
  WorkflowTransition<
    WorkflowActiveState,
    WorkflowStopEvent,
    WorkflowStopRequestedState
  >
  get transition =>
      WorkflowTransition<
        WorkflowActiveState,
        WorkflowStopEvent,
        WorkflowStopRequestedState
      >(
        guard: (state, event) {
          if (event.workflow_id != state.identity.workflow_id) {
            throw WorkflowTransitionException(
              code: WorkflowTransitionErrorCode.workflow_id_mismatch,
              state: state,
              event: event,
              message: 'The stop request refers to a different workflow.',
            );
          }
        },
        apply: (state, event, next_version) {
          return WorkflowStopRequestedState(
            identity: state.identity,
            version: next_version,
          );
        },
      );

  /// Validates a Stop request against committed workflow state.
  ///
  /// [previous] must represent an unfinished workflow.
  /// [identity] must agree with every original identity binding.
  ///
  /// Throws [WorkflowCommandValidationException] for absent or
  /// terminal workflows, stale workflow IDs, and inconsistent
  /// processing identity.
  ///
  /// This method performs no state transition or persistence.
  @override
  void validate_command(
    WorkflowStopEvent command, {
    required WorkflowSnapshot? previous,
    required WorkflowIdentity identity,
  }) {
    if (previous == null || previous.is_terminal) {
      throw const WorkflowCommandValidationException(
        code: WorkflowCommandValidationErrorCode.workflow_not_active,
        message: 'No unfinished workflow exists for the Stop request.',
      );
    }

    final established = previous.identity;

    if (command.workflow_id != established.workflow_id) {
      throw const WorkflowCommandValidationException(
        code: WorkflowCommandValidationErrorCode.workflow_id_mismatch,
        message: 'The Stop request targets another workflow.',
      );
    }

    if (identity.workflow_id != established.workflow_id ||
        identity.os_user_id != established.os_user_id ||
        identity.target_id != established.target_id ||
        identity.root.value != established.root.value) {
      throw const WorkflowCommandValidationException(
        code: WorkflowCommandValidationErrorCode.identity_mismatch,
        message: 'Processing identity differs from committed workflow state.',
      );
    }
  }

  /// Proposes the terminal outcome of a validated Stop request.
  ///
  /// The workflow ID remains bound to the accepted command.
  ///
  /// The event must pass authoritative outcome-transition
  /// validation before it may be committed.
  @override
  List<WorkflowEvent> handle_command(
    WorkflowStopEvent command,
    WorkflowIdentity identity,
  ) {
    return [WorkflowEndedEvent(workflow_id: command.workflow_id)];
  }
}
