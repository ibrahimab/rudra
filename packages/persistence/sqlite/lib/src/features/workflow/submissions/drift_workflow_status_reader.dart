import 'package:drift/drift.dart';
import 'package:rudra_sdk/rudra_sdk.dart';

import '../../../database/rudra_database.dart';

/// Reads durable submission status within one trusted scope.
///
/// Completed submissions are linked to their committed journal outcomes
/// through the already persisted causation identifier. The journal sequence
/// provides a global order that is distinct from workflow-local versions.
final class DriftWorkflowStatusReader
    implements WorkflowSubmissionStatusReader {
  /// Creates a status reader bound to [database] and [scope_id].
  ///
  /// The caller owns the database connection. A blank [scope_id] throws
  /// [ArgumentError]; construction performs no persistence operations.
  DriftWorkflowStatusReader({
    required RudraDatabase database,
    required String scope_id,
  }) : _database = database,
       _scope_id = _require_scope(scope_id);

  /// Shared persistence owner containing submissions and outcomes.
  final RudraDatabase _database;

  /// Trusted durable submission scope, separate from OS-user identity.
  final String _scope_id;

  /// Finds the durable resolution for an exact [receipt].
  ///
  /// Both event and correlation IDs must match the trusted scope. Completed
  /// submissions must have a causally linked committed outcome. Unknown
  /// receipts return null; invalid resolution metadata throws [FormatException].
  /// Reading never processes a command or changes persistent state.
  @override
  Future<WorkflowSubmissionResolution?> status_for(
    EventSubmissionReceipt receipt,
  ) async {
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
      _ => throw FormatException(
        'Unknown submission processing state: ${stored.processing_state}',
      ),
    };

    if (state == WorkflowSubmissionState.quarantined) {
      // Quarantine and business rejection are mutually exclusive.
      if (stored.rejection_code != null || stored.rejected_at_unix_ms != null) {
        throw const FormatException(
          'Quarantined submission contains rejection metadata.',
        );
      }

      final code_name = stored.quarantine_code;
      final diagnostic = stored.quarantine_diagnostic;
      final quarantined_at = stored.quarantined_at_unix_ms;

      if (code_name == null || diagnostic == null || quarantined_at == null) {
        throw const FormatException(
          'Quarantined submission is missing resolution metadata.',
        );
      }

      final WorkflowQuarantineCode code;
      try {
        code = WorkflowQuarantineCode.values.byName(code_name);
      } on ArgumentError {
        throw FormatException('Unsupported quarantine code: $code_name');
      }

      return WorkflowSubmissionResolution(
        receipt: receipt,
        state: state,
        quarantine_code: code,
        quarantine_diagnostic: diagnostic,
        quarantined_at_unix_ms: quarantined_at,
      );
    }

    // Non-quarantined statuses cannot contain quarantine metadata.
    if (stored.quarantine_code != null ||
        stored.quarantine_diagnostic != null ||
        stored.quarantined_at_unix_ms != null) {
      throw const FormatException(
        'Non-quarantined submission contains quarantine metadata.',
      );
    }

    if (state != WorkflowSubmissionState.rejected) {
      if (stored.rejection_code != null || stored.rejected_at_unix_ms != null) {
        throw const FormatException(
          'Non-rejected submission contains rejection metadata.',
        );
      }

      WorkflowCommittedOutcome? committed_outcome;
      if (state == WorkflowSubmissionState.completed) {
        // The committer atomically writes outcomes and completion. Looking up
        // causation checks the exact submission, even after workflow replacement.
        final outcomes =
            await (_database.select(_database.workflowEvents)
                  ..where((row) => row.causation_id.equals(receipt.event_id))
                  ..orderBy([(row) => OrderingTerm.asc(row.sequence)]))
                .get();

        if (outcomes.isEmpty) {
          throw const FormatException(
            'Completed submission is missing its committed outcome.',
          );
        }

        // All outcomes caused by one accepted command must belong to the
        // same workflow and retain the submission's correlation identity.
        final workflow_id = outcomes.first.workflow_id;
        for (final outcome in outcomes) {
          if (outcome.workflow_id != workflow_id ||
              outcome.correlation_id != receipt.correlation_id) {
            throw const FormatException(
              'Completed submission has inconsistent journal causation.',
            );
          }
        }
        final outcome = outcomes.last;

        committed_outcome = WorkflowCommittedOutcome(
          workflow_id: outcome.workflow_id,
          event_type: outcome.event_type,
          version: outcome.version,
          sequence: outcome.sequence,
        );
      }

      return WorkflowSubmissionResolution(
        receipt: receipt,
        state: state,
        committed_outcome: committed_outcome,
      );
    }

    final code = stored.rejection_code;
    final rejected_at = stored.rejected_at_unix_ms;
    if (code == null || rejected_at == null) {
      throw const FormatException(
        'Rejected submission is missing resolution metadata.',
      );
    }

    // Persisted identifiers must be recognized without silently coercing them.
    WorkflowRejectionCode? resolved_code;
    for (final candidate in WorkflowRejectionCode.values) {
      if (candidate.name == code) {
        resolved_code = candidate;
        break;
      }
    }
    if (resolved_code == null) {
      throw FormatException('Unsupported submission rejection code: $code');
    }

    return WorkflowSubmissionResolution(
      receipt: receipt,
      state: state,
      rejection_code: resolved_code,
      rejected_at_unix_ms: rejected_at,
    );
  }

  /// Validates trusted [scope_id] without normalizing the original value.
  ///
  /// Returns the original identifier or throws [ArgumentError] if blank.
  static String _require_scope(String scope_id) {
    if (scope_id.trim().isEmpty) {
      throw ArgumentError.value(scope_id, 'scope_id');
    }
    return scope_id;
  }
}
