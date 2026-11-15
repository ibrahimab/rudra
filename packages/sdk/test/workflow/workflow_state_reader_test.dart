import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Verifies read-only workflow restoration using SDK contracts.
///
/// No SQLite connection, command processor, or filesystem
/// adapter participates in these tests.
void main() {
  final runtime = WorkflowRuntime.standard();

  WorkflowStateReader reader_for(WorkflowHistorySnapshot? snapshot) {
    return WorkflowStateReader(
      runtime: runtime,
      history_store: _FixtureHistoryStore(snapshot),
      os_user_id: 'os-user-1',
    );
  }

  Future<void> expect_failure(
    WorkflowHistorySnapshot snapshot,
    WorkflowStateReadErrorCode code,
  ) async {
    await expectLater(
      reader_for(snapshot).current(),
      throwsA(
        isA<WorkflowStateReadException>().having(
          (error) => error.code,
          'code',
          code,
        ),
      ),
    );
  }

  group('WorkflowStateReader', () {
    test('returns null without creating a workflow', () async {
      final store = _FixtureHistoryStore(null);

      final reader = WorkflowStateReader(
        runtime: runtime,
        history_store: store,
        os_user_id: 'os-user-1',
      );

      expect(await reader.current(), isNull);
      expect(store.reads, 1);
      expect(store.requested_user, 'os-user-1');
    });

    test('restores committed active workflow state', () async {
      final state = await reader_for(_snapshot(runtime)).current();

      expect(state, isNotNull);
      expect(state!.version, 2);
      expect(state.identity.workflow_id, 'workflow-1');
      expect(state.identity.os_user_id, 'os-user-1');
      expect(state.identity.target_id, 'local-macos');
      expect(state.identity.root.value, '/workspace');
    });

    test('does not modify the supplied history', () async {
      final snapshot = _snapshot(runtime);
      final original_events = List.of(snapshot.journal);

      await reader_for(snapshot).current();

      expect(snapshot.journal, orderedEquals(original_events));
      expect(() => snapshot.journal.clear(), throwsUnsupportedError);
    });

    test('rejects a foreign projection owner', () async {
      await expect_failure(
        _snapshot(
          runtime,
          projected_identity: _identity(os_user_id: 'os-user-2'),
        ),
        WorkflowStateReadErrorCode.ownership_mismatch,
      );
    });

    test('rejects foreign ownership in committed history', () async {
      await expect_failure(
        _snapshot(
          runtime,
          journal: _journal(
            runtime,
            outcome_identity: _identity(os_user_id: 'os-user-2'),
          ),
        ),
        WorkflowStateReadErrorCode.ownership_mismatch,
      );
    });

    test('rejects missing committed history', () async {
      await expect_failure(
        _snapshot(runtime, journal: []),
        WorkflowStateReadErrorCode.invalid_journal,
      );
    });

    test('rejects missing workflow versions', () async {
      final journal = _journal(runtime);

      final invalid = [
        journal.first,
        _entry(
          runtime,
          sequence: 12,
          version: 3,
          event_id: 'event-2',
          event: WorkflowStartedEvent(identity: _identity()),
        ),
      ];

      await expect_failure(
        _snapshot(runtime, journal: invalid),
        WorkflowStateReadErrorCode.invalid_journal,
      );
    });

    test('rejects reversed journal sequence', () async {
      final journal = _journal(runtime);

      final invalid = [
        journal.first,
        _entry(
          runtime,
          sequence: 10,
          version: 2,
          event_id: 'event-2',
          event: WorkflowStartedEvent(identity: _identity()),
        ),
      ];

      await expect_failure(
        _snapshot(runtime, journal: invalid),
        WorkflowStateReadErrorCode.invalid_journal,
      );
    });

    test('rejects events belonging to another workflow', () async {
      final journal = _journal(runtime);

      final invalid = [
        journal.first,
        WorkflowJournalEntry(
          sequence: journal.last.sequence,
          event_id: journal.last.event_id,
          workflow_id: 'another-workflow',
          version: journal.last.version,
          event_type: journal.last.event_type,
          payload_json: journal.last.payload_json,
        ),
      ];

      await expect_failure(
        _snapshot(runtime, journal: invalid),
        WorkflowStateReadErrorCode.invalid_journal,
      );
    });

    test('rejects duplicate event identifiers', () async {
      final journal = _journal(runtime);

      final invalid = [
        journal.first,
        WorkflowJournalEntry(
          sequence: journal.last.sequence,
          event_id: journal.first.event_id,
          workflow_id: journal.last.workflow_id,
          version: journal.last.version,
          event_type: journal.last.event_type,
          payload_json: journal.last.payload_json,
        ),
      ];

      await expect_failure(
        _snapshot(runtime, journal: invalid),
        WorkflowStateReadErrorCode.invalid_journal,
      );
    });

    test('rejects unreadable event payloads', () async {
      final journal = _journal(runtime);

      final invalid = [
        journal.first,
        const WorkflowJournalEntry(
          sequence: 12,
          event_id: 'event-2',
          workflow_id: 'workflow-1',
          version: 2,
          event_type: WorkflowStartedEvent.type_id,
          payload_json: 'not-json',
        ),
      ];

      await expect_failure(
        _snapshot(runtime, journal: invalid),
        WorkflowStateReadErrorCode.invalid_event,
      );
    });

    test('rejects contradictory domain history', () async {
      await expect_failure(
        _snapshot(
          runtime,
          journal: _journal(runtime, requested_root: '/wrong-root'),
        ),
        WorkflowStateReadErrorCode.invalid_history,
      );
    });

    test('rejects stale projected versions', () async {
      await expect_failure(
        _snapshot(runtime, projected_version: 1),
        WorkflowStateReadErrorCode.projection_mismatch,
      );
    });

    test('rejects altered projected target bindings', () async {
      await expect_failure(
        _snapshot(
          runtime,
          projected_identity: _identity(target_id: 'other-target'),
        ),
        WorkflowStateReadErrorCode.projection_mismatch,
      );
    });

    test('rejects altered projected root bindings', () async {
      await expect_failure(
        _snapshot(runtime, projected_identity: _identity(root: '/other-root')),
        WorkflowStateReadErrorCode.projection_mismatch,
      );
    });

    test('rejects terminal history with unfinished projection', () async {
      final journal = _journal(runtime);

      journal.add(
        _entry(
          runtime,
          sequence: 13,
          version: 3,
          event_id: 'event-3',
          event: WorkflowEndedEvent(workflow_id: 'workflow-1'),
        ),
      );

      await expect_failure(
        _snapshot(runtime, projected_version: 3, journal: journal),
        WorkflowStateReadErrorCode.projection_mismatch,
      );
    });

    test('rejects blank trusted OS-user identity', () {
      expect(
        () => WorkflowStateReader(
          runtime: runtime,
          history_store: _FixtureHistoryStore(null),
          os_user_id: ' ',
        ),
        throwsArgumentError,
      );
    });

    test('detects active history without its projection', () async {
      final store = _FixtureHistoryStore(
        null,
        other_histories: [
          WorkflowHistoryJournal(
            workflow_id: 'workflow-1',
            journal: _journal(runtime),
          ),
        ],
      );

      final reader = WorkflowStateReader(
        runtime: runtime,
        history_store: store,
        os_user_id: 'os-user-1',
      );

      await expectLater(
        reader.current(),
        throwsA(
          isA<WorkflowStateReadException>().having(
            (error) => error.code,
            'code',
            WorkflowStateReadErrorCode.orphaned_workflow,
          ),
        ),
      );
    });

    test('ignores another users valid active history', () async {
      final store = _FixtureHistoryStore(
        null,
        other_histories: [
          WorkflowHistoryJournal(
            workflow_id: 'workflow-1',
            journal: _journal(
              runtime,
              outcome_identity: _identity(os_user_id: 'os-user-2'),
            ),
          ),
        ],
      );

      final reader = WorkflowStateReader(
        runtime: runtime,
        history_store: store,
        os_user_id: 'os-user-1',
      );

      expect(await reader.current(), isNull);
    });

    test('accepts terminal history without a projection', () async {
      final journal = _journal(runtime);

      journal.add(
        _entry(
          runtime,
          sequence: 13,
          version: 3,
          event_id: 'event-3',
          event: WorkflowEndedEvent(workflow_id: 'workflow-1'),
        ),
      );

      final store = _FixtureHistoryStore(
        null,
        other_histories: [
          WorkflowHistoryJournal(workflow_id: 'workflow-1', journal: journal),
        ],
      );

      final reader = WorkflowStateReader(
        runtime: runtime,
        history_store: store,
        os_user_id: 'os-user-1',
      );

      expect(await reader.current(), isNull);
    });

    test('rejects malformed unprojected history', () async {
      final journal = _journal(runtime);

      final invalid = [
        journal.first,
        WorkflowJournalEntry(
          sequence: 12,
          event_id: 'event-2',
          workflow_id: 'workflow-1',
          version: 3,
          event_type: journal.last.event_type,
          payload_json: journal.last.payload_json,
        ),
      ];

      final store = _FixtureHistoryStore(
        null,
        other_histories: [
          WorkflowHistoryJournal(workflow_id: 'workflow-1', journal: invalid),
        ],
      );

      final reader = WorkflowStateReader(
        runtime: runtime,
        history_store: store,
        os_user_id: 'os-user-1',
      );

      await expectLater(
        reader.current(),
        throwsA(
          isA<WorkflowStateReadException>().having(
            (error) => error.code,
            'code',
            WorkflowStateReadErrorCode.invalid_journal,
          ),
        ),
      );
    });
  });
}

