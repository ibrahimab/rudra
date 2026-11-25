import 'dart:async';
import 'dart:io';

import 'package:rudra_persistence_sqlite/src/database/rudra_database.dart'
    hide WorkflowEvent;
import 'package:rudra_persistence_sqlite/src/features/workflow/history/drift_workflow_committer.dart';
import 'package:rudra_persistence_sqlite/src/features/workflow/history/drift_workflow_history_store.dart';
import 'package:rudra_persistence_sqlite/src/features/workflow/observation/publishing_workflow_committer.dart';
import 'package:rudra_persistence_sqlite/src/features/workflow/submissions/drift_event_submission_store.dart';
import 'package:rudra_persistence_sqlite/src/features/workflow/submissions/drift_workflow_inbox.dart';
import 'package:rudra_persistence_sqlite/src/features/workflow/submissions/drift_workflow_status_reader.dart';
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Verifies that a real transactional rollback cannot publish a change.
void main() {
  test(
    'rolled-back terminal outcome produces no commit notification',
    () async {
      const owner = 'trusted-owner';
      const scope = 'test-scope';

      final directory = await Directory.systemTemp.createTemp(
        'rudra-publication-rollback-',
      );

      final database = RudraDatabase.file(File('${directory.path}/rudra.db'));

      final channel = LocalWorkflowCommitChannel();

      final runtime = WorkflowRuntime.standard();

      final reader = WorkflowStateReader(
        runtime: runtime,
        history_store: DriftWorkflowHistoryStore(database: database),
        os_user_id: owner,
      );

      final manager = EventManager(
        store: DriftEventSubmissionStore(
          database: database,
          scope_id: scope,
          codec: runtime.codec,
        ),
      );

      final inbox = DriftWorkflowInbox(
        database: database,
        scope_id: scope,
        codec: runtime.codec,
        state_reader: reader,
      );

      final committer = PublishingWorkflowCommitter(
        delegate: DriftWorkflowCommitter(
          database: database,
          scope_id: scope,
          os_user_id: owner,
          runtime: runtime,
        ),
        publisher: channel,
        os_user_id: owner,
      );

      final machine = WorkflowStateMachine(runtime: runtime);

      StreamSubscription<void>? subscription;

      try {
        final identity = WorkflowIdentity(
          workflow_id: 'workflow-1',
          os_user_id: owner,
          target_id: 'local-macos',
          root: TargetPath('/workspace'),
        );

        await manager.trigger(
          WorkflowStartEvent(
            target_id: identity.target_id,
            root: identity.root,
          ),
        );

        final start = WorkflowStartedEvent(identity: identity);

        final start_pending = (await inbox.next_pending())!;

        await committer.commit(
          WorkflowProcessingPlan(
            submission: start_pending,
            previous_state: null,
            resulting_state: machine.transition(state: null, event: start),
            events_to_append: [start],
          ),
        );

        final initial = (await reader.current())!;

        expect(initial.state.identity.workflow_id, identity.workflow_id);
        expect(initial.state.version, 1);

        var notification_count = 0;

        // Begin observing only after the establishment has committed.
        subscription = channel.watch(os_user_id: owner).listen((_) {
          notification_count++;
        });

        final receipt = await manager.trigger(
          WorkflowStopEvent(workflow_id: identity.workflow_id),
        );

        final stop_pending = (await inbox.next_pending())!;

        final stop = WorkflowEndedEvent(workflow_id: identity.workflow_id);

        final plan = WorkflowProcessingPlan(
          submission: stop_pending,
          previous_state: initial.state,
          resulting_state: machine.replay([
            ...stop_pending.committed_events,
            stop,
          ])!,
          events_to_append: [stop],
        );

        // Stop appends its terminal outcome before deleting the unfinished
        // projection. Aborting the deletion forces the transaction to roll
        // back the already attempted journal mutation.
        await database.customStatement('''
        CREATE TEMP TRIGGER reject_workflow_release
        BEFORE DELETE ON ${database.unfinishedWorkflows.actualTableName}
        BEGIN
          SELECT RAISE(ABORT, 'forced publication rollback');
        END
      ''');

        await expectLater(
          committer.commit(plan),
          throwsA(
            predicate<Object>(
              (error) =>
                  error.toString().contains('forced publication rollback'),
            ),
          ),
        );

        // The terminal outcome must not survive the transaction failure.
        final journal = await database.select(database.workflowEvents).get();

        expect(journal, hasLength(1));
        expect(journal.single.version, 1);

        final restored = (await reader.current())!;

        expect(restored.state.identity.workflow_id, identity.workflow_id);
        expect(restored.state.version, 1);

        final resolution = await DriftWorkflowStatusReader(
          database: database,
          scope_id: scope,
          os_user_id: owner,
          runtime: runtime,
        ).status_for(receipt);

        expect(resolution?.state, WorkflowSubmissionState.pending);

        // Closing the source drains previously queued notifications.
        // This establishes the negative assertion without a timing sleep.
        await channel.close();

        expect(notification_count, 0);
      } finally {
        await subscription?.cancel();

        try {
          await channel.close();
        } finally {
          try {
            await database.close();
          } finally {
            await directory.delete(recursive: true);
          }
        }
      }
    },
  );
}
