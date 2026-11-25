import 'dart:async';

import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:rudra_sdk/src/workflow/observation/workflow_state_observer.dart';
import 'package:test/test.dart';

/// Verifies SDK observation independently of persistence adapters.
void main() {
  const owner = 'trusted-owner';

  final absent = RudraState(workflows: WorkflowsState(current_workflow: null));

  final runtime = WorkflowRuntime.standard();

  final identity = WorkflowIdentity(
    workflow_id: 'workflow-1',
    os_user_id: owner,
    target_id: 'local-macos',
    root: TargetPath('/workspace'),
  );

  final active = RudraState(
    workflows: WorkflowsState(
      current_workflow: WorkflowStateMachine(runtime: runtime).transition(
        state: null,
        event: WorkflowStartedEvent(identity: identity),
      ),
    ),
  );

  Future<void> flush() => Future<void>.delayed(Duration.zero);

  test('publishes initial verified state', () async {
    final commits = LocalWorkflowCommitChannel();

    final observer = WorkflowStateObserver(
      read_state: () async => absent,
      commits: commits,
      os_user_id: owner,
    );

    final values = <RudraState>[];
    final subscription = observer.observe().listen(values.add);

    await flush();

    expect(values, hasLength(1));
    expect(values.single.workflows.current_workflow, isNull);

    await subscription.cancel();
    await commits.close();
  });

  test('reconstructs state following a committed change', () async {
    final commits = LocalWorkflowCommitChannel();
    var current = absent;

    final observer = WorkflowStateObserver(
      read_state: () async => current,
      commits: commits,
      os_user_id: owner,
    );

    final values = <RudraState>[];
    final subscription = observer.observe().listen(values.add);

    await flush();

    current = active;
    commits.publish(os_user_id: owner);

    await flush();

    expect(values, hasLength(2));
    expect(
      values.last.workflows.current_workflow?.identity.workflow_id,
      'workflow-1',
    );

    current = absent;
    commits.publish(os_user_id: owner);

    await flush();

    expect(values, hasLength(3));
    expect(values.last.workflows.current_workflow, isNull);

    await subscription.cancel();
    await commits.close();
  });

  test('reconciles a commit overlapping initial restoration', () async {
    final commits = LocalWorkflowCommitChannel();
    final read_started = Completer<void>();
    final release_first_read = Completer<void>();

    var current = absent;
    var read_count = 0;

    final observer = WorkflowStateObserver(
      read_state: () async {
        final snapshot = current;
        read_count++;

        if (read_count == 1) {
          read_started.complete();
          await release_first_read.future;
        }

        return snapshot;
      },
      commits: commits,
      os_user_id: owner,
    );

    final values = <RudraState>[];
    final subscription = observer.observe().listen(values.add);

    await read_started.future;

    current = active;
    commits.publish(os_user_id: owner);

    await flush();
    release_first_read.complete();
    await flush();

    expect(read_count, 2);
    expect(values, hasLength(1));
    expect(values.single.workflows.current_workflow, isNotNull);

    await subscription.cancel();
    await commits.close();
  });

  test('propagates restoration failure instead of reporting absence', () async {
    final commits = LocalWorkflowCommitChannel();

    final observer = WorkflowStateObserver(
      read_state: () async => throw StateError('Corrupt journal'),
      commits: commits,
      os_user_id: owner,
    );

    await expectLater(observer.observe().first, throwsStateError);
    await commits.close();
  });

  test('cancellation prevents subsequent updates', () async {
    final commits = LocalWorkflowCommitChannel();
    var read_count = 0;

    final observer = WorkflowStateObserver(
      read_state: () async {
        read_count++;
        return absent;
      },
      commits: commits,
      os_user_id: owner,
    );

    final subscription = observer.observe().listen((_) {});

    await flush();
    expect(read_count, 1);

    await subscription.cancel();

    commits.publish(os_user_id: owner);
    await flush();

    expect(read_count, 1);
    await commits.close();
  });

  test('reconciles overlapping changes to the latest workflow', () async {
    final commits = LocalWorkflowCommitChannel();

    final replacement_identity = WorkflowIdentity(
      workflow_id: 'workflow-2',
      os_user_id: owner,
      target_id: 'local-macos',
      root: TargetPath('/replacement'),
    );

    final replacement = RudraState(
      workflows: WorkflowsState(
        current_workflow: WorkflowStateMachine(runtime: runtime).transition(
          state: null,
          event: WorkflowStartedEvent(identity: replacement_identity),
        ),
      ),
    );

    final second_read_started = Completer<void>();
    final release_second_read = Completer<void>();
    final initial_seen = Completer<void>();
    final replacement_seen = Completer<void>();

    var current = absent;
    var read_count = 0;

    final observer = WorkflowStateObserver(
      read_state: () async {
        read_count++;
        final sampled_state = current;

        if (read_count == 2) {
          second_read_started.complete();
          await release_second_read.future;
        }

        return sampled_state;
      },
      commits: commits,
      os_user_id: owner,
    );

    final values = <RudraState>[];

    final subscription = observer.observe().listen((state) {
      values.add(state);

      if (values.length == 1 && !initial_seen.isCompleted) {
        initial_seen.complete();
      }

      if (state.workflows.current_workflow?.identity.workflow_id ==
              'workflow-2' &&
          !replacement_seen.isCompleted) {
        replacement_seen.complete();
      }
    });

    try {
      await initial_seen.future;

      // Start the second read while workflow-1 is current.
      current = active;
      commits.publish(os_user_id: owner);
      await second_read_started.future;

      // Both changes arrive before that stale read completes.
      current = absent;
      commits.publish(os_user_id: owner);

      current = replacement;
      commits.publish(os_user_id: owner);

      await flush();
      release_second_read.complete();

      await replacement_seen.future;

      // Initial absence and the latest replacement are published.
      // Intermediate states may be coalesced.
      expect(read_count, 3);
      expect(values, hasLength(2));
      expect(
        values.last.workflows.current_workflow?.identity.workflow_id,
        'workflow-2',
      );
    } finally {
      if (!release_second_read.isCompleted) {
        release_second_read.complete();
      }

      await subscription.cancel();
      await commits.close();
    }
  });

  test('source shutdown terminates observation with an error', () async {
    final commits = LocalWorkflowCommitChannel();

    final initial_seen = Completer<void>();
    final failure_seen = Completer<Object>();
    final done_seen = Completer<void>();

    final observer = WorkflowStateObserver(
      read_state: () async => absent,
      commits: commits,
      os_user_id: owner,
    );

    final subscription = observer.observe().listen(
      (_) {
        if (!initial_seen.isCompleted) {
          initial_seen.complete();
        }
      },
      onError: (Object error, StackTrace stack_trace) {
        failure_seen.complete(error);
      },
      onDone: done_seen.complete,
    );

    await initial_seen.future;

    // Losing the change source is not equivalent to verified absence.
    await commits.close();

    expect(await failure_seen.future, isA<StateError>());
    await done_seen.future;

    await subscription.cancel();
  });

  test('restoration failure after a commit terminates observation', () async {
    final commits = LocalWorkflowCommitChannel();

    final initial_seen = Completer<void>();
    final failure_seen = Completer<Object>();
    final done_seen = Completer<void>();

    var read_count = 0;

    final observer = WorkflowStateObserver(
      read_state: () async {
        read_count++;

        if (read_count == 1) {
          return absent;
        }

        throw StateError('Committed journal is unreadable.');
      },
      commits: commits,
      os_user_id: owner,
    );

    final subscription = observer.observe().listen(
      (_) {
        if (!initial_seen.isCompleted) {
          initial_seen.complete();
        }
      },
      onError: (Object error, StackTrace stack_trace) {
        failure_seen.complete(error);
      },
      onDone: done_seen.complete,
    );

    try {
      await initial_seen.future;
      commits.publish(os_user_id: owner);

      expect(await failure_seen.future, isA<StateError>());
      await done_seen.future;
      expect(read_count, 2);
    } finally {
      await subscription.cancel();
      await commits.close();
    }
  });

  test(
    'cancellation drains restoration and suppresses the pending state',
    () async {
      final commits = LocalWorkflowCommitChannel();

      final read_started = Completer<void>();
      final release_read = Completer<void>();
      final read_finished = Completer<void>();

      final values = <RudraState>[];
      var read_count = 0;

      final observer = WorkflowStateObserver(
        read_state: () async {
          read_count++;
          read_started.complete();

          await release_read.future;
          read_finished.complete();

          return absent;
        },
        commits: commits,
        os_user_id: owner,
      );

      final subscription = observer.observe().listen(values.add);

      await read_started.future;

      var cancellation_completed = false;

      final cancellation = subscription.cancel().then<void>((_) {
        cancellation_completed = true;
      });

      try {
        await Future<void>.value();

        // Cancellation must retain the outstanding restoration.
        expect(cancellation_completed, isFalse);
        expect(read_finished.isCompleted, isFalse);
      } finally {
        release_read.complete();
        await cancellation;
      }

      expect(read_finished.isCompleted, isTrue);
      expect(cancellation_completed, isTrue);

      await flush();

      // The completed read must not publish into a cancelled subscription.
      expect(values, isEmpty);

      commits.publish(os_user_id: owner);
      await flush();

      expect(read_count, 1);
      await commits.close();
    },
  );
}
