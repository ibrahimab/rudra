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

  /// Loads restoration evidence through the authoritative owner index.
  ///
  /// The committed WorkflowStartedEvent identifies the workflow's
  /// owner independently of the unfinished-workflow projection.
  ///
  /// A missing or misassigned projection can therefore still be
  /// detected through SDK replay.
  ///
  /// Only histories associated with the requested OS user and
  /// the explicitly projected workflow are loaded.
  ///
  /// All reads share one consistent SQLite snapshot.
  /// This operation never modifies persistence.
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

      // Find workflows through the committed owner outcome.
      //
      // INDEXED BY makes the query fail explicitly if the owner
      // index is missing, rather than silently reverting to a
      // full historical journal scan.
      //
      // The OS-user ID is parameterized, not interpolated into
      // SQL. No journal payload is decoded at this boundary.
      final owner_rows = await _database
          .customSelect(
            r'''
        SELECT DISTINCT workflow_id
        FROM workflow_events
          INDEXED BY workflow_events_started_owner_idx
        WHERE event_type = 'workflow.started'
          AND (
            CASE
              WHEN json_valid(payload_json)
              THEN json_extract(payload_json, '$.os_user_id')
            END
          ) = ?
        ''',
            variables: [Variable.withString(os_user_id)],
            readsFrom: {_database.workflowEvents},
          )
          .get();

      // Also load the projected workflow, even if its owner
      // outcome does not index to the requested OS user.
      //
      // The SDK must validate such inconsistencies instead
      // of trusting the projection's ownership claims.
      final workflow_ids = <String>{
        for (final row in owner_rows) row.read<String>('workflow_id'),
        if (projection != null) projection.workflow_id,
      };

      final histories = <String, List<WorkflowJournalEntry>>{};

      for (final workflow_id in workflow_ids) {
        // Existing UNIQUE(workflow_id, version) provides the
        // indexed lookup and deterministic event ordering.
        final events =
            await (_database.select(_database.workflowEvents)
                  ..where((row) => row.workflow_id.equals(workflow_id))
                  ..orderBy([(row) => OrderingTerm.asc(row.version)]))
                .get();

        histories[workflow_id] = [
          for (final event in events)
            WorkflowJournalEntry(
              sequence: event.sequence,
              event_id: event.event_id,
              workflow_id: event.workflow_id,
              version: event.version,
              event_type: event.event_type,
              payload_json: event.payload_json,
            ),
        ];
      }

      WorkflowHistorySnapshot? projected;

      if (projection != null) {
        projected = WorkflowHistorySnapshot(
          projected_identity: WorkflowIdentity(
            workflow_id: projection.workflow_id,
            os_user_id: projection.os_user_id,
            target_id: projection.target_id,
            root: TargetPath(projection.root_path),
          ),
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
