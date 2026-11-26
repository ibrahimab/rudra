import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:rudra_persistence_sqlite/rudra_persistence_sqlite.dart';
import 'package:rudra_persistence_sqlite/src/database/rudra_database.dart'
    hide WorkflowEvent;
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Verifies durable idempotency, recovery and serialized application
/// execution against real SQLite persistence.
void main() {
  late _ExecutionFixture fixture;

  setUp(() async {
    fixture = await _ExecutionFixture.create();
  });

  tearDown(() async {
    await fixture.dispose();
  });

  group('durable idempotency', () {
    test('identical Starts preserve the original durable resolution', () async {
      final first = _completed(await fixture.start('start-001'));
      final retry = _completed(await fixture.start('start-001'));

      _expect_same_resolution(first, retry);

      expect(fixture.identities.proposal_count, 1);

      await fixture.verify_evidence(
        states: ['completed'],
        outcomes: [WorkflowStartedEvent.type_id],
        notifications: 1,
      );
    });

    test('identical Stops preserve the original durable resolution', () async {
      final started = _completed(await fixture.start('start-001'));
      final workflow_id = started.committed_outcome!.workflow_id;

      final first = _completed(await fixture.stop('stop-001', workflow_id));

      final retry = _completed(await fixture.stop('stop-001', workflow_id));

      _expect_same_resolution(first, retry);

      expect(await fixture.current(), isNull);

      await fixture.verify_evidence(
        states: ['completed', 'completed'],
        outcomes: [WorkflowStartedEvent.type_id, WorkflowEndedEvent.type_id],
        notifications: 2,
      );
    });

    test('rejects conflicting reuse of a Start operation key', () async {
      final original = _completed(await fixture.start('start-001'));

      final different_root = await fixture.start(
        'start-001',
        root: '/different-root',
      );

      final different_target = await fixture.start(
        'start-001',
        target_id: 'different-target',
      );

      expect(different_root, isA<WorkflowOperationIdempotencyConflict>());
      expect(different_target, isA<WorkflowOperationIdempotencyConflict>());

      final retry = _completed(await fixture.start('start-001'));

      _expect_same_resolution(original, retry);

      await fixture.verify_evidence(
        states: ['completed'],
        outcomes: [WorkflowStartedEvent.type_id],
        notifications: 1,
      );
    });

    test('rejects conflicting reuse of a Stop operation key', () async {
      final started = _completed(await fixture.start('start-001'));
      final workflow_id = started.committed_outcome!.workflow_id;

      final stopped = _completed(await fixture.stop('stop-001', workflow_id));

      final conflict = await fixture.stop('stop-001', 'different-workflow');

      expect(conflict, isA<WorkflowOperationIdempotencyConflict>());

      final retry = _completed(await fixture.stop('stop-001', workflow_id));

      _expect_same_resolution(stopped, retry);

      await fixture.verify_evidence(
        states: ['completed', 'completed'],
        outcomes: [WorkflowStartedEvent.type_id, WorkflowEndedEvent.type_id],
        notifications: 2,
      );
    });

    test('rejects reuse of a key for a different command type', () async {
      final started = _completed(await fixture.start('operation-001'));

      final conflict = await fixture.stop(
        'operation-001',
        started.committed_outcome!.workflow_id,
      );

      expect(conflict, isA<WorkflowOperationIdempotencyConflict>());

      expect(
        (await fixture.current())!.identity.workflow_id,
        started.committed_outcome!.workflow_id,
      );

      await fixture.verify_evidence(
        states: ['completed'],
        outcomes: [WorkflowStartedEvent.type_id],
        notifications: 1,
      );
    });
  });

  group('historical resolutions', () {
    test(
      'retrying Start after termination does not establish a workflow',
      () async {
        final original = _completed(await fixture.start('start-001'));

        _completed(
          await fixture.stop(
            'stop-001',
            original.committed_outcome!.workflow_id,
          ),
        );

        final retry = _completed(await fixture.start('start-001'));

        _expect_same_resolution(original, retry);

        expect(await fixture.current(), isNull);
        expect(fixture.identities.proposal_count, 1);

        await fixture.verify_evidence(
          states: ['completed', 'completed'],
          outcomes: [WorkflowStartedEvent.type_id, WorkflowEndedEvent.type_id],
          notifications: 2,
        );
      },
    );

    test(
      'historical Start and Stop retries preserve a replacement workflow',
      () async {
        final original = _completed(await fixture.start('start-001'));
        final original_id = original.committed_outcome!.workflow_id;

        final stopped = _completed(await fixture.stop('stop-001', original_id));

        final replacement = _completed(
          await fixture.start('start-002', root: '/replacement'),
        );

        final replacement_id = replacement.committed_outcome!.workflow_id;

        expect(replacement_id, isNot(original_id));

        final start_retry = _completed(await fixture.start('start-001'));

        final stop_retry = _completed(
          await fixture.stop('stop-001', original_id),
        );

        _expect_same_resolution(original, start_retry);
        _expect_same_resolution(stopped, stop_retry);

        final current = await fixture.current();

        expect(current!.identity.workflow_id, replacement_id);
        expect(current.identity.root.value, '/replacement');
        expect(current.version, 1);
        expect(fixture.identities.proposal_count, 2);

        await fixture.verify_evidence(
          states: ['completed', 'completed', 'completed'],
          outcomes: [
            WorkflowStartedEvent.type_id,
            WorkflowEndedEvent.type_id,
            WorkflowStartedEvent.type_id,
          ],
          notifications: 3,
        );
      },
    );

    test(
      'a rejected Start remains rejected after ownership is released',
      () async {
        final original = _completed(await fixture.start('start-001'));

        final rejected = _rejected(
          await fixture.start('start-002', root: '/second'),
          WorkflowRejectionCode.ownership_conflict,
        );

        _completed(
          await fixture.stop(
            'stop-001',
            original.committed_outcome!.workflow_id,
          ),
        );

        final retry = _rejected(
          await fixture.start('start-002', root: '/second'),
          WorkflowRejectionCode.ownership_conflict,
        );

        _expect_same_resolution(rejected, retry);

        expect(await fixture.current(), isNull);

        // A new key represents a new intention and may succeed.
        _completed(await fixture.start('start-003', root: '/second'));

        await fixture.verify_evidence(
          states: ['completed', 'rejected', 'completed', 'completed'],
          outcomes: [
            WorkflowStartedEvent.type_id,
            WorkflowEndedEvent.type_id,
            WorkflowStartedEvent.type_id,
          ],
          notifications: 3,
        );
      },
    );

    test(
      'a rejected Stop remains rejected after its target is established',
      () async {
        final rejected = _rejected(
          await fixture.stop('stop-001', 'workflow-1'),
          WorkflowRejectionCode.workflow_not_active,
        );

        final started = _completed(await fixture.start('start-001'));

        expect(started.committed_outcome!.workflow_id, 'workflow-1');

        final retry = _rejected(
          await fixture.stop('stop-001', 'workflow-1'),
          WorkflowRejectionCode.workflow_not_active,
        );

        _expect_same_resolution(rejected, retry);

        expect((await fixture.current())!.identity.workflow_id, 'workflow-1');

        _completed(await fixture.stop('stop-002', 'workflow-1'));

        await fixture.verify_evidence(
          states: ['rejected', 'completed', 'completed'],
          outcomes: [WorkflowStartedEvent.type_id, WorkflowEndedEvent.type_id],
          notifications: 2,
        );
      },
    );
  });

  group('durable recovery', () {
    test('read-only queries do not process an accepted command', () async {
      final receipt = await fixture.accept_start('start-001');

      final status = await fixture.application.status_for(receipt);

      expect(status!.state, WorkflowSubmissionState.pending);
      expect(status.committed_outcome, isNull);
      expect(await fixture.current(), isNull);
      expect(fixture.identities.proposal_count, 0);

      await fixture.verify_evidence(
        states: ['pending'],
        outcomes: [],
        notifications: 0,
      );
    });

    test('resumes pending acceptance after reopening persistence', () async {
      final receipt = await fixture.accept_start('start-001');

      await fixture.close();
      fixture.open();

      final pending = await fixture.application.status_for(receipt);

      expect(pending!.state, WorkflowSubmissionState.pending);
      expect(await fixture.current(), isNull);

      final completed = _completed(await fixture.start('start-001'));

      _expect_same_receipt(receipt, completed.receipt);

      expect(completed.committed_outcome!.version, 1);
      expect(fixture.identities.proposal_count, 1);

      await fixture.verify_evidence(
        states: ['completed'],
        outcomes: [WorkflowStartedEvent.type_id],
        notifications: 1,
      );
    });

    test('recovers a committed Start whose response was lost', () async {
      final receipt = await fixture.accept_start('start-001');

      final processed = await fixture.application.process_next();

      expect(processed, isA<WorkflowProcessingCommitted>());

      final plan = (processed as WorkflowProcessingCommitted).plan;
      final workflow_id = plan.resulting_state.identity.workflow_id;

      // Simulate interruption after commitment but before the frontend
      // receives its operation response.
      await fixture.close();
      fixture.open();

      final retry = _completed(await fixture.start('start-001'));

      _expect_same_receipt(receipt, retry.receipt);

      expect(retry.committed_outcome!.workflow_id, workflow_id);
      expect(retry.committed_outcome!.version, 1);
      expect(fixture.identities.proposal_count, 1);

      await fixture.verify_evidence(
        states: ['completed'],
        outcomes: [WorkflowStartedEvent.type_id],
        notifications: 1,
      );
    });

    test('recovers a committed Stop after reopening persistence', () async {
      final started = _completed(await fixture.start('start-001'));
      final workflow_id = started.committed_outcome!.workflow_id;

      final original = _completed(await fixture.stop('stop-001', workflow_id));

      await fixture.close();
      fixture.open();

      final retry = _completed(await fixture.stop('stop-001', workflow_id));

      _expect_same_resolution(original, retry);

      expect(await fixture.current(), isNull);

      await fixture.verify_evidence(
        states: ['completed', 'completed'],
        outcomes: [WorkflowStartedEvent.type_id, WorkflowEndedEvent.type_id],
        notifications: 2,
      );
    });

    test('recovers the original business rejection after reopening', () async {
      final original = _rejected(
        await fixture.stop('stop-001', 'missing-workflow'),
        WorkflowRejectionCode.workflow_not_active,
      );

      await fixture.close();
      fixture.open();

      final retry = _rejected(
        await fixture.stop('stop-001', 'missing-workflow'),
        WorkflowRejectionCode.workflow_not_active,
      );

      _expect_same_resolution(original, retry);

      final queried = await fixture.application.status_for(original.receipt);

      _expect_same_resolution(original, queried!);

      await fixture.verify_evidence(
        states: ['rejected'],
        outcomes: [],
        notifications: 0,
      );
    });

    test('recovers a quarantined submission after reopening', () async {
      final receipt = await fixture.accept_start('start-001');

      // Deliberately corrupt the accepted payload. The fixture closes
      // application persistence before opening its inspection connection.
      await fixture.inspect((database) async {
        await (database.update(
          database.workflowSubmissions,
        )..where((row) => row.event_id.equals(receipt.event_id))).write(
          const WorkflowSubmissionsCompanion(
            payload_json: Value('{"schema_version":'),
          ),
        );
      });

      fixture.open();

      final processed = await fixture.application.process_next();

      expect(processed, isA<WorkflowProcessingQuarantined>());

      final original = await fixture.application.status_for(receipt);

      expect(original!.state, WorkflowSubmissionState.quarantined);
      expect(
        original.quarantine_code,
        WorkflowQuarantineCode.undecodable_command,
      );

      expect(original.quarantine_diagnostic, isNotNull);

      await fixture.close();
      fixture.open();

      final recovered = await fixture.application.status_for(receipt);

      _expect_same_resolution(original, recovered!);

      // The original serialized command no longer matches the damaged
      // persisted payload. Key reuse must not overwrite that evidence.
      final retry = await fixture.start('start-001');

      expect(retry, isA<WorkflowOperationIdempotencyConflict>());

      expect(
        await fixture.application.process_next(),
        isA<WorkflowProcessingIdle>(),
      );

      await fixture.verify_evidence(
        states: ['quarantined'],
        outcomes: [],
        notifications: 0,
      );
    });

    test(
      'processing failure preserves acceptance for a subsequent retry',
      () async {
        final failure = StateError('Injected identity-provider failure.');

        fixture.identities.before_proposal = () async {
          throw failure;
        };

        await expectLater(fixture.start('start-001'), throwsA(same(failure)));

        // Identical acceptance must recover the existing pending receipt.
        final receipt = await fixture.accept_start('start-001');
        final pending = await fixture.application.status_for(receipt);

        expect(pending!.state, WorkflowSubmissionState.pending);
        expect(await fixture.current(), isNull);

        fixture.identities.before_proposal = null;

        final retry = _completed(await fixture.start('start-001'));

        _expect_same_receipt(receipt, retry.receipt);

        await fixture.verify_evidence(
          states: ['completed'],
          outcomes: [WorkflowStartedEvent.type_id],
          notifications: 1,
        );
      },
    );
  });

  group('concurrent application execution', () {
    test('concurrent identical Starts commit exactly once', () async {
      final results = await fixture.overlap_starts(
        first_key: 'shared-start',
        second_key: 'shared-start',
      );

      final first = _completed(results.first);
      final second = _completed(results.last);

      _expect_same_resolution(first, second);

      expect(fixture.identities.proposal_count, 1);

      await fixture.verify_evidence(
        states: ['completed'],
        outcomes: [WorkflowStartedEvent.type_id],
        notifications: 1,
      );
    });

    test(
      'concurrent distinct Starts commit one and reject the other',
      () async {
        final results = await fixture.overlap_starts(
          first_key: 'first-start',
          second_key: 'second-start',
          second_root: '/second',
        );

        final first = _completed(results.first);

        final second = _rejected(
          results.last,
          WorkflowRejectionCode.ownership_conflict,
        );

        expect(second.receipt.event_id, isNot(first.receipt.event_id));

        final current = await fixture.current();

        expect(
          current!.identity.workflow_id,
          first.committed_outcome!.workflow_id,
        );

        expect(current.identity.root.value, '/workspace');
        expect(fixture.identities.proposal_count, 1);

        await fixture.verify_evidence(
          states: ['completed', 'rejected'],
          outcomes: [WorkflowStartedEvent.type_id],
          notifications: 1,
        );
      },
    );

    test('concurrent identical Stops commit one terminal outcome', () async {
      final started = _completed(await fixture.start('start-001'));
      final workflow_id = started.committed_outcome!.workflow_id;

      final results = await Future.wait([
        fixture.stop('shared-stop', workflow_id),
        fixture.stop('shared-stop', workflow_id),
      ]);

      final first = _completed(results.first);
      final second = _completed(results.last);

      _expect_same_resolution(first, second);

      expect(await fixture.current(), isNull);

      await fixture.verify_evidence(
        states: ['completed', 'completed'],
        outcomes: [WorkflowStartedEvent.type_id, WorkflowEndedEvent.type_id],
        notifications: 2,
      );
    });

    test('concurrent distinct Stops commit one and reject the other', () async {
      final started = _completed(await fixture.start('start-001'));
      final workflow_id = started.committed_outcome!.workflow_id;

      final outcomes = await Future.wait([
        fixture.stop('first-stop', workflow_id),
        fixture.stop('second-stop', workflow_id),
      ]);

      final resolutions = outcomes.map(_resolved).toList();

      expect(
        resolutions.map((resolution) => resolution.state),
        unorderedEquals([
          WorkflowSubmissionState.completed,
          WorkflowSubmissionState.rejected,
        ]),
      );

      final committed = resolutions.singleWhere(
        (resolution) => resolution.state == WorkflowSubmissionState.completed,
      );

      final rejected = resolutions.singleWhere(
        (resolution) => resolution.state == WorkflowSubmissionState.rejected,
      );

      expect(committed.committed_outcome!.workflow_id, workflow_id);
      expect(
        rejected.rejection_code,
        WorkflowRejectionCode.workflow_not_active,
      );

      expect(await fixture.current(), isNull);

      await fixture.verify_evidence(
        states: ['completed', 'completed', 'rejected'],
        outcomes: [WorkflowStartedEvent.type_id, WorkflowEndedEvent.type_id],
        notifications: 2,
      );
    });

    test(
      'explicit processing and operation retries share the same lane',
      () async {
        final receipt = await fixture.accept_start('start-001');
        final barrier = _ProcessingBarrier();

        fixture.identities.before_proposal = barrier.hold;

        final processing = fixture.application.process_next();

        late Future<WorkflowOperationOutcome> retry;

        try {
          await barrier.entered;

          // The command is being processed but has not committed.
          final pending = await fixture.application.status_for(receipt);

          expect(pending!.state, WorkflowSubmissionState.pending);

          retry = fixture.start('start-001');
        } finally {
          barrier.release();
        }

        expect(await processing, isA<WorkflowProcessingCommitted>());

        final completed = _completed(await retry);

        _expect_same_receipt(receipt, completed.receipt);

        expect(fixture.identities.proposal_count, 1);

        await fixture.verify_evidence(
          states: ['completed'],
          outcomes: [WorkflowStartedEvent.type_id],
          notifications: 1,
        );
      },
    );
  });

  group('trusted submission scopes', () {
    test('independent scopes preserve separate operation identities', () async {
      final original = _completed(await fixture.start('shared-key'));

      await fixture.close();

      fixture.open(scope_id: 'another-scope', os_user_id: 'another-owner');

      expect(await fixture.application.status_for(original.receipt), isNull);

      final independent = _completed(
        await fixture.start('shared-key', root: '/another-root'),
      );

      expect(independent.receipt.event_id, isNot(original.receipt.event_id));

      expect(
        independent.committed_outcome!.workflow_id,
        isNot(original.committed_outcome!.workflow_id),
      );

      await fixture.close();
      fixture.open();

      expect(await fixture.application.status_for(independent.receipt), isNull);

      final retry = _completed(await fixture.start('shared-key'));

      _expect_same_resolution(original, retry);

      await fixture.verify_evidence(
        states: ['completed', 'completed'],
        outcomes: [WorkflowStartedEvent.type_id, WorkflowStartedEvent.type_id],
        notifications: 2,
      );
    });
  });
}

