import 'package:rudra_sdk/rudra_sdk.dart' show TargetPath, WorkflowActiveState;

import '../../explorer/application/explorer_action_registry.dart';
import 'workflow_explorer_state.dart';

/// Creates the Explorer contribution for workflow creation.
///
/// This action is owned by the Workflow feature, not by the
/// generic Explorer runner or terminal input decoder.
///
/// The action binds the S shortcut to the same application
/// operation used by the non-interactive workflow CLI.
///
/// The current Explorer directory is passed as the requested
/// workflow root without modifying navigation state.
///
/// Availability is determined from [state]. Execution also
/// checks availability independently, so direct invocation
/// cannot bypass the action's interaction-level guard.
///
/// [start_workflow] must return an authoritatively committed
/// and restored [WorkflowActiveState]. A submission receipt
/// or provisional result must not be reported as success.
///
/// Backend ownership, persistence, and concurrency checks
/// remain the responsibility of the injected application
/// operation.
///
/// The state snapshot is updated only after successful
/// completion. An operation failure propagates unchanged.
///
/// Example:
/// ```dart
/// final state = WorkflowExplorerState();
///
/// final action = create_workflow_start_action(
///   state: state,
///   start_workflow: application.start,
/// );
///
/// // Composition registers action under the Workflow feature.
/// // Explorer dispatches it only after an explicit S keypress.
/// ```
ExplorerAction create_workflow_start_action({
  required WorkflowExplorerState state,
  required Future<WorkflowActiveState> Function(TargetPath) start_workflow,
}) {
  return ExplorerAction(
    id: 'workflow.start',
    shortcut: 's',
    hint: 'Start Workflow',
    is_available: (_) => state.can_start,
    execute: (model) async {
      // An action must enforce its own interaction guard.
      // Registry availability alone is not authorization.
      if (!state.can_start) {
        throw StateError('Workflow Start is not available.');
      }

      // Use the exact directory displayed at the moment
      // the explicit action is dispatched.
      final root = model.current_directory;

      // The injected operation performs authoritative
      // persistence checks and returns committed state.
      final committed = await start_workflow(root);

      // Never display an accepted-but-uncommitted request
      // as an active workflow.
      state.record_started(committed);
    },
  );
}
