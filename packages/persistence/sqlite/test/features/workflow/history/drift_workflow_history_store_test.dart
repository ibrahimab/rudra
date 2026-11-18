import 'dart:io';

import 'package:drift/drift.dart' show Value, Variable;
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

import 'package:rudra_persistence_sqlite/src/database/rudra_database.dart'
    hide WorkflowEvent;
import 'package:rudra_persistence_sqlite/src/features/workflow/history/drift_workflow_committer.dart';
import 'package:rudra_persistence_sqlite/src/features/workflow/history/drift_workflow_history_store.dart';
import 'package:rudra_persistence_sqlite/src/features/workflow/submissions/drift_event_submission_store.dart';
import 'package:rudra_persistence_sqlite/src/features/workflow/submissions/drift_workflow_inbox.dart';
import 'package:rudra_persistence_sqlite/src/features/workflow/submissions/drift_workflow_quarantine_store.dart';
import 'package:rudra_persistence_sqlite/src/features/workflow/submissions/drift_workflow_rejection_store.dart';

/// Verifies committed workflow restoration from real SQLite.
///
/// Every test owns one database connection at a time.
/// Restart tests close the existing owner before reopening.
///
/// No actual filesystem inspection or cleanup is performed.
void main() {
  const scope_id = 'submission-scope';
  const os_user_id = 'trusted-os-user';
  const workflow_id = 'workflow-1';

  late Directory directory;
  late File database_file;
  late RudraDatabase database;
  late WorkflowRuntime runtime;
  late DriftWorkflowHistoryStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'rudra-history-reader-test-',
    );

    database_file = File('${directory.path}/rudra.db');
    database = RudraDatabase.file(database_file);

    runtime = WorkflowRuntime.standard();
    store = DriftWorkflowHistoryStore(database: database);
  });

  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  /// Creates a real submission manager over the test database.
  EventManager submission_manager() {
    return EventManager(
      store: DriftEventSubmissionStore(
        database: database,
        scope_id: scope_id,
        codec: runtime.codec,
      ),
    );
  }

  /// Constructs an SDK reader with trusted identity supplied
  /// independently of the submission scope.
  WorkflowStateReader state_reader({String trusted_user = os_user_id}) {
    return WorkflowStateReader(
      runtime: runtime,
      history_store: store,
      os_user_id: trusted_user,
    );
  }

  /// Establishes a workflow through actual production contracts.
  ///
  /// The processor validates the lifecycle and the committer
  /// atomically records the journal, projection, and completion.
  Future<void> establish_workflow() async {
    await submission_manager().trigger(
      WorkflowStartEvent(
        target_id: 'local-macos',
        root: TargetPath('/workspace'),
      ),
    );

    final processor = WorkflowProcessor(
      runtime: runtime,
      inbox: DriftWorkflowInbox(
        database: database,
        scope_id: scope_id,
        codec: runtime.codec,
      ),
      identity_provider: const _TestIdentityProvider(
        workflow_id: workflow_id,
        os_user_id: os_user_id,
      ),
      committer: DriftWorkflowCommitter(
        database: database,
        scope_id: scope_id,
        runtime: runtime,
      ),
      rejector: DriftWorkflowRejectionStore(
        database: database,
        scope_id: scope_id,
        codec: runtime.codec,
      ),
      quarantiner: DriftWorkflowQuarantineStore(
        database: database,
        scope_id: scope_id,
      ),
    );

    expect(await processor.process_next(), isA<WorkflowProcessingCommitted>());
  }

  /// Verifies that a corrupted persisted snapshot fails closed.
  Future<void> expect_restoration_failure(
    WorkflowStateReadErrorCode expected_code,
  ) async {
    await expectLater(
      state_reader().current(),
      throwsA(
        isA<WorkflowStateReadException>().having(
          (error) => error.code,
          'code',
          expected_code,
        ),
      ),
    );
  }

  group('DriftWorkflowHistoryStore', () {
    test('returns null when no workflow has been established', () async {
      expect(await state_reader().current(), isNull);

      expect(await database.select(database.workflowEvents).get(), isEmpty);

      expect(
        await database.select(database.unfinishedWorkflows).get(),
        isEmpty,
      );
    });

    test('does not process accepted pending submissions', () async {
      await submission_manager().trigger(
        WorkflowStartEvent(
          target_id: 'local-macos',
          root: TargetPath('/workspace'),
        ),
      );

      expect(await state_reader().current(), isNull);

      final submissions = await database
          .select(database.workflowSubmissions)
          .get();

      expect(submissions, hasLength(1));
      expect(submissions.single.processing_state, 'pending');

      expect(await database.select(database.workflowEvents).get(), isEmpty);
    });

    test('restores authoritative committed workflow state', () async {
      await establish_workflow();

      final snapshot = (await store.load_restoration_evidence(
        os_user_id: os_user_id,
      )).projected;

      expect(snapshot, isNotNull);
      expect(snapshot!.projected_version, 2);
      expect(snapshot.journal, hasLength(2));

      expect(
        snapshot.journal.map((entry) => entry.version),
        orderedEquals([1, 2]),
      );

      expect(
        snapshot.journal.map((entry) => entry.event_type),
        orderedEquals([
          WorkflowStartEvent.type_id,
          WorkflowStartedEvent.type_id,
        ]),
      );

      final restored = await state_reader().current();

      expect(restored, isNotNull);
      expect(restored!.version, 2);
      expect(restored.identity.workflow_id, workflow_id);
      expect(restored.identity.os_user_id, os_user_id);
      expect(restored.identity.target_id, 'local-macos');
      expect(restored.identity.root.value, '/workspace');
    });

    test('does not expose another OS user workflow', () async {
      await establish_workflow();

      final foreign = await state_reader(trusted_user: 'another-os-user')
          .current();

      expect(foreign, isNull);

      // The legitimate owner can still restore its state.
      expect(await state_reader().current(), isNotNull);
    });

    test('recovers state after a complete database restart', () async {
      await establish_workflow();

      await database.close();

      // The previous database owner is closed before creating
      // a replacement. No connections overlap.
      database = RudraDatabase.file(database_file);
      store = DriftWorkflowHistoryStore(database: database);

      final restored = await state_reader().current();

      expect(restored, isA<WorkflowActiveState>());
      expect(restored!.version, 2);
      expect(restored.identity.workflow_id, workflow_id);
      expect(restored.identity.root.value, '/workspace');

      final submissions = await database
          .select(database.workflowSubmissions)
          .get();

      expect(submissions.single.processing_state, 'completed');
    });

    test('restoration performs no persistence writes', () async {
      await establish_workflow();

      final events_before = await database
          .select(database.workflowEvents)
          .get();

      final projections_before = await database
          .select(database.unfinishedWorkflows)
          .get();

      final submissions_before = await database
          .select(database.workflowSubmissions)
          .get();

      await state_reader().current();
      await state_reader().current();

      expect(
        await database.select(database.workflowEvents).get(),
        orderedEquals(events_before),
      );

      expect(
        await database.select(database.unfinishedWorkflows).get(),
        orderedEquals(projections_before),
      );

      expect(
        await database.select(database.workflowSubmissions).get(),
        orderedEquals(submissions_before),
      );
    });

    test('rejects a stale unfinished projection version', () async {
      await establish_workflow();

      await database
          .update(database.unfinishedWorkflows)
          .write(const UnfinishedWorkflowsCompanion(version: Value(1)));

      await expect_restoration_failure(
        WorkflowStateReadErrorCode.projection_mismatch,
      );
    });

    test('rejects altered original target bindings', () async {
      await establish_workflow();

      await database
          .update(database.unfinishedWorkflows)
          .write(
            const UnfinishedWorkflowsCompanion(
              target_id: Value('different-target'),
            ),
          );

      await expect_restoration_failure(
        WorkflowStateReadErrorCode.projection_mismatch,
      );
    });

    test('rejects altered original root bindings', () async {
      await establish_workflow();

      await database
          .update(database.unfinishedWorkflows)
          .write(
            const UnfinishedWorkflowsCompanion(
              root_path: Value('/different-root'),
            ),
          );

      await expect_restoration_failure(
        WorkflowStateReadErrorCode.projection_mismatch,
      );
    });

    test('rejects missing committed journal events', () async {
      await establish_workflow();

      await database.delete(database.workflowEvents).go();

      await expect_restoration_failure(
        WorkflowStateReadErrorCode.invalid_journal,
      );
    });

    test('rejects a gap in journal versions', () async {
      await establish_workflow();

      await (database.update(database.workflowEvents)
            ..where((row) => row.version.equals(2)))
          .write(const WorkflowEventsCompanion(version: Value(3)));

      await expect_restoration_failure(
        WorkflowStateReadErrorCode.invalid_journal,
      );
    });

    test('rejects an unreadable committed event', () async {
      await establish_workflow();

      await (database.update(
        database.workflowEvents,
      )..where((row) => row.version.equals(2))).write(
        const WorkflowEventsCompanion(payload_json: Value('invalid-json')),
      );

      await expect_restoration_failure(
        WorkflowStateReadErrorCode.invalid_event,
      );
    });

    test('rejects a different journal owner', () async {
      await establish_workflow();

      final foreign_event = WorkflowStartedEvent(
        identity: WorkflowIdentity(
          workflow_id: workflow_id,
          os_user_id: 'different-owner',
          target_id: 'local-macos',
          root: TargetPath('/workspace'),
        ),
      );

      await (database.update(
        database.workflowEvents,
      )..where((row) => row.version.equals(2))).write(
        WorkflowEventsCompanion(
          payload_json: Value(runtime.codec.encode(foreign_event)),
        ),
      );

      await expect_restoration_failure(
        WorkflowStateReadErrorCode.ownership_mismatch,
      );
    });

    test('rejects blank OS-user identifiers', () async {
      await expectLater(
        store.load_restoration_evidence(os_user_id: ' '),
        throwsArgumentError,
      );
    });

    test('detects orphaned active workflow after restart', () async {
      await establish_workflow();

      // Simulate corruption by removing only the derived projection.
      // The authoritative committed journal remains unchanged.
      await database.delete(database.unfinishedWorkflows).go();

      await database.close();

      // Reopen only after releasing the previous database owner.
      database = RudraDatabase.file(database_file);
      store = DriftWorkflowHistoryStore(database: database);

      await expect_restoration_failure(
        WorkflowStateReadErrorCode.orphaned_workflow,
      );

      // Failed restoration must never recreate the missing projection.
      expect(
        await database.select(database.unfinishedWorkflows).get(),
        isEmpty,
      );

      expect(
        await database.select(database.workflowEvents).get(),
        hasLength(2),
      );
    });

    test('detects a workflow projected under another OS user', () async {
      await establish_workflow();

      // Simulate a corrupted ownership projection.
      await database
          .update(database.unfinishedWorkflows)
          .write(
            const UnfinishedWorkflowsCompanion(
              os_user_id: Value('incorrect-os-user'),
            ),
          );

      // The original owner must not be told that no workflow exists.
      await expect_restoration_failure(
        WorkflowStateReadErrorCode.orphaned_workflow,
      );
    });

    test('does not expose a foreign orphan as the current workflow', () async {
      await establish_workflow();

      await database.delete(database.unfinishedWorkflows).go();

      final foreign = await state_reader(trusted_user: 'another-os-user')
          .current();

      expect(foreign, isNull);

      // The actual owner still receives the integrity failure.
      await expect_restoration_failure(
        WorkflowStateReadErrorCode.orphaned_workflow,
      );
    });

    test('accepts terminal history with no unfinished projection', () async {
      await establish_workflow();

      final committed = await database.select(database.workflowEvents).get();

      final correlation_id = committed.first.correlation_id;

      // Simulate a future valid terminal commitment.
      // Production terminal processing is not implemented yet.
      await database.transaction(() async {
        final events = <WorkflowEvent>[
          WorkflowStopEvent(workflow_id: workflow_id),
          WorkflowEndedEvent(workflow_id: workflow_id),
        ];

        for (final (index, event) in events.indexed) {
          await database
              .into(database.workflowEvents)
              .insert(
                WorkflowEventsCompanion.insert(
                  event_id: 'terminal-event-${index + 1}',
                  workflow_id: workflow_id,
                  version: index + 3,
                  correlation_id: correlation_id,
                  event_type: event.event_type,
                  payload_json: runtime.codec.encode(event),
                  recorded_at_unix_ms: DateTime.now()
                      .toUtc()
                      .millisecondsSinceEpoch,
                ),
              );
        }

        await database.delete(database.unfinishedWorkflows).go();
      });

      expect(await state_reader().current(), isNull);

      final journal = await database.select(database.workflowEvents).get();

      expect(journal, hasLength(4));
    });

    test('does not replay unrelated malformed user history', () async {
      await establish_workflow();

      const foreign_workflow_id = 'foreign-workflow';

      final foreign_identity = WorkflowIdentity(
        workflow_id: foreign_workflow_id,
        os_user_id: 'foreign-os-user',
        target_id: 'local-macos',
        root: TargetPath('/foreign-root'),
      );

      // This first event is deliberately malformed.
      //
      // Its metadata is valid, but its payload cannot be
      // decoded by the SDK.
      await database
          .into(database.workflowEvents)
          .insert(
            WorkflowEventsCompanion.insert(
              event_id: 'foreign-start-event',
              workflow_id: foreign_workflow_id,
              version: 1,
              correlation_id: 'foreign-correlation',
              event_type: WorkflowStartEvent.type_id,
              payload_json: 'invalid-json',
              recorded_at_unix_ms: 1,
            ),
          );

      // The authoritative ownership outcome remains valid.
      // SQLite automatically indexes this user's identity.
      await database
          .into(database.workflowEvents)
          .insert(
            WorkflowEventsCompanion.insert(
              event_id: 'foreign-started-event',
              workflow_id: foreign_workflow_id,
              os_user_id: const Value('foreign-os-user'),
              version: 2,
              correlation_id: 'foreign-correlation',
              event_type: WorkflowStartedEvent.type_id,
              payload_json: runtime.codec.encode(
                WorkflowStartedEvent(identity: foreign_identity),
              ),
              recorded_at_unix_ms: 2,
            ),
          );

      // The legitimate user must not replay foreign history.
      final restored = await state_reader().current();

      expect(restored, isNotNull);
      expect(restored!.identity.workflow_id, workflow_id);

      // The malformed journal must still be detected when its
      // actual owner requests restoration.
      await expectLater(
        state_reader(trusted_user: 'foreign-os-user').current(),
        throwsA(
          isA<WorkflowStateReadException>().having(
            (error) => error.code,
            'code',
            WorkflowStateReadErrorCode.invalid_event,
          ),
        ),
      );
    });

    test('uses the workflow-owner index for restoration lookup', () async {
      await establish_workflow();

      final plan = await database
          .customSelect(
            '''
          EXPLAIN QUERY PLAN
          SELECT DISTINCT workflow_id
          FROM workflow_events
          WHERE os_user_id = ?
        ''',
            variables: [Variable.withString(os_user_id)],
          )
          .get();

      final details = plan.map((row) => row.read<String>('detail')).join('\n');

      expect(details, contains('workflow_events_owner_idx'));
    });

    test('detects corrupted owner event without a projection', () async {
      await establish_workflow();

      await (database.update(
        database.workflowEvents,
      )..where((row) => row.version.equals(2))).write(
        const WorkflowEventsCompanion(payload_json: Value('invalid-json')),
      );

      await database.delete(database.unfinishedWorkflows).go();

      // Independent owner metadata locates the journal.
      // The SDK still detects its invalid event payload.
      await expect_restoration_failure(
        WorkflowStateReadErrorCode.invalid_event,
      );
    });

    test('rejects changed event owner without a projection', () async {
      await establish_workflow();

      final altered_event = WorkflowStartedEvent(
        identity: WorkflowIdentity(
          workflow_id: workflow_id,
          os_user_id: 'another-os-user',
          target_id: 'local-macos',
          root: TargetPath('/workspace'),
        ),
      );

      await (database.update(
        database.workflowEvents,
      )..where((row) => row.version.equals(2))).write(
        WorkflowEventsCompanion(
          payload_json: Value(runtime.codec.encode(altered_event)),
        ),
      );

      await database.delete(database.unfinishedWorkflows).go();

      // Journal metadata still identifies the original owner.
      // The SDK must not silently return "no workflow".
      await expect_restoration_failure(
        WorkflowStateReadErrorCode.ownership_mismatch,
      );
    });
  });
}

/// Deterministic trusted identity provider for integration tests.
///
/// This substitutes the native identity boundary only.
/// Workflow processing and persistence remain real.
final class _TestIdentityProvider implements WorkflowIdentityProvider {
  /// Creates an identity provider with fixed test identities.
  const _TestIdentityProvider({
    required this.workflow_id,
    required this.os_user_id,
  });

  /// Workflow identifier used for establishment.
  final String workflow_id;

  /// Trusted owner supplied independently of the submission.
  final String os_user_id;

  /// Proposes an identity using the command's immutable bindings.
  @override
  Future<WorkflowIdentity> propose_identity(
    PendingWorkflowCommand submission,
  ) async {
    final command = submission.command;

    if (command is! WorkflowStartEvent) {
      throw StateError('Expected a workflow start command.');
    }

    return WorkflowIdentity(
      workflow_id: workflow_id,
      os_user_id: os_user_id,
      target_id: command.target_id,
      root: command.root,
    );
  }
}
