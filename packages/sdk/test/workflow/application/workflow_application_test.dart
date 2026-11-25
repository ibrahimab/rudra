import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Tests SDK application boundaries independently of SQLite and frontends.
///
/// Existing SQLite integration tests verify actual transactional commitment;
/// these tests exercise read-only behavior, explicit operations, durable
/// resolution contracts and causally bound confirmations.
void main() {
  final runtime = WorkflowRuntime.standard();
  final identity = WorkflowIdentity(
    workflow_id: 'workflow-1',
    os_user_id: 'trusted-owner',
    target_id: 'local-macos',
    root: TargetPath('/workspace'),
  );

  /// Composes one SDK application with isolated in-memory dependencies.
  ///
  /// [persistence] records submissions and supplies journal evidence.
  WorkflowApplication create_application(_FakePersistence persistence) =>
      WorkflowApplication(
        runtime: runtime,
        persistence: persistence,
        identity_provider: _IdentityProvider(identity),
        os_user_id: 'trusted-owner',
      );

  /// Creates one valid current workflow from committed establishment evidence.
  ///
  /// [workflow_identity] provides its original trusted owner and root.
  WorkflowRestorationEvidence established(WorkflowIdentity workflow_identity) {
    final event = WorkflowStartedEvent(identity: workflow_identity);
    return WorkflowRestorationEvidence(
      projected: WorkflowHistorySnapshot(
        projected_identity: workflow_identity,
        projected_version: 1,
        journal: [
          WorkflowJournalEntry(
            sequence: 1,
            event_id: 'journal-event-1',
            workflow_id: workflow_identity.workflow_id,
            version: 1,
            event_type: event.event_type,
            payload_json: runtime.codec.encode(event),
          ),
        ],
      ),
      other_histories: const [],
    );
  }

  /// Produces verified absence without an unfinished projection or history.
  WorkflowRestorationEvidence absent() =>
      WorkflowRestorationEvidence(projected: null, other_histories: const []);

  /// Produces a completed submission linked to its exact journal outcome.
  ///
  /// [workflow_id] and [event_type] come from committed journal metadata.
  WorkflowSubmissionResolution completed({
    required String workflow_id,
    required String event_type,
  }) => WorkflowSubmissionResolution(
    receipt: _receipt(),
    state: WorkflowSubmissionState.completed,
    committed_outcome: WorkflowCommittedOutcome(
      workflow_id: workflow_id,
      event_type: event_type,
      version: event_type == WorkflowStartedEvent.type_id ? 1 : 2,
      sequence: 7,
    ),
  );

  group('WorkflowApplication', () {
    test('validates trusted ownership during composition', () {
      final persistence = _FakePersistence((_) => absent());
      expect(
        () => WorkflowApplication(
          runtime: runtime,
          persistence: persistence,
          identity_provider: _IdentityProvider(identity),
          os_user_id: ' ',
        ),
        throwsArgumentError,
      );
    });

    test('reads verified absence without submitting commands', () async {
      final persistence = _FakePersistence((_) => absent());
      final application = create_application(persistence);

      final state = await application.read_state();

      expect(state.workflows.current_workflow, isNull);
      expect(persistence.submissions.accepted.length, 0);
    });

    test('reads committed workflow identity and version', () async {
      final persistence = _FakePersistence((_) => established(identity));
      final state = await create_application(persistence).read_state();

      expect(
        state.workflows.current_workflow?.identity.workflow_id,
        'workflow-1',
      );
      expect(state.workflows.current_workflow?.version, 1);
      expect(persistence.submissions.accepted, isEmpty);
    });

    test('refuses redundant Start before durable submission', () async {
      final persistence = _FakePersistence((_) => established(identity));

      await expectLater(
        create_application(persistence)
            .start(target_id: 'local-macos', root: TargetPath('/workspace')),
        throwsA(isA<WorkflowAlreadyActiveException>()),
      );

      expect(persistence.submissions.accepted, isEmpty);
    });

    test(
      'Start matches the committed outcome to its restored workflow',
      () async {
        final persistence =
            _FakePersistence(
                (read_count) =>
                    read_count == 1 ? absent() : established(identity),
              )
              ..statuses.resolution = completed(
                workflow_id: 'workflow-1',
                event_type: WorkflowStartedEvent.type_id,
              );

        final started = await create_application(persistence)
            .start(target_id: 'local-macos', root: TargetPath('/workspace'));

        expect(started.identity.workflow_id, 'workflow-1');
        expect(persistence.submissions.accepted, hasLength(1));
        expect(
          persistence.submissions.accepted.single,
          isA<WorkflowStartEvent>(),
        );
      },
    );

    test(
      'Start rejects a replacement even with the same target and root',
      () async {
        final replacement = WorkflowIdentity(
          workflow_id: 'replacement',
          os_user_id: identity.os_user_id,
          target_id: identity.target_id,
          root: identity.root,
        );
        final persistence =
            _FakePersistence(
                (read_count) =>
                    read_count == 1 ? absent() : established(replacement),
              )
              ..statuses.resolution = completed(
                workflow_id: identity.workflow_id,
                event_type: WorkflowStartedEvent.type_id,
              );

        await expectLater(
          create_application(persistence)
              .start(target_id: 'local-macos', root: TargetPath('/workspace')),
          throwsStateError,
        );
      },
    );

    test('Stop rejects verified absence without submitting', () async {
      final persistence = _FakePersistence((_) => absent());

      await expectLater(
        create_application(persistence).stop(),
        throwsA(
          isA<WorkflowStopRejectedException>().having(
            (error) => error.code,
            'code',
            WorkflowRejectionCode.workflow_not_active,
          ),
        ),
      );
      expect(persistence.submissions.accepted, isEmpty);
    });

    test('Stop protects a different displayed workflow identity', () async {
      final persistence = _FakePersistence((_) => established(identity));

      await expectLater(
        create_application(persistence)
            .stop(expected_workflow_id: 'previous-workflow'),
        throwsA(
          isA<WorkflowStopRejectedException>().having(
            (error) => error.code,
            'code',
            WorkflowRejectionCode.workflow_id_mismatch,
          ),
        ),
      );
      expect(persistence.submissions.accepted, isEmpty);
    });

    test('Stop confirms the accepted request terminal outcome', () async {
      final persistence = _FakePersistence((_) => established(identity))
        ..statuses.resolution = completed(
          workflow_id: 'workflow-1',
          event_type: WorkflowEndedEvent.type_id,
        );

      final stopped = await create_application(persistence)
          .stop(expected_workflow_id: 'workflow-1');

      expect(stopped, 'workflow-1');
      expect(persistence.submissions.accepted.single, isA<WorkflowStopEvent>());
    });

    test('Stop refuses a completed outcome for another workflow', () async {
      final persistence = _FakePersistence((_) => established(identity))
        ..statuses.resolution = completed(
          workflow_id: 'replacement',
          event_type: WorkflowEndedEvent.type_id,
        );

      await expectLater(
        create_application(persistence).stop(),
        throwsStateError,
      );
    });

    test('acceptance and durable status remain separate', () async {
      final persistence = _FakePersistence((_) => absent());
      final application = create_application(persistence);

      final receipt = await application.submit_command(
        WorkflowStartEvent(
          target_id: 'local-macos',
          root: TargetPath('/workspace'),
        ),
      );
      final status = await application.status_for(receipt);

      expect(receipt.event_id, 'submission-event');
      expect(status!.state, WorkflowSubmissionState.pending);
      expect(status.committed_outcome, isNull);
      expect(persistence.submissions.accepted, hasLength(1));
    });
  });
}

