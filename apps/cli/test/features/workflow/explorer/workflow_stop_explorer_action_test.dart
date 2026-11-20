import 'package:rudra_cli/src/features/explorer/application/explorer_model.dart';
import 'package:rudra_cli/src/features/workflow/explorer/workflow_stop_explorer_action.dart';
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Tests the Explorer adapter for workflow termination.
///
/// The application operation is injected to verify identity
/// handling and failure propagation independently of persistence.
void main() {
  group('WorkflowStopExplorerAction', () {
    test('has a stable identity and keyboard shortcut', () {
      final action = WorkflowStopExplorerAction(
        displayed_workflow: () => _active('workflow-1'),
        stop_workflow: (id) async => id,
      );

      expect(action.id, 'workflow.stop');
      expect(action.shortcut, 'x');
    });

    test('passes the displayed workflow identity to Stop', () async {
      String? requested_id;

      final action = WorkflowStopExplorerAction(
        displayed_workflow: () => _active('workflow-1'),
        stop_workflow: (expected_id) async {
          requested_id = expected_id;
          return expected_id;
        },
      );

      await action.execute(_explorer());

      expect(requested_id, 'workflow-1');
    });

    test('rejects Stop when no workflow is displayed', () async {
      var calls = 0;

      final action = WorkflowStopExplorerAction(
        displayed_workflow: () => null,
        stop_workflow: (id) async {
          calls++;
          return id;
        },
      );

      await expectLater(action.execute(_explorer()), throwsStateError);

      expect(calls, 0);
    });

    test('rejects a mismatched confirmed workflow ID', () async {
      final action = WorkflowStopExplorerAction(
        displayed_workflow: () => _active('workflow-1'),
        stop_workflow: (_) async => 'workflow-2',
      );

      await expectLater(action.execute(_explorer()), throwsStateError);
    });

    test(
      'does not retarget Stop after the displayed workflow changes',
      () async {
        var displayed = _active('workflow-1');
        String? requested_id;

        final action = WorkflowStopExplorerAction(
          displayed_workflow: () => displayed,
          stop_workflow: (expected_id) async {
            requested_id = expected_id;

            // Simulate another presentation snapshot replacing the
            // workflow while the original operation is in flight.
            displayed = _active('workflow-2');

            return expected_id;
          },
        );

        await action.execute(_explorer());

        expect(requested_id, 'workflow-1');
        expect(displayed.identity.workflow_id, 'workflow-2');
      },
    );

    test('propagates application rejection', () async {
      final action = WorkflowStopExplorerAction(
        displayed_workflow: () => _active('workflow-1'),
        stop_workflow: (_) async {
          throw StateError('Injected Stop rejection.');
        },
      );

      await expectLater(action.execute(_explorer()), throwsStateError);
    });

    test('reads the displayed workflow once per execution', () async {
      var reads = 0;

      final action = WorkflowStopExplorerAction(
        displayed_workflow: () {
          reads++;
          return _active('workflow-1');
        },
        stop_workflow: (id) async => id,
      );

      await action.execute(_explorer());

      expect(reads, 1);
    });
  });
}

/// Creates a committed active workflow with the requested identifier.
///
/// [workflow_id] is the exact identity supplied to the Stop action.
WorkflowActiveState _active(String workflow_id) {
  return WorkflowActiveState(
    identity: WorkflowIdentity(
      workflow_id: workflow_id,
      os_user_id: 'fixture-user',
      target_id: 'fixture-target',
      root: TargetPath('/workspace'),
    ),
    version: 2,
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
