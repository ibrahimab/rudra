import '../events/workflow_ended_event.dart';
import '../states/workflow_active_state.dart';
import '../states/workflow_ended_state.dart';
import '../workflow_transition_exception.dart';
import 'workflow_transition.dart';

/// Defines successful workflow termination.
///
/// Active + WorkflowEndedEvent -> Ended.
///
/// The guard prevents an event belonging to another workflow
/// from terminating the currently active workflow.
///
/// The resulting state preserves the established identity.
///
/// This transition only interprets an already established
/// terminal outcome. It does not perform cleanup, restoration,
/// or filesystem mutation.
WorkflowTransition<WorkflowActiveState, WorkflowEndedEvent, WorkflowEndedState>
workflow_ended_transition() {
  return WorkflowTransition(
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
