import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:rudra_persistence_sqlite/src/database/rudra_database.dart';
import 'package:rudra_persistence_sqlite/src/features/workflow/submissions/drift_event_submission_store.dart';
import 'package:rudra_persistence_sqlite/src/features/workflow/submissions/drift_workflow_inbox.dart';
import 'package:test/test.dart';

/// Verifies durable, read-only workflow inbox behavior.
void main() {
  const scope_id = 'trusted-user';

  late Directory directory;
  late File database_file;
  late RudraDatabase database;
  late DriftWorkflowInbox inbox;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('rudra-inbox-test-');

    database_file = File('${directory.path}/rudra.db');
    database = RudraDatabase.file(database_file);

    inbox = DriftWorkflowInbox(database: database, scope_id: scope_id);
  });

  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  /// Submits a command using Rudra's existing durable
  /// acceptance implementation.
  Future<EventSubmissionReceipt> submit(
    String root, {
    String submission_scope = scope_id,
  }) {
    final manager = EventManager(
      store: DriftEventSubmissionStore(
        database: database,
        scope_id: submission_scope,
      ),
    );

    return manager.trigger(
      WorkflowStartEvent(target_id: 'local-macos', root: TargetPath(root)),
    );
  }

  test('returns null when no pending command exists', () async {
    expect(await inbox.next_pending(), isNull);
  });

  test('reads the oldest pending command without claiming it', () async {
    final first = await submit('/first');
    await submit('/second');

    final pending = await inbox.next_pending();

    expect(pending, isNotNull);
    expect(pending!.receipt.event_id, first.event_id);
    expect(pending.receipt.correlation_id, first.correlation_id);
    expect(pending.scope_id, scope_id);
    expect(pending.command, isA<WorkflowStartEvent>());
    expect((pending.command as WorkflowStartEvent).root.value, '/first');
    expect(pending.committed_events, isEmpty);

    // Reading does not claim or complete the submission.
    // The same oldest pending command remains available.
    final repeated = await inbox.next_pending();

    expect(repeated!.receipt.event_id, first.event_id);

    final rows = await database.select(database.workflowSubmissions).get();

    expect(rows, hasLength(2));
    expect(rows.every((row) => row.processing_state == 'pending'), isTrue);
  });

  test('filters by scope and pending processing status', () async {
    await submit('/foreign', submission_scope: 'another-user');

    final completed = await submit('/completed');

    // Simulate a submission completed by a committer.
    await (database.update(
      database.workflowSubmissions,
    )..where((row) => row.event_id.equals(completed.event_id))).write(
      const WorkflowSubmissionsCompanion(processing_state: Value('completed')),
    );

    final eligible = await submit('/eligible');

    final pending = await inbox.next_pending();

    expect(pending, isNotNull);
    expect(pending!.receipt.event_id, eligible.event_id);
    expect((pending.command as WorkflowStartEvent).root.value, '/eligible');
  });

  test('recovers pending submissions after reopening', () async {
    final receipt = await submit('/workspace');

    await database.close();

    // A completely new SQLite connection must observe
    // the previously committed submission.
    database = RudraDatabase.file(database_file);

    inbox = DriftWorkflowInbox(database: database, scope_id: scope_id);

    final pending = await inbox.next_pending();

    expect(pending, isNotNull);
    expect(pending!.receipt.event_id, receipt.event_id);
    expect((pending.command as WorkflowStartEvent).root.value, '/workspace');
  });

  test('does not silently skip malformed commands', () async {
    await database
        .into(database.workflowSubmissions)
        .insert(
          WorkflowSubmissionsCompanion.insert(
            event_id: 'invalid-event',
            correlation_id: 'invalid-correlation',
            scope_id: scope_id,
            event_type: WorkflowStartEvent.type_id,
            payload_json: '{"schema_version":999}',
            accepted_at_unix_ms: 0,
          ),
        );

    // A corrupted accepted command cannot silently vanish
    // from the processing obligation.
    await expectLater(inbox.next_pending(), throwsFormatException);
  });
}
