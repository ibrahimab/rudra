import '../events/workflow_event.dart';
import '../events/workflow_start_event.dart';
import '../events/workflow_started_event.dart';

import '../states/workflow_initial_state.dart';
import '../states/workflow_start_requested_state.dart';

import '../transitions/workflow_transition.dart';

import '../workflow_identity.dart';

import 'workflow_behavior.dart';

/// Defines Initial + WorkflowStartEvent -> StartRequested.
///
/// Records the requested target and inspection root.
/// Does not establish a workflow or authorize cleanup.
final class WorkflowStartBehavior
    extends WorkflowCommandBehavior<WorkflowStartEvent> {
  /// Creates the stateless start behavior.
  const WorkflowStartBehavior();

  @override
  WorkflowTransition<
    WorkflowInitialState,
    WorkflowStartEvent,
    WorkflowStartRequestedState
  >
  get transition =>
      WorkflowTransition<
        WorkflowInitialState,
        WorkflowStartEvent,
        WorkflowStartRequestedState
      >(
        apply: (state, event, next_version) {
          return WorkflowStartRequestedState(
            target_id: event.target_id,
            root: event.root,
            version: next_version,
          );
        },
      );

  /// Proposes successful workflow establishment.
  ///
  /// The trusted processor supplies the workflow identity.
  /// The state machine validates the requested target and root
  /// before the outcome may be committed.
  @override
  List<WorkflowEvent> handle_command(
    WorkflowStartEvent command,
    WorkflowIdentity identity,
  ) {
    return [WorkflowStartedEvent(identity: identity)];
  }
}
