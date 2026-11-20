import '../../explorer/application/explorer_action_registry.dart';
import 'workflow_explorer_state.dart';

/// Creates the Explorer contribution for workflow termination.
///
/// This action is owned entirely by the Workflow feature.
///
/// The X shortcut invokes the injected Stop application
/// operation for the exact workflow currently displayed.
///
/// The expected workflow ID is captured before awaiting
/// backend processing. This prevents the action from
/// silently targeting a different workflow after a
/// concurrent state change.
///
/// [stop_workflow] must report the identifier of the
/// durably terminated workflow. The result must agree
/// with the captured expected identifier.
///
/// The displayed workflow is cleared only after:
/// - The injected operation completes successfully.
/// - The returned workflow ID matches the expected ID.
/// - The interaction state still refers to that workflow.
///
/// Failures propagate without clearing the displayed state.
///
/// The persistence layer remains responsible for rechecking
/// trusted ownership, lifecycle state and expected identity
/// inside the relevant transaction.
///
/// Example:
/// ```dart
/// final action = create_workflow_stop_action(
///   state: workflow_state,
///   stop_workflow: application.stop,
/// );
///
/// // The action becomes available only when an active
/// // workflow has been loaded or committed.
/// ```
ExplorerAction create_workflow_stop_action({
  required WorkflowExplorerState state,
  required Future<String> Function(String expected_workflow_id) stop_workflow,
}) {
  return ExplorerAction(
    id: 'workflow.stop',
    shortcut: 'x',
    hint: 'Stop Workflow',
    is_available: (_) => state.can_stop,
    execute: (_) async {
      // Do not rely solely on registry dispatch.
      // Direct invocation must also fail closed.
      if (!state.can_stop) {
        throw StateError('Workflow Stop is not available.');
      }

      // Capture the displayed workflow identity before
      // calling the asynchronous application operation.
      final expected_workflow_id = state.active_workflow!.identity.workflow_id;

      // This operation must perform authoritative
      // revalidation and durable termination.
      final stopped_workflow_id = await stop_workflow(expected_workflow_id);

      // Preserve the current snapshot on any mismatch.
      // In particular, never clear a replacement workflow.
      state.record_stopped(
        expected_workflow_id: expected_workflow_id,
        stopped_workflow_id: stopped_workflow_id,
      );
    },
  );
}
