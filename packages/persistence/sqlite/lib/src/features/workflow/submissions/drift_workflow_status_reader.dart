import 'package:drift/drift.dart';
import 'package:rudra_sdk/rudra_sdk.dart';

import '../../../database/rudra_database.dart' as sqlite;

/// Reads and validates durable submission resolutions.
///
/// Submission metadata and causally linked journal evidence are retrieved
/// from one consistent persistence snapshot.
///
/// Completed submissions are validated against their original commands
/// and committed historical workflow identities, independently of the
/// current unfinished-workflow projection.
///
/// Example:
/// ```dart
/// final reader = DriftWorkflowStatusReader(
///   database: database,
///   scope_id: trusted_scope_id,
///   os_user_id: trusted_os_user_id,
///   runtime: runtime,
/// );
///
/// final resolution = await reader.status_for(receipt);
/// ```
final class DriftWorkflowStatusReader
    implements WorkflowSubmissionStatusReader {
  /// Creates a reader bound to trusted application ownership.
  ///
  /// [database] supplies the durable submission inbox and journal.
  /// [scope_id] restricts access to accepted submissions.
  /// [os_user_id] identifies the authenticated historical workflow owner.
  /// [runtime] supplies the shared event serialization and replay rules.
  ///
  /// The caller must supply a scope and OS-user identity belonging to
  /// the same trusted application owner.
  ///
  /// Throws [ArgumentError] if either identifier is blank.
  DriftWorkflowStatusReader({
    required sqlite.RudraDatabase database,
    required String scope_id,
    required String os_user_id,
    required WorkflowRuntime runtime,
  }) : _database = database,
       _scope_id = _require_identifier(scope_id, 'scope_id'),
       _os_user_id = _require_identifier(os_user_id, 'os_user_id'),
       _codec = runtime.codec,
       _machine = WorkflowStateMachine(runtime: runtime);

  /// Shared persistence owner containing submissions and outcomes.
  final sqlite.RudraDatabase _database;

  /// Trusted durable submission namespace.
  final String _scope_id;

  /// Authenticated owner used to validate historical workflow identities.
  final String _os_user_id;

  /// Registry-driven serializer shared with submission and commitment.
  final WorkflowEventCodec _codec;

  /// Authoritative outcome-only historical replay engine.
  final WorkflowStateMachine _machine;

  /// Finds the durable resolution for an exact [receipt].
  ///
  /// Returns null when the receipt is unknown or inaccessible within
  /// the trusted submission scope.
  ///
  /// Throws [FormatException] when persisted resolution metadata,
  /// journal causation or historical ownership is inconsistent.
  /// Infrastructure failures propagate.
  ///
  /// Reading never processes submissions or modifies workflow history.
  @override
  Future<WorkflowSubmissionResolution?> status_for(
    EventSubmissionReceipt receipt,
  ) {
    return _database.transaction(() async {
      final stored =
          await (_database.select(_database.workflowSubmissions)..where(
                (row) =>
                    row.event_id.equals(receipt.event_id) &
                    row.correlation_id.equals(receipt.correlation_id) &
                    row.scope_id.equals(_scope_id),
              ))
              .getSingleOrNull();

      if (stored == null) {
        return null;
      }

      final state = switch (stored.processing_state) {
        'pending' => WorkflowSubmissionState.pending,
        'completed' => WorkflowSubmissionState.completed,
        'rejected' => WorkflowSubmissionState.rejected,
        'quarantined' => WorkflowSubmissionState.quarantined,
        _ => throw const FormatException(
          'Unknown submission processing state.',
        ),
      };

      // All processing states must agree with the journal, including
      // states that are not expected to have committed outcomes.
      final outcomes =
          await (_database.select(_database.workflowEvents)
                ..where((row) => row.causation_id.equals(stored.event_id))
                ..orderBy([(row) => OrderingTerm.asc(row.sequence)]))
              .get();

      final is_completed = state == WorkflowSubmissionState.completed;

      if (outcomes.isNotEmpty != is_completed) {
        throw const FormatException(
          'Submission processing state disagrees with journal causation.',
        );
      }

      final committed_outcome = is_completed
          ? await _validate_completed_outcome(stored, outcomes)
          : null;

      return _restore_resolution(
        stored: stored,
        receipt: receipt,
        state: state,
        committed_outcome: committed_outcome,
      );
    });
  }

  /// Reconstructs state-specific metadata from [stored].
  ///
  /// [receipt] identifies the exact accepted submission.
  /// [state] is the decoded durable processing state.
  /// [committed_outcome] is the validated historical journal reference,
  /// present exclusively for completed submissions.
  ///
  /// Returns a validated application resolution. Invalid persisted
  /// classifications or contradictory metadata throw [FormatException].
  WorkflowSubmissionResolution _restore_resolution({
    required sqlite.WorkflowSubmission stored,
    required EventSubmissionReceipt receipt,
    required WorkflowSubmissionState state,
    required WorkflowCommittedOutcome? committed_outcome,
  }) {
    final rejection_name = stored.rejection_code;
    final quarantine_name = stored.quarantine_code;

    // Persisted quarantine records must preserve their internal diagnostic.
    // The public model permits its absence after messaging serialization.
    if (state == WorkflowSubmissionState.quarantined &&
        stored.quarantine_diagnostic == null) {
      throw const FormatException(
        'Quarantined submission is missing its diagnostic.',
      );
    }

    try {
      return WorkflowSubmissionResolution(
        receipt: receipt,
        state: state,
        committed_outcome: committed_outcome,
        rejection_code: rejection_name == null
            ? null
            : WorkflowRejectionCode.values.byName(rejection_name),
        rejected_at_unix_ms: stored.rejected_at_unix_ms,
        quarantine_code: quarantine_name == null
            ? null
            : WorkflowQuarantineCode.values.byName(quarantine_name),
        quarantine_diagnostic: stored.quarantine_diagnostic,
        quarantined_at_unix_ms: stored.quarantined_at_unix_ms,
      );
    } on ArgumentError {
      throw const FormatException(
        'Invalid persisted submission resolution metadata.',
      );
    }
  }

  /// Validates the committed outcome caused by [stored].
  ///
  /// [outcomes] contains the journal entries causally linked to the
  /// accepted command. Start and Stop each establish exactly one outcome.
  ///
  /// Returns the original committed journal reference after verifying
  /// correlation, command compatibility and historical ownership.
  ///
  /// Throws [FormatException] when durable evidence is inconsistent.
  Future<WorkflowCommittedOutcome> _validate_completed_outcome(
    sqlite.WorkflowSubmission stored,
    List<sqlite.WorkflowEvent> outcomes,
  ) async {
    // The current persistence committer supports Start and Stop,
    // each of which commits exactly one domain outcome.
    if (outcomes.length != 1) {
      throw const FormatException(
        'Invalid number of committed outcomes for a workflow command.',
      );
    }

    final outcome = outcomes.single;

    if (outcome.correlation_id != stored.correlation_id) {
      throw const FormatException(
        'Committed outcome has inconsistent submission correlation.',
      );
    }

    final command = _codec.decode(
      event_type: stored.event_type,
      payload_json: stored.payload_json,
    );

    // Restore only the historical prefix belonging to this operation.
    // Subsequent workflow changes cannot alter its original resolution.
    final journal =
        await (_database.select(_database.workflowEvents)
              ..where(
                (row) =>
                    row.workflow_id.equals(outcome.workflow_id) &
                    row.version.isSmallerOrEqualValue(outcome.version),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.version)]))
            .get();

    if (journal.isEmpty || journal.last.sequence != outcome.sequence) {
      throw const FormatException(
        'Committed outcome is missing from its historical journal.',
      );
    }

    final decoded = <WorkflowOutcomeEvent>[];
    var previous_sequence = 0;

    for (var index = 0; index < journal.length; index++) {
      final entry = journal[index];

      if (entry.version != index + 1 ||
          entry.sequence <= previous_sequence ||
          entry.event_id.trim().isEmpty) {
        throw const FormatException(
          'Invalid historical journal ordering or identity.',
        );
      }

      final event = _codec.decode(
        event_type: entry.event_type,
        payload_json: entry.payload_json,
      );

      if (event is! WorkflowOutcomeEvent) {
        throw const FormatException(
          'Historical journal contains a non-outcome event.',
        );
      }

      // The establishment outcome must agree with independently
      // persisted owner metadata and authenticated application ownership.
      if (index == 0) {
        if (event is! WorkflowEstablishmentOutcomeEvent ||
            event.identity.workflow_id != outcome.workflow_id ||
            event.identity.os_user_id != _os_user_id ||
            entry.os_user_id != _os_user_id) {
          throw const FormatException(
            'Historical workflow ownership is inconsistent.',
          );
        }
      } else if (entry.os_user_id != null) {
        throw const FormatException(
          'Unexpected ownership metadata on a later journal outcome.',
        );
      }

      decoded.add(event);
      previous_sequence = entry.sequence;
    }

    final WorkflowSnapshot? snapshot;

    try {
      snapshot = _machine.replay(decoded);
    } on WorkflowReplayException {
      throw const FormatException(
        'Historical journal violates workflow transition rules.',
      );
    }

    if (snapshot == null ||
        snapshot.identity.workflow_id != outcome.workflow_id ||
        snapshot.identity.os_user_id != _os_user_id ||
        snapshot.version != outcome.version) {
      throw const FormatException(
        'Replayed history disagrees with its committed outcome.',
      );
    }

    final final_event = decoded.last;

    // Verify the exact accepted operation rather than inferring
    // success solely from a matching journal causation identifier.
    if (command is WorkflowStartEvent) {
      if (final_event is! WorkflowStartedEvent ||
          outcome.version != 1 ||
          snapshot.is_terminal ||
          snapshot.identity.target_id != command.target_id ||
          snapshot.identity.root.value != command.root.value) {
        throw const FormatException(
          'Committed Start disagrees with its accepted command.',
        );
      }
    } else if (command is WorkflowStopEvent) {
      if (final_event is! WorkflowEndedEvent ||
          !snapshot.is_terminal ||
          final_event.workflow_id != command.workflow_id ||
          outcome.workflow_id != command.workflow_id) {
        throw const FormatException(
          'Committed Stop disagrees with its accepted command.',
        );
      }
    } else {
      throw const FormatException('Unsupported completed workflow command.');
    }

    return WorkflowCommittedOutcome(
      workflow_id: outcome.workflow_id,
      event_type: outcome.event_type,
      version: outcome.version,
      sequence: outcome.sequence,
    );
  }

  /// Validates a trusted identifier without changing its spelling.
  ///
  /// Returns [value] or throws [ArgumentError] associated with [name]
  /// when the identifier is blank.
  static String _require_identifier(String value, String name) {
    if (value.trim().isEmpty) {
      throw ArgumentError.value(value, name);
    }

    return value;
  }
}
