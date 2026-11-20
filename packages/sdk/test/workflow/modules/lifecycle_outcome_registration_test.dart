import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

void main() {
  group('Standard lifecycle outcome registration', () {
    test('registers establishment and terminal outcome rules', () {
      final runtime = WorkflowRuntime.standard();

      expect(runtime.outcome_transitions, hasLength(2));

      final started = runtime.outcome_transitions.singleWhere(
        (transition) => transition.event_type == WorkflowStartedEvent,
      );

      expect(started.source_lifecycle_id, isNull);
      expect(started.destination_lifecycle_id, 'rudra.workflow.active');

      final ended = runtime.outcome_transitions.singleWhere(
        (transition) => transition.event_type == WorkflowEndedEvent,
      );

      expect(ended.source_lifecycle_id, 'rudra.workflow.active');

      expect(ended.destination_lifecycle_id, 'rudra.workflow.ended');

      expect(runtime.lifecycles['rudra.workflow.ended']!.is_terminal, isTrue);
    });

    test('validates workflow establishment without a snapshot', () {
      final runtime = WorkflowRuntime.standard();

      final started = runtime.outcome_transitions.singleWhere(
        (transition) => transition.event_type == WorkflowStartedEvent,
      );

      final identity = _identity();

      started.validate(null, WorkflowStartedEvent(identity: identity));

      // Registration never establishes or persists a workflow.
      expect(started.source_lifecycle_id, isNull);
    });

    test('rejects an ended outcome for another workflow', () {
      final runtime = WorkflowRuntime.standard();

      final ended = runtime.outcome_transitions.singleWhere(
        (transition) => transition.event_type == WorkflowEndedEvent,
      );

      final previous = WorkflowSnapshot(
        identity: _identity(),
        version: 1,
        lifecycle: runtime.lifecycles['rudra.workflow.active']!,
      );

      ended.validate(previous, WorkflowEndedEvent(workflow_id: 'workflow-1'));

      expect(
        () => ended.validate(
          previous,
          WorkflowEndedEvent(workflow_id: 'workflow-2'),
        ),
        throwsStateError,
      );

      // Failed validation leaves the previous snapshot unchanged.
      expect(previous.version, 1);
      expect(previous.lifecycle.id, 'rudra.workflow.active');
      expect(previous.is_terminal, isFalse);
    });

    test('retains existing command handling during migration', () {
      final runtime = WorkflowRuntime.standard();

      expect(runtime.command_behaviors[WorkflowStartEvent], isNotNull);

      expect(runtime.command_behaviors[WorkflowStopEvent], isNotNull);

      expect(
        runtime.codec.decode(
          event_type: WorkflowStartedEvent.type_id,
          payload_json: runtime.codec.encode(
            WorkflowStartedEvent(identity: _identity()),
          ),
        ),
        isA<WorkflowStartedEvent>(),
      );
    });
  });
}

/// Constructs an established identity for pure lifecycle tests.
///
/// The identity contains fixed test values and does not depend
/// on platform identity providers or persistence.
WorkflowIdentity _identity() {
  return WorkflowIdentity(
    workflow_id: 'workflow-1',
    os_user_id: 'user-1',
    target_id: 'local-macos',
    root: TargetPath('/tmp'),
  );
}
