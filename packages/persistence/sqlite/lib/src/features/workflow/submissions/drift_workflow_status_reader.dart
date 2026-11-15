import 'package:drift/drift.dart';

import 'package:rudra_sdk/rudra_sdk.dart';

import '../../../database/rudra_database.dart';

/// Reads durable submission status within one trusted scope.
///
/// This reader is independent of the workflow event journal.
/// It supports frontend recovery without transient listeners.
final class DriftWorkflowStatusReader
    implements WorkflowSubmissionStatusReader {
  /// Creates a scoped submission status reader.
  DriftWorkflowStatusReader({
    required RudraDatabase database,
    required String scope_id,
  }) : _database = database,
       _scope_id = _require_scope(scope_id);

  final RudraDatabase _database;
  final String _scope_id;

  /// Finds a submission by its original durable receipt.
  ///
  /// Both event and correlation IDs must match. Requests
  /// outside the trusted scope are not disclosed.
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
        'Unknown submission processing state: '
        '${stored.processing_state}',
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

    // Non-quarantined submissions must not carry quarantine
    // metadata, regardless of their other processing state.
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

      return WorkflowSubmissionResolution(receipt: receipt, state: state);
    }

    final code = stored.rejection_code;
    final rejected_at = stored.rejected_at_unix_ms;

    if (code == null || rejected_at == null) {
      throw const FormatException(
        'Rejected submission is missing resolution metadata.',
      );
    }

    // Persisted identifiers are validated, not silently
    // interpreted as different rejection reasons.
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

  /// Validates the trusted submission scope.
  static String _require_scope(String scope_id) {
    if (scope_id.trim().isEmpty) {
      throw ArgumentError.value(scope_id, 'scope_id');
    }

    return scope_id;
  }
}