/// Extracts the durable resolution from [outcome].
///
/// Asserts that the operation was accepted rather than refused due
/// to conflicting idempotency-key reuse.
WorkflowSubmissionResolution _resolved(WorkflowOperationOutcome outcome) {
  expect(outcome, isA<WorkflowOperationResolved>());

  return (outcome as WorkflowOperationResolved).resolution;
}

/// Extracts and verifies a successfully committed [outcome].
WorkflowSubmissionResolution _completed(WorkflowOperationOutcome outcome) {
  final resolution = _resolved(outcome);

  expect(resolution.state, WorkflowSubmissionState.completed);
  expect(resolution.committed_outcome, isNotNull);

  return resolution;
}

/// Extracts a durable rejection classified by [code] from [outcome].
WorkflowSubmissionResolution _rejected(
  WorkflowOperationOutcome outcome,
  WorkflowRejectionCode code,
) {
  final resolution = _resolved(outcome);

  expect(resolution.state, WorkflowSubmissionState.rejected);
  expect(resolution.rejection_code, code);
  expect(resolution.rejected_at_unix_ms, isNotNull);

  return resolution;
}

/// Verifies that [actual] identifies the original accepted [expected] receipt.
void _expect_same_receipt(
  EventSubmissionReceipt expected,
  EventSubmissionReceipt actual,
) {
  expect(actual.event_id, expected.event_id);
  expect(actual.correlation_id, expected.correlation_id);
}

