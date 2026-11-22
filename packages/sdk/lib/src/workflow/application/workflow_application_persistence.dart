import '../event_submission_store.dart';
import '../processing/workflow_committer.dart';
import '../processing/workflow_inbox.dart';
import '../processing/workflow_quarantine.dart';
import '../processing/workflow_submission_resolution.dart';
import '../reading/workflow_history_store.dart';

/// Groups the durable workflow contracts needed by one SDK application.
///
/// Trusted host composition supplies a persistence implementation and retains
/// responsibility for its connection lifetime and submission scope. All
/// readers, processors and committers must share the same committed history.
///
/// Example:
/// ```dart
/// final application = WorkflowApplication(
///   runtime: runtime,
///   persistence: persistence,
///   identity_provider: identity_provider,
///   os_user_id: trusted_os_user_id,
/// );
/// ```
abstract interface class WorkflowApplicationPersistence {
  /// Store that durably accepts explicit workflow commands.
  EventSubmissionStore get event_submission_store;

  /// Store that supplies consistent committed history evidence.
  WorkflowHistoryStore get workflow_history_store;

  /// Reader for durable acceptance, completion and failure statuses.
  WorkflowSubmissionStatusReader get workflow_status_reader;

  /// Writer for recognized business rejections.
  WorkflowSubmissionRejector get workflow_rejector;

  /// Writer for unreadable accepted commands requiring quarantine.
  WorkflowSubmissionQuarantiner get workflow_quarantiner;

  /// Creates an inbox scoped to the trusted [os_user_id].
  ///
  /// The returned inbox reads pending submissions and validated history.
  /// Calling this method must not process or submit commands.
  WorkflowInbox workflow_inbox_for({required String os_user_id});

  /// Creates an atomic committer bound to the trusted [os_user_id].
  ///
  /// The committer validates the owner's current journal and reservation
  /// inside the persistence transaction before accepting a proposed change.
  WorkflowCommitter workflow_committer_for({required String os_user_id});
}
