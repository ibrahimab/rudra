import '../events/workflow_started_event.dart';
import '../states/workflow_active_state.dart';
import '../states/workflow_start_requested_state.dart';
import '../transitions/workflow_transition.dart';
import '../workflow_transition_exception.dart';
import 'workflow_behavior.dart';

/// Defines StartRequested + WorkflowStartedEvent -> Active.
///
/// Ensures that the established workflow retains its
/// originally requested target and inspection root.
///
/// Paths are compared using their target-native strings.
/// This does not establish filesystem-object identity.
final class WorkflowStartedBehavior implements WorkflowBehavior {
  /// Creates the stateless started behavior.
  const WorkflowStartedBehavior();

  @override
  WorkflowTransition<
    WorkflowStartRequestedState,
    WorkflowStartedEvent,
    WorkflowActiveState
  >
  get transition =>
      WorkflowTransition<
        WorkflowStartRequestedState,
        WorkflowStartedEvent,
        WorkflowActiveState
      >(
        guard: (state, event) {
          final identity = event.identity;

          if (identity.target_id != state.target_id) {
            throw WorkflowTransitionException(
              code: WorkflowTransitionErrorCode.target_mismatch,
              state: state,
              event: event,
              message:
                  'The workflow target differs from the '
                  'original start request.',
            );
          }

          if (identity.root.value != state.root.value) {
            throw WorkflowTransitionException(
              code: WorkflowTransitionErrorCode.root_mismatch,
              state: state,
              event: event,
              message:
                  'The workflow root differs from the '
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
