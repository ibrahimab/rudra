import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Verifies workflow outcome contracts behavior through this file's focused tests.
void main() {
  group('WorkflowOutcomeTransition', () {
    test('supports initial establishment without a prior snapshot', () {
      final transition = WorkflowOutcomeTransition<WorkflowStartedEvent>(
        source_lifecycle_id: null,
        destination_lifecycle_id: 'test.active',
      );

      expect(transition.source_lifecycle_id, isNull);
      expect(transition.destination_lifecycle_id, 'test.active');
      expect(transition.event_type, WorkflowStartedEvent);

      transition.validate(null, WorkflowStartedEvent(identity: _identity()));
    });

    test('evaluates a typed lifecycle guard', () {
      final snapshot = _snapshot();
      final transition = WorkflowOutcomeTransition<WorkflowEndedEvent>(
        source_lifecycle_id: 'test.active',
        destination_lifecycle_id: 'test.ended',
        guard: (previous, event) {
          if (previous?.identity.workflow_id != event.workflow_id) {
            throw StateError('Workflow identity mismatch.');
          }
        },
      );

      transition.validate(
        snapshot,
        WorkflowEndedEvent(workflow_id: 'workflow-1'),
      );

      expect(
        () => transition.validate(
          snapshot,
          WorkflowEndedEvent(workflow_id: 'workflow-2'),
        ),
        throwsStateError,
      );

      expect(snapshot.version, 1);
      expect(snapshot.is_terminal, isFalse);
    });

    test('rejects an unrelated outcome type', () {
      final transition = WorkflowOutcomeTransition<WorkflowStartedEvent>(
        source_lifecycle_id: null,
        destination_lifecycle_id: 'test.active',
      );

      expect(
        () => transition.validate(
          null,
          WorkflowEndedEvent(workflow_id: 'workflow-1'),
        ),
        throwsStateError,
      );
    });

    test('rejects blank lifecycle identifiers', () {
      expect(
        () => WorkflowOutcomeTransition<WorkflowEndedEvent>(
          source_lifecycle_id: ' ',
          destination_lifecycle_id: 'test.ended',
        ),
        throwsArgumentError,
      );

      expect(
        () => WorkflowOutcomeTransition<WorkflowEndedEvent>(
          source_lifecycle_id: 'test.active',
          destination_lifecycle_id: '',
        ),
        throwsArgumentError,
      );
    });
  });

  group('WorkflowSliceReducer', () {
    test('creates a typed slice from a committed outcome', () {
      final key = WorkflowSliceKey<_InspectionSlice>('test.inspection');

      final reducer =
          WorkflowSliceReducer<_InspectionSlice, WorkflowStartedEvent>(
            key: key,
            reduce: (previous, event, current) {
              expect(previous, isNull);
              expect(current, isNull);

              return const _InspectionSlice('/first');
            },
          );

      final result = reducer.apply(
        null,
        WorkflowStartedEvent(identity: _identity()),
      );

      expect(result, isA<_InspectionSlice>());
      expect((result as _InspectionSlice).root, '/first');
    });

    test('receives the previous committed slice value', () {
      final key = WorkflowSliceKey<_InspectionSlice>('test.inspection');

      final previous = _snapshot(
        slices: [
          WorkflowSliceBinding(
            key: key,
            value: const _InspectionSlice('/first'),
          ),
        ],
      );

      final reducer =
          WorkflowSliceReducer<_InspectionSlice, WorkflowEndedEvent>(
            key: key,
            reduce: (snapshot, event, current) {
              expect(snapshot, same(previous));
              expect(current?.root, '/first');

              return const _InspectionSlice('/second');
            },
          );

      final result = reducer.apply(
        previous,
        WorkflowEndedEvent(workflow_id: 'workflow-1'),
      );

      expect((result as _InspectionSlice).root, '/second');

      // A reduction does not mutate the previous snapshot.
      expect(previous.slice(key)?.root, '/first');
      expect(previous.version, 1);
    });

    test('supports explicit removal of an owned slice', () {
      final key = WorkflowSliceKey<_InspectionSlice>('test.inspection');

      final reducer =
          WorkflowSliceReducer<_InspectionSlice, WorkflowEndedEvent>(
            key: key,
            reduce: (previous, event, current) => null,
          );

      final result = reducer.apply(
        _snapshot(),
        WorkflowEndedEvent(workflow_id: 'workflow-1'),
      );

      expect(result, isNull);
    });

    test('rejects an unrelated outcome type', () {
      final key = WorkflowSliceKey<_InspectionSlice>('test.inspection');

      final reducer =
          WorkflowSliceReducer<_InspectionSlice, WorkflowEndedEvent>(
            key: key,
            reduce: (previous, event, current) => current,
          );

      expect(
        () => reducer.apply(
          _snapshot(),
          WorkflowStartedEvent(identity: _identity()),
        ),
        throwsStateError,
      );
    });
  });
}

/// Creates an established snapshot for reducer contract tests.
WorkflowSnapshot _snapshot({
  Iterable<WorkflowSliceBinding<WorkflowSlice>> slices = const [],
}) {
  return WorkflowSnapshot(
    identity: _identity(),
    version: 1,
    lifecycle: WorkflowLifecycle(id: 'test.active', is_terminal: false),
    slices: slices,
  );
}

/// Creates the original trusted workflow identity used in tests.
WorkflowIdentity _identity() {
  return WorkflowIdentity(
    workflow_id: 'workflow-1',
    os_user_id: 'user-1',
    target_id: 'local-macos',
    root: TargetPath('/tmp'),
  );
}

/// Synthetic immutable inspection slice.
final class _InspectionSlice extends WorkflowSlice {
  const _InspectionSlice(this.root);

  /// Fixture root captured by the test reducer.
  final String root;
}
