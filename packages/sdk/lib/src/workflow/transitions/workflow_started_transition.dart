import '../events/workflow_started_event.dart';
import '../states/workflow_active_state.dart';
import '../states/workflow_start_requested_state.dart';
import '../workflow_transition_exception.dart';
import 'workflow_transition.dart';

/// Defines successful workflow establishment.
///
/// StartRequested + WorkflowStartedEvent -> Active.
///
/// The guard ensures that the established workflow retains
/// the original target identifier and requested root.
///
/// Paths are compared using their exact target-native strings.
/// This verifies immutable bindings, not filesystem identity.
///
/// The successful event introduces the authoritative workflow
/// identifier and OS-user owner reference.
///
/// Invalid bindings produce typed transition failures.
WorkflowTransition<WorkflowStartRequestedState, WorkflowStartedEvent,
    WorkflowActiveState> workflow_started_transition() {
  return WorkflowTransition(
    guard: (state, event) {
      final identity = event.identity;

      if (identity.target_id != state.target_id) {
        throw WorkflowTransitionException(
          code: WorkflowTransitionErrorCode.target_mismatch,
          state: state,
          event: event,
          message: 'The workflow target differs from the '
              'original start request.',
        );
      }

      if (identity.root.value != state.root.value) {
        throw WorkflowTransitionException(
          code: WorkflowTransitionErrorCode.root_mismatch,
          state: state,
          event: event,
          message: 'The workflow root differs from the '
              'original start request.',
        );
      }
    },
    apply: (state, event, next_version) {
      return WorkflowActiveState(
        identity: event.identity,
        version: next_version,
      );
    },
  );
}
