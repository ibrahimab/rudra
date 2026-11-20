import 'package:rudra_sdk/rudra_sdk.dart' show TargetPath, WorkflowActiveState;

import '../../explorer/application/explorer_action_registry.dart';
import '../../explorer/application/explorer_model.dart';

/// Explorer action for starting a workflow.
///
/// The S shortcut starts a workflow using the directory currently
/// displayed in Explorer as its requested filesystem root.
///
/// Workflow creation is performed by the supplied application
/// operation, which returns a confirmed [WorkflowActiveState].
///
/// Example:
/// ```dart
/// final action = WorkflowStartExplorerAction(
///   start_workflow: (root) => workflows.start(
///     target_id: target_id,
///     root: root,
///   ),
/// );
///
/// final contribution = ExplorerFeatureContribution(
///   id: 'workflow',
///   actions: [action],
/// );
/// ```
final class WorkflowStartExplorerAction implements ExplorerAction {
  /// Creates a workflow Start action.
  ///
  /// [start_workflow] is the application operation responsible for
  /// creating a workflow at the requested filesystem root.
  ///
  /// The operation must return an authoritatively committed
  /// [WorkflowActiveState]. Submission acceptance alone is
  /// insufficient.
  ///
  /// Construction does not invoke the supplied operation.
  const WorkflowStartExplorerAction({required this.start_workflow});

  /// Application operation used to create a workflow.
  ///
  /// Receives a [TargetPath] identifying the requested root
  /// and returns the resulting committed [WorkflowActiveState].
  ///
  /// Validation, persistence, and processing exceptions propagate
  /// through the returned future.
  final Future<WorkflowActiveState> Function(TargetPath) start_workflow;

  /// Stable identifier for workflow creation.
  @override
  String get id => 'workflow.start';

  /// Keyboard shortcut used to start a workflow.
  @override
  String get shortcut => 's';

  /// Starts a workflow for the currently displayed directory.
  ///
  /// [model] supplies the Explorer navigation snapshot at dispatch
  /// time. Its [ExplorerModel.current_directory] determines the
  /// requested workflow root.
  ///
  /// Returns a future that completes when the application operation
  /// confirms workflow creation.
  ///
  /// Errors from [start_workflow] propagate to the caller.
  @override
  Future<void> execute(ExplorerModel model) async {
    // Capture the root associated with this keyboard interaction.
    final root = model.current_directory;

    await start_workflow(root);
  }
}