/// Stable accepted-submission receipt reused by the fake status reader.
EventSubmissionReceipt _receipt() => EventSubmissionReceipt(
  event_id: 'submission-event',
  correlation_id: 'submission-correlation',
);

/// Test-only composition of stable SDK persistence interfaces.
///
/// [evidence_for_read] supplies one consistent restoration result per read.
final class _FakePersistence implements WorkflowApplicationPersistence {
  /// Creates independently controlled submission and history fakes.
  ///
  /// [evidence_for_read] supplies each consistent journal restoration view.
  _FakePersistence(this.evidence_for_read);

  /// Generates journal restoration evidence for successive SDK reads.
  final WorkflowRestorationEvidence Function(int read_count) evidence_for_read;

  /// Records each read-only history access for deterministic sequencing.
  int read_count = 0;

  /// Records durably accepted commands without processing them.
  final _SubmissionStore submissions = _SubmissionStore();

  /// Supplies controlled submission processing statuses.
  final _StatusReader statuses = _StatusReader();

  /// Local committed-change notifications for application boundary tests.
  final LocalWorkflowCommitChannel commits = LocalWorkflowCommitChannel();

  @override
  WorkflowCommitSubscriber get workflow_commit_subscriber => commits;

  /// Supplies committed journal evidence for the SDK state reader.
  @override
  WorkflowHistoryStore get workflow_history_store => _HistoryStore(this);

