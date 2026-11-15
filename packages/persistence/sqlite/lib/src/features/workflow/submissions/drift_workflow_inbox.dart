import 'package:drift/drift.dart';
import 'package:rudra_sdk/rudra_sdk.dart';

import '../../../database/rudra_database.dart' hide WorkflowEvent;

/// Reads accepted workflow commands from the SQLite inbox.
///
/// Commands are selected by durable submission sequence,
/// not acceptance timestamp.
///
/// Only submissions belonging to the configured trusted scope
/// and retaining the pending processing state are returned.
///
/// This adapter does not:
/// - Claim or complete submissions.
/// - Generate workflow identities.
/// - Execute command handlers.
/// - Commit workflow events.
/// - Perform filesystem operations.
///
/// Example:
/// ```dart
/// final inbox = DriftWorkflowInbox(
///   database: database,
///   scope_id: 'trusted-user',
/// );
///
/// final pending = await inbox.next_pending();
/// ```
final class DriftWorkflowInbox implements WorkflowInbox {
  /// Creates a read-only workflow inbox for one trusted scope.
  ///
  /// The injected codec must recognize every command type
  /// accepted by the corresponding submission store.
  DriftWorkflowInbox({
    required RudraDatabase database,
    required String scope_id,
    WorkflowEventCodec? codec,
  }) : _database = database,
       _scope_id = _require_scope(scope_id),
       _codec = codec ?? WorkflowEventCodec.standard();

  /// Injected event codec shared with submission persistence.
  final WorkflowEventCodec _codec;

  /// Shared SQLite connection.
  final RudraDatabase _database;

  /// Trusted submission scope handled by this inbox.
  final String _scope_id;

  /// Reads the oldest eligible pending submission.
  ///
  /// Returns null when no pending submission exists.
  ///
  /// This is a read-only operation. Repeated calls may return
  /// the same submission until another component commits
  /// its processing outcome.
  ///
  /// The resulting snapshot is not a lock or processing claim.
  ///
  /// Malformed or unsupported commands propagate the codec's
  /// failure instead of being silently skipped.
  ///
  /// Malformed submissions raise [WorkflowInboxDecodingException]
  /// but remain pending until the processor's quarantine boundary
  /// persists its resolution.
  @override
  Future<PendingWorkflowCommand?> next_pending() async {
    final query = _database.select(_database.workflowSubmissions)
      ..where(
        (row) =>
            row.scope_id.equals(_scope_id) &
            row.processing_state.equals('pending'),
      )
      ..orderBy([(row) => OrderingTerm.asc(row.sequence)])
      ..limit(1);

    final submission = await query.getSingleOrNull();

    if (submission == null) {
      return null;
    }

    final receipt = EventSubmissionReceipt(
      event_id: submission.event_id,
      correlation_id: submission.correlation_id,
    );

    final WorkflowEvent event;

    try {
      event = _codec.decode(
        event_type: submission.event_type,
        payload_json: submission.payload_json,
      );
    } on FormatException catch (error) {
      // Only recognized serialization failures are classified
      // as unreadable commands. Database failures, StateErrors,
      // and unexpected programming failures still propagate.
      throw WorkflowInboxDecodingException(
        receipt: receipt,
        scope_id: submission.scope_id,
        event_type: submission.event_type,
        payload_json: submission.payload_json,
        code: WorkflowQuarantineCode.undecodable_command,
        diagnostic: error.message.isEmpty
            ? 'Unable to decode persisted workflow command.'
            : error.message,
      );
    }

    // A correctly serialized outcome is still not a command.
    // Persisted data must not bypass the command/event boundary.
    if (event is! WorkflowCommandEvent) {
      throw WorkflowInboxDecodingException(
        receipt: receipt,
        scope_id: submission.scope_id,
        event_type: submission.event_type,
        payload_json: submission.payload_json,
        code: WorkflowQuarantineCode.non_command_event,
        diagnostic: 'Inbox entry contains a non-command event.',
      );
    }

    return PendingWorkflowCommand(
      receipt: receipt,
      scope_id: submission.scope_id,
      command: event,
    );
  }

  /// Validates a trusted submission scope.
  ///
  /// Does not change the identifier's original representation.
  static String _require_scope(String scope_id) {
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
