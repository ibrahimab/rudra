import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Verifies processing orchestration with independent test doubles.
void main() {
  late WorkflowRuntime runtime;

  setUp(() {
    final registry = WorkflowModuleRegistry()
      ..register(const LifecycleWorkflowModule());

    runtime = WorkflowRuntime.from_registry(registry);
  });

  test('commits a validated workflow start', () async {
    final inbox = _FakeWorkflowInbox(_pending());
    final committer = _FakeWorkflowCommitter();

    final processor = WorkflowProcessor(
      runtime: runtime,
      inbox: inbox,
      identity_provider: _FakeWorkflowIdentityProvider(),
      committer: committer,
      rejector: _FakeWorkflowRejector(),
      quarantiner: _FakeWorkflowQuarantiner(),
    );

    final result = await processor.process_next();

    expect(result, isA<WorkflowProcessingCommitted>());

    final plan = (result as WorkflowProcessingCommitted).plan;

    expect(committer.committed, same(plan));

    expect(plan.previous_state, isA<WorkflowInitialState>());
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
      runtime: runtime,
      inbox: _FakeWorkflowInbox(null),
      identity_provider: identity_provider,
      committer: committer,
      rejector: _FakeWorkflowRejector(),
      quarantiner: _FakeWorkflowQuarantiner(),
    );

    expect(await processor.process_next(), isA<WorkflowProcessingIdle>());
    expect(identity_provider.calls, 0);
    expect(committer.committed, isNull);
  });

  test('invalid identity does not reach the committer', () async {
    final committer = _FakeWorkflowCommitter();

    final processor = WorkflowProcessor(
      runtime: runtime,
      inbox: _FakeWorkflowInbox(_pending()),
      identity_provider: _FakeWorkflowIdentityProvider(root: '/different-root'),
      committer: committer,
      rejector: _FakeWorkflowRejector(),
      quarantiner: _FakeWorkflowQuarantiner(),
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
      runtime: runtime,
      inbox: _FakeWorkflowInbox(_pending()),
      identity_provider: _FakeWorkflowIdentityProvider(),
      committer: committer,
      rejector: _FakeWorkflowRejector(),
      quarantiner: _FakeWorkflowQuarantiner(),
    );

    await expectLater(processor.process_next(), throwsStateError);

    expect(committer.committed, isNull);
  });

  test('persists known business rejection before reporting it', () async {
    final rejector = _FakeWorkflowRejector();

    final processor = WorkflowProcessor(
      runtime: runtime,
      inbox: _FakeWorkflowInbox(_pending()),
      identity_provider: _FakeWorkflowIdentityProvider(),
      committer: _RejectingWorkflowCommitter(
        WorkflowCommitErrorCode.ownership_conflict,
      ),
      rejector: rejector,
      quarantiner: _FakeWorkflowQuarantiner(),
    );

    final result = await processor.process_next();

    expect(result, isA<WorkflowProcessingRejected>());

    final rejected = result as WorkflowProcessingRejected;

    expect(rejected.code, WorkflowRejectionCode.ownership_conflict);

    expect(rejected.receipt.event_id, 'event-1');
    expect(rejected.receipt.correlation_id, 'correlation-1');

    expect(rejector.calls, 1);
    expect(rejector.last_code, WorkflowRejectionCode.ownership_conflict);
  });

  test('does not persist rejection for an invalid processing plan', () async {
    final rejector = _FakeWorkflowRejector();

    final processor = WorkflowProcessor(
      runtime: runtime,
      inbox: _FakeWorkflowInbox(_pending()),
      identity_provider: _FakeWorkflowIdentityProvider(),
      committer: _RejectingWorkflowCommitter(
        WorkflowCommitErrorCode.invalid_plan,
      ),
      rejector: rejector,
      quarantiner: _FakeWorkflowQuarantiner(),
    );

    await expectLater(
      processor.process_next(),
      throwsA(
        isA<WorkflowCommitException>().having(
          (error) => error.code,
          'code',
          WorkflowCommitErrorCode.invalid_plan,
        ),
      ),
    );

    expect(rejector.calls, 0);
  });

  test('does not report rejection when persistence fails', () async {
    final rejector = _FakeWorkflowRejector(fail_rejection: true);

    final processor = WorkflowProcessor(
      runtime: runtime,
      inbox: _FakeWorkflowInbox(_pending()),
      identity_provider: _FakeWorkflowIdentityProvider(),
      committer: _RejectingWorkflowCommitter(
        WorkflowCommitErrorCode.ownership_conflict,
      ),
      rejector: rejector,
      quarantiner: _FakeWorkflowQuarantiner(),
    );

    await expectLater(processor.process_next(), throwsStateError);

    expect(rejector.calls, 1);
  });

  test('quarantines unreadable commands without domain execution', () async {
    final identity_provider = _FakeWorkflowIdentityProvider();
    final committer = _FakeWorkflowCommitter();
    final rejector = _FakeWorkflowRejector();
    final quarantiner = _FakeWorkflowQuarantiner();

    final issue = WorkflowInboxDecodingException(
      receipt: _pending().receipt,
      scope_id: 'submission-scope-1',
      event_type: WorkflowStartEvent.type_id,
      payload_json: 'invalid-json',
      code: WorkflowQuarantineCode.undecodable_command,
      diagnostic: 'Invalid workflow command payload.',
    );

    final processor = WorkflowProcessor(
      runtime: runtime,
      inbox: _UnreadableWorkflowInbox(issue),
      identity_provider: identity_provider,
      committer: committer,
      rejector: rejector,
      quarantiner: quarantiner,
    );

    final result = await processor.process_next();

    expect(result, isA<WorkflowProcessingQuarantined>());

    final quarantined = result as WorkflowProcessingQuarantined;

    expect(quarantined.receipt.event_id, issue.receipt.event_id);
    expect(quarantined.code, WorkflowQuarantineCode.undecodable_command);

    expect(quarantiner.calls, 1);
    expect(quarantiner.last_issue, same(issue));

    // The unreadable data must never reach workflow execution.
    expect(identity_provider.calls, 0);
    expect(committer.committed, isNull);
    expect(rejector.calls, 0);
  });

  test('does not report quarantine when persistence fails', () async {
    final quarantiner = _FakeWorkflowQuarantiner(fail_quarantine: true);

    final issue = WorkflowInboxDecodingException(
      receipt: _pending().receipt,
      scope_id: 'submission-scope-1',
      event_type: WorkflowStartEvent.type_id,
      payload_json: 'invalid-json',
      code: WorkflowQuarantineCode.undecodable_command,
      diagnostic: 'Invalid workflow command payload.',
    );

    final processor = WorkflowProcessor(
      runtime: runtime,
      inbox: _UnreadableWorkflowInbox(issue),
      identity_provider: _FakeWorkflowIdentityProvider(),
      committer: _FakeWorkflowCommitter(),
      rejector: _FakeWorkflowRejector(),
      quarantiner: quarantiner,
    );

    await expectLater(processor.process_next(), throwsStateError);

    expect(quarantiner.calls, 1);
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

/// Simulates a classified transactional commitment failure.
final class _RejectingWorkflowCommitter implements WorkflowCommitter {
  /// Creates a committer that always reports [code].
  const _RejectingWorkflowCommitter(this.code);

  /// Failure returned during commitment.
  final WorkflowCommitErrorCode code;

  @override
  Future<void> commit(WorkflowProcessingPlan plan) async {
    throw WorkflowCommitException(
      code: code,
      message: 'Simulated commitment failure.',
    );
  }
}

/// Test double for the durable workflow submission rejection boundary.
///
/// Implements [WorkflowSubmissionRejector] without accessing a database,
/// writing submission records, or performing actual persistence.
///
/// This class allows tests to verify how [WorkflowProcessor] interacts
/// with the rejection boundary when a workflow command cannot be
/// committed because of a recognized business conflict.
///
/// It supports two distinct scenarios:
///
/// - **Successful rejection:** Records the rejection attempt and
///   completes normally, simulating a successfully persisted rejection.
/// - **Failed rejection:** Records the rejection attempt and throws
///   [StateError], simulating a persistence failure.
///
/// In both scenarios, [calls] and [last_code] record the attempted
/// operation. They do not prove that the rejection was persisted.
///
/// The processor must only return [WorkflowProcessingRejected] when
/// this implementation completes successfully. If rejection fails,
/// the exception must propagate to the caller.
///
/// This distinction prevents a frontend from being informed that a
/// command was rejected when its durable processing status may
/// still be pending.
///
/// Example:
/// ```dart
/// final rejector = _FakeWorkflowRejector();
///
/// await rejector.reject(
///   submission: _pending(),
///   code: WorkflowRejectionCode.ownership_conflict,
/// );
///
/// expect(rejector.calls, 1);
/// expect(
///   rejector.last_code,
///   WorkflowRejectionCode.ownership_conflict,
/// );
/// ```
///
/// Example simulating a persistence failure:
/// ```dart
/// final rejector = _FakeWorkflowRejector(
///   fail_rejection: true,
/// );
///
/// await expectLater(
///   rejector.reject(
///     submission: _pending(),
///     code: WorkflowRejectionCode.ownership_conflict,
///   ),
///   throwsStateError,
/// );
///
/// // The attempted rejection is still observable.
/// expect(rejector.calls, 1);
/// ```
final class _FakeWorkflowRejector implements WorkflowSubmissionRejector {
  /// Creates a configurable rejection persistence test double.
  ///
  /// When [fail_rejection] is false, calls to [reject] complete
  /// successfully without writing anything to persistent storage.
  ///
  /// When [fail_rejection] is true, [reject] throws [StateError]
  /// after recording the attempted operation.
  ///
  /// Defaults to successful rejection behavior.
  ///
  /// Each instance starts with zero recorded calls and no
  /// previously observed rejection code.
  _FakeWorkflowRejector({this.fail_rejection = false});

  /// Whether rejection attempts should simulate persistence failure.
  ///
  /// This setting is immutable for the lifetime of the test double.
  ///
  /// A value of true causes every invocation of [reject] to throw
  /// [StateError] instead of completing successfully.
  final bool fail_rejection;

  /// Total number of rejection attempts received.
  ///
  /// Incremented once for every invocation of [reject],
  /// regardless of whether the simulated operation succeeds.
  ///
  /// Tests use this counter to verify that the processor invokes
  /// the rejection boundary exactly when required.
  ///
  /// A value of zero indicates that no rejection was attempted.
  int calls = 0;

  /// Business rejection code supplied by the most recent attempt.
  ///
  /// Initially null until [reject] is called.
  ///
  /// Updated even when [fail_rejection] is true, allowing tests
  /// to inspect which business reason the processor attempted
  /// to persist.
  ///
  /// This field describes an attempted rejection, not necessarily
  /// a successfully committed rejection.
  WorkflowRejectionCode? last_code;

  /// Simulates durably rejecting an accepted workflow submission.
  ///
  /// [submission] identifies the pending command being rejected.
  /// The test double does not inspect or modify its contents.
  ///
  /// [code] identifies the business reason supplied by the processor.
  ///
  /// The method records the attempt before checking [fail_rejection].
  /// Consequently, failed operations remain observable through
  /// [calls] and [last_code].
  ///
  /// If failure simulation is disabled, the returned future completes
  /// normally. The processor may interpret that completion as a
  /// successful rejection for the purposes of its unit tests.
  ///
  /// If failure simulation is enabled, throws [StateError] to verify
  /// that [WorkflowProcessor] propagates infrastructure failures
  /// instead of returning [WorkflowProcessingRejected].
  ///
  /// No actual submission state is changed, and no workflow events
  /// or filesystem operations are performed.
  @override
  Future<void> reject({
    required PendingWorkflowCommand submission,
    required WorkflowRejectionCode code,
  }) async {
    // Count the attempted operation, including failed attempts.
    calls++;

    // Retain the requested business reason for test assertions.
    last_code = code;

    // Simulate a failed persistence operation after the request
    // has reached the rejection boundary.
    if (fail_rejection) {
      throw StateError('Simulated rejection persistence failure.');
    }
  }
}

/// Test double for durable quarantine persistence.
///
/// Records whether the processor attempted to quarantine an
/// unreadable submission without writing to a real database.
///
/// Successful completion simulates a committed quarantine.
/// A configured failure simulates unsuccessful persistence,
/// allowing tests to verify that the processor propagates
/// errors instead of returning a successful quarantine result.
final class _FakeWorkflowQuarantiner implements WorkflowSubmissionQuarantiner {
  /// Creates a configurable quarantine test double.
  _FakeWorkflowQuarantiner({this.fail_quarantine = false});

  /// Whether quarantine operations should fail.
  final bool fail_quarantine;

  /// Number of attempted quarantine operations.
  int calls = 0;

  /// Last unreadable submission supplied to this boundary.
  WorkflowInboxDecodingException? last_issue;

  /// Records an attempted quarantine operation.
  ///
  /// This does not actually persist the submission.
  /// Both successful and failed attempts increment [calls].
  @override
  Future<void> quarantine(WorkflowInboxDecodingException issue) async {
    calls++;
    last_issue = issue;

    if (fail_quarantine) {
      throw StateError('Simulated quarantine persistence failure.');
    }
  }
}

/// Simulates an inbox that encounters an unreadable persisted row.
///
/// The exception is classified by the inbox boundary, not
/// constructed or inferred by the processor.
final class _UnreadableWorkflowInbox implements WorkflowInbox {
  /// Creates an inbox returning one classified decoding failure.
  const _UnreadableWorkflowInbox(this.issue);

  /// Original decoding failure to propagate.
  final WorkflowInboxDecodingException issue;

  @override
  Future<PendingWorkflowCommand?> next_pending() async {
    throw issue;
  }
}