/// Verifies that [actual] preserves the complete durable [expected] resolution.
///
/// Compares committed references, rejection metadata and quarantine evidence
/// independently of object identity or the currently active workflow.
void _expect_same_resolution(
  WorkflowSubmissionResolution expected,
  WorkflowSubmissionResolution actual,
) {
  _expect_same_receipt(expected.receipt, actual.receipt);

  expect(actual.state, expected.state);

  expect(
    actual.committed_outcome?.workflow_id,
    expected.committed_outcome?.workflow_id,
  );

  expect(
    actual.committed_outcome?.event_type,
    expected.committed_outcome?.event_type,
  );

  expect(
    actual.committed_outcome?.version,
    expected.committed_outcome?.version,
  );

  expect(
    actual.committed_outcome?.sequence,
    expected.committed_outcome?.sequence,
  );

  expect(actual.rejection_code, expected.rejection_code);
  expect(actual.rejected_at_unix_ms, expected.rejected_at_unix_ms);

  expect(actual.quarantine_code, expected.quarantine_code);
  expect(actual.quarantine_diagnostic, expected.quarantine_diagnostic);
  expect(actual.quarantined_at_unix_ms, expected.quarantined_at_unix_ms);
}

/// Owns isolated SQLite persistence and application execution fixtures.
///
/// Each persistence lifetime retains exactly one WorkflowApplication.
/// Reopening constructs a new application and notification channel while
/// preserving the original durable database.
final class _ExecutionFixture {
  /// Binds the fixture to its owned temporary [directory].
  _ExecutionFixture(this.directory);