/// Creates a deterministic workflow identity.
WorkflowIdentity _identity({
  String os_user_id = 'os-user-1',
  String target_id = 'local-macos',
  String root = '/workspace',
}) {
  return WorkflowIdentity(
    workflow_id: 'workflow-1',
    os_user_id: os_user_id,
    target_id: target_id,
    root: TargetPath(root),
  );
}

/// Serializes one committed event using the production codec.
WorkflowJournalEntry _entry(
  WorkflowRuntime runtime, {
  required int sequence,
  required int version,
  required String event_id,
  required WorkflowEvent event,
}) {
  return WorkflowJournalEntry(
    sequence: sequence,
    event_id: event_id,
    workflow_id: 'workflow-1',
    version: version,
    event_type: event.event_type,
    payload_json: runtime.codec.encode(event),
  );
}

/// Creates the two events of an established workflow.
///
/// Global sequences intentionally begin at 11 to verify that
/// workflow-local versions are independent of database position.
List<WorkflowJournalEntry> _journal(
  WorkflowRuntime runtime, {
  WorkflowIdentity? outcome_identity,
  String requested_root = '/workspace',
}) {
  return [
    _entry(
      runtime,
      sequence: 11,
      version: 1,
      event_id: 'event-1',
      event: WorkflowStartEvent(
        target_id: 'local-macos',
        root: TargetPath(requested_root),
      ),
    ),
    _entry(
      runtime,
      sequence: 12,
      version: 2,
      event_id: 'event-2',
      event: WorkflowStartedEvent(identity: outcome_identity ?? _identity()),
    ),
  ];
}