  /// Supplies the explicit command acceptance boundary.
  @override
  EventSubmissionStore get event_submission_store => submissions;

  /// Supplies durable receipt status lookups for [os_user_id].
  @override
  WorkflowSubmissionStatusReader workflow_status_reader_for({
    required String os_user_id,
  }) => statuses;

  /// Supplies a rejection writer unused by these boundary tests.
  @override
  WorkflowSubmissionRejector get workflow_rejector => _NoopRejector();

  /// Supplies a quarantine writer unused by these boundary tests.
  @override
  WorkflowSubmissionQuarantiner get workflow_quarantiner => _NoopQuarantiner();

  /// Creates an empty inbox for trusted [os_user_id] processing.
  @override
  WorkflowInbox workflow_inbox_for({required String os_user_id}) =>
      _EmptyInbox();

  /// Creates an inert committer for trusted [os_user_id].
  @override
  WorkflowCommitter workflow_committer_for({required String os_user_id}) =>
      _NoopCommitter();
}

/// Read-only fake journal boundary backing an SDK state reader.
final class _HistoryStore implements WorkflowHistoryStore {
  /// Binds journal evidence to the containing test [persistence].
  const _HistoryStore(this.persistence);

  /// Owner of the successive restoration evidence.
  final _FakePersistence persistence;

  /// Returns owner-scoped restoration evidence without mutation.
  ///
  /// [os_user_id] is supplied by the SDK's trusted application context.
  @override
  Future<WorkflowRestorationEvidence> load_restoration_evidence({
    required String os_user_id,
  }) async {
    persistence.read_count++;
    return persistence.evidence_for_read(persistence.read_count);
  }
}

/// Records explicit command acceptance without domain transitions.
final class _SubmissionStore implements EventSubmissionStore {
  /// Accepted typed commands in submission order.
  final List<WorkflowCommandEvent> accepted = [];

  /// Records [event] and returns a durable fake receipt.
  ///
  /// [idempotency_key] is accepted as part of the SDK contract.
  @override
  Future<EventSubmissionReceipt> accept(
    WorkflowCommandEvent event, {
    String? idempotency_key,
  }) async {
    accepted.add(event);
    return _receipt();
  }
}

/// Returns an injected durable status without processing work.
final class _StatusReader implements WorkflowSubmissionStatusReader {
  /// Current fake status, initially accepted but still pending.
  WorkflowSubmissionResolution resolution = WorkflowSubmissionResolution(
    receipt: _receipt(),
    state: WorkflowSubmissionState.pending,
  );

  /// Returns the configured resolution for [receipt].
  @override
  Future<WorkflowSubmissionResolution?> status_for(
    EventSubmissionReceipt receipt,
  ) async => resolution;
}

/// Supplies no processing commands for isolated application tests.
final class _EmptyInbox implements WorkflowInbox {
  /// Finds no pending command and performs no processing.
  @override
  Future<PendingWorkflowCommand?> next_pending() async => null;
}

/// Prevents accidental durable commitment in SDK-only tests.
final class _NoopCommitter implements WorkflowCommitter {
  /// Rejects an unexpected [plan] rather than claiming a commit.
  @override
  Future<void> commit(WorkflowProcessingPlan plan) async {
    throw StateError('Unexpected workflow commit.');
  }
}

/// Prevents accidental durable rejection in SDK-only tests.
final class _NoopRejector implements WorkflowSubmissionRejector {
  /// Rejects an unexpected durable rejection request.
  ///
  /// [submission] and [code] would describe the rejected command.
  @override
  Future<void> reject({
    required PendingWorkflowCommand submission,
    required WorkflowRejectionCode code,
  }) async {
    throw StateError('Unexpected workflow rejection.');
  }
}

/// Prevents accidental quarantine in SDK-only tests.
final class _NoopQuarantiner implements WorkflowSubmissionQuarantiner {
  /// Refuses an unexpected unreadable command [issue].
  @override
  Future<void> quarantine(WorkflowInboxDecodingException issue) async {
    throw StateError('Unexpected workflow quarantine.');
  }
}

/// Supplies a deterministic proposed workflow identity for SDK tests.
final class _IdentityProvider implements WorkflowIdentityProvider {
  /// Creates a provider returning the preconfigured [identity].
  const _IdentityProvider(this.identity);

  /// Owner-bound identity proposed on workflow establishment.
  final WorkflowIdentity identity;

  /// Returns the fixed identity for accepted Start [submission].
  @override
  Future<WorkflowIdentity> propose_identity(
    PendingWorkflowCommand submission,
  ) async => identity;
}
