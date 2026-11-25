import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:uuid/uuid.dart';

import '../../explorer/application/explorer_action_registry.dart';
import '../../explorer/application/explorer_model.dart';

import 'workflow_explorer_operation_exception.dart';

/// Explorer action requesting termination of the displayed workflow.
///
/// The X shortcut captures the intended workflow identity before
/// dispatching the identified application operation.
///
/// Subsequent presentation changes cannot retarget that operation.
///
/// Example:
/// ```dart
/// final action = WorkflowStopExplorerAction(
///   displayed_workflow: () => current_workflow,
///   stop_workflow: (id, key) => workflows.stop(
///     workflow_id: id,
///     idempotency_key: key,
///   ),
/// );
/// ```
final class WorkflowStopExplorerAction implements ExplorerAction {
  /// Creates a Stop action using the supplied application capabilities.
  ///
  /// [displayed_workflow] supplies the workflow represented by Explorer.
  /// [stop_workflow] executes termination for an explicit workflow ID
  /// and idempotency key.
  ///
  /// Construction does not invoke either function.
  const WorkflowStopExplorerAction({
    required this.displayed_workflow,
    required this.stop_workflow,
  });

  /// Supplies the current displayed workflow or null when none exists.
  final WorkflowSnapshot? Function() displayed_workflow;

  /// Application operation receiving the intended workflow and operation key.
  final Future<WorkflowOperationOutcome> Function(
    String workflow_id,
    String idempotency_key,
  )
  stop_workflow;

  /// Stable identifier for workflow termination.
  @override
  String get id => 'workflow.stop';

  /// Keyboard shortcut used to request Stop.
  @override
  String get shortcut => 'x';

  /// Requests termination of the workflow displayed at dispatch time.
  ///
  /// [model] identifies the current Explorer navigation snapshot.
  /// Workflow selection originates from [displayed_workflow].
  ///
  /// Completes only after the intended workflow's terminal outcome
  /// has been confirmed.
  ///
  /// Throws [StateError] when no workflow is displayed or commitment
  /// evidence contradicts the request.
  ///
  /// Throws [WorkflowExplorerOperationException] for unsuccessful
  /// application outcomes. Unexpected application failures propagate.
  @override
  Future<void> execute(ExplorerModel model) async {
    final workflow = displayed_workflow();

    if (workflow == null) {
      throw StateError('No displayed workflow is available to stop.');
    }

    // Capture both operation identifiers before dispatching Stop.
    final workflow_id = workflow.identity.workflow_id;
    final idempotency_key = Uuid().v4();

    final outcome = await stop_workflow(workflow_id, idempotency_key);

    if (outcome is! WorkflowOperationResolved ||
        outcome.resolution.state != WorkflowSubmissionState.completed) {
      throw WorkflowExplorerOperationException(outcome: outcome);
    }

    final committed = outcome.resolution.committed_outcome!;

    if (committed.workflow_id != workflow_id ||
        committed.event_type != WorkflowEndedEvent.type_id) {
      throw StateError(
        'Confirmed Stop result does not match the requested workflow.',
      );
    }
  }
}
