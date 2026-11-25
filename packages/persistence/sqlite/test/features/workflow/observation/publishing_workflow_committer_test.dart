import 'dart:async';
import 'dart:io';

import 'package:rudra_persistence_sqlite/rudra_persistence_sqlite.dart';
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Verifies notifications against real SQLite workflow commitments.
void main() {
  const os_user_id = 'trusted-owner';
  const notification_timeout = Duration(seconds: 5);

  final runtime = WorkflowRuntime.standard();

  late Directory directory;
  late RudraSqlitePersistence persistence;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'rudra-commit-observation-',
    );

    persistence = RudraSqlitePersistence(
      database_file: File('${directory.path}/rudra.db'),
      scope_id: 'test-scope',
      runtime: runtime,
    );
  });

  tearDown(() async {
    await persistence.close();
    await directory.delete(recursive: true);
  });

  WorkflowApplication create_application() => WorkflowApplication(
    runtime: runtime,
    persistence: persistence,
    identity_provider: const _TestIdentityProvider(os_user_id),
    os_user_id: os_user_id,
  );

  test('publishes after committed Start and Stop', () async {
    final application = create_application();

    final first_signal = Completer<void>();
    final second_signal = Completer<void>();

    var signal_count = 0;
    var foreign_signal_count = 0;

    final subscription = persistence.workflow_commit_subscriber
        .watch(os_user_id: os_user_id)
        .listen((_) {
          signal_count++;

          if (signal_count == 1) first_signal.complete();
          if (signal_count == 2) second_signal.complete();
        });

    final foreign_subscription = persistence.workflow_commit_subscriber
        .watch(os_user_id: 'another-owner')
        .listen((_) => foreign_signal_count++);

    try {
      final started_outcome = await application.start(
        target_id: 'local-macos',
        root: TargetPath('/workspace'),
        idempotency_key: 'start-workspace',
      );

      expect(started_outcome, isA<WorkflowOperationResolved>());

      final started_resolution =
          (started_outcome as WorkflowOperationResolved).resolution;

      expect(started_resolution.state, WorkflowSubmissionState.completed);

      final started = started_resolution.committed_outcome!;

      await first_signal.future.timeout(notification_timeout);

      expect(started.version, 1);
      expect(signal_count, 1);

      final active = await application.read_state();
      expect(active.workflows.current_workflow?.version, 1);

      final stopped_outcome = await application.stop(
        workflow_id: started.workflow_id,
        idempotency_key: 'stop-workspace',
      );

      expect(stopped_outcome, isA<WorkflowOperationResolved>());

      final stopped_resolution =
          (stopped_outcome as WorkflowOperationResolved).resolution;

      expect(stopped_resolution.state, WorkflowSubmissionState.completed);

      await second_signal.future.timeout(notification_timeout);

      expect(
        stopped_resolution.committed_outcome!.workflow_id,
        started.workflow_id,
      );
      expect(signal_count, 2);
      expect(foreign_signal_count, 0);

      final ended = await application.read_state();
      expect(ended.workflows.current_workflow, isNull);
    } finally {
      await subscription.cancel();
      await foreign_subscription.cancel();
    }
  });

  test('does not publish acceptance, rejection or failed commits', () async {
    final application = create_application();

    final first_signal = Completer<void>();
    var signal_count = 0;

    final subscription = persistence.workflow_commit_subscriber
        .watch(os_user_id: os_user_id)
        .listen((_) {
          signal_count++;
          if (signal_count == 1) first_signal.complete();
        });

    try {
      final receipt = await application.submit_command(
        WorkflowStartEvent(
          target_id: 'local-macos',
          root: TargetPath('/workspace'),
        ),
      );

      expect(
        (await application.status_for(receipt))?.state,
        WorkflowSubmissionState.pending,
      );
      expect(signal_count, 0);

      final result = await application.process_next();
      expect(result, isA<WorkflowProcessingCommitted>());

      await first_signal.future.timeout(notification_timeout);
      expect(signal_count, 1);

      // A second Start is a business rejection, not a domain change.
      await application.submit_command(
        WorkflowStartEvent(
          target_id: 'local-macos',
          root: TargetPath('/another'),
        ),
      );

      expect(
        await application.process_next(),
        isA<WorkflowProcessingRejected>(),
      );

      // A completed submission cannot be committed a second time.
      final plan = (result as WorkflowProcessingCommitted).plan;

      await expectLater(
        persistence.workflow_committer_for(os_user_id: os_user_id).commit(plan),
        throwsA(isA<WorkflowCommitException>()),
      );

      await Future<void>.delayed(Duration.zero);
      expect(signal_count, 1);
    } finally {
      await subscription.cancel();
    }
  });
}

/// Supplies a deterministic trusted identity for integration tests.
final class _TestIdentityProvider implements WorkflowIdentityProvider {
  /// Binds the identity provider to the trusted [os_user_id].
  const _TestIdentityProvider(this.os_user_id);

  final String os_user_id;

  /// Proposes a workflow identity for an accepted Start submission.
  ///
  /// Returns an owner-bound identity using the submitted target and root.
  /// Other commands throw [StateError].
  @override
  Future<WorkflowIdentity> propose_identity(
    PendingWorkflowCommand submission,
  ) async {
    final command = submission.command;
    if (command is! WorkflowStartEvent) {
      throw StateError('Only Start establishes a workflow identity.');
    }

    return WorkflowIdentity(
      workflow_id: 'workflow-1',
      os_user_id: os_user_id,
      target_id: command.target_id,
      root: command.root,
    );
  }
}
