import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Pure unit tests for the single authoritative outcome-driven state machine.
void main() {
  final machine = WorkflowStateMachine(runtime: WorkflowRuntime.standard());

  group('WorkflowStateMachine', () {
    test('establishes version one from the first committed outcome', () {
      final started = WorkflowStartedEvent(identity: _identity());
      final active = machine.transition(state: null, event: started);
      expect(active.version, 1);
      expect(active.lifecycle.id, 'rudra.workflow.active');
      expect(active.identity.workflow_id, 'workflow-1');
      expect(active.is_terminal, isFalse);
    });

    test('ends a workflow at version two without a command event', () {
      final active = machine.transition(
        state: null,
        event: WorkflowStartedEvent(identity: _identity()),
      );
      final ended = machine.transition(
        state: active,
        event: WorkflowEndedEvent(workflow_id: 'workflow-1'),
      );
      expect(ended.version, 2);
      expect(ended.is_terminal, isTrue);
      expect(ended.identity, same(active.identity));
      expect(active.version, 1);
      expect(active.is_terminal, isFalse);
    });

    test('rejects a terminal outcome before establishment', () {
      expect(
        () => machine.transition(
          state: null,
          event: WorkflowEndedEvent(workflow_id: 'workflow-1'),
        ),
        _transition_error(WorkflowTransitionErrorCode.invalid_transition),
      );
    });

    test('rejects establishment of an existing workflow', () {
      final active = machine.transition(
        state: null,
        event: WorkflowStartedEvent(identity: _identity()),
      );
      expect(
        () => machine.transition(
          state: active,
          event: WorkflowStartedEvent(identity: _identity()),
        ),
        _transition_error(WorkflowTransitionErrorCode.invalid_transition),
      );
    });

    test('rejects a terminal event for an unrelated workflow', () {
      final active = machine.transition(
        state: null,
        event: WorkflowStartedEvent(identity: _identity()),
      );
      expect(
        () => machine.transition(
          state: active,
          event: WorkflowEndedEvent(workflow_id: 'another-workflow'),
        ),
        _transition_error(WorkflowTransitionErrorCode.guard_rejected),
      );
      expect(active.is_terminal, isFalse);
      expect(active.version, 1);
    });

    test('never reopens a terminal workflow', () {
      final terminal = machine.replay([
        WorkflowStartedEvent(identity: _identity()),
        WorkflowEndedEvent(workflow_id: 'workflow-1'),
      ])!;
      expect(
        () => machine.transition(
          state: terminal,
          event: WorkflowEndedEvent(workflow_id: 'workflow-1'),
        ),
        _transition_error(WorkflowTransitionErrorCode.invalid_transition),
      );
    });

    test('returns null for an empty committed history', () {
      expect(machine.replay(const <WorkflowOutcomeEvent>[]), isNull);
    });

    test('replays only outcomes and advances once for each', () {
      final replayed = machine.replay([
        WorkflowStartedEvent(identity: _identity()),
        WorkflowEndedEvent(workflow_id: 'workflow-1'),
      ])!;
      expect(replayed.version, 2);
      expect(replayed.lifecycle.id, 'rudra.workflow.ended');
    });

    test('reports the index of an invalid committed event', () {
      expect(
        () => machine.replay([
          WorkflowStartedEvent(identity: _identity()),
          WorkflowEndedEvent(workflow_id: 'wrong-id'),
        ]),
        throwsA(
          isA<WorkflowReplayException>().having(
            (failure) => failure.event_index,
            'event_index',
            1,
          ),
        ),
      );
    });

    test('rejects an unregistered previous lifecycle', () {
      final forged = WorkflowSnapshot(
        identity: _identity(),
        version: 1,
        lifecycle: WorkflowLifecycle(
          id: 'unregistered.lifecycle',
          is_terminal: false,
        ),
      );
      expect(
        () => machine.transition(
          state: forged,
          event: WorkflowEndedEvent(workflow_id: 'workflow-1'),
        ),
        _transition_error(WorkflowTransitionErrorCode.invalid_snapshot),
      );
    });
  });

  group('Independent feature slice projection', () {
    test('projects two slices from one shared previous snapshot', () {
      final inspection_key = WorkflowSliceKey<_Inspection>('test.inspection');
      final planning_key = WorkflowSliceKey<_Planning>('test.planning');
      final registry = WorkflowModuleRegistry()
        ..register(const LifecycleWorkflowModule())
        ..register(
          _FeatureModule('test.inspection', (registration) {
            registration
              ..add_slice(inspection_key)
              ..add_slice_reducer(
                WorkflowSliceReducer<_Inspection, WorkflowStartedEvent>(
                  key: inspection_key,
                  reduce: (previous, event, current) {
                    expect(previous, isNull);
                    expect(current, isNull);
                    return const _Inspection();
                  },
                ),
              );
          }),
        )
        ..register(
          _FeatureModule('test.planning', (registration) {
            registration
              ..add_slice(planning_key)
              ..add_slice_reducer(
                WorkflowSliceReducer<_Planning, WorkflowStartedEvent>(
                  key: planning_key,
                  reduce: (previous, event, current) {
                    expect(previous, isNull);
                    expect(current, isNull);
                    return const _Planning();
                  },
                ),
              );
          }),
        );

      final extended = WorkflowStateMachine(
        runtime: WorkflowRuntime.from_registry(registry),
      );
      final active = extended.transition(
        state: null,
        event: WorkflowStartedEvent(identity: _identity()),
      );
      expect(active.slice(inspection_key), isA<_Inspection>());
      expect(active.slice(planning_key), isA<_Planning>());
      expect(active.slice_bindings.length, 2);

      final ended = extended.transition(
        state: active,
        event: WorkflowEndedEvent(workflow_id: 'workflow-1'),
      );
      expect(ended.slice(inspection_key), same(active.slice(inspection_key)));
      expect(ended.slice(planning_key), same(active.slice(planning_key)));
    });

    test('a failing reducer never mutates the prior snapshot', () {
      final key = WorkflowSliceKey<_Inspection>('test.inspection');
      final registry = WorkflowModuleRegistry()
        ..register(const LifecycleWorkflowModule())
        ..register(
          _FeatureModule('test.inspection', (registration) {
            registration
              ..add_slice(key)
              ..add_slice_reducer(
                WorkflowSliceReducer<_Inspection, WorkflowEndedEvent>(
                  key: key,
                  reduce: (previous, event, current) =>
                      throw StateError('Simulated reducer failure.'),
                ),
              );
          }),
        );
      final extended = WorkflowStateMachine(
        runtime: WorkflowRuntime.from_registry(registry),
      );
      final active = extended.transition(
        state: null,
        event: WorkflowStartedEvent(identity: _identity()),
      );
      expect(
        () => extended.transition(
          state: active,
          event: WorkflowEndedEvent(workflow_id: 'workflow-1'),
        ),
        _transition_error(WorkflowTransitionErrorCode.reducer_failure),
      );
      expect(active.version, 1);
      expect(active.is_terminal, isFalse);
    });
  });
}

