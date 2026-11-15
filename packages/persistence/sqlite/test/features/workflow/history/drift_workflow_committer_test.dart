import 'dart:io';

import 'package:rudra_sdk/rudra_sdk.dart';

import 'package:rudra_persistence_sqlite/src/database/rudra_database.dart';

import 'package:rudra_persistence_sqlite/src/features/workflow/history/drift_workflow_committer.dart';

import 'package:rudra_persistence_sqlite/src/features/workflow/submissions/drift_event_submission_store.dart';
import 'package:rudra_persistence_sqlite/src/features/workflow/submissions/drift_workflow_inbox.dart';
import 'package:rudra_persistence_sqlite/src/features/workflow/submissions/drift_workflow_rejection_store.dart';
import 'package:rudra_persistence_sqlite/src/features/workflow/submissions/drift_workflow_status_reader.dart';

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

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('rudra-committer-test-');

    database_file = File('${directory.path}/rudra.db');
    database = RudraDatabase.file(database_file);

    registry = WorkflowModuleRegistry()
      ..register(const LifecycleWorkflowModule());

    codec = WorkflowEventCodec.from_registry(registry);

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
    );

    committer = DriftWorkflowCommitter(
      database: database,
      scope_id: scope_id,
      codec: codec,
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
      registry: registry,
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
    );
  }

  test('atomically establishes a workflow', () async {
    final receipt = await submit('/workspace');

    final plan = await processor('workflow-1').process_next();

    expect(plan, isNotNull);
    expect(plan!.resulting_state, isA<WorkflowActiveState>());

    final submissions = await database
        .select(database.workflowSubmissions)
        .get();

    final history = await database.select(database.workflowEvents).get();

    final unfinished = await database
        .select(database.unfinishedWorkflows)
        .get();

    expect(submissions, hasLength(1));
    expect(submissions.single.processing_state, 'completed');

    expect(history, hasLength(2));

    // Query results are sorted by workflow version for replay.
    history.sort((first, second) => first.version.compareTo(second.version));

    expect(history[0].version, 1);
    expect(history[1].version, 2);

    expect(history[0].event_id, receipt.event_id);
    expect(history[0].event_type, WorkflowStartEvent.type_id);
    expect(history[1].event_type, WorkflowStartedEvent.type_id);
    expect(history[1].causation_id, receipt.event_id);

    expect(
      history.every((event) => event.correlation_id == receipt.correlation_id),
      isTrue,
    );

    expect(unfinished, hasLength(1));
    expect(unfinished.single.os_user_id, os_user_id);
    expect(unfinished.single.workflow_id, 'workflow-1');
    expect(unfinished.single.root_path, '/workspace');
    expect(unfinished.single.version, 2);

    // Replay the actual persisted event representations.
    final events = history.map(
      (event) => codec.decode(
        event_type: event.event_type,
        payload_json: event.payload_json,
      ),
    );

    final restored = WorkflowStateMachine().replay(events);

    expect(restored, isA<WorkflowActiveState>());
    expect(restored.version, 2);
  });

  test('rejects repeat commitment of a completed submission', () async {
    await submit('/workspace');

    final plan = await processor('workflow-1').process_next();

    expect(plan, isNotNull);

    await expectLater(
      committer.commit(plan!),
      throwsA(
        isA<WorkflowCommitException>().having(
          (error) => error.code,
          'code',
          WorkflowCommitErrorCode.stale_submission,
        ),
      ),
    );

    expect(await database.select(database.workflowEvents).get(), hasLength(2));

    expect(
      await database.select(database.unfinishedWorkflows).get(),
      hasLength(1),
    );
  });

  test('durably rejects competing starts and advances the inbox', () async {
    final first = await submit('/first');
    final second = await submit('/second');

    await processor('workflow-1').process_next();

    // The competing start must be durably rejected rather
    // than repeatedly returned as pending.
    await expectLater(
      processor('workflow-2').process_next(),
      throwsA(
        isA<WorkflowSubmissionRejectedException>().having(
          (error) => error.code,
          'code',
          WorkflowRejectionCode.ownership_conflict,
        ),
      ),
    );

    final reader = DriftWorkflowStatusReader(
      database: database,
      scope_id: scope_id,
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
    expect(await database.select(database.workflowEvents).get(), hasLength(2));

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

    await expectLater(
      processor('workflow-2').process_next(),
      throwsA(isA<WorkflowSubmissionRejectedException>()),
    );

    await database.close();
    database = RudraDatabase.file(database_file);

    // Construct fresh services after restarting persistence.
    // No in-memory notification or previous processor state
    // is needed to recover the rejection.
    final reader = DriftWorkflowStatusReader(
      database: database,
      scope_id: scope_id,
    );

    final resolved = await reader.status_for(rejected_receipt);

    expect(resolved, isNotNull);
    expect(resolved!.state, WorkflowSubmissionState.rejected);
    expect(resolved.rejection_code, WorkflowRejectionCode.ownership_conflict);

    final restarted_inbox = DriftWorkflowInbox(
      database: database,
      scope_id: scope_id,
      codec: codec,
    );

    expect(await restarted_inbox.next_pending(), isNull);

    // Status must not be disclosed outside its trusted scope.
    final foreign_reader = DriftWorkflowStatusReader(
      database: database,
      scope_id: 'another-scope',
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
    expect(await database.select(database.workflowEvents).get(), hasLength(2));
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
        ),
      ),
    );

    expect(restored, isA<WorkflowActiveState>());
    expect(restored.version, 2);

    final active = restored as WorkflowActiveState;

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

    final pending = await inbox.next_pending();
    expect(pending, isNotNull);

    final command = pending!.command;

    final identity = WorkflowIdentity(
      workflow_id: 'workflow-1',
      os_user_id: os_user_id,
      target_id: 'local-macos',
      root: TargetPath('/workspace'),
    );

    final outcome = WorkflowStartedEvent(identity: identity);

    final plan = WorkflowProcessingPlan(
      submission: pending,
      previous_state: const WorkflowInitialState(),
      resulting_state: WorkflowStateMachine().replay([command, outcome]),
      events_to_append: [command, outcome],
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

  final String workflow_id;
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
