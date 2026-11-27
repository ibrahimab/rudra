import 'package:rudra_sdk/rudra_sdk.dart';

import '../../../core/rendering/theme.dart';
import '../../../core/rendering/widgets/terminal_widget.dart';

import '../../explorer/application/explorer_action_registry.dart';

import 'workflow_start_explorer_action.dart';
import 'workflow_stop_explorer_action.dart';

/// Registers workflow actions and projects verified workflow state for Explorer.
///
/// Example:
/// ```dart
/// final actions = ExplorerActionRegistry([
///   WorkflowExplorerContribution(sdk.workflows),
/// ]);
/// ```
final class WorkflowExplorerContribution extends ExplorerFeatureContribution {
  /// Creates the actions using the SDK's [workflows] service.
  ///
  /// The service is borrowed from the enclosing invocation. Registration
  /// neither establishes the SDK connection nor submits a workflow command.
  WorkflowExplorerContribution(WorkflowService workflows)
    : super(
        id: 'workflow',
        actions: [
          WorkflowStartExplorerAction(start_workflow: workflows.start),
          WorkflowStopExplorerAction(stop_workflow: workflows.stop),
        ],
      );

  /// Returns workflow status and the matching shortcut hint for [state].
  ///
  /// The controller supplies the same verified SDK snapshot to Stop.
  @override
  ExplorerFeaturePresentation present(RudraState state) {
    final active = state.workflows.current_workflow;
    if (active == null) {
      return (
        status: const TerminalLine('Workflow: NONE', role: TerminalRole.muted),
        instruction:
            '${WorkflowStartExplorerAction.key.toUpperCase()} Start Workflow',
      );
    }

    return (
      status: TerminalLine(
        'Workflow: ACTIVE'
        '  |  ID: ${active.identity.workflow_id}'
        '  |  Version: ${active.version}'
        '  |  Target: ${active.identity.target_id}',
        role: TerminalRole.heading,
      ),
      instruction:
          '${WorkflowStopExplorerAction.key.toUpperCase()} Stop Workflow',
    );
  }
}
