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

  test('observes verified absence, Start and Stop', () async {
    // Initialize durable persistence through explicit workflow operations.
    // The new subscription must restore the resulting verified absence.
    final seeded = await application.start(
      target_id: 'local-macos',
      root: TargetPath('/seed'),
    );

    await application.stop(expected_workflow_id: seeded.identity.workflow_id);

    final iterator = StreamIterator<RudraState>(application.observe_state());

    try {
      final initial = await next_state(iterator);
      expect(initial.workflows.current_workflow, isNull);

      final started = await application.start(
        target_id: 'local-macos',
        root: TargetPath('/workspace'),
      );

      final active = await next_state(iterator);

      expect(
        active.workflows.current_workflow?.identity.workflow_id,
        started.identity.workflow_id,
      );
      expect(active.workflows.current_workflow?.version, 1);
      expect(
        active.workflows.current_workflow?.identity.root.value,
        '/workspace',
      );

      await application.stop(
        expected_workflow_id: started.identity.workflow_id,
      );

      final ended = await next_state(iterator);
      expect(ended.workflows.current_workflow, isNull);
    } finally {
      await iterator.cancel();
    }
  });

  test('multiple consumers receive committed state changes', () async {
    final started = await application.start(
      target_id: 'local-macos',
      root: TargetPath('/workspace'),
    );

    final first = StreamIterator<RudraState>(application.observe_state());

    final second = StreamIterator<RudraState>(application.observe_state());

    try {
      final first_initial = await next_state(first);
      final second_initial = await next_state(second);

      expect(
        first_initial.workflows.current_workflow?.identity.workflow_id,
        started.identity.workflow_id,
      );

      expect(
        second_initial.workflows.current_workflow?.identity.workflow_id,
        started.identity.workflow_id,
      );

      await application.stop(
        expected_workflow_id: started.identity.workflow_id,
      );

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
