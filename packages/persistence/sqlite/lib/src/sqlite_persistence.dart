import 'dart:io';

import 'package:rudra_sdk/rudra_sdk.dart';

import 'database/rudra_database.dart';
import 'features/workflow/submissions/drift_event_submission_store.dart';
import 'features/workflow/submissions/drift_workflow_inbox.dart';

/// Owns SQLite persistence resources for one Rudra application.
///
/// Exposes SDK-defined contracts while keeping database
/// implementation details private.
///
/// The caller supplies a trusted operating-system user scope
/// and owns the lifetime of this persistence instance.
///
/// Example:
/// ```dart
/// final persistence = RudraSqlitePersistence(
///   database_file: File('rudra.db'),
///   scope_id: 'trusted-user',
/// );
///
/// try {
///   final events = EventManager(
///     store: persistence.event_submission_store,
///   );
/// } finally {
///   await persistence.close();
/// }
/// ```
final class RudraSqlitePersistence {
  /// Creates a SQLite persistence context.
  ///
  /// The caller must provide an existing parent directory
  /// and a scope obtained from a trusted platform boundary.
  ///
  /// Construction does not initialize workflow state.
  RudraSqlitePersistence({
    required File database_file,
    required String scope_id,
  }) : _scope_id = _validate_scope(scope_id),
       _database = RudraDatabase.file(database_file);

  final String _scope_id;
  final RudraDatabase _database;

  /// Durable submission contract consumed by the SDK.
  ///
  /// The adapter shares this instance's database connection.
  late final EventSubmissionStore event_submission_store =
      DriftEventSubmissionStore(database: _database, scope_id: _scope_id);

  /// Read boundary for accepted workflow commands.
  ///
  /// Uses the same SQLite connection and trusted submission
  /// scope as [event_submission_store].
  ///
  /// Reading a command does not claim or process it.
  late final WorkflowInbox workflow_inbox = DriftWorkflowInbox(
    database: _database,
    scope_id: _scope_id,
  );

  /// Releases the database connection and its resources.
  ///
  /// Consumers must finish outstanding operations before closing.
  Future<void> close() => _database.close();

  /// Validates the trusted submission scope.
  static String _validate_scope(String scope_id) {
    if (scope_id.trim().isEmpty) {
      throw ArgumentError.value(
        scope_id,
        'scope_id',
        'Submission scope must not be blank.',
      );
    }

    return scope_id;
  }
}
