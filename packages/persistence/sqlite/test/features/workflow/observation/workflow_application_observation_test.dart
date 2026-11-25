import 'dart:async';
import 'dart:io';

import 'package:rudra_persistence_sqlite/rudra_persistence_sqlite.dart';
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Verifies authoritative SDK observation over committed SQLite history.
///
/// The tests use public persistence and application contracts. Each test
/// owns its database connection and releases subscriptions before cleanup.
void main() {
  const os_user_id = 'trusted-owner';
  const observation_timeout = Duration(seconds: 5);

  final runtime = WorkflowRuntime.standard();

  late Directory directory;
  late RudraSqlitePersistence persistence;
  late WorkflowApplication application;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'rudra-application-observation-',
    );

    persistence = RudraSqlitePersistence(
      database_file: File('${directory.path}/rudra.db'),
      scope_id: 'test-scope',
      runtime: runtime,
    );

    application = WorkflowApplication(
      runtime: runtime,
      persistence: persistence,
      identity_provider: _SequentialIdentityProvider(os_user_id: os_user_id),
      os_user_id: os_user_id,
    );
  });

  tearDown(() async {
    await persistence.close();
    await directory.delete(recursive: true);
  });

  /// Retrieves the next observed state within [observation_timeout].
  ///
  /// Returns the next immutable application state. Throws [StateError] if
  /// the stream ends unexpectedly; timeout and stream errors propagate.
  Future<RudraState> next_state(StreamIterator<RudraState> iterator) async {
    final has_value = await iterator.moveNext().timeout(observation_timeout);

    if (!has_value) {
      throw StateError('Application observation ended unexpectedly.');
    }

    return iterator.current;
  }

  test('observation does not initialize missing SQLite storage', () async {
    final database_file = File('${directory.path}/rudra.db');

    expect(await database_file.exists(), isFalse);

    final iterator = StreamIterator<RudraState>(application.observe_state());

    try {
      // Initial observation restores absence without opening SQLite.
      final initial = await next_state(iterator);

      expect(initial.workflows.current_workflow, isNull);
      expect(await database_file.exists(), isFalse);

      // An explicit Start submission may initialize durable storage.
      final started = _committed(
        await application.start(
          target_id: 'local-macos',
          root: TargetPath('/workspace'),
          idempotency_key: 'start-workspace',
        ),
      );

      expect(await database_file.exists(), isTrue);

      // The existing subscription must observe the committed workflow.
      final active = await next_state(iterator);

      expect(
        active.workflows.current_workflow?.identity.workflow_id,
        started.workflow_id,
      );
      expect(active.workflows.current_workflow?.version, 1);
    } finally {
      await iterator.cancel();
    }
  });

  test('observes verified absence, Start and Stop', () async {
    // Initialize durable persistence through explicit workflow operations.
    // The new subscription must restore the resulting verified absence.
    final seeded = _committed(
      await application.start(
        target_id: 'local-macos',
        root: TargetPath('/seed'),
        idempotency_key: 'start-seed',
      ),
    );

    final seed_stop = _committed(
      await application.stop(
        workflow_id: seeded.workflow_id,
        idempotency_key: 'stop-seed',
      ),
    );

    expect(seed_stop.workflow_id, seeded.workflow_id);

    final iterator = StreamIterator<RudraState>(application.observe_state());

    try {
      final initial = await next_state(iterator);
      expect(initial.workflows.current_workflow, isNull);

      final started = _committed(
        await application.start(
          target_id: 'local-macos',
          root: TargetPath('/workspace'),
          idempotency_key: 'start-workspace',
        ),
      );

      final active = await next_state(iterator);

      expect(
        active.workflows.current_workflow?.identity.workflow_id,
        started.workflow_id,
      );
      expect(active.workflows.current_workflow?.version, 1);
      expect(
        active.workflows.current_workflow?.identity.root.value,
        '/workspace',
      );

      final stopped = _committed(
        await application.stop(
          workflow_id: started.workflow_id,
          idempotency_key: 'stop-workspace',
        ),
      );

      expect(stopped.workflow_id, started.workflow_id);

      final ended = await next_state(iterator);
      expect(ended.workflows.current_workflow, isNull);
    } finally {
      await iterator.cancel();
    }
  });

  test('multiple consumers receive committed state changes', () async {
    final started = _committed(
      await application.start(
        target_id: 'local-macos',
        root: TargetPath('/workspace'),
        idempotency_key: 'start-workspace',
      ),
    );

    final first = StreamIterator<RudraState>(application.observe_state());

    final second = StreamIterator<RudraState>(application.observe_state());

    try {
      final first_initial = await next_state(first);
      final second_initial = await next_state(second);

      expect(
        first_initial.workflows.current_workflow?.identity.workflow_id,
        started.workflow_id,
      );

      expect(
        second_initial.workflows.current_workflow?.identity.workflow_id,
        started.workflow_id,
      );

      final stopped = _committed(
        await application.stop(
          workflow_id: started.workflow_id,
          idempotency_key: 'stop-workspace',
        ),
      );

      expect(stopped.workflow_id, started.workflow_id);

      final first_ended = await next_state(first);
      final second_ended = await next_state(second);

      expect(first_ended.workflows.current_workflow, isNull);
      expect(second_ended.workflows.current_workflow, isNull);
    } finally {
      await first.cancel();
      await second.cancel();
    }
  });
}

/// Extracts the committed journal reference from an application [outcome].
///
/// Asserts successful durable completion before returning the original
/// committed outcome reference.
WorkflowCommittedOutcome _committed(WorkflowOperationOutcome outcome) {
  expect(outcome, isA<WorkflowOperationResolved>());

  final resolution = (outcome as WorkflowOperationResolved).resolution;

  expect(resolution.state, WorkflowSubmissionState.completed);

  return resolution.committed_outcome!;
}

/// Generates distinct workflow identities for explicit Start operations.
///
/// The trusted owner is supplied by test composition, while each accepted
/// Start determines its target and root.
final class _SequentialIdentityProvider implements WorkflowIdentityProvider {
  /// Creates an identity provider for trusted [os_user_id].
  ///
  /// Construction does not access persistence or generate an identity.
  _SequentialIdentityProvider({required this.os_user_id});

  /// Authenticated owner assigned to proposed workflow identities.
  final String os_user_id;

  /// Next workflow ordinal, local to this test application.
  int _next_workflow_number = 0;

  /// Proposes a distinct identity for the accepted [submission].
  ///
  /// Returns an identity bound to the trusted owner, target and root.
  /// Throws [StateError] for commands other than Start.
  @override
  Future<WorkflowIdentity> propose_identity(
    PendingWorkflowCommand submission,
  ) async {
    final command = submission.command;

    if (command is! WorkflowStartEvent) {
      throw StateError('Only Start may establish workflow identity.');
    }

    _next_workflow_number++;

    return WorkflowIdentity(
      workflow_id: 'workflow-$_next_workflow_number',
      os_user_id: os_user_id,
      target_id: command.target_id,
      root: command.root,
    );
  }
}
