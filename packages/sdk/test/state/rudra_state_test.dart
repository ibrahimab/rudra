import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

void main() {
  group('RudraState', () {
    test('always exposes a non-null workflow collection', () {
      final workflows = WorkflowsState(current_workflow: null);

      final state = RudraState(workflows: workflows);

      expect(state.workflows, same(workflows));
      expect(state.workflows.current_workflow, isNull);
    });

    test('retains the supplied composite domain state', () {
      final snapshot = WorkflowSnapshot(
        identity: WorkflowIdentity(
          workflow_id: 'workflow-1',
          os_user_id: 'user-1',
          target_id: 'local-macos',
          root: TargetPath('/tmp'),
        ),
        version: 1,
        lifecycle: WorkflowLifecycle(id: 'test.active', is_terminal: false),
      );

      final workflows = WorkflowsState(current_workflow: snapshot);

      final state = RudraState(workflows: workflows);

      expect(state.workflows.current_workflow, same(snapshot));
      expect(
        state.workflows.current_workflow!.identity.workflow_id,
        'workflow-1',
      );
    });

    test('separate application states retain their own snapshots', () {
      final first = RudraState(
        workflows: WorkflowsState(current_workflow: null),
      );

      final second_workflows = WorkflowsState(
        current_workflow: WorkflowSnapshot(
          identity: WorkflowIdentity(
            workflow_id: 'workflow-2',
            os_user_id: 'user-1',
            target_id: 'local-macos',
            root: TargetPath('/other'),
          ),
          version: 1,
          lifecycle: WorkflowLifecycle(id: 'test.active', is_terminal: false),
        ),
      );

      final second = RudraState(workflows: second_workflows);

      expect(first.workflows.current_workflow, isNull);
      expect(
        second.workflows.current_workflow!.identity.workflow_id,
        'workflow-2',
      );
    });
  });
}
