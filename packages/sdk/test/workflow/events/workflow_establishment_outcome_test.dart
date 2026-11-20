import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

void main() {
  group('Workflow establishment outcome', () {
    test('exposes complete identity through the shared contract', () {
      final identity = _identity();

      final WorkflowOutcomeEvent outcome = WorkflowStartedEvent(
        identity: identity,
      );

      expect(outcome, isA<WorkflowEstablishmentOutcomeEvent>());

      final establishing = outcome as WorkflowEstablishmentOutcomeEvent;

      expect(establishing.identity, same(identity));
      expect(establishing.identity.workflow_id, 'workflow-1');
      expect(establishing.identity.os_user_id, 'user-1');
      expect(establishing.identity.target_id, 'local-macos');
      expect(establishing.identity.root.value, '/tmp');
    });

    test('terminal outcomes cannot establish workflow identity', () {
      final WorkflowOutcomeEvent outcome = WorkflowEndedEvent(
        workflow_id: 'workflow-1',
      );

      expect(outcome, isNot(isA<WorkflowEstablishmentOutcomeEvent>()));

      expect(outcome, isA<WorkflowOutcomeEvent>());
    });

    test('submitted commands are not establishment outcomes', () {
      final WorkflowCommandEvent command = WorkflowStartEvent(
        target_id: 'local-macos',
        root: TargetPath('/tmp'),
      );

      expect(command, isA<WorkflowCommandEvent>());

      expect(command, isNot(isA<WorkflowEstablishmentOutcomeEvent>()));

      expect(command, isNot(isA<WorkflowOutcomeEvent>()));
    });
  });
}

/// Constructs a complete workflow identity for event-contract tests.
///
/// Identity validation is performed by its domain constructor.
/// These tests do not perform persistence or authentication.
WorkflowIdentity _identity() {
  return WorkflowIdentity(
    workflow_id: 'workflow-1',
    os_user_id: 'user-1',
    target_id: 'local-macos',
    root: TargetPath('/tmp'),
  );
}
