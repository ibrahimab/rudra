import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Verifies workflow snapshot behavior through this file's focused tests.
void main() {
  group('WorkflowSnapshot', () {
    test('requires established identity, version and lifecycle', () {
      final identity = _identity();
      final lifecycle = _active();

      final snapshot = WorkflowSnapshot(
        identity: identity,
        version: 1,
        lifecycle: lifecycle,
      );

      expect(snapshot.identity, same(identity));
      expect(snapshot.version, 1);
      expect(snapshot.lifecycle, same(lifecycle));
      expect(snapshot.is_terminal, isFalse);
      expect(snapshot.slice_bindings, isEmpty);
    });

    test('rejects nonpositive established workflow versions', () {
      for (final version in [0, -1]) {
        expect(() => _snapshot(version: version), throwsArgumentError);
      }
    });

    test('exposes terminality through the lifecycle', () {
      final snapshot = _snapshot(
        version: 4,
        lifecycle: WorkflowLifecycle(id: 'test.ended', is_terminal: true),
      );

      expect(snapshot.is_terminal, isTrue);
    });

    test('retrieves independently owned typed slices', () {
      final inspection_key = WorkflowSliceKey<_InspectionSlice>(
        'test.inspection',
      );
      final planning_key = WorkflowSliceKey<_PlanningSlice>('test.planning');

      const inspection = _InspectionSlice('/tmp');
      const planning = _PlanningSlice(3);

      final snapshot = _snapshot(
        slices: [
          WorkflowSliceBinding(key: inspection_key, value: inspection),
          WorkflowSliceBinding(key: planning_key, value: planning),
        ],
      );

      expect(snapshot.slice(inspection_key), same(inspection));
      expect(snapshot.slice(planning_key), same(planning));
      expect(snapshot.slice_bindings, hasLength(2));
    });

    test('returns null for an absent optional slice', () {
      final snapshot = _snapshot();

      final key = WorkflowSliceKey<_InspectionSlice>('test.inspection');

      expect(snapshot.slice(key), isNull);
    });

    test('rejects a conflicting requested slice type', () {
      final inspection_key = WorkflowSliceKey<_InspectionSlice>('test.shared');

      final snapshot = _snapshot(
        slices: [
          WorkflowSliceBinding(
            key: inspection_key,
            value: const _InspectionSlice('/tmp'),
          ),
        ],
      );

      final incompatible_key = WorkflowSliceKey<_PlanningSlice>('test.shared');

      expect(() => snapshot.slice(incompatible_key), throwsStateError);
    });

    test('rejects duplicate slice identifiers', () {
      final inspection_key = WorkflowSliceKey<_InspectionSlice>('test.shared');
      final planning_key = WorkflowSliceKey<_PlanningSlice>('test.shared');

      expect(
        () => _snapshot(
          slices: [
            WorkflowSliceBinding(
              key: inspection_key,
              value: const _InspectionSlice('/tmp'),
            ),
            WorkflowSliceBinding(
              key: planning_key,
              value: const _PlanningSlice(3),
            ),
          ],
        ),
        throwsStateError,
      );
    });

    test('rejects duplicate slice types', () {
      final first = WorkflowSliceKey<_InspectionSlice>('test.first');
      final second = WorkflowSliceKey<_InspectionSlice>('test.second');

      expect(
        () => _snapshot(
          slices: [
            WorkflowSliceBinding(
              key: first,
              value: const _InspectionSlice('/tmp'),
            ),
            WorkflowSliceBinding(
              key: second,
              value: const _InspectionSlice('/other'),
            ),
          ],
        ),
        throwsStateError,
      );
    });

    test('defensively copies supplied slice bindings', () {
      final key = WorkflowSliceKey<_InspectionSlice>('test.inspection');

      final bindings = <WorkflowSliceBinding<WorkflowSlice>>[
        WorkflowSliceBinding(key: key, value: const _InspectionSlice('/tmp')),
      ];

      final snapshot = _snapshot(slices: bindings);

      bindings.clear();

      expect(snapshot.slice(key)?.root, '/tmp');
      expect(snapshot.slice_bindings, hasLength(1));
    });

    test('does not mutate an earlier snapshot', () {
      final key = WorkflowSliceKey<_InspectionSlice>('test.inspection');

      final first = _snapshot(
        version: 1,
        slices: [
          WorkflowSliceBinding(
            key: key,
            value: const _InspectionSlice('/first'),
          ),
        ],
      );

      final second = _snapshot(
        version: 2,
        slices: [
          WorkflowSliceBinding(
            key: key,
            value: const _InspectionSlice('/second'),
          ),
        ],
      );

      expect(first.slice(key)?.root, '/first');
      expect(first.version, 1);
      expect(second.slice(key)?.root, '/second');
      expect(second.version, 2);
    });
  });
}

/// Constructs a snapshot for pure domain-contract tests.
WorkflowSnapshot _snapshot({
  int version = 1,
  WorkflowLifecycle? lifecycle,
  Iterable<WorkflowSliceBinding<WorkflowSlice>> slices = const [],
}) {
  return WorkflowSnapshot(
    identity: _identity(),
    version: version,
    lifecycle: lifecycle ?? _active(),
    slices: slices,
  );
}

/// Returns a valid established workflow identity.
WorkflowIdentity _identity() {
  return WorkflowIdentity(
    workflow_id: 'workflow-1',
    os_user_id: 'user-1',
    target_id: 'local-macos',
    root: TargetPath('/tmp'),
  );
}

/// Returns a nonterminal lifecycle definition.
WorkflowLifecycle _active() {
  return WorkflowLifecycle(id: 'test.active', is_terminal: false);
}

/// Synthetic inspection state owned by the inspection test feature.
final class _InspectionSlice extends WorkflowSlice {
  /// Creates an inspection fixture retaining [root].
  const _InspectionSlice(this.root);

  /// Fixture root stored in the inspection state slice.
  final String root;
}

/// Synthetic planning state owned by the planning test feature.
final class _PlanningSlice extends WorkflowSlice {
  /// Creates a planning fixture retaining [candidate_count].
  const _PlanningSlice(this.candidate_count);

  /// Fixture candidate count stored in the planning state slice.
  final int candidate_count;
}
