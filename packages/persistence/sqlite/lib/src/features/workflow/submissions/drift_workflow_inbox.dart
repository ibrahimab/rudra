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
  /// [state_reader] is configured by trusted application
  /// composition with the authenticated OS-user identity.
  ///
  /// The codec and reader must use the same workflow runtime.
  DriftWorkflowInbox({
    required RudraDatabase database,
    required String scope_id,
    required WorkflowStateReader state_reader,
    WorkflowEventCodec? codec,
  }) : _database = database,
       _scope_id = _require_scope(scope_id),
       _state_reader = state_reader,
       _codec = codec ?? WorkflowEventCodec.standard();

  /// Injected event codec shared with submission persistence.
  final WorkflowEventCodec _codec;

  /// Shared SQLite connection.
  final RudraDatabase _database;

  /// Trusted submission scope handled by this inbox.
  final String _scope_id;

  /// Reader configured with independently trusted OS-user identity.
  final WorkflowStateReader _state_reader;

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

    // Only stop commands need an established workflow history.
    //
    // The reader selects by trusted OS-user ownership, never by
    // the workflow identifier supplied in the command.
    //
    // The committer must revalidate this snapshot transactionally
    // because another processor may commit after this read.
    final List<WorkflowEvent> committed_events;

    if (event is WorkflowStopEvent) {
      final active = await _state_reader.current();
      committed_events = active?.events ?? const <WorkflowEvent>[];
    } else {
      committed_events = const <WorkflowEvent>[];
    }

    return PendingWorkflowCommand(
      receipt: receipt,
      scope_id: submission.scope_id,
      command: event,
      committed_events: committed_events,
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
