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
/// final snapshot = await store.load_restoration_evidence(
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

  /// Loads a consistent ownership projection and committed histories.
  ///
  /// The current schema does not index OS-user identity directly
  /// in the event journal. Therefore this implementation reads
  /// committed history across workflows for SDK-side verification.
  ///
  /// This is a correctness-first implementation. An indexed,
  /// immutable owner reference will be needed before production
  /// deployment to avoid scanning all historical events.
  ///
  /// All SELECT operations share one database transaction.
  /// No lifecycle rules are interpreted by this adapter.
  @override
  Future<WorkflowRestorationEvidence> load_restoration_evidence({
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
      final projection = await (_database.select(
        _database.unfinishedWorkflows,
      )..where((row) => row.os_user_id.equals(os_user_id))).getSingleOrNull();

      // All journal evidence comes from the same SQLite snapshot.
      //
      // Ordering by workflow and version allows deterministic
      // reconstruction while preserving original global sequences.
      final rows =
          await (_database.select(_database.workflowEvents)..orderBy([
                (row) => OrderingTerm.asc(row.workflow_id),
                (row) => OrderingTerm.asc(row.version),
              ]))
              .get();

      final histories = <String, List<WorkflowJournalEntry>>{};

      for (final row in rows) {
        histories
            .putIfAbsent(row.workflow_id, () => [])
            .add(
              WorkflowJournalEntry(
                sequence: row.sequence,
                event_id: row.event_id,
                workflow_id: row.workflow_id,
                version: row.version,
                event_type: row.event_type,
                payload_json: row.payload_json,
              ),
            );
      }

      WorkflowHistorySnapshot? projected;

      if (projection != null) {
        final identity = WorkflowIdentity(
          workflow_id: projection.workflow_id,
          os_user_id: projection.os_user_id,
          target_id: projection.target_id,
          root: TargetPath(projection.root_path),
        );

        projected = WorkflowHistorySnapshot(
          projected_identity: identity,
          projected_version: projection.version,
          journal:
              histories.remove(projection.workflow_id) ??
              <WorkflowJournalEntry>[],
        );
      }

      return WorkflowRestorationEvidence(
        projected: projected,
        other_histories: [
          for (final history in histories.entries)
            WorkflowHistoryJournal(
              workflow_id: history.key,
              journal: history.value,
            ),
        ],
      );
    });
  }
}
