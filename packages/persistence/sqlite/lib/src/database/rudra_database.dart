import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import '../features/workflow/submissions/workflow_submissions.dart';
import '../features/workflow/history/workflow_events.dart';
import '../features/workflow/lifecycle/unfinished_workflows.dart';

import 'rudra_database.steps.dart';

part 'rudra_database.g.dart';

/// SQLite persistence database for Rudra.
///
/// The database belongs exclusively to the persistence package.
/// SDK services depend on contracts rather than this class.
///
/// Queries run in a background isolate to avoid blocking
/// frontend interaction.
@DriftDatabase(
  tables: [WorkflowSubmissions, WorkflowEvents, UnfinishedWorkflows],
)
final class RudraDatabase extends _$RudraDatabase {
  /// Creates a database using an injected Drift query executor.
  ///
  /// Used by migration tests and other controlled connections.
  /// The caller transfers connection lifecycle ownership to
  /// this database instance.
  RudraDatabase(QueryExecutor executor) : super(executor);

  /// Opens a production file-backed SQLite database.
  ///
  /// Queries execute in a background isolate.
  /// WAL supports concurrency and FULL synchronization
  /// strengthens commit durability.
  RudraDatabase.file(File database_file)
    : this(
        NativeDatabase.createInBackground(
          database_file,
          setup: (database) {
            database.execute('PRAGMA busy_timeout = 5000');
            database.execute('PRAGMA journal_mode = WAL');
            database.execute('PRAGMA synchronous = FULL');
          },
        ),
      );

  /// Version of Rudra's persisted SQLite schema.
  @override
  int get schemaVersion => 5;

  /// Upgrades existing databases without discarding
  /// previously accepted workflow submissions.
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: stepByStep(
      from1To2: (migrator, schema) async {
        await migrator.createTable(schema.workflowEvents);
        await migrator.createTable(schema.unfinishedWorkflows);
      },

      from2To3: (migrator, schema) async {
        // Both fields are nullable, so existing accepted
        // submissions can be preserved without backfilling.
        await migrator.addColumn(
          schema.workflowSubmissions,
          schema.workflowSubmissions.rejectionCode,
        );

        await migrator.addColumn(
          schema.workflowSubmissions,
          schema.workflowSubmissions.rejectedAtUnixMs,
        );
      },

      from3To4: (migrator, schema) async {
        // Existing rows must retain their state and payloads.
        // All new quarantine columns are nullable.
        await migrator.addColumn(
          schema.workflowSubmissions,
          schema.workflowSubmissions.quarantineCode,
        );

        await migrator.addColumn(
          schema.workflowSubmissions,
          schema.workflowSubmissions.quarantineDiagnostic,
        );

        await migrator.addColumn(
          schema.workflowSubmissions,
          schema.workflowSubmissions.quarantinedAtUnixMs,
        );
      },

      from4To5: (migrator, schema) async {
        // Index historical workflow ownership without modifying
        // committed event data.
        //
        // Malformed event payloads receive a NULL index entry
        // instead of preventing database migration.
        await customStatement(r'''
          CREATE INDEX workflow_events_started_owner_idx
          ON workflow_events (
            CASE
              WHEN json_valid(payload_json)
              THEN json_extract(payload_json, '$.os_user_id')
            END,
            workflow_id
          )
          WHERE event_type = 'workflow.started'
        ''');
      },
    ),
  );
}
