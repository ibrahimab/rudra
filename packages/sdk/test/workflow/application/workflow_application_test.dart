import 'dart:async';

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

  /// Produces a durable business rejection for the original submission.
  ///
  /// [code] identifies the business rule refusing the operation.
  WorkflowSubmissionResolution rejected(WorkflowRejectionCode code) {
    return WorkflowSubmissionResolution(
      receipt: _receipt(),
      state: WorkflowSubmissionState.rejected,
      rejection_code: code,
      rejected_at_unix_ms: 1795618800000,
    );
  }

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

    test('Start returns the durable ownership rejection', () async {
      final persistence = _FakePersistence((_) => established(identity))
        ..statuses.resolution = rejected(
          WorkflowRejectionCode.ownership_conflict,
        );

      final outcome = await create_application(persistence).start(
        target_id: 'local-macos',
        root: TargetPath('/workspace'),
        idempotency_key: 'start-001',
      );

      expect(outcome, isA<WorkflowOperationResolved>());

      final resolution = (outcome as WorkflowOperationResolved).resolution;

      expect(resolution.state, WorkflowSubmissionState.rejected);
      expect(
        resolution.rejection_code,
        WorkflowRejectionCode.ownership_conflict,
      );

      expect(persistence.submissions.accepted, hasLength(1));
      expect(persistence.submissions.keys, ['start-001']);
      expect(persistence.read_count, 0);
    });

    test('Start returns its historical establishment outcome', () async {
      final persistence = _FakePersistence((_) => absent())
        ..statuses.resolution = completed(
          workflow_id: 'workflow-1',
          event_type: WorkflowStartedEvent.type_id,
        );

      final outcome = await create_application(persistence).start(
        target_id: 'local-macos',
        root: TargetPath('/workspace'),
        idempotency_key: 'start-001',
      );

      final resolution = (outcome as WorkflowOperationResolved).resolution;

      expect(resolution.state, WorkflowSubmissionState.completed);
      expect(resolution.committed_outcome!.workflow_id, 'workflow-1');
      expect(resolution.committed_outcome!.version, 1);

      expect(
        persistence.submissions.accepted.single,
        isA<WorkflowStartEvent>(),
      );

      expect(persistence.read_count, 0);
      expect(persistence.inbox.read_count, 0);
    });

    test('Start resolution is independent of a replacement workflow', () async {
      final replacement = WorkflowIdentity(
        workflow_id: 'replacement',
        os_user_id: identity.os_user_id,
        target_id: identity.target_id,
        root: identity.root,
      );

      final persistence = _FakePersistence((_) => established(replacement))
        ..statuses.resolution = completed(
          workflow_id: identity.workflow_id,
          event_type: WorkflowStartedEvent.type_id,
        );

      final outcome = await create_application(persistence).start(
        target_id: identity.target_id,
        root: identity.root,
        idempotency_key: 'original-start',
      );

      final resolution = (outcome as WorkflowOperationResolved).resolution;

      expect(resolution.committed_outcome!.workflow_id, identity.workflow_id);
      expect(persistence.read_count, 0);
      expect(persistence.inbox.read_count, 0);
    });

    test('explicit Stop returns a durable absence rejection', () async {
      final persistence = _FakePersistence((_) => absent())
        ..statuses.resolution = rejected(
          WorkflowRejectionCode.workflow_not_active,
        );

      final outcome = await create_application(persistence)
          .stop(workflow_id: 'previous-workflow', idempotency_key: 'stop-001');

      final resolution = (outcome as WorkflowOperationResolved).resolution;

      expect(resolution.state, WorkflowSubmissionState.rejected);
      expect(
        resolution.rejection_code,
        WorkflowRejectionCode.workflow_not_active,
      );

      final command =
          persistence.submissions.accepted.single as WorkflowStopEvent;

      expect(command.workflow_id, 'previous-workflow');
      expect(persistence.submissions.keys, ['stop-001']);
      expect(persistence.read_count, 0);
    });

    test('Stop preserves the requested workflow identity', () async {
      final persistence = _FakePersistence((_) => established(identity))
        ..statuses.resolution = rejected(
          WorkflowRejectionCode.workflow_id_mismatch,
        );

      final outcome = await create_application(persistence)
          .stop(workflow_id: 'previous-workflow', idempotency_key: 'stop-001');

      final resolution = (outcome as WorkflowOperationResolved).resolution;

      expect(
        resolution.rejection_code,
        WorkflowRejectionCode.workflow_id_mismatch,
      );

      final command =
          persistence.submissions.accepted.single as WorkflowStopEvent;

      expect(command.workflow_id, 'previous-workflow');
      expect(persistence.read_count, 0);
    });

    test('Stop returns its historical terminal outcome', () async {
      final persistence = _FakePersistence((_) => absent())
        ..statuses.resolution = completed(
          workflow_id: 'workflow-1',
          event_type: WorkflowEndedEvent.type_id,
        );

      final outcome = await create_application(persistence)
          .stop(workflow_id: 'workflow-1', idempotency_key: 'stop-001');

      final resolution = (outcome as WorkflowOperationResolved).resolution;

      expect(resolution.committed_outcome!.workflow_id, 'workflow-1');
      expect(resolution.committed_outcome!.version, 2);
      expect(persistence.read_count, 0);
      expect(persistence.inbox.read_count, 0);
    });

    test('Stop rejects a contradictory completed outcome', () async {
      final persistence = _FakePersistence((_) => established(identity))
        ..statuses.resolution = completed(
          workflow_id: 'replacement',
          event_type: WorkflowEndedEvent.type_id,
        );

      await expectLater(
        create_application(persistence)
            .stop(workflow_id: 'workflow-1', idempotency_key: 'stop-001'),
        throwsStateError,
      );
    });

    test('Start rejects a contradictory completed outcome', () async {
      final persistence = _FakePersistence((_) => absent())
        ..statuses.resolution = completed(
          workflow_id: 'workflow-1',
          event_type: WorkflowEndedEvent.type_id,
        );

      await expectLater(
        create_application(persistence).start(
          target_id: identity.target_id,
          root: identity.root,
          idempotency_key: 'start-001',
        ),
        throwsStateError,
      );
    });

    test('translates only the explicit idempotency conflict', () async {
      final persistence = _FakePersistence((_) => absent())
        ..submissions.failure = const EventSubmissionException(
          code: EventSubmissionErrorCode.idempotency_conflict,
          message: 'Conflicting operation.',
        );

      final outcome = await create_application(persistence).start(
        target_id: identity.target_id,
        root: identity.root,
        idempotency_key: 'conflicting-key',
      );

      expect(outcome, isA<WorkflowOperationIdempotencyConflict>());
      expect(persistence.submissions.accepted, isEmpty);
      expect(persistence.inbox.read_count, 0);
      expect(persistence.read_count, 0);
    });

    test('preserves unexpected submission failures', () async {
      const failure = EventSubmissionException(
        code: EventSubmissionErrorCode.persistence_failed,
        message: 'Injected persistence failure.',
      );

      final persistence = _FakePersistence((_) => absent())
        ..submissions.failure = failure;

      await expectLater(
        create_application(persistence).start(
          target_id: identity.target_id,
          root: identity.root,
          idempotency_key: 'start-001',
        ),
        throwsA(same(failure)),
      );

      expect(persistence.inbox.read_count, 0);
    });

    test('preserves durable quarantine without processing again', () async {
      final persistence = _FakePersistence((_) => absent())
        ..statuses.resolution = WorkflowSubmissionResolution(
          receipt: _receipt(),
          state: WorkflowSubmissionState.quarantined,
          quarantine_code: WorkflowQuarantineCode.undecodable_command,
          quarantined_at_unix_ms: 1795618800000,
        );

      final outcome = await create_application(persistence).start(
        target_id: identity.target_id,
        root: identity.root,
        idempotency_key: 'start-001',
      );

      final resolution = (outcome as WorkflowOperationResolved).resolution;

      expect(resolution.state, WorkflowSubmissionState.quarantined);
      expect(persistence.inbox.read_count, 0);
    });

    test('rejects blank operation keys without accepting commands', () async {
      final persistence = _FakePersistence((_) => absent());
      final application = create_application(persistence);

      await expectLater(
        application.start(
          target_id: identity.target_id,
          root: identity.root,
          idempotency_key: ' ',
        ),
        throwsArgumentError,
      );

      await expectLater(
        application.stop(
          workflow_id: identity.workflow_id,
          idempotency_key: ' ',
        ),
        throwsArgumentError,
      );

      expect(persistence.submissions.accepted, isEmpty);
    });

    test('rejects a blank Stop workflow identity before submission', () {
      final persistence = _FakePersistence((_) => absent());
      final application = create_application(persistence);

      expect(
        () => application.stop(workflow_id: ' ', idempotency_key: 'stop-001'),
        throwsArgumentError,
      );

      expect(persistence.submissions.accepted, isEmpty);
    });

    test('rejects a resolution belonging to another submission', () async {
      final persistence = _FakePersistence((_) => absent())
        ..statuses.resolution = WorkflowSubmissionResolution(
          receipt: EventSubmissionReceipt(
            event_id: 'another-event',
            correlation_id: 'another-correlation',
          ),
          state: WorkflowSubmissionState.pending,
        );

      await expectLater(
        create_application(persistence).start(
          target_id: identity.target_id,
          root: identity.root,
          idempotency_key: 'start-001',
        ),
        throwsStateError,
      );

      expect(persistence.inbox.read_count, 0);
    });

    test('does not fabricate completion for unresolved acceptance', () async {
      final persistence = _FakePersistence((_) => absent());

      await expectLater(
        create_application(persistence).start(
          target_id: identity.target_id,
          root: identity.root,
          idempotency_key: 'start-001',
        ),
        throwsStateError,
      );

      expect(
        persistence.statuses.resolution.state,
        WorkflowSubmissionState.pending,
      );

      expect(persistence.inbox.read_count, 1);
    });

    test(
      'concurrent identical operations process their submission once',
      () async {
        final persistence = _FakePersistence((_) => absent());
        final application = create_application(persistence);

        final processing_entered = Completer<void>();
        final release_processing = Completer<void>();
        final second_accepted = Completer<void>();

        persistence.submissions.on_accept = () {
          if (persistence.submissions.accepted.length == 2) {
            second_accepted.complete();
          }
        };

        persistence.inbox.read_pending = () async {
          processing_entered.complete();

          await release_processing.future;

          return PendingWorkflowCommand(
            receipt: _receipt(),
            scope_id: 'trusted-scope',
            command: persistence.submissions.accepted.first,
            committed_events: const [],
          );
        };

        persistence.committer.commit_plan = (plan) async {
          persistence.statuses.resolution = completed(
            workflow_id: plan.resulting_state.identity.workflow_id,
            event_type: WorkflowStartedEvent.type_id,
          );
        };

        final first = application.start(
          target_id: identity.target_id,
          root: identity.root,
          idempotency_key: 'shared-start',
        );

        await processing_entered.future;

        final second = application.start(
          target_id: identity.target_id,
          root: identity.root,
          idempotency_key: 'shared-start',
        );

        // The second operation is durably accepted while the first
        // operation still owns the processing lane.
        await second_accepted.future;

        release_processing.complete();

        final outcomes = await Future.wait([first, second]);

        final first_resolution =
            (outcomes.first as WorkflowOperationResolved).resolution;

        final second_resolution =
            (outcomes.last as WorkflowOperationResolved).resolution;

        expect(
          first_resolution.receipt.event_id,
          second_resolution.receipt.event_id,
        );
        expect(
          first_resolution.receipt.correlation_id,
          second_resolution.receipt.correlation_id,
        );

        expect(
          first_resolution.committed_outcome!.workflow_id,
          second_resolution.committed_outcome!.workflow_id,
        );

        expect(persistence.inbox.read_count, 1);
        expect(persistence.committer.commit_count, 1);
        expect(persistence.submissions.keys, ['shared-start', 'shared-start']);
      },
    );

    test(
      'a failed processing operation releases the processing lane',
      () async {
        final persistence = _FakePersistence((_) => absent());
        final application = create_application(persistence);

        final entered = Completer<void>();
        final release = Completer<void>();

        persistence.inbox.read_pending = () async {
          if (persistence.inbox.read_count == 1) {
            entered.complete();

            await release.future;

            throw StateError('Injected processing failure.');
          }

          return null;
        };

        final first = application.process_next();

        final first_failure = expectLater(first, throwsStateError);

        await entered.future;

        final second = application.process_next();

        expect(persistence.inbox.read_count, 1);

        release.complete();

        await first_failure;

        expect(await second, isA<WorkflowProcessingIdle>());
        expect(persistence.inbox.read_count, 2);
      },
    );

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

  /// Controlled inbox supplying processing evidence.
  final _ControlledInbox inbox = _ControlledInbox();

  /// Controlled committer supplying durable completion behavior.
  final _ControlledCommitter committer = _ControlledCommitter();

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

  /// Supplies the controlled inbox for trusted [os_user_id] processing.
  @override
  WorkflowInbox workflow_inbox_for({required String os_user_id}) => inbox;

  /// Supplies the controlled committer for trusted [os_user_id].
  @override
  WorkflowCommitter workflow_committer_for({required String os_user_id}) =>
      committer;
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

