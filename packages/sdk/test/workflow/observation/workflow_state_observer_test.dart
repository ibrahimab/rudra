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
}
