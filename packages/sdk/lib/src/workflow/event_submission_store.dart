
import 'events/workflow_event.dart';
import 'event_submission_receipt.dart';
import 'event_submission_exception.dart';

/// Persistence boundary for accepted workflow command events.
///
/// Implementations must durably store a submission before
/// returning [EventSubmissionReceipt].
///
/// The storage transaction must establish:
/// - Stable event identity.
/// - Correlation metadata.
/// - The original typed request payload.
/// - A pending processing obligation.
/// - Idempotent acceptance for repeated logical submissions.
///
/// Reusing an idempotency key with a different request must
/// produce an explicit conflict, not silently replace data.
///
/// The key must be scoped to the relevant trusted submitting
/// principal. Neither the key nor its presence establishes
/// authorization or operating-system user identity.
///
/// Accepted submissions belong to the processing inbox.
/// They are not automatically valid workflow-state transitions.
///
/// A concrete SQLite implementation will fulfill this contract
/// in Block 5A.3.
///
/// This SDK interface does not access SQLite or filesystem APIs.
abstract interface class EventSubmissionStore {
  /// Atomically accepts a typed workflow command.
  ///
  /// [event] expresses a requested domain operation.
  ///
  /// [idempotency_key] optionally identifies a retry of the
  /// same logical request. The store must return the original
  /// receipt for a matching committed submission.
  ///
  /// Returns only after durable acceptance has completed.
  ///
  /// Persistence failures and conflicting retries must throw
  /// [EventSubmissionException].
  ///
  /// This method does not run an event handler or perform
  /// filesystem operations.
  Future<EventSubmissionReceipt> accept(
    WorkflowCommandEvent event, {
    String? idempotency_key,
  });
}
