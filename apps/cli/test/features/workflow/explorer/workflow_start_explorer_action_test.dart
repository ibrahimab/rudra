import 'package:rudra_cli/src/features/explorer/application/explorer_action_registry.dart';
import 'package:rudra_cli/src/features/explorer/application/explorer_model.dart';
import 'package:rudra_cli/src/features/workflow/explorer/workflow_start_explorer_action.dart';
import 'package:rudra_cli/src/features/workflow/explorer/workflow_explorer_operation_exception.dart';

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
        start_workflow: (_, _) async => _completed_start(),
      );

      expect(action.id, 'workflow.start');
      expect(action.shortcut, 's');
    });

    test('uses the displayed directory and identifies the operation', () async {
      TargetPath? requested_root;
      String? requested_key;

      final action = WorkflowStartExplorerAction(
        start_workflow: (root, idempotency_key) async {
          requested_root = root;
          requested_key = idempotency_key;

          return _completed_start();
        },
      );

      await action.execute(_explorer('/workspace/src'));

      expect(requested_root?.value, '/workspace/src');
      expect(requested_key, isNotNull);
      expect(requested_key!.trim(), isNotEmpty);
    });

    test('does not execute during construction or registration', () {
      var submissions = 0;

      final action = WorkflowStartExplorerAction(
        start_workflow: (_, _) async {
          submissions++;
          return _completed_start();
        },
      );

      final registry = ExplorerActionRegistry([
        ExplorerFeatureContribution(id: 'workflow', actions: [action]),
      ]);

      expect(registry.resolve('s'), same(action));
      expect(submissions, 0);
    });

    test('propagates unexpected application failure', () async {
      final action = WorkflowStartExplorerAction(
        start_workflow: (_, _) async {
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
        start_workflow: (_, _) async => _completed_start(),
      );

      await action.execute(explorer);

      expect(explorer.current_directory.value, '/workspace');
      expect(explorer.is_closed, isFalse);
      expect(explorer.history, isEmpty);
    });

    test('preserves a durable business rejection', () async {
      final outcome = WorkflowOperationResolved(
        resolution: WorkflowSubmissionResolution(
          receipt: EventSubmissionReceipt(
            event_id: 'rejected-event',
            correlation_id: 'rejected-correlation',
          ),
          state: WorkflowSubmissionState.rejected,
          rejection_code: WorkflowRejectionCode.ownership_conflict,
          rejected_at_unix_ms: 1795618800000,
        ),
      );

      final action = WorkflowStartExplorerAction(
        start_workflow: (_, _) async => outcome,
      );

      await expectLater(
        action.execute(_explorer('/workspace')),
        throwsA(
          isA<WorkflowExplorerOperationException>().having(
            (error) => error.outcome,
            'outcome',
            same(outcome),
          ),
        ),
      );
    });

    test('identifies separate user intentions with different keys', () async {
      final keys = <String>[];

      final action = WorkflowStartExplorerAction(
        start_workflow: (_, idempotency_key) async {
          keys.add(idempotency_key);
          return _completed_start();
        },
      );

      final explorer = _explorer('/workspace');

      await action.execute(explorer);
      await action.execute(explorer);

      expect(keys, hasLength(2));
      expect(keys.first, isNot(keys.last));
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

/// Creates a successfully committed Start operation fixture.
WorkflowOperationOutcome _completed_start() {
  return WorkflowOperationResolved(
    resolution: WorkflowSubmissionResolution(
      receipt: EventSubmissionReceipt(
        event_id: 'fixture-start-event',
        correlation_id: 'fixture-start-correlation',
      ),
      state: WorkflowSubmissionState.completed,
      committed_outcome: WorkflowCommittedOutcome(
        workflow_id: 'fixture-workflow',
        event_type: WorkflowStartedEvent.type_id,
        version: 1,
        sequence: 1,
      ),
    ),
  );
}