  /// Creates a temporary database location and opens its application context.
  ///
  /// Returns a fixture whose caller must eventually invoke [dispose].
  static Future<_ExecutionFixture> create() async {
    final directory = await Directory.systemTemp.createTemp(
      'rudra-application-execution-',
    );

    final fixture = _ExecutionFixture(directory);

    fixture.open();

    return fixture;
  }

  /// Default trusted submission namespace.
  static const default_scope_id = 'trusted-scope';

  /// Default authenticated workflow owner.
  static const default_os_user_id = 'trusted-owner';

  /// Default configured filesystem target.
  static const default_target_id = 'local-macos';

  /// Default requested filesystem root.
  static const default_root = '/workspace';

  /// Temporary directory exclusively owned by this fixture.
  final Directory directory;

  /// Database retained across persistence lifetimes.
  late final File database_file = File('${directory.path}/rudra.db');

  /// Shared immutable workflow runtime configuration.
  final WorkflowRuntime runtime = WorkflowRuntime.standard();

  /// Deterministic workflow identity source retained across reopening.
  final _IdentityProvider identities = _IdentityProvider();

  /// Current persistence owner, or null when closed.
  RudraSqlitePersistence? _persistence;

  /// Retained application for the current persistence lifetime.
  late WorkflowApplication application;

