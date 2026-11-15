import 'package:drift/drift.dart';
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:uuid/uuid.dart';

import '../../../database/rudra_database.dart';

/// Durable Drift implementation of [EventSubmissionStore].
///
/// Accepted commands are committed as pending submissions.
/// Their eventual workflow outcomes belong to SDK processing.
///
/// The caller owns the database connection and supplies a trusted
/// submission scope. This store does not authenticate principals.
final class DriftEventSubmissionStore implements EventSubmissionStore {
  /// Creates a store bound to a database and trusted scope.
  ///
  /// The database connection remains owned by its caller.
  DriftEventSubmissionStore({
    required RudraDatabase database,
    required String scope_id,
  }) : _database = database,
       _scope_id = scope_id {
    if (scope_id.trim().isEmpty) {
      throw ArgumentError.value(scope_id, 'scope_id');
    }
  }

  static final Uuid _uuid = Uuid();
  static const WorkflowCommandCodec _codec = WorkflowCommandCodec();

  final RudraDatabase _database;
  final String _scope_id;

  /// Durably accepts a workflow command.
  ///
  /// A matching idempotent retry returns the original receipt.
  /// A different command with the same scoped key is rejected.
  ///
  /// No workflow transitions or filesystem operations occur.
  @override
  Future<EventSubmissionReceipt> accept(
    WorkflowCommandEvent event, {
    String? idempotency_key,
  }) async {
    if (idempotency_key != null && idempotency_key.trim().isEmpty) {
      throw ArgumentError.value(idempotency_key, 'idempotency_key');
    }

    final payload_json = _codec.encode(event);
    final event_id = _uuid.v4();
    final correlation_id = _uuid.v4();

    try {
      return await _database.transaction(() async {
        final submission = WorkflowSubmissionsCompanion.insert(
          event_id: event_id,
          correlation_id: correlation_id,
          scope_id: _scope_id,
          idempotency_key: Value(idempotency_key),
          event_type: event.event_type,
          payload_json: payload_json,
          accepted_at_unix_ms: DateTime.now().toUtc().millisecondsSinceEpoch,
        );

        if (idempotency_key == null) {
          await _database
              .into(_database.workflowSubmissions)
              .insert(submission);

          return EventSubmissionReceipt(
            event_id: event_id,
            correlation_id: correlation_id,
          );
        }

        // Attempt the write first so concurrent processes
        // arbitrate through SQLite's unique constraint.
        //
        // Never use INSERT OR REPLACE: it would destroy the
        // original submission identity and processing state.
        await _database
            .into(_database.workflowSubmissions)
            .insert(submission, mode: InsertMode.insertOrIgnore);

        final existing =
            await (_database.select(_database.workflowSubmissions)..where(
                  (row) =>
                      row.scope_id.equals(_scope_id) &
                      row.idempotency_key.equals(idempotency_key),
                ))
                .getSingleOrNull();

        if (existing == null) {
          throw const EventSubmissionException(
            code: EventSubmissionErrorCode.persistence_failed,
            message: 'Submission was not persisted.',
          );
        }

        if (existing.event_type != event.event_type ||
            existing.payload_json != payload_json) {
          throw const EventSubmissionException(
            code: EventSubmissionErrorCode.idempotency_conflict,
            message: 'Idempotency key belongs to another request.',
          );
        }

        return EventSubmissionReceipt(
          event_id: existing.event_id,
          correlation_id: existing.correlation_id,
        );
      });
    } on EventSubmissionException {
      rethrow;
    } on Exception catch (error) {
      throw EventSubmissionException(
        code: EventSubmissionErrorCode.persistence_failed,
        message: 'Unable to persist workflow submission: $error',
      );
    }
  }
}
