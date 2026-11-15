import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Verifies composable workflow behavior registration.
void main() {
  test('assembles the standard lifecycle behaviors', () {
    final flow = WorkflowFlow.standard();

    expect(flow.transitions, hasLength(3));

    final cases = <(Type, Type, Type)>[
      (WorkflowInitialState, WorkflowStartEvent, WorkflowStartRequestedState),
      (WorkflowStartRequestedState, WorkflowStartedEvent, WorkflowActiveState),
      (WorkflowActiveState, WorkflowEndedEvent, WorkflowEndedState),
    ];

    for (final (source, event, destination) in cases) {
      final transition = flow.transition_for(
        state_type: source,
        event_type: event,
      );

      expect(transition, isNotNull);
      expect(transition!.destination_state_type, destination);
    }
  });

  test('rejects duplicate module identifiers', () {
    expect(
      () => WorkflowFlow.from_modules(
        modules: [
          const LifecycleWorkflowModule(),
          _TestWorkflowModule(
            module_id: 'rudra.workflow.lifecycle',
            behaviors: [],
          ),
        ],
      ),
      throwsStateError,
    );
  });

  test('rejects duplicate transitions across modules', () {
    final transition = WorkflowFlow.standard().transitions.first;
    final behavior = _TestWorkflowBehavior(transition);

    expect(
      () => WorkflowFlow.from_modules(
        modules: [
          _TestWorkflowModule(module_id: 'module.one', behaviors: [behavior]),
          _TestWorkflowModule(module_id: 'module.two', behaviors: [behavior]),
        ],
      ),
      throwsA(
        isA<WorkflowFlowException>().having(
          (error) => error.code,
          'code',
          WorkflowFlowErrorCode.duplicate_transition,
        ),
      ),
    );
  });

  test('preserves immutable registry snapshots', () {
    final registry = WorkflowModuleRegistry();
    final before = registry.transitions;

    registry.register(const LifecycleWorkflowModule());

    expect(before, isEmpty);
    expect(registry.transitions, hasLength(3));

    expect(() => registry.transitions.clear(), throwsUnsupportedError);
  });

  test('preserves registrations after input mutation', () {
    final behaviors = <WorkflowBehavior>[
      _TestWorkflowBehavior(WorkflowFlow.standard().transitions.first),
    ];

    final registry = WorkflowModuleRegistry();

    registry.register(
      _TestWorkflowModule(module_id: 'test.module', behaviors: behaviors),
    );

    behaviors.clear();

    expect(registry.transitions, hasLength(1));
  });

  test('failed registration leaves registry unchanged', () {
    final behavior = _TestWorkflowBehavior(
      WorkflowFlow.standard().transitions.first,
    );

    final registry = WorkflowModuleRegistry();

    expect(
      () => registry.register(_FailingWorkflowModule(behavior)),
      throwsStateError,
    );

    expect(registry.transitions, isEmpty);

    registry.register(
      _TestWorkflowModule(module_id: 'test.failure', behaviors: [behavior]),
    );

    expect(registry.transitions, hasLength(1));
  });
}

/// Adapts an existing typed transition for registration tests.
final class _TestWorkflowBehavior implements WorkflowBehavior {
  /// Creates a behavior backed by a known transition.
  const _TestWorkflowBehavior(this.transition);

  @override
  final WorkflowTransitionDefinition transition;
}

/// Supplies configurable workflow behaviors to a module registry.
final class _TestWorkflowModule implements WorkflowModule {
  /// Creates an isolated module fixture.
  _TestWorkflowModule({
    required this.module_id,
    required Iterable<WorkflowBehavior> behaviors,
  }) : _behaviors = List<WorkflowBehavior>.of(behaviors);

  @override
  final String module_id;

  final List<WorkflowBehavior> _behaviors;

  @override
  void register(WorkflowModuleRegistration registration) {
    for (final behavior in _behaviors) {
      registration.add(behavior);
    }
  }
}

/// Simulates a failure after contributing one behavior.
final class _FailingWorkflowModule implements WorkflowModule {
  /// Creates a failing module fixture.
  const _FailingWorkflowModule(this.behavior);

  final WorkflowBehavior behavior;

  @override
  String get module_id => 'test.failure';

  @override
  void register(WorkflowModuleRegistration registration) {
    registration.add(behavior);
    throw StateError('Simulated registration failure.');
  }
}
