import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Verifies workflow outcome registration behavior through this file's focused tests.
void main() {
  group('Workflow outcome registration', () {
    test('assembles lifecycle transitions and owned reducers', () {
      final registry = _registry_with_lifecycle();

      registry.register(
        _TestModule('test.outcomes', (registration) {
          registration
            ..add_outcome_transition(
              WorkflowOutcomeTransition<WorkflowStartedEvent>(
                source_lifecycle_id: null,
                destination_lifecycle_id: 'rudra.workflow.active',
              ),
            )
            ..add_outcome_transition(
              WorkflowOutcomeTransition<WorkflowEndedEvent>(
                source_lifecycle_id: 'rudra.workflow.active',
                destination_lifecycle_id: 'rudra.workflow.ended',
              ),
            );
        }),
      );

      final inspection_key = WorkflowSliceKey<_InspectionSlice>(
        'test.inspection',
      );
      final planning_key = WorkflowSliceKey<_PlanningSlice>('test.planning');

      registry.register(
        _TestModule('test.inspection', (registration) {
          registration
            ..add_slice(inspection_key)
            ..add_slice_reducer(
              WorkflowSliceReducer<_InspectionSlice, WorkflowStartedEvent>(
                key: inspection_key,
                reduce: (previous, event, current) => const _InspectionSlice(),
              ),
            );
        }),
      );

      registry.register(
        _TestModule('test.planning', (registration) {
          registration
            ..add_slice(planning_key)
            ..add_slice_reducer(
              WorkflowSliceReducer<_PlanningSlice, WorkflowStartedEvent>(
                key: planning_key,
                reduce: (previous, event, current) => const _PlanningSlice(),
              ),
            );
        }),
      );

      final runtime = WorkflowRuntime.from_registry(registry);

      expect(runtime.outcome_transitions, hasLength(2));
      expect(runtime.slice_reducers, hasLength(2));

      expect(runtime.slice_reducers.map((reducer) => reducer.key.id).toSet(), {
        'test.inspection',
        'test.planning',
      });
    });

    test('rejects duplicate outcome pairs atomically', () {
      final registry = _registry_with_lifecycle();

      final transition = WorkflowOutcomeTransition<WorkflowStartedEvent>(
        source_lifecycle_id: null,
        destination_lifecycle_id: 'rudra.workflow.active',
      );

      registry.register(
        _TestModule('test.first', (registration) {
          registration.add_outcome_transition(transition);
        }),
      );

      expect(
        () => registry.register(
          _TestModule('test.second', (registration) {
            registration
              ..add_lifecycle(
                WorkflowLifecycle(id: 'test.temporary', is_terminal: false),
              )
              ..add_outcome_transition(transition);
          }),
        ),
        throwsStateError,
      );

      expect(registry.outcome_transitions, hasLength(1));
      expect(registry.lifecycles.containsKey('test.temporary'), isFalse);
    });

    test('rejects duplicate reducers for one slice and event', () {
      final registry = _registry_with_lifecycle();
      final key = WorkflowSliceKey<_InspectionSlice>('test.inspection');

      final reducer =
          WorkflowSliceReducer<_InspectionSlice, WorkflowStartedEvent>(
            key: key,
            reduce: (previous, event, current) => const _InspectionSlice(),
          );

      expect(
        () => registry.register(
          _TestModule('test.duplicate.reducers', (registration) {
            registration
              ..add_slice(key)
              ..add_slice_reducer(reducer)
              ..add_slice_reducer(reducer);
          }),
        ),
        throwsStateError,
      );

      expect(registry.slice_keys, isEmpty);
      expect(registry.slice_reducers, isEmpty);
    });

    test('prevents reducers from claiming another module slice', () {
      final registry = _registry_with_lifecycle();
      final key = WorkflowSliceKey<_InspectionSlice>('test.inspection');

      registry.register(
        _TestModule('test.owner', (registration) {
          registration.add_slice(key);
        }),
      );

      expect(
        () => registry.register(
          _TestModule('test.foreign', (registration) {
            registration.add_slice_reducer(
              WorkflowSliceReducer<_InspectionSlice, WorkflowStartedEvent>(
                key: key,
                reduce: (previous, event, current) => const _InspectionSlice(),
              ),
            );
          }),
        ),
        throwsStateError,
      );

      expect(registry.slice_reducers, isEmpty);
      expect(registry.slice_keys, hasLength(1));
    });

    test('rejects unknown lifecycle references', () {
      final registry = _registry_with_lifecycle();

      registry.register(
        _TestModule('test.unknown.lifecycle', (registration) {
          registration.add_outcome_transition(
            WorkflowOutcomeTransition<WorkflowEndedEvent>(
              source_lifecycle_id: 'test.missing',
              destination_lifecycle_id: 'rudra.workflow.ended',
            ),
          );
        }),
      );

      expect(() => WorkflowRuntime.from_registry(registry), throwsStateError);
    });

    test('rejects terminal lifecycle transition sources', () {
      final registry = _registry_with_lifecycle();

      registry.register(
        _TestModule('test.terminal.source', (registration) {
          registration.add_outcome_transition(
            WorkflowOutcomeTransition<WorkflowStartedEvent>(
              source_lifecycle_id: 'rudra.workflow.ended',
              destination_lifecycle_id: 'rudra.workflow.active',
            ),
          );
        }),
      );

      expect(() => WorkflowRuntime.from_registry(registry), throwsStateError);
    });

    test('rejects reducers without a matching outcome transition', () {
      final registry = _registry_with_lifecycle();
      final key = WorkflowSliceKey<_InspectionSlice>('test.inspection');

      registry.register(
        _TestModule('test.orphaned.reducer', (registration) {
          registration
            ..add_slice(key)
            ..add_slice_reducer(
              WorkflowSliceReducer<_InspectionSlice, WorkflowStartedEvent>(
                key: key,
                reduce: (previous, event, current) => const _InspectionSlice(),
              ),
            );
        }),
      );

      expect(() => WorkflowRuntime.from_registry(registry), throwsStateError);
    });

    test('preserves immutable registration snapshots', () {
      final registry = _registry_with_lifecycle();

      final before = registry.outcome_transitions;
      final runtime = WorkflowRuntime.from_registry(registry);

      registry.register(
        _TestModule('test.later', (registration) {
          registration.add_outcome_transition(
            WorkflowOutcomeTransition<WorkflowStartedEvent>(
              source_lifecycle_id: null,
              destination_lifecycle_id: 'rudra.workflow.active',
            ),
          );
        }),
      );

      expect(before, isEmpty);
      expect(registry.outcome_transitions, hasLength(1));
      expect(runtime.outcome_transitions, isEmpty);

      expect(
        () => registry.outcome_transitions.clear(),
        throwsUnsupportedError,
      );

      expect(() => runtime.slice_reducers.clear(), throwsUnsupportedError);
    });
  });
}

