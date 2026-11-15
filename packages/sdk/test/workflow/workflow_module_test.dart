import 'package:test/test.dart';

import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:rudra_sdk/src/workflow/behaviors/workflow_start_behavior.dart';
import 'package:rudra_sdk/src/workflow/modules/lifecycle/serialization/workflow_start_serializer.dart';

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

    // Failed module registration must not partially commit
    // any transitions, command handlers, or serializers.
    expect(registry.transitions, isEmpty);
    expect(registry.command_behaviors, isEmpty);
    expect(registry.serializers, isEmpty);

    registry.register(
      _TestWorkflowModule(module_id: 'test.failure', behaviors: [behavior]),
    );

    expect(registry.transitions, hasLength(1));
  });

  test('registers command handling through the start behavior', () {
    final registry = WorkflowModuleRegistry();

    registry.register(const LifecycleWorkflowModule());

    expect(registry.transitions, hasLength(3));
    expect(registry.command_behaviors, hasLength(1));

    expect(registry.handler_for(command_type: WorkflowStartEvent), isNotNull);

    expect(registry.handler_for(command_type: WorkflowStartedEvent), isNull);

    expect(registry.handler_for(command_type: WorkflowEndedEvent), isNull);
  });

  test('start handler proposes a valid active workflow', () {
    final registry = WorkflowModuleRegistry();
    registry.register(const LifecycleWorkflowModule());

    final command = WorkflowStartEvent(
      target_id: 'local-macos',
      root: TargetPath('/workspace'),
    );

    final identity = WorkflowIdentity(
      workflow_id: 'workflow-1',
      os_user_id: 'user-1',
      target_id: 'local-macos',
      root: TargetPath('/workspace'),
    );

    final handler = registry.handler_for(command_type: WorkflowStartEvent);

    expect(handler, isNotNull);

    final outcomes = handler!.propose_outcomes(command, identity: identity);

    expect(outcomes, hasLength(1));
    expect(outcomes.single, isA<WorkflowStartedEvent>());

    expect(() => outcomes.clear(), throwsUnsupportedError);

    final machine = WorkflowStateMachine(
      flow: WorkflowFlow(transitions: registry.transitions),
    );

    final state = machine.replay([command, ...outcomes]);

    expect(state, isA<WorkflowActiveState>());
    expect(state.version, 2);

    expect((state as WorkflowActiveState).identity.workflow_id, 'workflow-1');
  });

  test('rejects duplicate command handlers atomically', () {
    final registry = WorkflowModuleRegistry();

    registry.register(const LifecycleWorkflowModule());

    expect(
      () => registry.register(
        _TestWorkflowModule(
          module_id: 'duplicate.handler',
          behaviors: [const WorkflowStartBehavior()],
        ),
      ),
      throwsStateError,
    );

    expect(registry.transitions, hasLength(3));
    expect(registry.command_behaviors, hasLength(1));
  });

  test('registers serializers through lifecycle module', () {
    final registry = WorkflowModuleRegistry();

    registry.register(const LifecycleWorkflowModule());

    expect(registry.serializers, hasLength(3));

    final codec = WorkflowEventCodec.from_registry(registry);

    final event = WorkflowStartEvent(
      target_id: 'local-macos',
      root: TargetPath('/workspace'),
    );

    final restored = codec.decode(
      event_type: event.event_type,
      payload_json: codec.encode(event),
    );

    expect(restored, isA<WorkflowStartEvent>());
  });

  test('rejects duplicate serializers atomically', () {
    final registry = WorkflowModuleRegistry();
    registry.register(const LifecycleWorkflowModule());

    final before = registry.serializers;

    expect(
      () => registry.register(
        _TestWorkflowModule(
          module_id: 'duplicate.serializer',
          behaviors: [],
          serializers: [const WorkflowStartSerializer()],
        ),
      ),
      throwsStateError,
    );

    expect(registry.serializers, hasLength(3));
    expect(registry.transitions, hasLength(3));

    // The previously retrieved snapshot is unchanged.
    expect(before, hasLength(3));
  });
}

/// Adapts an existing typed transition for registration tests.
final class _TestWorkflowBehavior implements WorkflowBehavior {
  /// Creates a behavior backed by a known transition.
  const _TestWorkflowBehavior(this.transition);

  @override
  final WorkflowTransitionDefinition transition;
}

/// Supplies configurable workflow contributions to registry tests.
final class _TestWorkflowModule implements WorkflowModule {
  /// Creates an isolated module registration fixture.
  _TestWorkflowModule({
    required this.module_id,
    required Iterable<WorkflowBehavior> behaviors,
    Iterable<WorkflowEventSerializer> serializers = const [],
  }) : _behaviors = List.of(behaviors),
       _serializers = List.of(serializers);

  @override
  final String module_id;

  final List<WorkflowBehavior> _behaviors;
  final List<WorkflowEventSerializer> _serializers;

  @override
  void register(WorkflowModuleRegistration registration) {
    for (final behavior in _behaviors) {
      registration.add(behavior);
    }

    for (final serializer in _serializers) {
      registration.add_serializer(serializer);
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
