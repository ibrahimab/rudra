import 'package:rudra_cli/src/features/explorer/application/explorer_action_registry.dart';
import 'package:rudra_cli/src/features/explorer/application/explorer_model.dart';
import 'package:rudra_cli/src/features/workflow/explorer/workflow_start_explorer_action.dart';
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Tests the Explorer adapter for workflow creation.
///
/// Application operations are injected; persistence and event
/// processing are covered by integration tests.
void main() {
  group('WorkflowStartExplorerAction', () {
    test('has a stable identity and keyboard shortcut', () {
      final action = WorkflowStartExplorerAction(
        start_workflow: (_) async => _active(),
      );

      expect(action.id, 'workflow.start');
      expect(action.shortcut, 's');
    });

    test('uses the displayed directory as the workflow root', () async {
      TargetPath? requested_root;

      final action = WorkflowStartExplorerAction(
        start_workflow: (root) async {
          requested_root = root;
          return _active();
        },
      );

      await action.execute(_explorer('/workspace/src'));

      expect(requested_root?.value, '/workspace/src');
    });

    test('does not execute during construction or registration', () {
      var submissions = 0;

      final action = WorkflowStartExplorerAction(
        start_workflow: (_) async {
          submissions++;
          return _active();
        },
      );

      final registry = ExplorerActionRegistry([
        ExplorerFeatureContribution(id: 'workflow', actions: [action]),
      ]);

      expect(registry.resolve('s'), same(action));
      expect(submissions, 0);
    });

    test('propagates application rejection', () async {
      final action = WorkflowStartExplorerAction(
        start_workflow: (_) async {
          throw StateError('Workflow already exists.');
        },
      );

      await expectLater(
        action.execute(_explorer('/workspace')),
        throwsStateError,
      );
    });

    test('does not mutate Explorer navigation state', () async {
      final explorer = _explorer('/workspace');

      final action = WorkflowStartExplorerAction(
        start_workflow: (_) async => _active(),
      );

      await action.execute(explorer);

      expect(explorer.current_directory.value, '/workspace');
      expect(explorer.is_closed, isFalse);
      expect(explorer.history, isEmpty);
    });
  });
}

/// Creates an in-memory Explorer navigation snapshot.
///
/// [path] is the target-native directory displayed by Explorer.
ExplorerModel _explorer(String path) {
  final root = TargetPath(path);

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

/// Creates a committed workflow-state fixture.
WorkflowActiveState _active() {
  return WorkflowActiveState(
    identity: WorkflowIdentity(
      workflow_id: 'fixture-workflow',
      os_user_id: 'fixture-user',
      target_id: 'fixture-target',
      root: TargetPath('/workspace'),
    ),
    version: 2,
  );
}