  /// Number of committed-change notifications across all fixture lifetimes.
  ///
  /// Historical resolution recovery must never publish a new commit signal.
  int notification_count = 0;

  /// Opens a new application bound to [scope_id] and [os_user_id].
  ///
  /// Throws [StateError] when another persistence context remains open.
  /// The identifiers originate from trusted fixture composition.
  void open({
    String scope_id = default_scope_id,
    String os_user_id = default_os_user_id,
  }) {
    if (_persistence != null) {
      throw StateError('Fixture persistence is already open.');
    }

    final persistence = RudraSqlitePersistence(
      database_file: database_file,
      scope_id: scope_id,
      runtime: runtime,
    );

    _persistence = persistence;

    identities.os_user_id = os_user_id;

    application = WorkflowApplication(
      runtime: runtime,
      persistence: persistence,
      identity_provider: identities,
      os_user_id: os_user_id,
    );

    // Subscribe to raw commit signals instead of reconciled snapshots,
    // which may legitimately coalesce consecutive state changes.
    persistence.workflow_commit_subscriber.watch(os_user_id: os_user_id).listen(
      (_) {
        notification_count++;
      },
    );
  }

  /// Accepts an identified Start using [key], [root] and [target_id].
  ///
  /// Returns the original durable acceptance receipt without processing.
  Future<EventSubmissionReceipt> accept_start(
    String key, {
    String root = default_root,
    String target_id = default_target_id,
  }) {
    return application.submit_command(
      WorkflowStartEvent(target_id: target_id, root: TargetPath(root)),
      idempotency_key: key,
    );
  }

