import 'dart:io';

import 'package:rudra_sdk/rudra_sdk.dart';

import 'database/rudra_database.dart';

import 'features/workflow/history/drift_workflow_committer.dart';

import 'features/workflow/submissions/drift_event_submission_store.dart';
import 'features/workflow/submissions/drift_workflow_inbox.dart';
import 'features/workflow/submissions/drift_workflow_rejection_store.dart';
import 'features/workflow/submissions/drift_workflow_status_reader.dart';
import 'features/workflow/submissions/drift_workflow_quarantine_store.dart';

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
///   runtime: WorkflowRuntime.standard(),
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
  /// [runtime] supplies the exact workflow configuration
  /// shared with the SDK processor.
  ///
  /// The database does not register modules or construct
  /// default state-transition rules independently.
  RudraSqlitePersistence({
    required File database_file,
    required String scope_id,
    required WorkflowRuntime runtime,
  }) : _scope_id = _validate_scope(scope_id),
       _runtime = runtime,
       _database = RudraDatabase.file(database_file);

  final String _scope_id;
  final WorkflowRuntime _runtime;
  final RudraDatabase _database;

  /// Durable submission contract consumed by the SDK.
  late final EventSubmissionStore event_submission_store =
      DriftEventSubmissionStore(
        database: _database,
        scope_id: _scope_id,
        codec: _runtime.codec,
      );

  /// Read boundary for accepted workflow commands.
  late final WorkflowInbox workflow_inbox = DriftWorkflowInbox(
    database: _database,
    scope_id: _scope_id,
    codec: _runtime.codec,
  );

  /// Atomic persistence boundary for committed workflow changes.
  ///
  /// Shares the same database and event codec as the
  /// submission store and inbox.
  late final WorkflowCommitter workflow_committer = DriftWorkflowCommitter(
    database: _database,
    scope_id: _scope_id,
    codec: _runtime.codec,
    flow: _runtime.flow,
  );

  /// Records confirmed business rejections of pending commands.
  ///
  /// Shares the submission scope, codec, and database connection
  /// with the inbox and transaction committer.
  late final WorkflowSubmissionRejector workflow_rejector =
      DriftWorkflowRejectionStore(
        database: _database,
        scope_id: _scope_id,
        codec: _runtime.codec,
      );

  /// Durable quarantine boundary for unreadable submissions.
  ///
  /// Shares the trusted scope and database connection with
  /// the inbox and other submission persistence adapters.
  ///
  /// Quarantine never modifies workflow event history or
  /// unfinished-workflow ownership.
  late final WorkflowSubmissionQuarantiner workflow_quarantiner =
      DriftWorkflowQuarantineStore(database: _database, scope_id: _scope_id);

  /// Read-only, durable submission status lookup.
  ///
  /// Applications can query a previously accepted request
  /// without subscribing to transient processing events.
  late final WorkflowSubmissionStatusReader workflow_status_reader =
      DriftWorkflowStatusReader(database: _database, scope_id: _scope_id);

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
