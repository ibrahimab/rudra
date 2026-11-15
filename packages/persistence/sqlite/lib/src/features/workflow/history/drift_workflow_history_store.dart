import 'package:drift/drift.dart';
import 'package:rudra_sdk/rudra_sdk.dart';

import '../../../database/rudra_database.dart';

/// SQLite-backed read-only access to committed workflow history.
///
/// Retrieves the unfinished-workflow projection for a trusted
/// operating-system user and its complete committed journal.
///
/// The projection and journal are read inside one SQLite
/// transaction, preventing a mixed snapshot if another process
/// commits workflow changes concurrently.
///
/// The adapter does not decode domain events or reconstruct
/// lifecycle state. Those responsibilities belong to the SDK's
/// WorkflowStateReader and WorkflowRuntime.
///
/// Reading never submits commands, appends events, modifies
/// projections, or initiates recovery.
///
/// Example:
/// ```dart
/// final store = DriftWorkflowHistoryStore(
///   database: database,
/// );
///
/// final snapshot = await store.load_unfinished(
///   os_user_id: 'trusted-os-user',
/// );
/// ```
final class DriftWorkflowHistoryStore implements WorkflowHistoryStore {
  /// Creates a history store using an existing database owner.
  ///
  /// The caller owns the database lifetime. This adapter never
  /// creates or closes a database connection.
  DriftWorkflowHistoryStore({required RudraDatabase database})
    : _database = database;

  /// Shared persistence connection.
  final RudraDatabase _database;

  /// Loads a consistent history snapshot for [os_user_id].
  ///
  /// Returns null if no unfinished-workflow projection exists
  /// for the requested user.
  ///
  /// Journal rows are ordered by workflow-local version.
  /// Database-global sequence numbers are retained for
  /// independent ordering validation by the SDK.
  ///
  /// No filtering of invalid history is performed.
  /// Missing events, version gaps, and contradictory metadata
  /// must remain visible to the SDK's integrity checks.
  ///
  /// An invalid or blank trusted identity is rejected.
  @override
  Future<WorkflowHistorySnapshot?> load_unfinished({
    required String os_user_id,
  }) async {
    if (os_user_id.trim().isEmpty) {
      throw ArgumentError.value(
        os_user_id,
        'os_user_id',
        'Trusted OS-user identity must not be blank.',
      );
    }

    return _database.transaction(() async {
      // The projection locates the unfinished workflow.
      // It is not the authoritative lifecycle state.
      final projection = await (_database.select(
        _database.unfinishedWorkflows,
      )..where((row) => row.os_user_id.equals(os_user_id))).getSingleOrNull();

      if (projection == null) {
        return null;
      }

      // Read all committed events from the same transaction.
      // Do not use LIMIT, the projection version, or an
      // event-type filter to hide contradictory history.
      final journal_query = _database.select(_database.workflowEvents)
        ..where((row) => row.workflow_id.equals(projection.workflow_id))
        ..orderBy([(row) => OrderingTerm.asc(row.version)]);

      final rows = await journal_query.get();

      // Preserve the exact persisted identity bindings.
      // Do not normalize or reinterpret the target-native root.
      final identity = WorkflowIdentity(
        workflow_id: projection.workflow_id,
        os_user_id: projection.os_user_id,
        target_id: projection.target_id,
        root: TargetPath(projection.root_path),
      );

      return WorkflowHistorySnapshot(
        projected_identity: identity,
        projected_version: projection.version,
        journal: [
          for (final row in rows)
            WorkflowJournalEntry(
              sequence: row.sequence,
              event_id: row.event_id,
              workflow_id: row.workflow_id,
              version: row.version,
              event_type: row.event_type,
              payload_json: row.payload_json,
            ),
        ],
      );
    });
  }
}
