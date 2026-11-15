import 'package:drift/drift.dart';
import 'package:rudra_sdk/rudra_sdk.dart';

import '../../../database/rudra_database.dart';

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
  /// Creates an inbox reader for a trusted submission scope.
  ///
  /// [database] is owned by the application composition boundary.
  /// [scope_id] must originate from trusted application context.
  ///
  /// Throws [ArgumentError] for a blank submission scope.
  DriftWorkflowInbox({
    required RudraDatabase database,
    required String scope_id,
  }) : _database = database,
       _scope_id = _require_scope(scope_id);

  /// Codec responsible for reconstructing typed commands.
  static const WorkflowCommandCodec _codec = WorkflowCommandCodec();

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

    // Command reconstruction remains delegated to the SDK's
    // versioned codec rather than implementing JSON parsing
    // or command-specific logic inside the SQLite adapter.
    final command = _codec.decode(
      event_type: submission.event_type,
      payload_json: submission.payload_json,
    );

    return PendingWorkflowCommand(
      receipt: EventSubmissionReceipt(
        event_id: submission.event_id,
        correlation_id: submission.correlation_id,
      ),
      scope_id: submission.scope_id,
      command: command,
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
