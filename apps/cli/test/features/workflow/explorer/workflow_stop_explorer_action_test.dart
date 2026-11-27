import 'package:rudra_cli/src/features/explorer/application/explorer_model.dart';
import 'package:rudra_cli/src/features/workflow/explorer/workflow_stop_explorer_action.dart';
import 'package:rudra_cli/src/features/workflow/explorer/workflow_explorer_operation_exception.dart';

import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Tests the Explorer adapter for workflow termination.
///
/// The application operation is injected to verify identity
/// handling and failure propagation independently of persistence.
void main() {
  final state = _state('workflow-1');
  group('WorkflowStopExplorerAction', () {
    test('has a stable identity and keyboard shortcut', () {
      final action = WorkflowStopExplorerAction(
        stop_workflow: ({
          required workflow_id,
          required idempotency_key,
        }) async => _completed_stop(workflow_id),
      );

      expect(action.id, 'workflow.stop');
      expect(action.shortcut, 'x');
    });

    test('passes the displayed workflow identity to Stop', () async {
      String? requested_id;

      final action = WorkflowStopExplorerAction(
        stop_workflow:
            ({required workflow_id, required idempotency_key}) async {
              requested_id = workflow_id;
              return _completed_stop(workflow_id);
            },
      );

      await action.execute(_explorer(), state);

      expect(requested_id, 'workflow-1');
    });

    test('rejects Stop when no workflow is displayed', () async {
      var calls = 0;

      final action = WorkflowStopExplorerAction(
        stop_workflow:
            ({required workflow_id, required idempotency_key}) async {
              calls++;
              return _completed_stop(workflow_id);
            },
      );

      await expectLater(
        action.execute(_explorer(), _state()),
        throwsStateError,
      );

      expect(calls, 0);
    });

    test('rejects a mismatched confirmed workflow ID', () async {
      final action = WorkflowStopExplorerAction(
        stop_workflow: ({
          required workflow_id,
          required idempotency_key,
        }) async => _completed_stop('workflow-2'),
      );

      await expectLater(action.execute(_explorer(), state), throwsStateError);
    });

    test(
      'does not retarget Stop after the displayed workflow changes',
      () async {
        var displayed = state;
        String? requested_id;

        final action = WorkflowStopExplorerAction(
          stop_workflow:
              ({required workflow_id, required idempotency_key}) async {
                requested_id = workflow_id;

                // Simulate another presentation snapshot replacing the
                // workflow while the original operation is in flight.
                displayed = _state('workflow-2');

                return _completed_stop(workflow_id);
              },
        );

        await action.execute(_explorer(), displayed);

        expect(requested_id, 'workflow-1');
        expect(
          displayed.workflows.current_workflow!.identity.workflow_id,
          'workflow-2',
        );
      },
    );

    test('propagates unexpected application failure', () async {
      final action = WorkflowStopExplorerAction(
        stop_workflow:
            ({required workflow_id, required idempotency_key}) async {
              throw StateError('Injected Stop rejection.');
            },
      );

      await expectLater(action.execute(_explorer(), state), throwsStateError);
    });

    test('preserves the durable rejection of a stale Stop', () async {
      final outcome = WorkflowOperationResolved(
        resolution: WorkflowSubmissionResolution(
          receipt: EventSubmissionReceipt(
            event_id: 'rejected-stop-event',
            correlation_id: 'rejected-stop-correlation',
          ),
          state: WorkflowSubmissionState.rejected,
          rejection_code: WorkflowRejectionCode.workflow_id_mismatch,
          rejected_at_unix_ms: 1795618800000,
        ),
      );

      final action = WorkflowStopExplorerAction(
        stop_workflow: ({
          required workflow_id,
          required idempotency_key,
        }) async => outcome,
      );

      await expectLater(
        action.execute(_explorer(), state),
        throwsA(
          isA<WorkflowExplorerOperationException>().having(
            (error) => error.outcome,
            'outcome',
            same(outcome),
          ),
        ),
      );
    });

    test('supplies an explicit identity and operation key', () async {
      String? requested_id;
      String? requested_key;

      final action = WorkflowStopExplorerAction(
        stop_workflow:
            ({required workflow_id, required idempotency_key}) async {
              requested_id = workflow_id;
              requested_key = idempotency_key;

              return _completed_stop(workflow_id);
            },
      );

      await action.execute(_explorer(), state);

      expect(requested_id, 'workflow-1');
      expect(requested_key, isNotNull);
      expect(requested_key!.trim(), isNotEmpty);
    });
  });
}

/// Creates the SDK state supplied with a rendered frame.
RudraState _state([String? workflow_id]) => RudraState(
  workflows: WorkflowsState(
    current_workflow: workflow_id == null ? null : _active(workflow_id),
  ),
);

/// Creates a committed active workflow with the requested identifier.
///
/// [workflow_id] is the exact identity supplied to the Stop action.
WorkflowSnapshot _active(String workflow_id) {
  return WorkflowSnapshot(
    identity: WorkflowIdentity(
      workflow_id: workflow_id,
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

/// Creates a committed terminal outcome for [workflow_id].
WorkflowOperationOutcome _completed_stop(String workflow_id) {
  return WorkflowOperationResolved(
    resolution: WorkflowSubmissionResolution(
      receipt: EventSubmissionReceipt(
        event_id: 'fixture-stop-event',
        correlation_id: 'fixture-stop-correlation',
      ),
      state: WorkflowSubmissionState.completed,
      committed_outcome: WorkflowCommittedOutcome(
        workflow_id: workflow_id,
        event_type: WorkflowEndedEvent.type_id,
        version: 2,
        sequence: 2,
      ),
    ),
  );
}
