import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:uuid/uuid.dart';

import '../../explorer/application/explorer_action_registry.dart';
import '../../explorer/application/explorer_model.dart';

import 'workflow_explorer_operation_exception.dart';

/// Explorer action requesting workflow establishment.
///
/// The S shortcut captures the currently displayed directory and creates
/// a new identified Start operation.
///
/// The application determines whether establishment can be committed.
///
/// Example:
/// ```dart
/// final action = WorkflowStartExplorerAction(
///   start_workflow: sdk.workflows.start,
/// );
/// ```
final class WorkflowStartExplorerAction implements ExplorerAction {
  /// Creates a Start action using [start_workflow].
  ///
  /// The supplied operation returns the durable application outcome.
  /// Construction does not submit or process workflow commands.
  const WorkflowStartExplorerAction({required this.start_workflow});

  /// Application operation receiving the requested root and operation key.
  final Future<WorkflowOperationOutcome> Function({
    required TargetPath root,
    required String idempotency_key,
  })
  start_workflow;

  /// Stable identifier for workflow establishment.
  @override
  String get id => 'workflow.start';

  /// Keyboard shortcut used to request Start.
  static const String key = 's';

  @override
  String get shortcut => key;

  /// Requests workflow establishment for [model]'s displayed directory.
  ///
  /// The SDK [state] accompanies the frame. The host decides whether a new
  /// workflow can be established.
  ///
  /// Completes only after the application confirms establishment.
  ///
  /// Throws [WorkflowExplorerOperationException] for unsuccessful
  /// application outcomes, or [StateError] for contradictory commitment
  /// evidence. Unexpected application failures propagate.
  @override
  Future<void> execute(ExplorerModel model, RudraState state) async {
    final root = model.current_directory;
    final idempotency_key = Uuid().v4();

    final outcome = await start_workflow(
      root: root,
      idempotency_key: idempotency_key,
    );

    if (outcome is! WorkflowOperationResolved ||
        outcome.resolution.state != WorkflowSubmissionState.completed) {
      throw WorkflowExplorerOperationException(outcome: outcome);
    }

    final committed = outcome.resolution.committed_outcome!;

    if (committed.event_type != WorkflowStartedEvent.type_id ||
        committed.version != 1) {
      throw StateError('Start result lacks its establishment outcome.');
    }
  }
}
