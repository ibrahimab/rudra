import '../event_submission_receipt.dart';

/// Stable reasons for quarantining accepted workflow commands.
///
/// These identifiers are persisted and must remain stable.
enum WorkflowQuarantineCode {
  /// The current codec cannot decode the stored command.
  ///
  /// This includes malformed payloads and unsupported event
  /// types or schema versions. It does not necessarily mean
  /// that the original submission was corrupt.
  undecodable_command,

  /// The stored submission contains an outcome event,
  /// which must never be processed as a command.
  non_command_event,
}

/// Identifies a persisted inbox entry that cannot be processed.
///
/// This exception carries the original submission identity
/// and payload so persistence can verify the exact row before
/// quarantining it.
///
/// Extending FormatException preserves compatibility with
/// callers that already classify invalid serialized data
/// as a formatting error.
///
/// The raw payload is untrusted and may contain sensitive data.
/// It must not be inserted into diagnostic log messages.
final class WorkflowInboxDecodingException extends FormatException {
  /// Creates a classified failure for one persisted inbox entry.
  WorkflowInboxDecodingException({
    required this.receipt,
    required this.scope_id,
    required this.event_type,
    required this.payload_json,
    required this.code,
    required this.diagnostic,
  }) : super(diagnostic);

  /// Original durable submission receipt.
  final EventSubmissionReceipt receipt;

  /// Trusted submission scope retrieved from persistence.
  final String scope_id;

  /// Original persisted event type identifier.
  final String event_type;

  /// Original serialized payload, preserved without modification.
  final String payload_json;

  /// Stable failure classification.
  final WorkflowQuarantineCode code;

  /// Diagnostic produced by the decoding boundary.
  final String diagnostic;
}

/// Persistence boundary for quarantining unreadable submissions.
///
/// Implementations must atomically transition the exact pending
/// submission to quarantined while retaining its original
/// event type, payload, receipt, and correlation identity.
///
/// An already resolved or modified submission must not be
/// overwritten. Quarantine must not append workflow events.
abstract interface class WorkflowSubmissionQuarantiner {
  /// Durably quarantines an unreadable pending submission.
  Future<void> quarantine(WorkflowInboxDecodingException issue);
}
