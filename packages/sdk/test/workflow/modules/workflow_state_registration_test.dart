import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

void main() {
  group('Workflow state registration', () {
    test('standard runtime owns active and ended phases', () {
      final runtime = WorkflowRuntime.standard();

      expect(runtime.lifecycles.keys, {
        'rudra.workflow.active',
        'rudra.workflow.ended',
      });

      expect(runtime.lifecycles['rudra.workflow.active']!.is_terminal, isFalse);

      expect(runtime.lifecycles['rudra.workflow.ended']!.is_terminal, isTrue);
    });

    test('registers independently owned typed slices', () {
      final registry = WorkflowModuleRegistry();

      registry.register(
        _TestModule('inspection', (registration) {
          registration.add_slice(
            WorkflowSliceKey<_InspectionSlice>('test.inspection'),
          );
        }),
      );

      registry.register(
        _TestModule('planning', (registration) {
          registration.add_slice(
            WorkflowSliceKey<_PlanningSlice>('test.planning'),
          );
        }),
      );

      final runtime = WorkflowRuntime.from_registry(registry);

      expect(
        runtime.slice_keys['test.inspection']!.slice_type,
        _InspectionSlice,
      );
      expect(runtime.slice_keys['test.planning']!.slice_type, _PlanningSlice);

      expect(
        () => runtime.slice_keys['test.inspection']!.require_type(
          const _PlanningSlice(),
        ),
        throwsStateError,
      );
    });

    test('rejects duplicate lifecycle identifiers', () {
      final registry = WorkflowModuleRegistry();

      registry.register(
        _TestModule('one', (registration) {
          registration.add_lifecycle(
            WorkflowLifecycle(id: 'test.active', is_terminal: false),
          );
        }),
      );

      expect(
        () => registry.register(
          _TestModule('two', (registration) {
            registration.add_lifecycle(
              WorkflowLifecycle(id: 'test.active', is_terminal: true),
            );
          }),
        ),
        throwsStateError,
      );

      expect(registry.lifecycles['test.active']!.is_terminal, isFalse);
    });

    test('rejects conflicting slice identifiers', () {
      final registry = WorkflowModuleRegistry();

      registry.register(
        _TestModule('one', (registration) {
          registration.add_slice(
            WorkflowSliceKey<_InspectionSlice>('test.shared'),
          );
        }),
      );

      expect(
        () => registry.register(
          _TestModule('two', (registration) {
            registration.add_slice(
              WorkflowSliceKey<_PlanningSlice>('test.shared'),
            );
          }),
        ),
        throwsStateError,
      );

      expect(registry.slice_keys, hasLength(1));
    });

    test('rejects one slice type under multiple identities', () {
      final registry = WorkflowModuleRegistry();

      registry.register(
        _TestModule('one', (registration) {
          registration.add_slice(
            WorkflowSliceKey<_InspectionSlice>('test.first'),
          );
        }),
      );

      expect(
        () => registry.register(
          _TestModule('two', (registration) {
            registration.add_slice(
              WorkflowSliceKey<_InspectionSlice>('test.second'),
            );
          }),
        ),
        throwsStateError,
      );
    });

    test('rejects an untyped base slice key', () {
      final registry = WorkflowModuleRegistry();

      expect(
        () => registry.register(
          _TestModule('untyped', (registration) {
            registration.add_slice(
              WorkflowSliceKey<WorkflowSlice>('test.untyped'),
            );
          }),
        ),
        throwsStateError,
      );

      expect(registry.slice_keys, isEmpty);
    });

    test('failed registration leaves no partial contributions', () {
      final registry = WorkflowModuleRegistry();

      expect(
        () => registry.register(
          _TestModule('invalid', (registration) {
            registration.add_lifecycle(
              WorkflowLifecycle(id: 'test.pending', is_terminal: false),
            );
            registration.add_slice(
              WorkflowSliceKey<_InspectionSlice>('test.duplicate'),
            );
            registration.add_slice(
              WorkflowSliceKey<_PlanningSlice>('test.duplicate'),
            );
          }),
        ),
        throwsStateError,
      );

      expect(registry.lifecycles, isEmpty);
      expect(registry.slice_keys, isEmpty);
      expect(registry.outcome_transitions, isEmpty);

      // The rejected module identifier is not reserved.
      registry.register(_TestModule('invalid', (_) {}));
    });

    test('runtime remains frozen after later registrations', () {
      final registry = WorkflowModuleRegistry();

      final runtime = WorkflowRuntime.from_registry(registry);

      registry.register(
        _TestModule('later', (registration) {
          registration.add_lifecycle(
            WorkflowLifecycle(id: 'test.later', is_terminal: false),
          );
        }),
      );

      expect(runtime.lifecycles, isEmpty);
      expect(registry.lifecycles, hasLength(1));

      expect(() => runtime.lifecycles.clear(), throwsUnsupportedError);
      expect(() => runtime.slice_keys.clear(), throwsUnsupportedError);
    });
  });
}

final class _TestModule implements WorkflowModule {
  const _TestModule(this.module_id, this.contribute);

  @override
  final String module_id;

  final void Function(WorkflowModuleRegistration) contribute;

  @override
  void register(WorkflowModuleRegistration registration) {
    contribute(registration);
  }
}

final class _InspectionSlice extends WorkflowSlice {
  const _InspectionSlice();
}

final class _PlanningSlice extends WorkflowSlice {
  const _PlanningSlice();
}
