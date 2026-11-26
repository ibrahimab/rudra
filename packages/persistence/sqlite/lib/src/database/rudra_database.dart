import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart' show Database, SqliteException;

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
/// Each file connection runs in a background isolate owned by its host.
///
/// Example:
/// ```dart
/// final database = RudraDatabase.file(File('/workspace/fixture.sqlite'));
/// try {
///   await database.select(database.unfinishedWorkflows).get();
/// } finally {
///   await database.close();
/// }
/// ```
@DriftDatabase(
  tables: [WorkflowSubmissions, WorkflowEvents, UnfinishedWorkflows],
)
final class RudraDatabase extends _$RudraDatabase {
  /// Creates a database using an injected Drift query executor.
  ///
  /// Used by migration tests and other controlled connections.
  /// The caller transfers connection lifecycle ownership to
  /// this database instance.
  RudraDatabase(QueryExecutor executor)
    : _managed_schema = false,
      super(executor);

  /// Prepares a file-backed SQLite database without opening it immediately.
  ///
  /// [database_file] identifies the persistent SQLite database.
  /// The first database operation opens the connection in a background
  /// isolate, using WAL journaling and FULL synchronization.
  ///
  /// [require_existing_wal] verifies the provisioned database is already in
  /// WAL mode. Shared production storage uses this to avoid a rollback journal
  /// that a different account could be unable to remove after a crash.
  ///
  /// Construction does not create the database file or its parent directory.
  /// Explicit write operations may initialize a missing database.
  RudraDatabase.file(File database_file, {bool require_existing_wal = false})
    : _managed_schema = true,
      super(
        LazyDatabase(() => _file_executor(database_file, require_existing_wal)),
      );

  final bool _managed_schema;
  static const _busy_timeout = Duration(seconds: 5);
  static const _wal_retry_delay = Duration(milliseconds: 20);
  static const _sqlite_busy = 5;
  // SQLITE_DBCONFIG_NO_CKPT_ON_CLOSE leaves the WAL and SHM in place across
  // disconnects. SQLite still performs ordinary automatic checkpoints.
  static const _no_checkpoint_on_close = 1006;

  static QueryExecutor _file_executor(
    File database_file,
    bool require_existing_wal,
  ) => NativeDatabase.createInBackground(
    database_file,
    enableMigrations: false,
    setup: (database) => _configure_connection(
      database,
      require_existing_wal: require_existing_wal,
    ),
  );

  static void _configure_connection(
    Database database, {
    required bool require_existing_wal,
  }) {
    database.execute('PRAGMA busy_timeout = ${_busy_timeout.inMilliseconds}');
    database.config.setIntConfig(_no_checkpoint_on_close, 1);

    // The initial journal mode transition can return BUSY without invoking
    // SQLite's busy handler. Retry only this setup pragma, before admitting
    // any application operation.
    final elapsed = Stopwatch()..start();
    while (true) {
      try {
        final journal_mode = require_existing_wal
            ? 'PRAGMA journal_mode'
            : 'PRAGMA journal_mode = WAL';
        final mode = database.select(journal_mode).single.values.single;
        if (mode != 'wal') {
          throw StateError('Rudra requires SQLite WAL mode, got $mode.');
        }
        break;
      } on SqliteException catch (error) {
        if (error.resultCode != _sqlite_busy ||
            elapsed.elapsed >= _busy_timeout) {
          rethrow;
        }
        sleep(_wal_retry_delay);
      }
    }
    database.execute('PRAGMA synchronous = FULL');
  }

  /// Checks the schema on the real opening connection before it admits queries.
  Future<void> _prepare_schema(OpeningDetails _) async {
    // Drift normally reads user_version and sets it outside the migration.
    // Serialize both of those steps with the DDL using SQLite's writer lock.
    // The beforeOpen executor is already pinned to this connection.
    await customStatement('BEGIN IMMEDIATE');
    try {
      final version = await customSelect('PRAGMA user_version')
          .map((row) => row.read<int>('user_version'))
          .getSingle();

      if (version == 0) {
        // Rudra's fresh database has no application objects. Fail closed if
        // a different database was placed at its provisioned pathname.
        final entries = await customSelect(
          "SELECT 1 FROM sqlite_schema WHERE name NOT LIKE 'sqlite_%' LIMIT 1",
        ).get();
        if (entries.isNotEmpty) {
          throw StateError(
            'Unversioned Rudra database contains an existing schema.',
          );
        }
        await createMigrator().createAll();
      } else if (version < schemaVersion) {
        await migration.onUpgrade(createMigrator(), version, schemaVersion);
      } else if (version != schemaVersion) {
        throw StateError('Unsupported Rudra database schema version $version.');
      }

      if (version != schemaVersion) {
        await customStatement('PRAGMA user_version = $schemaVersion');
      }
      await customStatement('COMMIT');
    } catch (_) {
      await customStatement('ROLLBACK');
      rethrow;
    }
  }

  /// Version of Rudra's persisted SQLite schema.
  @override
  int get schemaVersion => 5;

  /// Upgrades existing databases without discarding
  /// previously accepted workflow submissions.
  @override
  MigrationStrategy get migration => MigrationStrategy(
    beforeOpen: _managed_schema ? _prepare_schema : null,
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
        await migrator.addColumn(
          schema.workflowEvents,
          schema.workflowEvents.osUserId,
        );

        // Backfill existing v4 histories using their original
        // ownership outcome. This is migration-only compatibility.
        //
        // New commits receive trusted ownership metadata directly
        // and never need JSON extraction for owner lookup.
        await customStatement(r'''
          UPDATE workflow_events
          SET os_user_id = CASE
            WHEN json_valid(payload_json)
            THEN json_extract(payload_json, '$.os_user_id')
          END
          WHERE event_type = 'workflow.started'
        ''');

        await customStatement('''
          CREATE INDEX workflow_events_owner_idx
          ON workflow_events (os_user_id, workflow_id)
        ''');
      },
    ),
  );
}
