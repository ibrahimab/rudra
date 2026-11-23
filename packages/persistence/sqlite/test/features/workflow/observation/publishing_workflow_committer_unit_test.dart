import 'package:rudra_persistence_sqlite/src/features/workflow/observation/publishing_workflow_committer.dart';
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Tests the publishing decorator independently of SQLite transactions.
void main() {
  const owner = 'trusted-owner';

  /// Creates a valid processing proposal for a deterministic Start outcome.
  WorkflowProcessingPlan create_plan() {
    final identity = WorkflowIdentity(
      workflow_id: 'workflow-1',
      os_user_id: owner,
      target_id: 'local-macos',
      root: TargetPath('/workspace'),
    );

    final outcome = WorkflowStartedEvent(identity: identity);

    return WorkflowProcessingPlan(
      submission: PendingWorkflowCommand(
        receipt: EventSubmissionReceipt(
          event_id: 'submission-1',
          correlation_id: 'correlation-1',
        ),
        scope_id: 'test-scope',
        command: WorkflowStartEvent(
          target_id: identity.target_id,
          root: identity.root,
        ),
      ),
      previous_state: null,
      resulting_state: WorkflowStateMachine(runtime: WorkflowRuntime.standard())
          .transition(state: null, event: outcome),
      events_to_append: [outcome],
    );
  }

  test('publication failure does not invalidate a committed result', () async {
    final delegate = _RecordingCommitter();
    final publisher = _RecordingPublisher(should_throw: true);

    final committer = PublishingWorkflowCommitter(
      delegate: delegate,
      publisher: publisher,
      os_user_id: owner,
    );

    await expectLater(committer.commit(create_plan()), completes);

    expect(delegate.commit_count, 1);
    expect(publisher.publish_count, 1);
    expect(publisher.last_owner, owner);
  });

  test('failed persistence does not publish', () async {
    final delegate = _RecordingCommitter(should_throw: true);
    final publisher = _RecordingPublisher();

    final committer = PublishingWorkflowCommitter(
      delegate: delegate,
      publisher: publisher,
      os_user_id: owner,
    );

    await expectLater(committer.commit(create_plan()), throwsStateError);

    expect(delegate.commit_count, 1);
    expect(publisher.publish_count, 0);
  });
}

/// Simulates a persistence committer with configurable failure behavior.
final class _RecordingCommitter implements WorkflowCommitter {
  /// Creates a committer; [should_throw] simulates transactional failure.
  _RecordingCommitter({this.should_throw = false});

  /// Whether commitment should fail before successful completion.
  final bool should_throw;

  /// Number of attempted commitments.
  int commit_count = 0;

  /// Attempts to commit [plan].
  ///
  /// Returns normally when configured to succeed, otherwise throws
  /// [StateError]. No actual persistence is performed.
  @override
  Future<void> commit(WorkflowProcessingPlan plan) async {
    commit_count++;

    if (should_throw) {
      throw StateError('Simulated persistence failure.');
    }
  }
}

/// Records publication attempts and optionally simulates delivery failure.
final class _RecordingPublisher implements WorkflowCommitPublisher {
  /// Creates a publisher with configurable [should_throw] behavior.
  _RecordingPublisher({this.should_throw = false});

  /// Whether publication should throw after recording the attempt.
  final bool should_throw;

  /// Number of publication attempts.
  int publish_count = 0;

  /// Trusted owner supplied in the most recent publication attempt.
  String? last_owner;

  /// Records a publication for [os_user_id].
  ///
  /// Throws [StateError] when configured to simulate notifier failure.
  @override
  void publish({required String os_user_id}) {
    publish_count++;
    last_owner = os_user_id;

    if (should_throw) {
      throw StateError('Simulated publication failure.');
    }
  }
}
