import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:rudra_sdk/src/workflow/behaviors/workflow_start_behavior.dart';
import 'package:rudra_sdk/src/workflow/behaviors/workflow_stop_behavior.dart';
import 'package:test/test.dart';

void main() {
  group('WorkflowStartBehavior command validation', () {
    const behavior = WorkflowStartBehavior();

    test('accepts a Start request with matching identity', () {
      final command = _start();

      behavior.validate_submission(
        command,
        previous: null,
        identity: _identity(),
      );
    });

    test('rejects Start when a workflow already exists', () {
      expect(
        () => behavior.validate_submission(
          _start(),
          previous: _snapshot(),
          identity: _identity(),
        ),
        _validation_error(
          WorkflowCommandValidationErrorCode.workflow_already_active,
        ),
      );
    });

    test('rejects a changed filesystem target', () {
      expect(
        () => behavior.validate_submission(
          _start(),
          previous: null,
          identity: _identity(target_id: 'another-target'),
        ),
        _validation_error(WorkflowCommandValidationErrorCode.target_mismatch),
      );
    });

    test('rejects a changed inspection root', () {
      expect(
        () => behavior.validate_submission(
          _start(),
          previous: null,
          identity: _identity(root: '/different'),
        ),
        _validation_error(WorkflowCommandValidationErrorCode.root_mismatch),
      );
    });

    test('rejects a command of another concrete type', () {
      expect(
        () => behavior.validate_submission(
          WorkflowStopEvent(workflow_id: 'workflow-1'),
          previous: null,
          identity: _identity(),
        ),
        throwsArgumentError,
      );
    });
  });

  group('WorkflowStopBehavior command validation', () {
    const behavior = WorkflowStopBehavior();

    test('accepts Stop for the current workflow', () {
      final snapshot = _snapshot();

      behavior.validate_submission(
        WorkflowStopEvent(workflow_id: 'workflow-1'),
        previous: snapshot,
        identity: snapshot.identity,
      );

      expect(snapshot.version, 1);
      expect(snapshot.is_terminal, isFalse);
    });

    test('rejects Stop when no workflow exists', () {
      expect(
        () => behavior.validate_submission(
          WorkflowStopEvent(workflow_id: 'workflow-1'),
          previous: null,
          identity: _identity(),
        ),
        _validation_error(
          WorkflowCommandValidationErrorCode.workflow_not_active,
        ),
      );
    });

    test('rejects Stop against a terminal workflow', () {
      expect(
        () => behavior.validate_submission(
          WorkflowStopEvent(workflow_id: 'workflow-1'),
          previous: _snapshot(is_terminal: true),
          identity: _identity(),
        ),
        _validation_error(
          WorkflowCommandValidationErrorCode.workflow_not_active,
        ),
      );
    });

    test('rejects Stop targeting another workflow', () {
      final snapshot = _snapshot();

      expect(
        () => behavior.validate_submission(
          WorkflowStopEvent(workflow_id: 'workflow-2'),
          previous: snapshot,
          identity: snapshot.identity,
        ),
        _validation_error(
          WorkflowCommandValidationErrorCode.workflow_id_mismatch,
        ),
      );
    });

    test('rejects a conflicting processing identity', () {
      final snapshot = _snapshot();

      expect(
        () => behavior.validate_submission(
          WorkflowStopEvent(workflow_id: 'workflow-1'),
          previous: snapshot,
          identity: _identity(os_user_id: 'another-user'),
        ),
        _validation_error(WorkflowCommandValidationErrorCode.identity_mismatch),
      );

      expect(snapshot.identity.os_user_id, 'user-1');
      expect(snapshot.version, 1);
    });
  });
}

/// Matches a thrown command-validation exception by its typed error code.
///
/// Executes the supplied closure and verifies that it throws
/// [WorkflowCommandValidationException] with the expected [code].
///
/// Diagnostic messages are intentionally excluded from matching,
/// allowing their wording to change without breaking the tests.
Matcher _validation_error(WorkflowCommandValidationErrorCode code) {
  return throwsA(
    isA<WorkflowCommandValidationException>().having(
      (error) => error.code,
      'code',
      code,
    ),
  );
}

/// Creates the standard Start request for pure behavior tests.
WorkflowStartEvent _start() {
  return WorkflowStartEvent(target_id: 'local-macos', root: TargetPath('/tmp'));
}

/// Creates a complete identity with individually configurable bindings.
WorkflowIdentity _identity({
  String workflow_id = 'workflow-1',
  String os_user_id = 'user-1',
  String target_id = 'local-macos',
  String root = '/tmp',
}) {
  return WorkflowIdentity(
    workflow_id: workflow_id,
    os_user_id: os_user_id,
    target_id: target_id,
    root: TargetPath(root),
  );
}

/// Creates an established workflow snapshot for command validation.
///
/// The fixture has no database, event journal, or frontend state.
WorkflowSnapshot _snapshot({bool is_terminal = false}) {
  return WorkflowSnapshot(
    identity: _identity(),
    version: 1,
    lifecycle: WorkflowLifecycle(
      id: is_terminal ? 'test.ended' : 'test.active',
      is_terminal: is_terminal,
    ),
  );
}
