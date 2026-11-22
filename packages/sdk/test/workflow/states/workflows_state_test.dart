import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Verifies workflows state behavior through this file's focused tests.
void main() {
  group('WorkflowsState', () {
    test('represents verified absence explicitly', () {
      final workflows = WorkflowsState(current_workflow: null);

      expect(workflows.current_workflow, isNull);
    });

    test('retains an established unfinished workflow', () {
      final snapshot = _snapshot(lifecycle_id: 'test.active');

      final workflows = WorkflowsState(current_workflow: snapshot);

      expect(workflows.current_workflow, same(snapshot));
      expect(workflows.current_workflow!.version, 1);
      expect(workflows.current_workflow!.identity.workflow_id, 'workflow-1');
    });

    test('accepts nonterminal lifecycle phases', () {
      final paused = _snapshot(lifecycle_id: 'test.paused');

      final workflows = WorkflowsState(current_workflow: paused);

      expect(workflows.current_workflow, same(paused));
      expect(workflows.current_workflow!.is_terminal, isFalse);
    });

    test('rejects terminal workflows as current', () {
      final ended = _snapshot(lifecycle_id: 'test.ended', is_terminal: true);

      expect(
        () => WorkflowsState(current_workflow: ended),
        throwsArgumentError,
      );
    });

    test('does not mutate an existing workflow snapshot', () {
      final snapshot = _snapshot(lifecycle_id: 'test.active');

      final workflows = WorkflowsState(current_workflow: snapshot);

      expect(snapshot.version, 1);
      expect(snapshot.lifecycle.id, 'test.active');
      expect(workflows.current_workflow, same(snapshot));
    });
  });
}

/// Creates an established workflow for collection-contract tests.
///
/// Lifecycle identifiers are synthetic; registration validation
/// belongs to the workflow runtime and state machine.
WorkflowSnapshot _snapshot({
  required String lifecycle_id,
  bool is_terminal = false,
}) {
  return WorkflowSnapshot(
    identity: WorkflowIdentity(
      workflow_id: 'workflow-1',
      os_user_id: 'user-1',
      target_id: 'local-macos',
      root: TargetPath('/tmp'),
    ),
    version: 1,
    lifecycle: WorkflowLifecycle(id: lifecycle_id, is_terminal: is_terminal),
  );
}