/// Creates a persisted snapshot with optional inconsistencies.
WorkflowHistorySnapshot _snapshot(
  WorkflowRuntime runtime, {
  WorkflowIdentity? projected_identity,
  int projected_version = 2,
  List<WorkflowJournalEntry>? journal,
}) {
  return WorkflowHistorySnapshot(
    projected_identity: projected_identity ?? _identity(),
    projected_version: projected_version,
    journal: journal ?? _journal(runtime),
  );
}

/// In-memory read-only restoration evidence provider.
///
/// Records the requested OS-user identity and read count.
final class _FixtureHistoryStore implements WorkflowHistoryStore {
  /// Creates a fixture with optional projected history.
  _FixtureHistoryStore(this.snapshot, {this.other_histories = const []});

  /// Existing projected workflow, if any.
  final WorkflowHistorySnapshot? snapshot;

  /// Other committed histories in the same logical snapshot.
  final List<WorkflowHistoryJournal> other_histories;

  /// Number of reads.
  int reads = 0;

  /// Last trusted OS-user identity requested.
  String? requested_user;

  @override
  Future<WorkflowRestorationEvidence> load_restoration_evidence({
    required String os_user_id,
  }) async {
    reads++;
    requested_user = os_user_id;

    return WorkflowRestorationEvidence(
      projected: snapshot,
      other_histories: other_histories,
    );
  }
}
