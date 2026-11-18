import '../events/workflow_ended_event.dart';
import '../states/workflow_ended_state.dart';
import '../states/workflow_stop_requested_state.dart';
import '../transitions/workflow_transition.dart';
import '../workflow_transition_exception.dart';

import 'workflow_behavior.dart';

/// Defines StopRequested + WorkflowEndedEvent -> Ended.
///
/// Ensures the terminal outcome belongs to the workflow
/// whose stop was explicitly requested.
///
/// This transition does not perform filesystem operations.
final class WorkflowEndedBehavior implements WorkflowBehavior {
  /// Creates the stateless ended behavior.
  const WorkflowEndedBehavior();

  @override
  WorkflowTransition<
    WorkflowStopRequestedState,
    WorkflowEndedEvent,
    WorkflowEndedState
  >
  get transition =>
      WorkflowTransition<
        WorkflowStopRequestedState,
        WorkflowEndedEvent,
        WorkflowEndedState
      >(
        guard: (state, event) {
          if (event.workflow_id != state.identity.workflow_id) {
            throw WorkflowTransitionException(
              code: WorkflowTransitionErrorCode.workflow_id_mismatch,
              state: state,
              event: event,
              message: 'The end event refers to a different workflow.',
            );
          }
        },
        apply: (state, event, next_version) {
          return WorkflowEndedState(
            identity: state.identity,
            version: next_version,
          );
        },
      );
}