/// Creates an isolated registry with the lifecycle identities
/// required by outcome-registration tests.
///
/// The fixture deliberately registers only lifecycle definitions.
/// It does not depend on standard lifecycle behaviors, serializers,
/// or outcome transitions.
///
/// This ensures that changes to production module composition
/// cannot invalidate tests of independent registration contracts.
///
/// Example:
/// ```dart
/// final registry = _registry_with_lifecycle();
///
/// expect(registry.lifecycles, hasLength(2));
/// expect(registry.outcome_transitions, isEmpty);
/// ```
WorkflowModuleRegistry _registry_with_lifecycle() {
  final registry = WorkflowModuleRegistry();

  registry.register(
    _TestModule('test.lifecycle', (registration) {
      registration
        ..add_lifecycle(
          WorkflowLifecycle(id: 'rudra.workflow.active', is_terminal: false),
        )
        ..add_lifecycle(
          WorkflowLifecycle(id: 'rudra.workflow.ended', is_terminal: true),
        );
    }),
  );

  return registry;
}

/// Synthetic module for isolated workflow registration tests.
final class _TestModule implements WorkflowModule {
  /// Creates a module with an explicit registration callback.
  const _TestModule(this.module_id, this.contribute);

  /// Stable identifier of this test module.
  @override
  final String module_id;

  /// Callback contributing the module's test contracts.
  final void Function(WorkflowModuleRegistration) contribute;

  /// Registers the test contracts without external I/O.
  @override
  void register(WorkflowModuleRegistration registration) {
    contribute(registration);
  }
}

/// Immutable synthetic inspection domain slice.
final class _InspectionSlice extends WorkflowSlice {
  /// Creates an inspection slice for contract tests.
  const _InspectionSlice();
}

/// Immutable synthetic planning domain slice.
final class _PlanningSlice extends WorkflowSlice {
  /// Creates a planning slice for contract tests.
  const _PlanningSlice();
}
