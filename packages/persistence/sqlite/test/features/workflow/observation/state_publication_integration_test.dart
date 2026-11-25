import 'dart:async';
import 'dart:io';

import 'package:rudra_persistence_sqlite/rudra_persistence_sqlite.dart';
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Verifies shared state publication over authoritative SQLite persistence.
void main() {
  const owner = 'trusted-owner';
  const generation = 'test-generation';
  const observation_timeout = Duration(seconds: 5);

  late Directory directory;
  late File database_file;
  late RudraSqlitePersistence persistence;
  late WorkflowApplication application;
  late StatePublication publication;
  late int observation_count;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'rudra-state-publication-',
    );

    database_file = File('${directory.path}/rudra.db');

    final runtime = WorkflowRuntime.standard();

    persistence = RudraSqlitePersistence(
      database_file: database_file,
      scope_id: 'test-scope',
      runtime: runtime,
    );

    application = WorkflowApplication(
      runtime: runtime,
      persistence: persistence,
      identity_provider: _IdentityProvider(owner),
      os_user_id: owner,
    );

    observation_count = 0;

    publication = StatePublication(
      generation: generation,
      observe_state: () {
        observation_count++;
        return application.observe_state();
      },
    );
  });

  tearDown(() async {
    try {
      await publication.close();
    } finally {
      try {
        await persistence.close();
      } finally {
        await directory.delete(recursive: true);
      }
    }
  });

  test(
    'publication and observation do not initialize missing storage',
    () async {
      expect(await database_file.exists(), isFalse);
      expect(observation_count, 0);

      final initial = Completer<StatePublicationSnapshot>();

      final ready = publication.start();

      final subscription = publication.subscribe(
        deliver: (snapshot) async {
          initial.complete(snapshot);
        },
      );

      await ready.timeout(observation_timeout);

      final snapshot = await initial.future.timeout(observation_timeout);

      expect(snapshot.generation, generation);
      expect(snapshot.revision, 1);
      expect(snapshot.state.workflows.current_workflow, isNull);
      expect(await database_file.exists(), isFalse);
      expect(observation_count, 1);

      await subscription.cancel();
      await publication.close();

      expect(await database_file.exists(), isFalse);
    },
  );

  test('shares verified Start and Stop across subscribers', () async {
    final first = _PublicationProbe();
    final second = _PublicationProbe();

    final ready = publication.start();

    publication.subscribe(deliver: first.deliver);
    publication.subscribe(deliver: second.deliver);

    await ready.timeout(observation_timeout);

    final first_initial = await first.at(0).timeout(observation_timeout);
    final second_initial = await second.at(0).timeout(observation_timeout);

    expect(first_initial, same(second_initial));
    expect(first_initial.revision, 1);
    expect(first_initial.state.workflows.current_workflow, isNull);
    expect(await database_file.exists(), isFalse);

    final started = _require_committed(
      await application.start(
        target_id: 'local-macos',
        root: TargetPath('/workspace'),
        idempotency_key: 'start-workspace',
      ),
    );

    final first_active = await first.at(1).timeout(observation_timeout);
    final second_active = await second.at(1).timeout(observation_timeout);

    expect(first_active, same(second_active));
    expect(first_active.revision, 2);
    expect(
      first_active.state.workflows.current_workflow?.identity.workflow_id,
      started.workflow_id,
    );
    expect(first_active.state.workflows.current_workflow?.version, 1);
    expect(await database_file.exists(), isTrue);

    final stopped = _require_committed(
      await application.stop(
        workflow_id: started.workflow_id,
        idempotency_key: 'stop-workspace',
      ),
    );

    expect(stopped.workflow_id, started.workflow_id);

    final first_ended = await first.at(2).timeout(observation_timeout);
    final second_ended = await second.at(2).timeout(observation_timeout);

    expect(first_ended, same(second_ended));
    expect(first_ended.revision, 3);
    expect(first_ended.state.workflows.current_workflow, isNull);

    expect(publication.latest, same(first_ended));
    expect(observation_count, 1);

    final late = _PublicationProbe();

    publication.subscribe(deliver: late.deliver);

    final late_initial = await late.at(0).timeout(observation_timeout);

    expect(late_initial, same(first_ended));
    expect(observation_count, 1);
  });

  test(
    'restores existing committed state without executing a command',
    () async {
      final started = _require_committed(
        await application.start(
          target_id: 'local-macos',
          root: TargetPath('/workspace'),
          idempotency_key: 'start-workspace',
        ),
      );

      final probe = _PublicationProbe();

      final ready = publication.start();

      publication.subscribe(deliver: probe.deliver);

      await ready.timeout(observation_timeout);

      final initial = await probe.at(0).timeout(observation_timeout);

      expect(initial.revision, 1);
      expect(initial.generation, generation);
      expect(
        initial.state.workflows.current_workflow?.identity.workflow_id,
        started.workflow_id,
      );
      expect(initial.state.workflows.current_workflow?.version, 1);

      final evidence = await persistence.workflow_history_store
          .load_restoration_evidence(os_user_id: owner);

      expect(evidence.projected?.journal, hasLength(1));
      expect(evidence.other_histories, isEmpty);
      expect(observation_count, 1);
    },
  );
}

/// Extracts the original committed reference from an application [outcome].
///
/// Requires successful durable completion before returning the reference.
WorkflowCommittedOutcome _require_committed(WorkflowOperationOutcome outcome) {
  expect(outcome, isA<WorkflowOperationResolved>());

  final resolution = (outcome as WorkflowOperationResolved).resolution;

  expect(resolution.state, WorkflowSubmissionState.completed);

  return resolution.committed_outcome!;
}

/// Supplies distinct owner-bound workflow identities for integration tests.
final class _IdentityProvider implements WorkflowIdentityProvider {
  /// Creates an identity provider for trusted [owner].
  _IdentityProvider(this.owner);

  /// Trusted owner associated with proposed workflow identities.
  final String owner;

  /// Last allocated workflow ordinal.
  int _sequence = 0;

  /// Proposes an identity for an accepted Start [submission].
  ///
  /// Returns a distinct owner-bound identity preserving target and root.
  /// Throws [StateError] for unsupported commands.
  @override
  Future<WorkflowIdentity> propose_identity(
    PendingWorkflowCommand submission,
  ) async {
    final command = submission.command;

    if (command is! WorkflowStartEvent) {
      throw StateError('Only Start establishes workflow identity.');
    }

    return WorkflowIdentity(
      workflow_id: 'workflow-${++_sequence}',
      os_user_id: owner,
      target_id: command.target_id,
      root: command.root,
    );
  }
}

/// Records acknowledged publications for deterministic integration tests.
final class _PublicationProbe {
  /// Publications accepted by this consumer.
  final List<StatePublicationSnapshot> values = [];

  /// Notification of the next accepted publication.
  Completer<void> _changed = Completer<void>();

  /// Accepts and acknowledges [publication].
  Future<void> deliver(StatePublicationSnapshot publication) async {
    values.add(publication);

    final changed = _changed;
    _changed = Completer<void>();
    changed.complete();
  }

  /// Returns the accepted publication at zero-based [index].
  ///
  /// Waits until the requested publication has been delivered.
  Future<StatePublicationSnapshot> at(int index) async {
    while (values.length <= index) {
      await _changed.future;
    }

    return values[index];
  }
}
