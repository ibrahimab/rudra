import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:rudra_persistence_sqlite/src/database/rudra_database.dart';
import 'package:rudra_persistence_sqlite/src/features/workflow/submissions/drift_event_submission_store.dart';
import 'package:rudra_persistence_sqlite/src/features/workflow/submissions/drift_workflow_inbox.dart';
import 'package:rudra_persistence_sqlite/src/features/workflow/submissions/drift_workflow_quarantine_store.dart';
import 'package:rudra_persistence_sqlite/src/features/workflow/submissions/drift_workflow_status_reader.dart';
import 'package:rudra_persistence_sqlite/src/features/workflow/history/drift_workflow_history_store.dart';

import 'package:test/test.dart';

/// Verifies durable, read-only workflow inbox behavior.
void main() {
  const scope_id = 'trusted-user';
  const os_user_id = 'trusted-os-user';

  late Directory directory;
  late File database_file;
  late RudraDatabase database;
  late DriftWorkflowInbox inbox;
  late WorkflowRuntime runtime;

  /// Creates an inbox with a separately trusted OS-user identity.
  DriftWorkflowInbox create_inbox() {
    return DriftWorkflowInbox(
      database: database,
      scope_id: scope_id,
      codec: runtime.codec,
      state_reader: WorkflowStateReader(
        runtime: runtime,
        history_store: DriftWorkflowHistoryStore(database: database),
        os_user_id: os_user_id,
      ),
    );
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('rudra-inbox-test-');

    database_file = File('${directory.path}/rudra.db');
    database = RudraDatabase.file(database_file);

    runtime = WorkflowRuntime.standard();
    inbox = create_inbox();
  });

  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  /// Submits a command using Rudra's existing durable
  /// acceptance implementation.
  Future<EventSubmissionReceipt> submit(
    String root, {
    String submission_scope = scope_id,
  }) {
    final manager = EventManager(
      store: DriftEventSubmissionStore(
        database: database,
        scope_id: submission_scope,
      ),
    );

    return manager.trigger(
      WorkflowStartEvent(target_id: 'local-macos', root: TargetPath(root)),
    );
  }

  test('returns null when no pending command exists', () async {
    expect(await inbox.next_pending(), isNull);
  });

  test('reads the oldest pending command without claiming it', () async {
    final first = await submit('/first');
    await submit('/second');

    final pending = await inbox.next_pending();

    expect(pending, isNotNull);
    expect(pending!.receipt.event_id, first.event_id);
    expect(pending.receipt.correlation_id, first.correlation_id);
    expect(pending.scope_id, scope_id);
    expect(pending.command, isA<WorkflowStartEvent>());
    expect((pending.command as WorkflowStartEvent).root.value, '/first');
    expect(pending.committed_events, isEmpty);

    // Reading does not claim or complete the submission.
    // The same oldest pending command remains available.
    final repeated = await inbox.next_pending();

    expect(repeated!.receipt.event_id, first.event_id);

    final rows = await database.select(database.workflowSubmissions).get();

    expect(rows, hasLength(2));
    expect(rows.every((row) => row.processing_state == 'pending'), isTrue);
  });

  test('loads validated committed history for a stop command', () async {
    final identity = WorkflowIdentity(
      workflow_id: 'workflow-1',
      os_user_id: os_user_id,
      target_id: 'local-macos',
      root: TargetPath('/workspace'),
    );

    final started = WorkflowStartedEvent(identity: identity);

    // Establish a valid journal and its ownership projection.
    // This fixture tests inbox reading, not start processing.
    await database.transaction(() async {
      await database
          .into(database.workflowEvents)
          .insert(
            WorkflowEventsCompanion.insert(
              event_id: 'committed-started',
              workflow_id: identity.workflow_id,
              os_user_id: const Value(os_user_id),
              version: 1,
              correlation_id: 'original-correlation',
              causation_id: const Value('accepted-command'),
              event_type: started.event_type,
              payload_json: runtime.codec.encode(started),
              recorded_at_unix_ms: 2,
            ),
          );

      await database
          .into(database.unfinishedWorkflows)
          .insert(
            UnfinishedWorkflowsCompanion.insert(
              os_user_id: os_user_id,
              workflow_id: identity.workflow_id,
              target_id: identity.target_id,
              root_path: identity.root.value,
              version: 1,
            ),
          );
    });

    final manager = EventManager(
      store: DriftEventSubmissionStore(
        database: database,
        scope_id: scope_id,
        codec: runtime.codec,
      ),
    );

    final receipt = await manager.trigger(
      WorkflowStopEvent(workflow_id: identity.workflow_id),
    );

    final pending = await inbox.next_pending();

    expect(pending, isNotNull);
    expect(pending!.receipt.event_id, receipt.event_id);
    expect(pending.command, isA<WorkflowStopEvent>());

    expect(pending.committed_events, hasLength(1));
    expect(pending.committed_events[0], isA<WorkflowStartedEvent>());
    expect(pending.committed_events.single, isA<WorkflowStartedEvent>());

    final restored = WorkflowStateMachine(runtime: runtime)
        .replay(pending.committed_events);

    expect(restored, isA<WorkflowSnapshot>());
    expect(restored!.version, 1);

    final active = restored;

    expect(active.identity.workflow_id, identity.workflow_id);
    expect(active.identity.os_user_id, os_user_id);

    // Inbox reads must not process or mutate a stop request.
    expect(await database.select(database.workflowEvents).get(), hasLength(1));

    expect(
      await database.select(database.unfinishedWorkflows).get(),
      hasLength(1),
    );

    final submissions = await database
        .select(database.workflowSubmissions)
        .get();

    expect(submissions.single.processing_state, 'pending');
  });

  test('filters by scope and pending processing status', () async {
    await submit('/foreign', submission_scope: 'another-user');

    final completed = await submit('/completed');

    // Simulate a submission completed by a committer.
    await (database.update(
      database.workflowSubmissions,
    )..where((row) => row.event_id.equals(completed.event_id))).write(
      const WorkflowSubmissionsCompanion(processing_state: Value('completed')),
    );

    final eligible = await submit('/eligible');

    final pending = await inbox.next_pending();

    expect(pending, isNotNull);
    expect(pending!.receipt.event_id, eligible.event_id);
    expect((pending.command as WorkflowStartEvent).root.value, '/eligible');
  });

  test('recovers pending submissions after reopening', () async {
    final receipt = await submit('/workspace');

    await database.close();

    // A completely new SQLite connection must observe
    // the previously committed submission.
    database = RudraDatabase.file(database_file);

    inbox = create_inbox();

    final pending = await inbox.next_pending();

    expect(pending, isNotNull);
    expect(pending!.receipt.event_id, receipt.event_id);
    expect((pending.command as WorkflowStartEvent).root.value, '/workspace');
  });

  test('does not silently skip malformed commands', () async {
    await database
        .into(database.workflowSubmissions)
        .insert(
          WorkflowSubmissionsCompanion.insert(
            event_id: 'invalid-event',
            correlation_id: 'invalid-correlation',
            scope_id: scope_id,
            event_type: WorkflowStartEvent.type_id,
            payload_json: '{"schema_version":999}',
            accepted_at_unix_ms: 0,
          ),
        );

    // A corrupted accepted command cannot silently vanish
    // from the processing obligation.
    await expectLater(inbox.next_pending(), throwsFormatException);
  });

  test('quarantines unreadable command and advances inbox', () async {
    const invalid_payload = '{"schema_version":999}';

    // Insert an unreadable accepted submission directly.
    // The normal public submission API would refuse to
    // create malformed event data.
    await database
        .into(database.workflowSubmissions)
        .insert(
          WorkflowSubmissionsCompanion.insert(
            event_id: 'unreadable-event',
            correlation_id: 'unreadable-correlation',
            scope_id: scope_id,
            event_type: WorkflowStartEvent.type_id,
            payload_json: invalid_payload,
            accepted_at_unix_ms: 0,
          ),
        );

    final valid_receipt = await submit('/next-workspace');

    late WorkflowInboxDecodingException issue;

    try {
      await inbox.next_pending();
      fail('Expected the unreadable submission to be reported.');
    } on WorkflowInboxDecodingException catch (error) {
      issue = error;
    }

    expect(issue.receipt.event_id, 'unreadable-event');
    expect(issue.code, WorkflowQuarantineCode.undecodable_command);

    final quarantine_store = DriftWorkflowQuarantineStore(
      database: database,
      scope_id: scope_id,
    );

    await quarantine_store.quarantine(issue);

    // The accepted evidence must remain unchanged.
    final stored = await (database.select(
      database.workflowSubmissions,
    )..where((row) => row.event_id.equals('unreadable-event'))).getSingle();

    expect(stored.processing_state, 'quarantined');
    expect(stored.event_type, WorkflowStartEvent.type_id);
    expect(stored.payload_json, invalid_payload);
    expect(stored.correlation_id, 'unreadable-correlation');
    expect(stored.quarantine_code, 'undecodable_command');
    expect(stored.quarantine_diagnostic, isNotEmpty);
    expect(stored.quarantined_at_unix_ms, isNotNull);

    // Quarantine must not fabricate workflow journal events
    // or claim unfinished-workflow ownership.
    expect(await database.select(database.workflowEvents).get(), isEmpty);
    expect(await database.select(database.unfinishedWorkflows).get(), isEmpty);

    // The next valid pending submission becomes eligible.
    final next = await inbox.next_pending();

    expect(next, isNotNull);
    expect(next!.receipt.event_id, valid_receipt.event_id);

    // Frontends can query the outcome by the original receipt.
    final status_reader = DriftWorkflowStatusReader(
      database: database,
      scope_id: scope_id,
      os_user_id: os_user_id,
      runtime: runtime,
    );

    final status = await status_reader.status_for(issue.receipt);

    expect(status, isNotNull);
    expect(status!.state, WorkflowSubmissionState.quarantined);
    expect(status.quarantine_code, WorkflowQuarantineCode.undecodable_command);
    expect(status.quarantined_at_unix_ms, isNotNull);

    // A second attempt cannot overwrite the recorded resolution.
    await expectLater(
      quarantine_store.quarantine(issue),
      throwsA(
        isA<WorkflowCommitException>().having(
          (error) => error.code,
          'code',
          WorkflowCommitErrorCode.stale_submission,
        ),
      ),
    );

    // Close the existing connection before reopening the
    // database, preserving the one-owner-per-fixture rule.
    await database.close();

    database = RudraDatabase.file(database_file);

    inbox = create_inbox();

    final recovered_status = await DriftWorkflowStatusReader(
      database: database,
      scope_id: scope_id,
      os_user_id: os_user_id,
      runtime: runtime,
    ).status_for(issue.receipt);

    expect(recovered_status, isNotNull);
    expect(recovered_status!.state, WorkflowSubmissionState.quarantined);
    expect(
      recovered_status.quarantine_code,
      WorkflowQuarantineCode.undecodable_command,
    );

    // The valid submission remains eligible after restart.
    final recovered_pending = await inbox.next_pending();

    expect(recovered_pending, isNotNull);
    expect(recovered_pending!.receipt.event_id, valid_receipt.event_id);
  });

  test('quarantines an outcome stored as a command', () async {
    final codec = WorkflowEventCodec.standard();

    final outcome = WorkflowEndedEvent(
      workflow_id: 'workflow-that-was-not-started',
    );

    await database
        .into(database.workflowSubmissions)
        .insert(
          WorkflowSubmissionsCompanion.insert(
            event_id: 'invalid-command',
            correlation_id: 'invalid-command-correlation',
            scope_id: scope_id,
            event_type: outcome.event_type,
            payload_json: codec.encode(outcome),
            accepted_at_unix_ms: 0,
          ),
        );

    late WorkflowInboxDecodingException issue;

    try {
      await inbox.next_pending();
      fail('Expected a non-command event to be rejected by the inbox.');
    } on WorkflowInboxDecodingException catch (error) {
      issue = error;
    }

    expect(issue.code, WorkflowQuarantineCode.non_command_event);

    await DriftWorkflowQuarantineStore(
      database: database,
      scope_id: scope_id,
    ).quarantine(issue);

    final status = await DriftWorkflowStatusReader(
      database: database,
      scope_id: scope_id,
      os_user_id: os_user_id,
      runtime: runtime,
    ).status_for(issue.receipt);

    expect(status!.state, WorkflowSubmissionState.quarantined);
    expect(status.quarantine_code, WorkflowQuarantineCode.non_command_event);

    expect(await inbox.next_pending(), isNull);
    expect(await database.select(database.workflowEvents).get(), isEmpty);
  });

  test('does not quarantine a submission modified after reading', () async {
    await database
        .into(database.workflowSubmissions)
        .insert(
          WorkflowSubmissionsCompanion.insert(
            event_id: 'changing-event',
            correlation_id: 'changing-correlation',
            scope_id: scope_id,
            event_type: WorkflowStartEvent.type_id,
            payload_json: '{"schema_version":999}',
            accepted_at_unix_ms: 0,
          ),
        );

    late WorkflowInboxDecodingException issue;

    try {
      await inbox.next_pending();
      fail('Expected unreadable submission.');
    } on WorkflowInboxDecodingException catch (error) {
      issue = error;
    }

    // Simulate another writer changing the persisted payload
    // between the inbox read and the quarantine attempt.
    await (database.update(
      database.workflowSubmissions,
    )..where((row) => row.event_id.equals('changing-event'))).write(
      const WorkflowSubmissionsCompanion(
        payload_json: Value('{"schema_version":998}'),
      ),
    );

    final quarantiner = DriftWorkflowQuarantineStore(
      database: database,
      scope_id: scope_id,
    );

    await expectLater(
      quarantiner.quarantine(issue),
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

    expect(stored.processing_state, 'pending');
    expect(stored.quarantine_code, isNull);
  });
}
