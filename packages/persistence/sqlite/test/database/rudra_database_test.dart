import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:rudra_persistence_sqlite/rudra_persistence_sqlite.dart';
import 'package:test/test.dart';

/// Verifies SQLite schema creation, persistence and constraints.
///
/// No native filesystem targets or cleanup operations are used.
void main() {
  test('preserves a pending submission across database reopening', () async {
    final directory = await Directory.systemTemp.createTemp(
      'rudra-sqlite-test-',
    );

    final database_file = File('${directory.path}/rudra.db');

    try {
      final database = RudraDatabase(database_file);

      try {
        await database
            .into(database.workflowSubmissions)
            .insert(
              WorkflowSubmissionsCompanion.insert(
                event_id: 'event-1',
                correlation_id: 'correlation-1',
                scope_id: 'test-user',
                idempotency_key: const Value('request-1'),
                event_type: WorkflowStartEvent.type_id,
                payload_json: '{"target_id":"local-macos","root":"/workspace"}',
                accepted_at_unix_ms: DateTime.utc(
                  2026,
                  11,
                  15,
                ).millisecondsSinceEpoch,
              ),
            );
      } finally {
        await database.close();
      }

      // A new database connection must recover the committed row.
      final reopened = RudraDatabase(database_file);

      try {
        final submission = await reopened
            .select(reopened.workflowSubmissions)
            .getSingle();

        expect(submission.sequence, 1);
        expect(submission.event_id, 'event-1');
        expect(submission.correlation_id, 'correlation-1');
        expect(submission.scope_id, 'test-user');
        expect(submission.idempotency_key, 'request-1');
        expect(submission.event_type, WorkflowStartEvent.type_id);
        expect(submission.processing_state, 'pending');
        expect(submission.payload_json, contains('/workspace'));
      } finally {
        await reopened.close();
      }
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