/// Matches a thrown typed transition failure, never the closure itself.
Matcher _transition_error(WorkflowTransitionErrorCode code) => throwsA(
  isA<WorkflowTransitionException>().having(
    (failure) => failure.code,
    'code',
    code,
  ),
);

/// Creates fixed immutable workflow identity bindings for replay tests.
WorkflowIdentity _identity() => WorkflowIdentity(
  workflow_id: 'workflow-1',
  os_user_id: 'user-1',
  target_id: 'local-macos',
  root: TargetPath('/workspace'),
);

/// Synthetic owner module, independent of the standard lifecycle behavior.
final class _FeatureModule implements WorkflowModule {
  /// Creates one synthetic feature contribution.
  const _FeatureModule(this.module_id, this.contribute);

  /// Stable module identifier for registration tests.
  @override
  final String module_id;

  /// Pure registration callback owned by this test module.
  final void Function(WorkflowModuleRegistration) contribute;

  /// Registers only this feature's owned slice and reducer contracts.
  @override
  void register(WorkflowModuleRegistration registration) =>
      contribute(registration);
}

/// Immutable synthetic inspection domain slice.
final class _Inspection extends WorkflowSlice {
  /// Creates an inspection value for isolated reducer tests.
  const _Inspection();
}

/// Immutable synthetic planning domain slice.
final class _Planning extends WorkflowSlice {
  /// Creates a planning value for isolated reducer tests.
  const _Planning();
}
