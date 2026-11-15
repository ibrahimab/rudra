import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Verifies processing orchestration without persistence or I/O.
void main() {
  late WorkflowModuleRegistry registry;

  setUp(() {
    registry = WorkflowModuleRegistry()
      ..register(const LifecycleWorkflowModule());
  });

  test('processes a start command into a validated active workflow', () async {
    final store = _FakeWorkflowProcessingStore(_pending());

    final processor = WorkflowProcessor(registry: registry, store: store);

    final plan = await processor.process_next();

    expect(plan, isNotNull);
    expect(store.committed, same(plan));

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

  test('returns null when no submission is pending', () async {
    final store = _FakeWorkflowProcessingStore(null);

    final processor = WorkflowProcessor(registry: registry, store: store);

    expect(await processor.process_next(), isNull);
    expect(store.committed, isNull);
  });

  test('does not commit invalid workflow bindings', () async {
    final pending = _pending(identity_root: '/different-root');

    final store = _FakeWorkflowProcessingStore(pending);

    final processor = WorkflowProcessor(registry: registry, store: store);

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

    expect(store.committed, isNull);
    expect(store.pending, same(pending));
  });

  test('does not claim success if persistence fails', () async {
    final pending = _pending();

    final store = _FakeWorkflowProcessingStore(pending, fail_commit: true);

    final processor = WorkflowProcessor(registry: registry, store: store);

    await expectLater(processor.process_next(), throwsStateError);

    expect(store.committed, isNull);
    expect(store.pending, same(pending));
  });
}

/// Creates a pending start command with trusted test identity.
PendingWorkflowCommand _pending({String identity_root = '/workspace'}) {
  return PendingWorkflowCommand(
    receipt: EventSubmissionReceipt(
      event_id: 'event-1',
      correlation_id: 'correlation-1',
    ),
    command: WorkflowStartEvent(
      target_id: 'local-macos',
      root: TargetPath('/workspace'),
    ),
    identity: WorkflowIdentity(
      workflow_id: 'workflow-1',
      os_user_id: 'user-1',
      target_id: 'local-macos',
      root: TargetPath(identity_root),
    ),
  );
}

/// In-memory test double for transactional persistence.
final class _FakeWorkflowProcessingStore implements WorkflowProcessingStore {
  /// Creates a fake store with an optional pending command.
  _FakeWorkflowProcessingStore(this.pending, {this.fail_commit = false});

  /// Command available for processing.
  PendingWorkflowCommand? pending;

  /// Simulates a persistence transaction failure.
  final bool fail_commit;

  /// Last successfully committed processing plan.
  WorkflowProcessingPlan? committed;

  @override
  Future<PendingWorkflowCommand?> next_pending() async {
    return pending;
  }

  @override
  Future<void> commit(WorkflowProcessingPlan plan) async {
    if (fail_commit) {
      throw StateError('Simulated database transaction failure.');
    }

    committed = plan;
    pending = null;
  }
}
