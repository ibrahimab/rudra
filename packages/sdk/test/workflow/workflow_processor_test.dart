import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Verifies processing orchestration with independent test doubles.
void main() {
  late WorkflowModuleRegistry registry;

  setUp(() {
    registry = WorkflowModuleRegistry()
      ..register(const LifecycleWorkflowModule());
  });

  test('commits a validated workflow start', () async {
    final inbox = _FakeWorkflowInbox(_pending());
    final committer = _FakeWorkflowCommitter();

    final processor = WorkflowProcessor(
      registry: registry,
      inbox: inbox,
      identity_provider: _FakeWorkflowIdentityProvider(),
      committer: committer,
    );

    final plan = await processor.process_next();

    expect(plan, isNotNull);
    expect(committer.committed, same(plan));

    expect(plan!.previous_state, isA<WorkflowInitialState>());
    expect(plan.resulting_state, isA<WorkflowActiveState>());

    expect(plan.previous_state.version, 0);
    expect(plan.resulting_state.version, 2);

    expect(plan.events_to_append, hasLength(2));
    expect(plan.events_to_append.first, isA<WorkflowStartEvent>());
    expect(plan.events_to_append.last, isA<WorkflowStartedEvent>());

    expect(
      (plan.resulting_state as WorkflowActiveState).identity.workflow_id,
      'workflow-1',
    );

    expect(() => plan.events_to_append.clear(), throwsUnsupportedError);
  });

  test('does not request identity or commitment for an empty inbox', () async {
    final committer = _FakeWorkflowCommitter();
    final identity_provider = _FakeWorkflowIdentityProvider();

    final processor = WorkflowProcessor(
      registry: registry,
      inbox: _FakeWorkflowInbox(null),
      identity_provider: identity_provider,
      committer: committer,
    );

    expect(await processor.process_next(), isNull);
    expect(identity_provider.calls, 0);
    expect(committer.committed, isNull);
  });

  test('invalid identity does not reach the committer', () async {
    final committer = _FakeWorkflowCommitter();

    final processor = WorkflowProcessor(
      registry: registry,
      inbox: _FakeWorkflowInbox(_pending()),
      identity_provider: _FakeWorkflowIdentityProvider(root: '/different-root'),
      committer: committer,
    );

    await expectLater(
      processor.process_next(),
      throwsA(
        isA<WorkflowTransitionException>().having(
          (error) => error.code,
          'code',
          WorkflowTransitionErrorCode.root_mismatch,
        ),
      ),
    );

    expect(committer.committed, isNull);
  });

  test('does not claim success when commitment fails', () async {
    final committer = _FakeWorkflowCommitter(fail_commit: true);

    final processor = WorkflowProcessor(
      registry: registry,
      inbox: _FakeWorkflowInbox(_pending()),
      identity_provider: _FakeWorkflowIdentityProvider(),
      committer: committer,
    );

    await expectLater(processor.process_next(), throwsStateError);

    expect(committer.committed, isNull);
  });
}

/// Creates a pending command with no authoritative workflow yet.
PendingWorkflowCommand _pending() {
  return PendingWorkflowCommand(
    receipt: EventSubmissionReceipt(
      event_id: 'event-1',
      correlation_id: 'correlation-1',
    ),
    scope_id: 'submission-scope-1',
    command: WorkflowStartEvent(
      target_id: 'local-macos',
      root: TargetPath('/workspace'),
    ),
  );
}

/// Test inbox; has no authority to commit workflows.
final class _FakeWorkflowInbox implements WorkflowInbox {
  _FakeWorkflowInbox(this.pending);

  final PendingWorkflowCommand? pending;

  @override
  Future<PendingWorkflowCommand?> next_pending() async => pending;
}

/// Test double for the trusted workflow identity provider.
///
/// Returns a predictable workflow identity so tests can
/// verify processor behavior without relying on platform
/// identity services or randomly generated identifiers.
///
/// Tracks how many times [propose_identity] is invoked,
/// allowing tests to verify whether the processor requests
/// identity creation at the correct point in its lifecycle.
///
/// No actual authentication or operating-system identity
/// resolution is performed.
final class _FakeWorkflowIdentityProvider implements WorkflowIdentityProvider {
  /// Creates a test identity provider.
  ///
  /// [root] allows tests to simulate either a valid identity
  /// or an identity whose root differs from the submitted command.
  ///
  /// Example:
  /// ```dart
  /// final provider = _FakeWorkflowIdentityProvider();
  ///
  /// expect(provider.calls, 0);
  ///
  /// await provider.propose_identity(_pending());
  ///
  /// expect(provider.calls, 1);
  /// ```
  _FakeWorkflowIdentityProvider({this.root = '/workspace'});

  /// Filesystem root returned in the proposed workflow identity.
  ///
  /// A different root can be supplied to test whether the
  /// state machine rejects inconsistent workflow bindings.
  final String root;

  /// Number of times the processor requested an identity.
  ///
  /// Starts at zero and increases once per invocation of
  /// [propose_identity].
  ///
  /// Exposed for test assertions only.
  int calls = 0;

  /// Proposes a predictable workflow identity.
  ///
  /// Each invocation increments [calls], allowing tests to
  /// detect unwanted identity creation attempts.
  ///
  /// The identity uses fixed identifiers for reproducible tests.
  /// The workflow remains uncommitted until its processing
  /// plan is successfully persisted.
  @override
  Future<WorkflowIdentity> propose_identity(
    PendingWorkflowCommand submission,
  ) async {
    // Record that the processor requested an identity.
    //
    // The counter begins at zero and increases by one for
    // every invocation, regardless of whether the returned
    // identity is subsequently accepted or rejected.
    calls++;

    return WorkflowIdentity(
      workflow_id: 'workflow-1',
      os_user_id: 'user-1',
      target_id: 'local-macos',
      root: TargetPath(root),
    );
  }
}

/// Simulates atomic commitment without implementing inbox reads.
final class _FakeWorkflowCommitter implements WorkflowCommitter {
  _FakeWorkflowCommitter({this.fail_commit = false});

  final bool fail_commit;

  WorkflowProcessingPlan? committed;

  @override
  Future<void> commit(WorkflowProcessingPlan plan) async {
    if (fail_commit) {
      throw StateError('Simulated transaction failure.');
    }

    committed = plan;
  }
}
