import '../events/workflow_ended_event.dart';
import '../events/workflow_event.dart';
import '../events/workflow_stop_event.dart';

import '../states/workflow_active_state.dart';
import '../states/workflow_stop_requested_state.dart';

import '../transitions/workflow_transition.dart';
import '../workflow_identity.dart';
import '../workflow_transition_exception.dart';

import 'workflow_behavior.dart';

/// Defines Active + WorkflowStopEvent -> StopRequested.
///
/// Only the currently active workflow can receive a stop
/// request. The established identity remains unchanged.
///
/// Proposes a terminal outcome without committing it.
final class WorkflowStopBehavior
    extends WorkflowCommandBehavior<WorkflowStopEvent> {
  /// Creates the stateless stop behavior.
  const WorkflowStopBehavior();

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

  /// Proposes the successful terminal outcome.
  ///
  /// The state machine validates both transitions before
  /// the persistence boundary may commit the events.
  @override
  List<WorkflowEvent> handle_command(
    WorkflowStopEvent command,
    WorkflowIdentity identity,
  ) {
    return [WorkflowEndedEvent(workflow_id: command.workflow_id)];
  }
}
