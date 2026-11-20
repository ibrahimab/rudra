import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Read-only restoration tests with isolated in-memory journal evidence.
void main() {
  final runtime = WorkflowRuntime.standard();

  WorkflowStateReader reader_for(
    WorkflowHistorySnapshot? projected, {
    List<WorkflowHistoryJournal> other_histories = const [],
    String owner = 'os-user-1',
  }) => WorkflowStateReader(
    runtime: runtime,
    history_store: _Store(projected, other_histories),
    os_user_id: owner,
  );

  Future<void> expect_failure(
    WorkflowHistorySnapshot projected,
    WorkflowStateReadErrorCode code,
  ) async {
    await expectLater(
      reader_for(projected).current(),
      throwsA(
        isA<WorkflowStateReadException>().having(
          (error) => error.code,
          'code',
          code,
        ),
      ),
    );
  }

  group('WorkflowStateReader outcome-only restoration', () {
    test('returns null only after verifying absence of ownership', () async {
      expect(await reader_for(null).current(), isNull);
    });

    test('restores version-one workflow from one committed outcome', () async {
      final restored = await reader_for(_snapshot(runtime)).current();
      expect(restored, isNotNull);
      expect(restored!.state.version, 1);
      expect(restored.state.identity.workflow_id, 'workflow-1');
      expect(restored.state.lifecycle.id, 'rudra.workflow.active');
      expect(restored.events, hasLength(1));
      expect(restored.events.single, isA<WorkflowStartedEvent>());
      expect(() => restored.events.clear(), throwsUnsupportedError);
    });

    test('does not mutate journal evidence', () async {
      final projected = _snapshot(runtime);
      final before = List.of(projected.journal);
      await reader_for(projected).current();
      expect(projected.journal, orderedEquals(before));
      expect(() => projected.journal.clear(), throwsUnsupportedError);
    });

    test('rejects foreign projected owner', () async {
      await expect_failure(
        _snapshot(runtime, projected_identity: _identity(owner: 'other-user')),
        WorkflowStateReadErrorCode.ownership_mismatch,
      );
    });

    test('rejects a committed owner different from the projection', () async {
      await expect_failure(
        _snapshot(
          runtime,
          journal: _journal(runtime, identity: _identity(owner: 'other-user')),
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

    test('rejects missing first committed version', () async {
      await expect_failure(
        _snapshot(
          runtime,
          journal: [
            _entry(
              runtime,
              version: 2,
              sequence: 11,
              event: WorkflowStartedEvent(identity: _identity()),
            ),
          ],
        ),
        WorkflowStateReadErrorCode.invalid_journal,
      );
    });

    test('rejects duplicate or nonmonotonic journal sequence', () async {
      await expect_failure(
        _snapshot(
          runtime,
          journal: [
            _entry(
              runtime,
              version: 1,
              sequence: 11,
              event: WorkflowStartedEvent(identity: _identity()),
            ),
            _entry(
              runtime,
              version: 2,
              sequence: 10,
              event: WorkflowEndedEvent(workflow_id: 'workflow-1'),
            ),
          ],
        ),
        WorkflowStateReadErrorCode.invalid_journal,
      );
    });

    test('rejects journal event assigned to another workflow ID', () async {
      final valid = _journal(runtime).single;
      await expect_failure(
        _snapshot(
          runtime,
          journal: [
            WorkflowJournalEntry(
              sequence: valid.sequence,
              event_id: valid.event_id,
              workflow_id: 'foreign-workflow',
              version: valid.version,
              event_type: valid.event_type,
              payload_json: valid.payload_json,
            ),
          ],
        ),
        WorkflowStateReadErrorCode.invalid_journal,
      );
    });

    test('rejects duplicated event IDs within the journal', () async {
      await expect_failure(
        _snapshot(
          runtime,
          journal: [
            _entry(
              runtime,
              version: 1,
              sequence: 11,
              event_id: 'duplicate',
              event: WorkflowStartedEvent(identity: _identity()),
            ),
            _entry(
              runtime,
              version: 2,
              sequence: 12,
              event_id: 'duplicate',
              event: WorkflowEndedEvent(workflow_id: 'workflow-1'),
            ),
          ],
        ),
        WorkflowStateReadErrorCode.invalid_journal,
      );
    });

    test('rejects malformed encoded outcomes', () async {
      await expect_failure(
        _snapshot(
          runtime,
          journal: const [
            WorkflowJournalEntry(
              sequence: 11,
              event_id: 'event-1',
              workflow_id: 'workflow-1',
              version: 1,
              event_type: WorkflowStartedEvent.type_id,
              payload_json: 'invalid-json',
            ),
          ],
        ),
        WorkflowStateReadErrorCode.invalid_event,
      );
    });

    test(
      'rejects submitted commands inside an authoritative journal',
      () async {
        await expect_failure(
          _snapshot(
            runtime,
            journal: [
              _entry(
                runtime,
                version: 1,
                sequence: 11,
                event: WorkflowStartEvent(
                  target_id: 'local-macos',
                  root: TargetPath('/workspace'),
                ),
              ),
            ],
          ),
          WorkflowStateReadErrorCode.invalid_event,
        );
      },
    );

    test('rejects an impossible first terminal outcome', () async {
      await expect_failure(
        _snapshot(
          runtime,
          journal: [
            _entry(
              runtime,
              version: 1,
              sequence: 11,
              event: WorkflowEndedEvent(workflow_id: 'workflow-1'),
            ),
          ],
        ),
        WorkflowStateReadErrorCode.invalid_history,
      );
    });

    test('rejects stale projected version', () async {
      await expect_failure(
        _snapshot(runtime, projected_version: 2),
        WorkflowStateReadErrorCode.projection_mismatch,
      );
    });

    test('rejects altered projected target', () async {
      await expect_failure(
        _snapshot(runtime, projected_identity: _identity(target: 'other')),
        WorkflowStateReadErrorCode.projection_mismatch,
      );
    });

    test('rejects altered projected root', () async {
      await expect_failure(
        _snapshot(runtime, projected_identity: _identity(root: '/other')),
        WorkflowStateReadErrorCode.projection_mismatch,
      );
    });

    test('rejects terminal history retaining unfinished ownership', () async {
      await expect_failure(
        _snapshot(
          runtime,
          projected_version: 2,
          journal: _terminal_journal(runtime),
        ),
        WorkflowStateReadErrorCode.projection_mismatch,
      );
    });

    test('rejects blank trusted OS-user identity', () {
      expect(() => reader_for(null, owner: ' '), throwsArgumentError);
    });

    test('detects orphaned active history after losing projection', () async {
      await expectLater(
        reader_for(
          null,
          other_histories: [
            WorkflowHistoryJournal(
              workflow_id: 'workflow-1',
              journal: _journal(runtime),
            ),
          ],
        ).current(),
        throwsA(
          isA<WorkflowStateReadException>().having(
            (error) => error.code,
            'code',
            WorkflowStateReadErrorCode.orphaned_workflow,
          ),
        ),
      );
    });

    test('rejects owner-indexed history belonging to another user', () async {
      await expectLater(
        reader_for(
          null,
          other_histories: [
            WorkflowHistoryJournal(
              workflow_id: 'workflow-1',
              journal: _journal(
                runtime,
                identity: _identity(owner: 'other-user'),
              ),
            ),
          ],
        ).current(),
        throwsA(
          isA<WorkflowStateReadException>().having(
            (error) => error.code,
            'code',
            WorkflowStateReadErrorCode.ownership_mismatch,
          ),
        ),
      );
    });

    test('accepts terminal history without unfinished projection', () async {
      expect(
        await reader_for(
          null,
          other_histories: [
            WorkflowHistoryJournal(
              workflow_id: 'workflow-1',
              journal: _terminal_journal(runtime),
            ),
          ],
        ).current(),
        isNull,
      );
    });

    test('rejects malformed unprojected history', () async {
      await expectLater(
        reader_for(
          null,
          other_histories: [
            WorkflowHistoryJournal(
              workflow_id: 'workflow-1',
              journal: [
                _entry(
                  runtime,
                  version: 2,
                  sequence: 11,
                  event: WorkflowStartedEvent(identity: _identity()),
                ),
              ],
            ),
          ],
        ).current(),
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

/// Creates stable original identity bindings for journal fixtures.
WorkflowIdentity _identity({
  String owner = 'os-user-1',
  String target = 'local-macos',
  String root = '/workspace',
}) => WorkflowIdentity(
  workflow_id: 'workflow-1',
  os_user_id: owner,
  target_id: target,
  root: TargetPath(root),
);

/// Encodes a single journal entry with independent sequence and version.
WorkflowJournalEntry _entry(
  WorkflowRuntime runtime, {
  required int version,
  required int sequence,
  required WorkflowEvent event,
  String event_id = 'event-1',
}) => WorkflowJournalEntry(
  sequence: sequence,
  event_id: event_id,
  workflow_id: 'workflow-1',
  version: version,
  event_type: event.event_type,
  payload_json: runtime.codec.encode(event),
);

/// Creates a valid one-outcome active workflow history.
List<WorkflowJournalEntry> _journal(
  WorkflowRuntime runtime, {
  WorkflowIdentity? identity,
}) => [
  _entry(
    runtime,
    version: 1,
    sequence: 11,
    event: WorkflowStartedEvent(identity: identity ?? _identity()),
  ),
];

/// Creates the first two committed outcomes of a completed workflow.
List<WorkflowJournalEntry> _terminal_journal(WorkflowRuntime runtime) => [
  ..._journal(runtime),
  _entry(
    runtime,
    version: 2,
    sequence: 12,
    event_id: 'event-2',
    event: WorkflowEndedEvent(workflow_id: 'workflow-1'),
  ),
];

/// Builds an owner reservation and optional deliberately invalid journal.
WorkflowHistorySnapshot _snapshot(
  WorkflowRuntime runtime, {
  WorkflowIdentity? projected_identity,
  int projected_version = 1,
  List<WorkflowJournalEntry>? journal,
}) => WorkflowHistorySnapshot(
  projected_identity: projected_identity ?? _identity(),
  projected_version: projected_version,
  journal: journal ?? _journal(runtime),
);

/// Supplies immutable fake restoration evidence without persistence.
final class _Store implements WorkflowHistoryStore {
  /// Creates one consistent fixture evidence snapshot.
  const _Store(this.projected, this.other_histories);

  /// Current owner projection, if any.
  final WorkflowHistorySnapshot? projected;

  /// Additional owner-indexed histories.
  final List<WorkflowHistoryJournal> other_histories;

  @override
  Future<WorkflowRestorationEvidence> load_restoration_evidence({
    required String os_user_id,
  }) async => WorkflowRestorationEvidence(
    projected: projected,
    other_histories: other_histories,
  );
}
