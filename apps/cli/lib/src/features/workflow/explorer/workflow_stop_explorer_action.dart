import 'package:rudra_sdk/rudra_sdk.dart' show WorkflowActiveState;

import '../../explorer/application/explorer_action_registry.dart';
import '../../explorer/application/explorer_model.dart';

/// Explorer action for stopping the displayed workflow.
///
/// The X shortcut requests termination of the workflow currently
/// represented by Explorer's presentation state.
///
/// The expected workflow identifier is captured before invoking
/// the asynchronous application operation.
///
/// The confirmed result must reference the same workflow, ensuring
/// that a concurrent state change cannot cause a different workflow
/// to be accepted as the completed operation.
///
/// Example:
/// ```dart
/// final action = WorkflowStopExplorerAction(
///   displayed_workflow: () => current_workflow,
///   stop_workflow: (expected_id) => workflows.stop(
///     expected_workflow_id: expected_id,
///   ),
/// );
/// ```
final class WorkflowStopExplorerAction implements ExplorerAction {
  /// Creates a workflow Stop action.
  ///
  /// [displayed_workflow] returns the workflow currently represented
  /// by Explorer's presentation state. It returns null when no
  /// workflow is displayed.
  ///
  /// [stop_workflow] terminates the workflow identified by its
  /// expected ID and returns the confirmed workflow identifier.
  ///
  /// Construction does not invoke either function.
  const WorkflowStopExplorerAction({
    required this.displayed_workflow,
    required this.stop_workflow,
  });

  /// Supplies the workflow currently displayed by Explorer.
  ///
  /// Returns the current [WorkflowActiveState] or null when
  /// no workflow is represented by the view.
  ///
  /// The returned workflow identity is used as the expected
  /// identifier for the termination request.
  final WorkflowActiveState? Function() displayed_workflow;

  /// Application operation used to terminate a workflow.
  ///
  /// Receives the exact workflow identifier expected to be
  /// terminated.
  ///
  /// Returns the identifier of the workflow whose termination
  /// has been successfully committed.
  ///
  /// Validation, persistence, and processing exceptions propagate
  /// through the returned future.
  final Future<String> Function(String expected_workflow_id) stop_workflow;

  /// Stable identifier for workflow termination.
  @override
  String get id => 'workflow.stop';

  /// Keyboard shortcut used to stop a workflow.
  @override
  String get shortcut => 'x';

  /// Terminates the workflow currently displayed by Explorer.
  ///
  /// [model] is the Explorer navigation snapshot at dispatch time.
  /// Workflow identity is obtained through [displayed_workflow].
  ///
  /// Returns a future that completes after the termination result
  /// has been verified.
  ///
  /// Throws [StateError] when no workflow is displayed or when
  /// the confirmed identifier differs from the requested one.
  ///
  /// Errors from [stop_workflow] propagate to the caller.
  @override
  Future<void> execute(ExplorerModel model) async {
    final workflow = displayed_workflow();

    if (workflow == null) {
      throw StateError('No displayed workflow is available to stop.');
    }

    // Capture the workflow ID before awaiting the application
    // operation. Subsequent UI updates cannot retarget the request.
    final expected_workflow_id = workflow.identity.workflow_id;

    final stopped_workflow_id = await stop_workflow(expected_workflow_id);

    // Verify that the confirmed result belongs to the workflow
    // originally selected for termination.
    if (stopped_workflow_id != expected_workflow_id) {
      throw StateError(
        'Confirmed Stop result does not match '
        'the requested workflow.',
      );
    }
  }
}
