import 'dart:io';

import 'package:rudra_persistence_sqlite/rudra_persistence_sqlite.dart';
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:uuid/uuid.dart';

/// Constructs one independently owned context in a shared persistence fixture.
(RudraSqlitePersistence, WorkflowApplication) shared_context(
  File database,
  String owner,
) {
  final runtime = WorkflowRuntime.standard();
  final persistence = RudraSqlitePersistence(
    database_file: database,
    scope_id: owner,
    runtime: runtime,
  );
  return (
    persistence,
    WorkflowApplication(
      runtime: runtime,
      persistence: persistence,
      identity_provider: _IdentityProvider(owner),
      os_user_id: owner,
    ),
  );
}

/// Waits on stdin so the parent can start two first writes together.
Future<void> main(List<String> arguments) async {
  final (persistence, application) = shared_context(
    File(arguments[0]),
    arguments[1],
  );
  try {
    stdout.writeln('ready');
    await stdout.flush();
    if (stdin.readLineSync() != 'start') {
      throw StateError('Worker did not receive the initialization signal.');
    }
    final outcome = await application.start(
      target_id: 'fixture-filesystem',
      root: TargetPath('/${application.os_user_id}'),
      idempotency_key: 'shared-key',
    );
    final resolution = (outcome as WorkflowOperationResolved).resolution;
    if (resolution.state != WorkflowSubmissionState.completed) {
      throw StateError('Failed to establish the worker workflow.');
    }
    stdout.writeln(resolution.committed_outcome!.workflow_id);
  } finally {
    await persistence.close();
  }
}

final class _IdentityProvider implements WorkflowIdentityProvider {
  const _IdentityProvider(this.owner);

  final String owner;

  @override
  Future<WorkflowIdentity> propose_identity(
    PendingWorkflowCommand submission,
  ) async {
    final start = submission.command as WorkflowStartEvent;
    return WorkflowIdentity(
      workflow_id: Uuid().v4(),
      os_user_id: owner,
      target_id: start.target_id,
      root: start.root,
    );
  }
}