  /// Executes an identified Start using [key], [root] and [target_id].
  ///
  /// Returns the durable application outcome.
  /// Unexpected application and persistence failures propagate.
  Future<WorkflowOperationOutcome> start(
    String key, {
    String root = default_root,
    String target_id = default_target_id,
  }) {
    return application.start(
      target_id: target_id,
      root: TargetPath(root),
      idempotency_key: key,
    );
  }

  /// Executes Stop using [key] for the explicit [workflow_id].
  ///
  /// Returns the durable application outcome.
  /// Unexpected application and persistence failures propagate.
  Future<WorkflowOperationOutcome> stop(String key, String workflow_id) {
    return application.stop(workflow_id: workflow_id, idempotency_key: key);
  }

  /// Reads the authoritative unfinished workflow.
  ///
  /// Returns null for verified absence.
  Future<WorkflowSnapshot?> current() async {
    final state = await application.read_state();

    return state.workflows.current_workflow;
  }

  /// Overlaps two identified Start operations.
  ///
  /// [first_key] identifies the first operation.
  /// [second_key] identifies the overlapping operation.
  /// [second_root] supplies the root of the overlapping Start.
  ///
  /// The first operation is held during identity proposal while the
  /// second command is durably accepted. Both high-level executions
  /// subsequently resolve through the same application processing lane.
  ///
  /// Returns the two application outcomes in invocation order.
  Future<List<WorkflowOperationOutcome>> overlap_starts({
    required String first_key,
    required String second_key,
    String second_root = default_root,
  }) async {
    final barrier = _ProcessingBarrier();

    identities.before_proposal = barrier.hold;

    final first = start(first_key);

    late Future<WorkflowOperationOutcome> second;

    try {
      await barrier.entered;

      // Establish real durable acceptance before releasing the first
      // processor. An identical key retrieves the original receipt.
      final receipt = await accept_start(second_key, root: second_root);

      final pending = await application.status_for(receipt);

      expect(pending!.state, WorkflowSubmissionState.pending);

      second = start(second_key, root: second_root);
    } finally {
      barrier.release();
    }

    return Future.wait([first, second]);
  }

