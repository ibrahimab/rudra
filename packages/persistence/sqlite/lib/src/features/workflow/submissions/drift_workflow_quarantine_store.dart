import 'package:drift/drift.dart';
import 'package:rudra_sdk/rudra_sdk.dart';

import '../../../database/rudra_database.dart';

/// Atomically quarantines unreadable accepted submissions.
///
/// Quarantine is not workflow commitment or business rejection.
///
/// The original accepted event type, payload, receipt,
/// correlation ID, and submission sequence are preserved.
///
/// This adapter never decodes the stored payload. A decoding
/// failure is precisely why the submission is being quarantined.
///
/// Only an exact matching pending row can be updated.
final class DriftWorkflowQuarantineStore
    implements WorkflowSubmissionQuarantiner {
  /// Creates a scoped quarantine persistence boundary.
  DriftWorkflowQuarantineStore({
    required RudraDatabase database,
    required String scope_id,
  }) : _database = database,
       _scope_id = _require_scope(scope_id);

  /// Maximum persisted diagnostic length.
  ///
  /// Large or malformed payloads must not cause unbounded
  /// duplication of diagnostic information.
  static const int max_diagnostic_length = 512;

  final RudraDatabase _database;
  final String _scope_id;

  /// Atomically quarantines the exact unreadable submission.
  ///
  /// The SQL UPDATE itself is atomic. No multi-statement
  /// transaction is required because only one row is changed.
  ///
  /// Compare-and-set protects against concurrent processing,
  /// modified submissions, and attempts to overwrite a
  /// previously completed or rejected request.
  @override
  Future<void> quarantine(WorkflowInboxDecodingException issue) async {
    final receipt = issue.receipt;

    final diagnostic = issue.diagnostic.length > max_diagnostic_length
        ? issue.diagnostic.substring(0, max_diagnostic_length)
        : issue.diagnostic;

    final updated =
        await (_database.update(_database.workflowSubmissions)..where(
              (row) =>
                  row.event_id.equals(receipt.event_id) &
                  row.correlation_id.equals(receipt.correlation_id) &
                  row.scope_id.equals(_scope_id) &
                  row.scope_id.equals(issue.scope_id) &
                  row.processing_state.equals('pending') &
                  row.event_type.equals(issue.event_type) &
                  row.payload_json.equals(issue.payload_json),
            ))
            .write(
              WorkflowSubmissionsCompanion(
                processing_state: const Value('quarantined'),
                quarantine_code: Value(issue.code.name),
                quarantine_diagnostic: Value(diagnostic),
                quarantined_at_unix_ms: Value(
                  DateTime.now().toUtc().millisecondsSinceEpoch,
                ),
              ),
            );

    if (updated != 1) {
      throw const WorkflowCommitException(
        code: WorkflowCommitErrorCode.stale_submission,
        message:
            'Unreadable submission was modified or '
            'resolved before quarantine.',
      );
    }
  }

  /// Validates the trusted submission scope.
  static String _require_scope(String scope_id) {
    if (scope_id.trim().isEmpty) {
      throw ArgumentError.value(scope_id, 'scope_id');
    }

    return scope_id;
  }
}