/// Controlled application submission boundary.
///
/// Records acceptance invocations and can simulate durable acceptance
/// of an identical operation using the same original receipt.
final class _SubmissionStore implements EventSubmissionStore {
  /// Accepted command invocations in submission order.
  final List<WorkflowCommandEvent> accepted = [];

  /// Idempotency keys supplied to acceptance invocations.
  final List<String?> keys = [];

  /// Optional injected submission failure.
  EventSubmissionException? failure;

  /// Optional callback notified after successful acceptance.
  void Function()? on_accept;

  /// Accepts [event] using the supplied [idempotency_key].
  ///
  /// Returns the stable test receipt or propagates the injected failure.
  @override
  Future<EventSubmissionReceipt> accept(
    WorkflowCommandEvent event, {
    String? idempotency_key,
  }) async {
    final injected_failure = failure;

    if (injected_failure != null) {
      throw injected_failure;
    }

    accepted.add(event);
    keys.add(idempotency_key);

    on_accept?.call();

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

/// Controlled inbox for application processing tests.
final class _ControlledInbox implements WorkflowInbox {
  /// Number of pending submission reads.
  int read_count = 0;

  /// Optional asynchronous pending-command provider.
  Future<PendingWorkflowCommand?> Function()? read_pending;

  /// Returns controlled pending evidence or null when none is configured.
  @override
  Future<PendingWorkflowCommand?> next_pending() async {
    read_count++;

    final operation = read_pending;

    if (operation == null) {
      return null;
    }

    return await operation();
  }
}

/// Controlled commitment boundary for application execution tests.
final class _ControlledCommitter implements WorkflowCommitter {
  /// Number of commitment attempts.
  int commit_count = 0;

  /// Optional operation implementing simulated durable commitment.
  Future<void> Function(WorkflowProcessingPlan plan)? commit_plan;

  /// Commits [plan] using the configured fixture operation.
  ///
  /// Throws [StateError] when an unexpected commitment is attempted.
  @override
  Future<void> commit(WorkflowProcessingPlan plan) async {
    commit_count++;

    final operation = commit_plan;

    if (operation == null) {
      throw StateError('Unexpected workflow commit.');
    }

    await operation(plan);
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
