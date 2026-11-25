import 'dart:io';

import 'package:rudra_sdk/rudra_sdk.dart';

import 'package:rudra_persistence_sqlite/src/database/rudra_database.dart'
    hide WorkflowEvent;

import 'package:rudra_persistence_sqlite/src/features/workflow/history/drift_workflow_committer.dart';
import 'package:rudra_persistence_sqlite/src/features/workflow/history/drift_workflow_history_store.dart';

import 'package:rudra_persistence_sqlite/src/features/workflow/submissions/drift_event_submission_store.dart';
import 'package:rudra_persistence_sqlite/src/features/workflow/submissions/drift_workflow_inbox.dart';
import 'package:rudra_persistence_sqlite/src/features/workflow/submissions/drift_workflow_rejection_store.dart';
import 'package:rudra_persistence_sqlite/src/features/workflow/submissions/drift_workflow_status_reader.dart';
import 'package:rudra_persistence_sqlite/src/features/workflow/submissions/drift_workflow_quarantine_store.dart';

import 'package:test/test.dart';

/// Verifies atomic workflow establishment and durable recovery.
void main() {
  const scope_id = 'trusted-scope';
  const os_user_id = 'trusted-os-user';

  late Directory directory;
  late File database_file;
  late RudraDatabase database;
  late WorkflowEventCodec codec;
  late WorkflowModuleRegistry registry;
  late EventManager manager;
  late DriftWorkflowInbox inbox;
  late DriftWorkflowCommitter committer;
  late WorkflowRuntime runtime;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('rudra-committer-test-');

    database_file = File('${directory.path}/rudra.db');

    database = RudraDatabase.file(database_file);

    registry = WorkflowModuleRegistry()
      ..register(const LifecycleWorkflowModule());

    runtime = WorkflowRuntime.from_registry(registry);
    codec = runtime.codec;

    manager = EventManager(
      store: DriftEventSubmissionStore(
        database: database,
        scope_id: scope_id,
        codec: codec,
      ),
    );

    inbox = DriftWorkflowInbox(
      database: database,
      scope_id: scope_id,
      codec: codec,
      state_reader: WorkflowStateReader(
        runtime: runtime,
        history_store: DriftWorkflowHistoryStore(database: database),
        os_user_id: os_user_id,
      ),
    );

    committer = DriftWorkflowCommitter(
      database: database,
      scope_id: scope_id,
      os_user_id: os_user_id,
      runtime: runtime,
    );
  });

  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  /// Submits a workflow-start request through the public SDK.
  Future<EventSubmissionReceipt> submit(String root) {
    return manager.trigger(
      WorkflowStartEvent(target_id: 'local-macos', root: TargetPath(root)),
    );
  }

  /// Constructs a processor with deterministic test identities.
  WorkflowProcessor processor(String workflow_id) {
    return WorkflowProcessor(
      runtime: runtime,
      inbox: inbox,
      identity_provider: _TestIdentityProvider(
        workflow_id: workflow_id,
        os_user_id: os_user_id,
      ),
      committer: committer,
      rejector: DriftWorkflowRejectionStore(
        database: database,
        scope_id: scope_id,
        codec: codec,
      ),
      quarantiner: DriftWorkflowQuarantineStore(
        database: database,
        scope_id: scope_id,
      ),
    );
  }

  test(
    'atomically establishes a workflow using one committed outcome',
    () async {
      final receipt = await submit('/workspace');
      final result = await processor('workflow-1').process_next();
      expect(result, isA<WorkflowProcessingCommitted>());
      final plan = (result as WorkflowProcessingCommitted).plan;
      expect(plan.previous_state, isNull);
      expect(plan.resulting_state.version, 1);
      expect(plan.resulting_state.lifecycle.id, 'rudra.workflow.active');
      expect(plan.events_to_append, hasLength(1));
      expect(plan.events_to_append.single, isA<WorkflowStartedEvent>());

      final submissions = await database
          .select(database.workflowSubmissions)
          .get();
      final history = await database.select(database.workflowEvents).get();
      final unfinished = await database
          .select(database.unfinishedWorkflows)
          .get();

      expect(submissions, hasLength(1));
      expect(submissions.single.processing_state, 'completed');
      expect(history, hasLength(1));
      expect(history.single.version, 1);
      expect(history.single.os_user_id, os_user_id);
      expect(history.single.event_type, WorkflowStartedEvent.type_id);
      expect(history.single.event_id, isNot(receipt.event_id));
      expect(history.single.correlation_id, receipt.correlation_id);
      expect(history.single.causation_id, receipt.event_id);

      expect(unfinished, hasLength(1));
      expect(unfinished.single.workflow_id, 'workflow-1');
      expect(unfinished.single.version, 1);

      final restored = WorkflowStateMachine(runtime: runtime).replay([
        codec.decode(
          event_type: history.single.event_type,
          payload_json: history.single.payload_json,
        ) as WorkflowOutcomeEvent,
      ]);
      expect(restored!.version, 1);
      expect(restored.is_terminal, isFalse);
    },
  );

  test('atomically ends a workflow with one terminal outcome', () async {
    final start_receipt = await submit('/workspace');
    expect(
      await processor('workflow-1').process_next(),
      isA<WorkflowProcessingCommitted>(),
    );

    final stop_receipt = await manager.trigger(
      WorkflowStopEvent(workflow_id: 'workflow-1'),
    );
    final result = await processor('unused').process_next();
    expect(result, isA<WorkflowProcessingCommitted>());
    final plan = (result as WorkflowProcessingCommitted).plan;
    expect(plan.previous_state!.version, 1);
    expect(plan.resulting_state.version, 2);
    expect(plan.resulting_state.is_terminal, isTrue);
    expect(plan.events_to_append, hasLength(1));
    expect(plan.events_to_append.single, isA<WorkflowEndedEvent>());

    final history = await database.select(database.workflowEvents).get()
      ..sort((a, b) => a.version.compareTo(b.version));
    expect(history, hasLength(2));
    expect(history.map((event) => event.version), orderedEquals([1, 2]));
    expect(
      history.map((event) => event.event_type),
      orderedEquals([WorkflowStartedEvent.type_id, WorkflowEndedEvent.type_id]),
    );
    expect(history[0].os_user_id, os_user_id);
    expect(history[1].os_user_id, isNull);
    expect(history[0].causation_id, start_receipt.event_id);
    expect(history[1].causation_id, stop_receipt.event_id);
    expect(history[1].correlation_id, stop_receipt.correlation_id);

    final replayed = WorkflowStateMachine(runtime: runtime).replay([
      for (final row in history)
        codec.decode(event_type: row.event_type, payload_json: row.payload_json)
            as WorkflowOutcomeEvent,
    ]);
    expect(replayed!.is_terminal, isTrue);
    expect(replayed.version, 2);

    expect(await database.select(database.unfinishedWorkflows).get(), isEmpty);

    final current = await WorkflowStateReader(
      runtime: runtime,
      history_store: DriftWorkflowHistoryStore(database: database),
      os_user_id: os_user_id,
    ).current();

    expect(current, isNull);

    final status = await DriftWorkflowStatusReader(
      database: database,
      scope_id: scope_id,
      os_user_id: os_user_id,
      runtime: runtime,
    ).status_for(stop_receipt);

    expect(status!.state, WorkflowSubmissionState.completed);
    expect(await inbox.next_pending(), isNull);
  });

  test('rolls back stop when terminal serialization fails', () async {
    await submit('/workspace');

    expect(
      await processor('workflow-1').process_next(),
      isA<WorkflowProcessingCommitted>(),
    );

    final receipt = await manager.trigger(
      WorkflowStopEvent(workflow_id: 'workflow-1'),
    );

    final pending = await inbox.next_pending();

    expect(pending, isNotNull);

    final machine = WorkflowStateMachine(runtime: runtime);
    final outcome = WorkflowEndedEvent(workflow_id: 'workflow-1');

    final plan = WorkflowProcessingPlan(
      submission: pending!,
      previous_state: machine.replay(pending.committed_events),
      resulting_state: machine.replay([...pending.committed_events, outcome])!,
      events_to_append: [outcome],
    );

    // Retain all historical serializers but deliberately omit
    // the terminal outcome serializer.
    //
    // The transaction must fail after version 3 is inserted,
    // then roll that insertion back.
    final incomplete_codec = WorkflowEventCodec(
      serializers: registry.serializers.where(
        (serializer) => serializer.dart_type != WorkflowEndedEvent,
      ),
    );

    final failing_committer = DriftWorkflowCommitter(
      database: database,
      scope_id: scope_id,
      os_user_id: os_user_id,
      runtime: runtime,
      codec: incomplete_codec,
    );

    await expectLater(failing_committer.commit(plan), throwsUnsupportedError);

    // The original active history is unchanged.
    final history = await database.select(database.workflowEvents).get();

    expect(history, hasLength(1));
    expect(history.map((event) => event.version), orderedEquals([1]));

    // Ownership is still reserved.
    final unfinished = await database
        .select(database.unfinishedWorkflows)
        .get();

    expect(unfinished, hasLength(1));
    expect(unfinished.single.workflow_id, 'workflow-1');
    expect(unfinished.single.version, 1);

    // A failed stop cannot be reported as completed.
    final status = await DriftWorkflowStatusReader(
      database: database,
      scope_id: scope_id,
      os_user_id: os_user_id,
      runtime: runtime,
    ).status_for(receipt);

    expect(status, isNotNull);
    expect(status!.state, WorkflowSubmissionState.pending);

    // The accepted request remains available for retry.
    final retry = await inbox.next_pending();

    expect(retry, isNotNull);
    expect(retry!.receipt.event_id, receipt.event_id);
  });

  test('rejects a stale second stop after terminal commitment', () async {
    await submit('/workspace');

    expect(
      await processor('workflow-1').process_next(),
      isA<WorkflowProcessingCommitted>(),
    );

    final first_receipt = await manager.trigger(
      WorkflowStopEvent(workflow_id: 'workflow-1'),
    );

    final second_receipt = await manager.trigger(
      WorkflowStopEvent(workflow_id: 'workflow-1'),
    );

    // Simulate a second processor having read the active
    // workflow before the first processor commits Stop.
    final snapshot = await WorkflowStateReader(
      runtime: runtime,
      history_store: DriftWorkflowHistoryStore(database: database),
      os_user_id: os_user_id,
    ).current();

    expect(snapshot, isNotNull);

    final command = WorkflowStopEvent(workflow_id: 'workflow-1');
    final outcome = WorkflowEndedEvent(workflow_id: 'workflow-1');

    final pending = PendingWorkflowCommand(
      receipt: second_receipt,
      scope_id: scope_id,
      command: command,
      committed_events: snapshot!.events,
    );

    final stale_plan = WorkflowProcessingPlan(
      submission: pending,
      previous_state: snapshot.state,
      resulting_state: WorkflowStateMachine(runtime: runtime)
          .replay([...snapshot.events, outcome])!,
      events_to_append: [outcome],
    );

    // First processor commits the terminal transition.
    final first_result = await processor('unused').process_next();

    expect(first_result, isA<WorkflowProcessingCommitted>());
    expect(
      (first_result as WorkflowProcessingCommitted)
          .plan
          .submission
          .receipt
          .event_id,
      first_receipt.event_id,
    );

    // The second proposal still references the old active state.
    // The committer must not append a second terminal history.
    await expectLater(
      committer.commit(stale_plan),
      throwsA(
        isA<WorkflowCommitException>().having(
          (error) => error.code,
          'code',
          WorkflowCommitErrorCode.workflow_not_active,
        ),
      ),
    );

    // The second submission is still pending because the
    // rejected transaction must not resolve it implicitly.
    final status_reader = DriftWorkflowStatusReader(
      database: database,
      scope_id: scope_id,
      os_user_id: os_user_id,
      runtime: runtime,
    );

    final before = await status_reader.status_for(second_receipt);

    expect(before!.state, WorkflowSubmissionState.pending);

    // Reprocessing reconstructs the current authoritative
    // state and records a durable business rejection.
    final second_result = await processor('unused').process_next();

    expect(second_result, isA<WorkflowProcessingRejected>());
    expect(
      (second_result as WorkflowProcessingRejected).code,
      WorkflowRejectionCode.workflow_not_active,
    );

    final after = await status_reader.status_for(second_receipt);

    expect(after!.state, WorkflowSubmissionState.rejected);
    expect(after.rejection_code, WorkflowRejectionCode.workflow_not_active);

    expect(await database.select(database.workflowEvents).get(), hasLength(2));
    expect(await database.select(database.unfinishedWorkflows).get(), isEmpty);
    expect(await inbox.next_pending(), isNull);
  });

  test('rejects repeat commitment of a completed submission', () async {
    await submit('/workspace');

    final result = await processor('workflow-1').process_next();

    expect(result, isA<WorkflowProcessingCommitted>());

    final plan = (result as WorkflowProcessingCommitted).plan;

    await expectLater(
      committer.commit(plan),
      throwsA(
        isA<WorkflowCommitException>().having(
          (error) => error.code,
          'code',
          WorkflowCommitErrorCode.stale_submission,
        ),
      ),
    );

    expect(await database.select(database.workflowEvents).get(), hasLength(1));

    expect(
      await database.select(database.unfinishedWorkflows).get(),
      hasLength(1),
    );
  });

  test('rejects stop without an active workflow across restart', () async {
    final receipt = await manager.trigger(
      WorkflowStopEvent(workflow_id: 'workflow-1'),
    );

    final result = await processor('unused').process_next();

    expect(result, isA<WorkflowProcessingRejected>());
    expect(
      (result as WorkflowProcessingRejected).code,
      WorkflowRejectionCode.workflow_not_active,
    );

    final reader = DriftWorkflowStatusReader(
      database: database,
      scope_id: scope_id,
      os_user_id: os_user_id,
      runtime: runtime,
    );

    final resolution = await reader.status_for(receipt);

    expect(resolution, isNotNull);
    expect(resolution!.state, WorkflowSubmissionState.rejected);
    expect(
      resolution.rejection_code,
      WorkflowRejectionCode.workflow_not_active,
    );
    expect(resolution.rejected_at_unix_ms, isNotNull);

    expect(await database.select(database.workflowEvents).get(), isEmpty);
    expect(await database.select(database.unfinishedWorkflows).get(), isEmpty);
    expect(await inbox.next_pending(), isNull);

    // Reopen the authoritative SQLite database.
    await database.close();
    database = RudraDatabase.file(database_file);

    final restored = await DriftWorkflowStatusReader(
      database: database,
      scope_id: scope_id,
      os_user_id: os_user_id,
      runtime: runtime,
    ).status_for(receipt);

    expect(restored, isNotNull);
    expect(restored!.state, WorkflowSubmissionState.rejected);
    expect(restored.rejection_code, WorkflowRejectionCode.workflow_not_active);
  });

  test('rejects mismatched stop without changing active workflow', () async {
    await submit('/workspace');

    expect(
      await processor('workflow-1').process_next(),
      isA<WorkflowProcessingCommitted>(),
    );

    final history_before = await database.select(database.workflowEvents).get();

    final unfinished_before = await database
        .select(database.unfinishedWorkflows)
        .get();

    final receipt = await manager.trigger(
      WorkflowStopEvent(workflow_id: 'different-workflow'),
    );

    final result = await processor('unused').process_next();

    expect(result, isA<WorkflowProcessingRejected>());

    final rejected = result as WorkflowProcessingRejected;

    expect(rejected.code, WorkflowRejectionCode.workflow_id_mismatch);
    expect(rejected.receipt.event_id, receipt.event_id);

    final resolution = await DriftWorkflowStatusReader(
      database: database,
      scope_id: scope_id,
      os_user_id: os_user_id,
      runtime: runtime,
    ).status_for(receipt);

    expect(resolution, isNotNull);
    expect(resolution!.state, WorkflowSubmissionState.rejected);
    expect(
      resolution.rejection_code,
      WorkflowRejectionCode.workflow_id_mismatch,
    );

    // A rejected command must never alter the journal
    // or the existing workflow ownership projection.
    expect(
      await database.select(database.workflowEvents).get(),
      orderedEquals(history_before),
    );

    expect(
      await database.select(database.unfinishedWorkflows).get(),
      orderedEquals(unfinished_before),
    );

    final restored = await WorkflowStateReader(
      runtime: runtime,
      history_store: DriftWorkflowHistoryStore(database: database),
      os_user_id: os_user_id,
    ).current();

    expect(restored, isNotNull);
    expect(restored!.state.identity.workflow_id, 'workflow-1');
    expect(restored.state.version, 1);
    expect(restored.events, hasLength(1));

    expect(await inbox.next_pending(), isNull);
  });

  test('durably rejects competing starts and advances the inbox', () async {
    final first = await submit('/first');
    final second = await submit('/second');

    await processor('workflow-1').process_next();

    // The competing start must be durably rejected rather
    // than repeatedly returned as pending.
    final result = await processor('workflow-2').process_next();

    expect(result, isA<WorkflowProcessingRejected>());

    final rejected = result as WorkflowProcessingRejected;

    expect(rejected.receipt.event_id, second.event_id);
    expect(rejected.code, WorkflowRejectionCode.ownership_conflict);

    final reader = DriftWorkflowStatusReader(
      database: database,
      scope_id: scope_id,
      os_user_id: os_user_id,
      runtime: runtime,
    );

    final first_status = await reader.status_for(first);
    final second_status = await reader.status_for(second);

    expect(first_status!.state, WorkflowSubmissionState.completed);

    expect(second_status!.state, WorkflowSubmissionState.rejected);

    expect(
      second_status.rejection_code,
      WorkflowRejectionCode.ownership_conflict,
    );

    expect(second_status.rejected_at_unix_ms, isNotNull);

    // Only the first workflow has authoritative history.
    expect(await database.select(database.workflowEvents).get(), hasLength(1));

    final reservations = await database
        .select(database.unfinishedWorkflows)
        .get();

    expect(reservations, hasLength(1));
    expect(reservations.single.workflow_id, 'workflow-1');

    // The rejected request is no longer returned by the inbox.
    expect(await inbox.next_pending(), isNull);

    // A newly accepted request is not blocked by the
    // previous rejected submission.
    final third = await submit('/third');

    final pending = await inbox.next_pending();

    expect(pending, isNotNull);
    expect(pending!.receipt.event_id, third.event_id);
  });

  test('recovers rejection status after reopening SQLite', () async {
    await submit('/first');
    final rejected_receipt = await submit('/second');

    await processor('workflow-1').process_next();

    final result = await processor('workflow-2').process_next();

    expect(result, isA<WorkflowProcessingRejected>());

    await database.close();
    database = RudraDatabase.file(database_file);

    // Construct fresh services after restarting persistence.
    // No in-memory notification or previous processor state
    // is needed to recover the rejection.
    final reader = DriftWorkflowStatusReader(
      database: database,
      scope_id: scope_id,
      os_user_id: os_user_id,
      runtime: runtime,
    );

    final resolved = await reader.status_for(rejected_receipt);

    expect(resolved, isNotNull);
    expect(resolved!.state, WorkflowSubmissionState.rejected);
    expect(resolved.rejection_code, WorkflowRejectionCode.ownership_conflict);

    final restarted_inbox = DriftWorkflowInbox(
      database: database,
      scope_id: scope_id,
      codec: codec,
      state_reader: WorkflowStateReader(
        runtime: runtime,
        history_store: DriftWorkflowHistoryStore(database: database),
        os_user_id: os_user_id,
      ),
    );

    expect(await restarted_inbox.next_pending(), isNull);

    // Status must not be disclosed outside its trusted scope.
    final foreign_reader = DriftWorkflowStatusReader(
      database: database,
      scope_id: 'another-scope',
      os_user_id: 'another-owner',
      runtime: runtime,
    );

    expect(await foreign_reader.status_for(rejected_receipt), isNull);
  });

  test('cannot reject a submission that was already completed', () async {
    await submit('/workspace');

    final pending = await inbox.next_pending();
    expect(pending, isNotNull);

    await processor('workflow-1').process_next();

    final rejector = DriftWorkflowRejectionStore(
      database: database,
      scope_id: scope_id,
      codec: codec,
    );

    await expectLater(
      rejector.reject(
        submission: pending!,
        code: WorkflowRejectionCode.ownership_conflict,
      ),
      throwsA(
        isA<WorkflowCommitException>().having(
          (error) => error.code,
          'code',
          WorkflowCommitErrorCode.stale_submission,
        ),
      ),
    );

    final stored = await database
        .select(database.workflowSubmissions)
        .getSingle();

    expect(stored.processing_state, 'completed');
    expect(stored.rejection_code, isNull);

    // The original successful journal must remain intact.
    expect(await database.select(database.workflowEvents).get(), hasLength(1));
  });

  test('recovers committed workflow state after restart', () async {
    await submit('/workspace');

    await processor('workflow-1').process_next();

    await database.close();

    // Reopen the database through an independent connection.
    database = RudraDatabase.file(database_file);

    final history = await database.select(database.workflowEvents).get();

    history.sort((first, second) => first.version.compareTo(second.version));

    final restored = WorkflowStateMachine().replay(
      history.map(
        (event) => codec.decode(
          event_type: event.event_type,
          payload_json: event.payload_json,
        ) as WorkflowOutcomeEvent,
      ),
    );

    expect(restored, isA<WorkflowSnapshot>());
    expect(restored!.version, 1);

    final active = restored;

    expect(active.identity.workflow_id, 'workflow-1');
    expect(active.identity.os_user_id, os_user_id);
    expect(active.identity.root.value, '/workspace');

    final unfinished = await database
        .select(database.unfinishedWorkflows)
        .getSingle();

    expect(unfinished.workflow_id, active.identity.workflow_id);

    final submission = await database
        .select(database.workflowSubmissions)
        .getSingle();

    expect(submission.processing_state, 'completed');
  });

  test('rolls back all writes if outcome serialization fails', () async {
    await submit('/workspace');

    final pending = (await inbox.next_pending())!;

    final identity = WorkflowIdentity(
      workflow_id: 'workflow-1',
      os_user_id: os_user_id,
      target_id: 'local-macos',
      root: TargetPath('/workspace'),
    );

    final outcome = WorkflowStartedEvent(identity: identity);

    final plan = WorkflowProcessingPlan(
      submission: pending,
      previous_state: null,
      resulting_state: WorkflowStateMachine().replay([outcome])!,
      events_to_append: [outcome],
    );

    // Intentionally configure a codec that can serialize
    // the start command but not the started outcome.
    //
    // This causes the transaction to fail after the ownership
    // reservation and first journal event have been inserted.
    final incomplete_codec = WorkflowEventCodec(
      serializers: registry.serializers.where(
        (serializer) => serializer.dart_type != WorkflowStartedEvent,
      ),
    );

    final failing_committer = DriftWorkflowCommitter(
      database: database,
      scope_id: scope_id,
      os_user_id: os_user_id,
      runtime: runtime,
      codec: incomplete_codec,
    );

    await expectLater(failing_committer.commit(plan), throwsUnsupportedError);

    // The transaction must undo every earlier write.
    expect(await database.select(database.workflowEvents).get(), isEmpty);

    expect(await database.select(database.unfinishedWorkflows).get(), isEmpty);

    // The original request must remain available for retry.
    final submission = await database
        .select(database.workflowSubmissions)
        .getSingle();

    expect(submission.processing_state, 'pending');
  });

  test(
    'refuses a second start when the ownership projection is missing',
    () async {
      await submit('/first');

      expect(
        await processor('workflow-1').process_next(),
        isA<WorkflowProcessingCommitted>(),
      );

      // Simulate loss of the derived ownership reservation.
      // The authoritative workflow journal remains committed.
      await database.delete(database.unfinishedWorkflows).go();

      final second = await submit('/second');

      // Bypass the normal CLI read-before-start check.
      // The commit boundary must still protect the invariant.
      await expectLater(
        processor('workflow-2').process_next(),
        throwsA(
          isA<WorkflowStateReadException>().having(
            (error) => error.code,
            'code',
            WorkflowStateReadErrorCode.orphaned_workflow,
          ),
        ),
      );

      // No second workflow was committed.
      final history = await database.select(database.workflowEvents).get();

      expect(history, hasLength(1));
      expect(history.map((event) => event.workflow_id).toSet(), {'workflow-1'});

      // The failed commit must not recreate a projection.
      expect(
        await database.select(database.unfinishedWorkflows).get(),
        isEmpty,
      );

      // An integrity failure is not a confirmed business rejection.
      // The submission remains pending for explicit recovery.
      final status = await DriftWorkflowStatusReader(
        database: database,
        scope_id: scope_id,
        os_user_id: os_user_id,
        runtime: runtime,
      ).status_for(second);

      expect(status, isNotNull);
      expect(status!.state, WorkflowSubmissionState.pending);
    },
  );

  test('allows a new workflow after a valid terminal history', () async {
    await submit('/first');

    expect(
      await processor('workflow-1').process_next(),
      isA<WorkflowProcessingCommitted>(),
    );

    final stop_receipt = await manager.trigger(
      WorkflowStopEvent(workflow_id: 'workflow-1'),
    );

    expect(
      await processor('unused').process_next(),
      isA<WorkflowProcessingCommitted>(),
    );

    final stop_status = await DriftWorkflowStatusReader(
      database: database,
      scope_id: scope_id,
      os_user_id: os_user_id,
      runtime: runtime,
    ).status_for(stop_receipt);

    expect(stop_status!.state, WorkflowSubmissionState.completed);

    // Terminal workflows are no longer active, but their
    // committed history remains available for replay.
    final active = await WorkflowStateReader(
      runtime: runtime,
      history_store: DriftWorkflowHistoryStore(database: database),
      os_user_id: os_user_id,
    ).current();

    expect(active, isNull);

    await submit('/second');

    expect(
      await processor('workflow-2').process_next(),
      isA<WorkflowProcessingCommitted>(),
    );

    final history = await database.select(database.workflowEvents).get();

    expect(history, hasLength(3));

    expect(
      history
          .where((event) => event.workflow_id == 'workflow-1')
          .map((event) => event.event_type),
      orderedEquals([WorkflowStartedEvent.type_id, WorkflowEndedEvent.type_id]),
    );

    expect(
      history
          .where((event) => event.workflow_id == 'workflow-2')
          .map((event) => event.event_type),
      orderedEquals([WorkflowStartedEvent.type_id]),
    );

    final reservations = await database
        .select(database.unfinishedWorkflows)
        .get();

    expect(reservations, hasLength(1));
    expect(reservations.single.os_user_id, os_user_id);
    expect(reservations.single.workflow_id, 'workflow-2');
  });

  test('refuses workflow ownership for a different OS user', () async {
    await submit('/workspace');

    final pending = (await inbox.next_pending())!;

    final identity = WorkflowIdentity(
      workflow_id: 'workflow-1',
      os_user_id: 'different-os-user',
      target_id: 'local-macos',
      root: TargetPath('/workspace'),
    );

    final outcome = WorkflowStartedEvent(identity: identity);

    final plan = WorkflowProcessingPlan(
      submission: pending,
      previous_state: null,
      resulting_state: WorkflowStateMachine(runtime: runtime)
          .replay([outcome])!,
      events_to_append: [outcome],
    );

    await expectLater(
      committer.commit(plan),
      throwsA(
        isA<WorkflowCommitException>().having(
          (error) => error.code,
          'code',
          WorkflowCommitErrorCode.invalid_plan,
        ),
      ),
    );

    expect(await database.select(database.workflowEvents).get(), isEmpty);
    expect(await database.select(database.unfinishedWorkflows).get(), isEmpty);

    final submission = await database
        .select(database.workflowSubmissions)
        .getSingle();

    expect(submission.processing_state, 'pending');
  });
}

/// Deterministic identity provider for persistence integration tests.
///
/// The owner ID comes from the test's trusted composition,
/// not from the submitted command or submission scope.
final class _TestIdentityProvider implements WorkflowIdentityProvider {
  /// Creates a provider with explicit trusted identifiers.
  const _TestIdentityProvider({
    required this.workflow_id,
    required this.os_user_id,
  });

  /// Committed workflow identity expected by the fixture.
  final String workflow_id;

  /// Trusted owner identity expected by the fixture.
  final String os_user_id;

  @override
  Future<WorkflowIdentity> propose_identity(
    PendingWorkflowCommand submission,
  ) async {
    final command = submission.command;

    if (command is! WorkflowStartEvent) {
      throw StateError('Test provider supports start commands only.');
    }

    return WorkflowIdentity(
      workflow_id: workflow_id,
      os_user_id: os_user_id,
      target_id: command.target_id,
      root: command.root,
    );
  }
}
