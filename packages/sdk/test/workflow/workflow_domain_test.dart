import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Tests the immutable workflow domain contracts.
///
/// These tests do not perform filesystem operations or use
/// persistence. Transition and replay behavior is tested
/// separately when the state machine is implemented.
void main() {
  group('WorkflowIdentity', () {
    test('preserves all original workflow bindings', () {
      final root = TargetPath('/Users/example/Downloads');

      final identity = WorkflowIdentity(
        workflow_id: 'workflow-1',
        os_user_id: 'user-1',
        target_id: 'local-macos',
        root: root,
      );

      expect(identity.workflow_id, 'workflow-1');
      expect(identity.os_user_id, 'user-1');
      expect(identity.target_id, 'local-macos');
      expect(identity.root, same(root));
    });

    test('rejects blank identifiers', () {
      final root = TargetPath('/tmp');

      for (final value in ['', ' ', '\t', '\n']) {
        expect(
          () => WorkflowIdentity(
            workflow_id: value,
            os_user_id: 'user-1',
            target_id: 'local-macos',
            root: root,
          ),
          throwsArgumentError,
        );

        expect(
          () => WorkflowIdentity(
            workflow_id: 'workflow-1',
            os_user_id: value,
            target_id: 'local-macos',
            root: root,
          ),
          throwsArgumentError,
        );

        expect(
          () => WorkflowIdentity(
            workflow_id: 'workflow-1',
            os_user_id: 'user-1',
            target_id: value,
            root: root,
          ),
          throwsArgumentError,
        );
      }
    });

    test('preserves target-native Windows paths', () {
      final identity = WorkflowIdentity(
        workflow_id: 'workflow-1',
        os_user_id: 'user-1',
        target_id: 'local-windows',
        root: TargetPath(r'C:\Users\example\Downloads'),
      );

      expect(identity.root.value, r'C:\Users\example\Downloads');
    });
  });

  group('WorkflowEvent', () {
    test('provides stable event type identifiers', () {
      final identity = _create_identity();

      final events = <WorkflowEvent>[
        WorkflowStartEvent(target_id: 'local-macos', root: TargetPath('/tmp')),
        WorkflowStartedEvent(identity: identity),
        WorkflowStopEvent(workflow_id: identity.workflow_id),
        WorkflowEndedEvent(workflow_id: identity.workflow_id),
      ];

      expect(events.map((event) => event.event_type).toList(), [
        'workflow.start',
        'workflow.started',
        'workflow.stop',
        'workflow.ended',
      ]);
    });

    test('start request does not establish workflow identity', () {
      final root = TargetPath('/tmp');

      final event = WorkflowStartEvent(target_id: 'local-macos', root: root);

      expect(event.target_id, 'local-macos');
      expect(event.root, same(root));
      expect(event.event_type, WorkflowStartEvent.type_id);
    });

    test('started event retains established identity', () {
      final identity = _create_identity();

      final event = WorkflowStartedEvent(identity: identity);

      expect(event.identity, same(identity));
      expect(event.event_type, WorkflowStartedEvent.type_id);
    });

    test('stop event identifies its workflow', () {
      final event = WorkflowStopEvent(workflow_id: 'workflow-1');

      expect(event.workflow_id, 'workflow-1');
      expect(event.event_type, WorkflowStopEvent.type_id);
    });

    test('ended event identifies its workflow', () {
      final event = WorkflowEndedEvent(workflow_id: 'workflow-1');

      expect(event.workflow_id, 'workflow-1');
      expect(event.event_type, WorkflowEndedEvent.type_id);
    });

    test('rejects invalid event identifiers', () {
      expect(
        () => WorkflowStartEvent(target_id: ' ', root: TargetPath('/tmp')),
        throwsArgumentError,
      );

      expect(() => WorkflowEndedEvent(workflow_id: ' '), throwsArgumentError);
      expect(() => WorkflowStopEvent(workflow_id: ' '), throwsArgumentError);
    });
  });
}

/// Creates a valid established workflow identity for tests.
///
/// Each invocation returns a new immutable identity.
WorkflowIdentity _create_identity() {
  return WorkflowIdentity(
    workflow_id: 'workflow-1',
    os_user_id: 'user-1',
    target_id: 'local-macos',
    root: TargetPath('/Users/example/Downloads'),
  );
}
