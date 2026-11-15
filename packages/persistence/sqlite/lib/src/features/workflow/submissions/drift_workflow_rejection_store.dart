import 'package:drift/drift.dart';
import 'package:rudra_sdk/rudra_sdk.dart';

import '../../../database/rudra_database.dart';

/// Atomically records business rejection of accepted commands.
///
/// A rejection updates the original durable inbox entry.
/// It does not create a workflow, append journal events,
/// or modify unfinished-workflow ownership.
///
/// Only pending commands belonging to this trusted scope
/// can be rejected.
final class DriftWorkflowRejectionStore implements WorkflowSubmissionRejector {
  /// Creates a rejection writer using shared persistence.
  DriftWorkflowRejectionStore({
    required RudraDatabase database,
    required String scope_id,
    required WorkflowEventCodec codec,
  }) : _database = database,
       _scope_id = _require_scope(scope_id),
       _codec = codec;

  final RudraDatabase _database;
  final String _scope_id;
  final WorkflowEventCodec _codec;

  /// Durably rejects an eligible pending submission.
  ///
  /// Uses transactional validation and compare-and-set so
  /// another processor cannot overwrite a completed request.
  @override
  Future<void> reject({
    required PendingWorkflowCommand submission,
    required WorkflowRejectionCode code,
  }) async {
    final receipt = submission.receipt;

    await _database.transaction(() async {
      final stored =
          await (_database.select(_database.workflowSubmissions)..where(
                (row) =>
                    row.event_id.equals(receipt.event_id) &
                    row.scope_id.equals(_scope_id),
              ))
              .getSingleOrNull();

      if (stored == null ||
          stored.processing_state != 'pending' ||
          stored.scope_id != submission.scope_id ||
          stored.correlation_id != receipt.correlation_id ||
          stored.event_type != submission.command.event_type) {
        throw const WorkflowCommitException(
          code: WorkflowCommitErrorCode.stale_submission,
          message: 'Submission is no longer eligible for rejection.',
        );
      }

      // Check that the submitted command still represents
      // the actual persisted request. Versioned decoding
      // preserves compatibility with older accepted payloads.
      final persisted = _codec.decode(
        event_type: stored.event_type,
        payload_json: stored.payload_json,
      );

      if (persisted is! WorkflowCommandEvent ||
          _codec.encode(persisted) != _codec.encode(submission.command)) {
        throw const WorkflowCommitException(
          code: WorkflowCommitErrorCode.stale_submission,
          message: 'Submission payload differs from the pending command.',
        );
      }

      final updated =
          await (_database.update(_database.workflowSubmissions)..where(
                (row) =>
                    row.event_id.equals(receipt.event_id) &
                    row.scope_id.equals(_scope_id) &
                    row.processing_state.equals('pending'),
              ))
              .write(
                WorkflowSubmissionsCompanion(
                  processing_state: const Value('rejected'),
                  rejection_code: Value(code.name),
                  rejected_at_unix_ms: Value(
                    DateTime.now().toUtc().millisecondsSinceEpoch,
                  ),
                ),
              );

      if (updated != 1) {
        throw const WorkflowCommitException(
          code: WorkflowCommitErrorCode.stale_submission,
          message: 'Submission was resolved by another processor.',
        );
      }
    });
  }

  /// Validates the trusted submission scope.
  static String _require_scope(String scope_id) {
    if (scope_id.trim().isEmpty) {
      throw ArgumentError.value(scope_id, 'scope_id');
    }

    return scope_id;
  }
}
