import '../events/workflow_start_event.dart';
import '../states/workflow_initial_state.dart';
import '../states/workflow_start_requested_state.dart';
import 'workflow_transition.dart';

/// Defines the initial workflow creation-request transition.
///
/// Initial + WorkflowStartEvent -> StartRequested.
///
/// This transition records the requested target and root.
/// It does not create an active workflow or authorize cleanup.
///
/// The state version is supplied by the state-machine engine.
///
/// Example:
/// ```dart
/// final rule = workflow_start_transition();
/// print(rule.trigger_event_type == WorkflowStartEvent);
/// // true
/// ```
WorkflowTransition<WorkflowInitialState, WorkflowStartEvent,
    WorkflowStartRequestedState> workflow_start_transition() {
  return WorkflowTransition(
    apply: (state, event, next_version) {
      return WorkflowStartRequestedState(
        target_id: event.target_id,
        root: event.root,
        version: next_version,
      );
    },
  );
}
