import 'package:rudra_cli/src/core/rendering/widgets/terminal_widget.dart';
import 'package:rudra_cli/src/features/explorer/application/explorer_model.dart';
import 'package:rudra_cli/src/features/explorer/presentation/widgets/actions/explorer_actions.dart';
import 'package:rudra_cli/src/features/explorer/presentation/widgets/actions/explorer_actions_view_model.dart';
import 'package:rudra_cli/src/features/workflow/explorer/workflow_explorer_view_model.dart';

import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Tests the keyboard instructions displayed by Explorer.
void main() {
  final constraints = TerminalConstraints(columns: 120);

  group('ExplorerActions', () {
    test('renders navigation and Quit without workflow integration', () {
      final actions = _actions(workflow: null);

      final lines = actions.build(constraints).toList();

      expect(actions.height, 1);
      expect(lines, hasLength(1));
      expect(lines.single.text, contains('Up/Down Select'));
      expect(lines.single.text, contains('Q Quit'));
      expect(lines.single.text, isNot(contains('Start Workflow')));
      expect(lines.single.text, isNot(contains('Stop Workflow')));
    });

    test('offers Start when no workflow is loaded', () {
      final actions = _actions(
        workflow: const WorkflowExplorerViewModel(current_workflow: null),
      );

      final line = actions.build(constraints).single.text;

      expect(line, contains('S Start Workflow'));
      expect(line, isNot(contains('X Stop Workflow')));
    });

    test('offers Stop when a workflow is loaded', () {
      final active = WorkflowSnapshot(
        identity: WorkflowIdentity(
          workflow_id: 'workflow-1',
          os_user_id: 'fixture-user',
          target_id: 'fixture-target',
          root: TargetPath('/workspace'),
        ),
        version: 1,
        lifecycle: WorkflowLifecycle(
          id: 'rudra.workflow.active',
          is_terminal: false,
        ),
      );

      final actions = _actions(
        workflow: WorkflowExplorerViewModel(current_workflow: active),
      );

      final line = actions.build(constraints).single.text;

      expect(line, contains('X Stop Workflow'));
      expect(line, isNot(contains('S Start Workflow')));
    });

    test('shows the closed message without keyboard instructions', () {
      final explorer = _explorer().close();

      final actions = ExplorerActions(
        ExplorerActionsViewModel(
          explorer: explorer,
          workflow: const WorkflowExplorerViewModel(current_workflow: null),
        ),
      );

      final line = actions.build(constraints).single.text;

      expect(line, 'Explorer closed.');
      expect(line, isNot(contains('Q Quit')));
    });
  });
}

/// Creates the keyboard-instruction widget.
///
/// [workflow] supplies the workflow presentation snapshot.
/// Null means workflow integration is not configured.
ExplorerActions _actions({required WorkflowExplorerViewModel? workflow}) {
  return ExplorerActions(
    ExplorerActionsViewModel(explorer: _explorer(), workflow: workflow),
  );
}

/// Creates an in-memory Explorer navigation snapshot.
ExplorerModel _explorer() {
  final root = TargetPath('/workspace');

  return ExplorerModel(
    root_directory: root,
    listing: DirectoryListing(
      target_id: 'fixture-target',
      directory: root,
      entries: const [],
      is_complete: true,
    ),
  );
}
