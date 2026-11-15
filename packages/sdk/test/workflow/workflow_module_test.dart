import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Verifies composable workflow module registration.
void main() {
  test('assembles the standard lifecycle module', () {
    final flow = WorkflowFlow.standard();

    expect(flow.transitions, hasLength(3));

    expect(
      flow.transition_for(
        state_type: WorkflowInitialState,
        event_type: WorkflowStartEvent,
      ),
      isNotNull,
    );
  });

  test('rejects duplicate module identifiers', () {
    expect(
      () => WorkflowFlow.from_modules(
        modules: [
          const LifecycleWorkflowModule(),
          _TestWorkflowModule(
            module_id: 'rudra.workflow.lifecycle',
            transitions: [],
          ),
        ],
      ),
      throwsStateError,
    );
  });

  test('rejects duplicate transitions across modules', () {
    final transition = WorkflowFlow.standard().transitions.first;

    expect(
      () => WorkflowFlow.from_modules(
        modules: [
          _TestWorkflowModule(
            module_id: 'module.one',
            transitions: [transition],
          ),
          _TestWorkflowModule(
            module_id: 'module.two',
            transitions: [transition],
          ),
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

  test('preserves immutable registration snapshots', () {
    final registry = WorkflowModuleRegistry();

    final before_registration = registry.transitions;

    registry.register(const LifecycleWorkflowModule());

    expect(before_registration, isEmpty);
    expect(registry.transitions, hasLength(3));

    final snapshot = registry.transitions;

    expect(() => snapshot.clear(), throwsUnsupportedError);
  });

  test('preserves registrations after input mutation', () {
    final transitions = [...WorkflowFlow.standard().transitions];

    final registry = WorkflowModuleRegistry();

    registry.register(
      _TestWorkflowModule(module_id: 'test.module', transitions: transitions),
    );

    transitions.clear();

    expect(registry.transitions, hasLength(3));
  });

  test('failed registration leaves registry unchanged', () {
    final transition = WorkflowFlow.standard().transitions.first;
    final registry = WorkflowModuleRegistry();

    expect(
      () => registry.register(_FailingWorkflowModule(transition)),
      throwsStateError,
    );

    expect(registry.transitions, isEmpty);

    // A failed registration must not reserve its module ID.
    registry.register(
      _TestWorkflowModule(module_id: 'test.failure', transitions: [transition]),
    );

    expect(registry.transitions, hasLength(1));
  });
}

/// Test module contributing explicitly supplied transitions.
final class _TestWorkflowModule implements WorkflowModule {
  /// Creates a module with immutable test contributions.
  _TestWorkflowModule({
    required this.module_id,
    required Iterable<WorkflowTransitionDefinition> transitions,
  }) : _transitions = List<WorkflowTransitionDefinition>.unmodifiable(
         transitions,
       );

  @override
  final String module_id;

  final List<WorkflowTransitionDefinition> _transitions;

  @override
  void register(WorkflowModuleRegistration registration) {
    for (final transition in _transitions) {
      registration.add_transition(transition);
    }
  }
}

/// Simulates a module failing halfway through registration.
final class _FailingWorkflowModule implements WorkflowModule {
  /// Creates a failing registration fixture.
  const _FailingWorkflowModule(this.transition);

  /// Transition registered before the injected failure.
  final WorkflowTransitionDefinition transition;

  @override
  String get module_id => 'test.failure';

  @override
  void register(WorkflowModuleRegistration registration) {
    registration.add_transition(transition);

    throw StateError('Simulated module registration failure.');
  }
}