  /// Closes the current persistence lifetime.
  ///
  /// Awaited application operations must have completed before closing.
  /// Closing also drains and closes the notification channel.
  /// Repeated closure is permitted.
  Future<void> close() async {
    final persistence = _persistence;

    if (persistence == null) {
      return;
    }

    await persistence.close();

    _persistence = null;
  }

  /// Executes a controlled database inspection using [operation].
  ///
  /// Closes application persistence before opening the inspection
  /// connection and always releases that connection afterwards.
  ///
  /// The caller must explicitly invoke [open] to resume application
  /// execution after inspection.
  Future<void> inspect(
    Future<void> Function(RudraDatabase database) operation,
  ) async {
    await close();

    final database = RudraDatabase.file(database_file);

    try {
      await operation(database);
    } finally {
      await database.close();
    }
  }

  /// Verifies exact durable submission and journal evidence.
  ///
  /// [states] contains the expected persisted processing states in
  /// submission order.
  ///
  /// [outcomes] contains expected committed event types in journal order.
  ///
  /// [notifications] specifies the exact number of committed-change
  /// signals published across the fixture's persistence lifetimes.
  ///
  /// Also verifies that every committed outcome belongs to exactly one
  /// completed submission and retains its original correlation identity.
  ///
  /// Leaves application persistence closed.
  Future<void> verify_evidence({
    required List<String> states,
    required List<String> outcomes,
    required int notifications,
  }) async {
    await inspect((database) async {
      final submissions = await database
          .select(database.workflowSubmissions)
          .get();

      final journal = await database.select(database.workflowEvents).get();

      submissions.sort((a, b) => a.sequence.compareTo(b.sequence));
      journal.sort((a, b) => a.sequence.compareTo(b.sequence));

      expect(
        submissions.map((submission) => submission.processing_state),
        orderedEquals(states),
      );

      expect(journal.map((event) => event.event_type), orderedEquals(outcomes));

      // Start and Stop each produce exactly one journal outcome when
      // completed. All other resolution states produce no outcomes.
      for (final submission in submissions) {
        final caused = journal.where(
          (event) => event.causation_id == submission.event_id,
        );

        if (submission.processing_state == 'completed') {
          expect(caused, hasLength(1));

          expect(caused.single.correlation_id, submission.correlation_id);
        } else {
          expect(caused, isEmpty);
        }
      }

      // Detect orphan journal outcomes that are not attributable to
      // any accepted submission.
      for (final event in journal) {
        expect(
          submissions.where(
            (submission) => submission.event_id == event.causation_id,
          ),
          hasLength(1),
        );
      }
    });

    expect(notification_count, notifications);
  }

