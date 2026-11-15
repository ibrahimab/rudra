import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import '../features/workflow/submissions/workflow_submissions.dart';

part 'rudra_database.g.dart';

/// SQLite persistence database for Rudra.
///
/// The database belongs exclusively to the persistence package.
/// SDK services depend on contracts rather than this class.
///
/// Queries run in a background isolate to avoid blocking
/// frontend interaction.
@DriftDatabase(tables: [WorkflowSubmissions])
final class RudraDatabase extends _$RudraDatabase {
  /// Opens a file-backed database.
  ///
  /// The caller owns the database location and its directory.
  ///
  /// WAL supports concurrent readers and a single writer.
  /// FULL synchronization strengthens commit durability.
  RudraDatabase(File database_file)
    : super(
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
  int get schemaVersion => 1;
}
