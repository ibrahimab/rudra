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
  int get schemaVersion => 2;

  /// Upgrades existing databases without discarding
  /// previously accepted workflow submissions.
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: stepByStep(
      from1To2: (migrator, schema) async {
        await migrator.createTable(schema.workflowEvents);
        await migrator.createTable(schema.unfinishedWorkflows);
      },
    ),
  );
}