  /// Releases persistence resources and deletes the owned test directory.
  Future<void> dispose() async {
    try {
      await close();
    } finally {
      await directory.delete(recursive: true);
    }
  }
}

/// Supplies deterministic trusted workflow identities.
///
/// Supports controlled interruption and failure at identity proposal,
/// before any proposed workflow outcome reaches the committer.
final class _IdentityProvider implements WorkflowIdentityProvider {
  /// Trusted owner configured by the current application composition.
  String os_user_id = _ExecutionFixture.default_os_user_id;

  /// Number of identity proposals across all persistence lifetimes.
  int proposal_count = 0;

  /// Optional asynchronous barrier or injected proposal failure.
  Future<void> Function()? before_proposal;

  /// Proposes an identity preserving the accepted Start [submission].
  ///
  /// Returns a unique deterministic identity bound to the configured
  /// trusted owner and the original accepted command.
  ///
  /// Throws [StateError] for unsupported command types.
  /// Injected proposal failures propagate.
  @override
  Future<WorkflowIdentity> propose_identity(
    PendingWorkflowCommand submission,
  ) async {
    final command = submission.command;

    if (command is! WorkflowStartEvent) {
      throw StateError('Only Start establishes a workflow identity.');
    }

    final proposal = ++proposal_count;

    final before = before_proposal;

    if (before != null) {
      await before();
    }

    return WorkflowIdentity(
      workflow_id: 'workflow-$proposal',
      os_user_id: os_user_id,
      target_id: command.target_id,
      root: command.root,
    );
  }
}

/// Coordinates deterministic overlap between application operations.
///
/// The first processing invocation signals entry and remains suspended
/// until the fixture releases it.
final class _ProcessingBarrier {
  /// Maximum wait for the processor to reach the expected barrier.
  static const timeout = Duration(seconds: 5);

  /// Signals entry into the controlled processing operation.
  final Completer<void> _entered = Completer<void>();

  /// Releases the suspended processing operation.
  final Completer<void> _released = Completer<void>();

  /// Completes when processing reaches the barrier.
  ///
  /// Throws [TimeoutException] if the expected processing operation
  /// never arrives.
  Future<void> get entered => _entered.future.timeout(timeout);

  /// Signals processing entry and waits for explicit release.
  Future<void> hold() async {
    if (!_entered.isCompleted) {
      _entered.complete();
    }

    await _released.future;
  }

  /// Releases waiting processing operations.
  ///
  /// Repeated release is permitted for deterministic fixture cleanup.
  void release() {
    if (!_released.isCompleted) {
      _released.complete();
    }
  }
}
