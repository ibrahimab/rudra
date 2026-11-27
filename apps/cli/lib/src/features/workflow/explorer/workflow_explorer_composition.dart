import 'package:rudra_sdk/rudra_sdk.dart';

import '../../explorer/application/explorer_action_registry.dart';

import 'workflow_explorer_view_model.dart';
import 'workflow_start_explorer_action.dart';
import 'workflow_stop_explorer_action.dart';

/// Supplies the Explorer's workflow snapshot and workflow-owned actions.
///
/// Example:
/// ```dart
/// final workflows = WorkflowExplorerComposition(sdk);
/// await workflows.refresh();
/// final actions = ExplorerActionRegistry([workflows.contribution()]);
/// ```
final class WorkflowExplorerComposition {
  /// Borrows the connected [sdk] for the enclosing Explorer invocation.
  WorkflowExplorerComposition(this._sdk);

  /// Borrowed authenticated application services.
  final RudraSdk _sdk;

  /// Last successfully refreshed workflow presentation.
  late WorkflowExplorerViewModel _view_model;

  /// Returns the workflow presentation initialized by [refresh].
  WorkflowExplorerViewModel get view_model => _view_model;

  /// Reads verified workflow state and replaces the previous snapshot.
  ///
  /// Communication and application read failures propagate. An unsuccessful
  /// read leaves the last verified snapshot intact.
  Future<void> refresh() async {
    final state = await _sdk.read_state();
    _view_model = WorkflowExplorerViewModel(
      current_workflow: state.workflows.current_workflow,
    );
  }

  /// Creates the workflow action contribution for the Explorer registry.
  ///
  /// Stop uses the workflow identity from the displayed snapshot.
  ExplorerFeatureContribution contribution() => ExplorerFeatureContribution(
    id: 'workflow',
    actions: [
      WorkflowStartExplorerAction(
        start_workflow: (root, idempotency_key) =>
            _sdk.workflows.start(root: root, idempotency_key: idempotency_key),
      ),
      WorkflowStopExplorerAction(
        displayed_workflow: () => view_model.current_workflow,
        stop_workflow: (workflow_id, idempotency_key) => _sdk.workflows.stop(
          workflow_id: workflow_id,
          idempotency_key: idempotency_key,
        ),
      ),
    ],
  );
}
