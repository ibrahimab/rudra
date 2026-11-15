import 'dart:io';
import 'dart:isolate';

import 'package:rudra_persistence_sqlite/src/database/rudra_database.dart';
import 'package:rudra_persistence_sqlite/src/features/workflow/submissions/drift_event_submission_store.dart';
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:test/test.dart';

/// Verifies durable workflow submission and idempotency.
void main() {
  late Directory directory;
  late RudraDatabase database;
  late EventManager manager;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('rudra-store-');

    database = RudraDatabase(File('${directory.path}/rudra.db'));

    manager = EventManager(
      store: DriftEventSubmissionStore(
        database: database,
        scope_id: 'test-user',
      ),
    );
  });

  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  /// Creates a workflow-start request for a test root.
  WorkflowStartEvent start(String root) =>
      WorkflowStartEvent(target_id: 'local-macos', root: TargetPath(root));

  test('persists an accepted command as pending', () async {
    final receipt = await manager.trigger(start('/workspace'));

    final submission = await database
        .select(database.workflowSubmissions)
        .getSingle();

    expect(submission.event_id, receipt.event_id);
    expect(submission.correlation_id, receipt.correlation_id);
    expect(submission.scope_id, 'test-user');
    expect(submission.event_type, WorkflowStartEvent.type_id);
    expect(submission.processing_state, 'pending');
    expect(submission.payload_json, contains('/workspace'));
  });

  test('returns original receipt for identical retry', () async {
    final first = await manager.trigger(
      start('/workspace'),
      idempotency_key: 'request-1',
    );

    final second = await manager.trigger(
      start('/workspace'),
      idempotency_key: 'request-1',
    );

    expect(second.event_id, first.event_id);
    expect(second.correlation_id, first.correlation_id);

    final submissions = await database
        .select(database.workflowSubmissions)
        .get();

    expect(submissions, hasLength(1));
  });

  test('rejects conflicting idempotency keys', () async {
    await manager.trigger(start('/workspace'), idempotency_key: 'request-1');

    await expectLater(
      manager.trigger(start('/another-root'), idempotency_key: 'request-1'),
      throwsA(
        isA<EventSubmissionException>().having(
          (error) => error.code,
          'code',
          EventSubmissionErrorCode.idempotency_conflict,
        ),
      ),
    );

    final submissions = await database
        .select(database.workflowSubmissions)
        .get();

    expect(submissions, hasLength(1));
    expect(submissions.single.payload_json, contains('/workspace'));
  });

  test('deduplicates concurrent submissions across isolates', () async {
    final database_path = '${directory.path}/rudra.db';

    // Initialize the database schema before concurrent access.
    await database.select(database.workflowSubmissions).get();

    final receipts = await Future.wait<List<String>>([
      manager
          .trigger(start('/workspace'), idempotency_key: 'concurrent-request')
          .then((receipt) => [receipt.event_id, receipt.correlation_id]),
      _run_isolated_submission(database_path),
    ]);

    expect(receipts[0], receipts[1]);

    final submissions = await database
        .select(database.workflowSubmissions)
        .get();

    expect(submissions, hasLength(1));
    expect(submissions.single.processing_state, 'pending');
  });

  test('recovers idempotency after database reopening', () async {
    final original = await manager.trigger(
      start('/workspace'),
      idempotency_key: 'restart-request',
    );

    await database.close();

    database = RudraDatabase(File('${directory.path}/rudra.db'));

    manager = EventManager(
      store: DriftEventSubmissionStore(
        database: database,
        scope_id: 'test-user',
      ),
    );

    final recovered = await manager.trigger(
      start('/workspace'),
      idempotency_key: 'restart-request',
    );

    expect(recovered.event_id, original.event_id);
    expect(recovered.correlation_id, original.correlation_id);

    final submissions = await database
        .select(database.workflowSubmissions)
        .get();

    expect(submissions, hasLength(1));
  });
}

/// Submits a workflow request using an independent database isolate.
///
/// Only the database path crosses the isolate boundary.
/// The database and its dependencies are created and closed
/// within the worker isolate.
Future<List<String>> _accept_from_isolate(String database_path) async {
  final isolated_database = RudraDatabase(File(database_path));

  try {
    final manager = EventManager(
      store: DriftEventSubmissionStore(
        database: isolated_database,
        scope_id: 'test-user',
      ),
    );

    final receipt = await manager.trigger(
      WorkflowStartEvent(
        target_id: 'local-macos',
        root: TargetPath('/workspace'),
      ),
      idempotency_key: 'concurrent-request',
    );

    return [receipt.event_id, receipt.correlation_id];
  } finally {
    await isolated_database.close();
  }
}

/// Runs a database submission in an independent Dart isolate.
///
/// The spawned closure captures only the database path,
/// preventing non-sendable test fixtures from crossing
/// the isolate boundary.
Future<List<String>> _run_isolated_submission(String database_path) {
  return Isolate.run(() => _accept_from_isolate(database_path));
}
