import 'dart:io';

import 'package:rudra_sdk/rudra_sdk.dart';

import 'database/rudra_database.dart';

import 'features/workflow/history/drift_workflow_committer.dart';
import 'features/workflow/history/drift_workflow_history_store.dart';

import 'features/workflow/submissions/drift_event_submission_store.dart';
import 'features/workflow/submissions/drift_workflow_inbox.dart';
import 'features/workflow/submissions/drift_workflow_rejection_store.dart';
import 'features/workflow/submissions/drift_workflow_status_reader.dart';
import 'features/workflow/submissions/drift_workflow_quarantine_store.dart';

import 'features/workflow/observation/publishing_workflow_committer.dart';

/// Owns SQLite persistence resources for one Rudra application.
///
/// Exposes SDK-defined contracts while keeping database
/// implementation details private.
///
/// The caller supplies a trusted operating-system user scope
/// and owns the lifetime of this persistence instance.
///
/// Example:
/// ```dart
/// final persistence = RudraSqlitePersistence(
///   database_file: File('rudra.db'),
///   scope_id: 'trusted-user',
///   runtime: WorkflowRuntime.standard(),
/// );
///
/// try {
///   final events = EventManager(
///     store: persistence.event_submission_store,
///   );
/// } finally {
///   await persistence.close();
/// }
/// ```
final class RudraSqlitePersistence implements WorkflowApplicationPersistence {
  /// Creates a SQLite persistence context.
  ///
  /// [runtime] supplies the exact workflow configuration
  /// shared with the SDK processor.
  ///
  /// The database does not register modules or construct
  /// default state-transition rules independently.
  ///
  /// [database_file] is the SQLite file supplied by host composition.
  /// [scope_id] identifies the trusted durable submission scope.
  /// The caller must close this persistence instance after pending operations.
  RudraSqlitePersistence({
    required File database_file,
    required String scope_id,
    required WorkflowRuntime runtime,
  }) : _scope_id = _validate_scope(scope_id),
       _runtime = runtime,
       _database = RudraDatabase.file(database_file);

  /// Trusted submission scope shared by every persistence adapter.
  final String _scope_id;

  /// Immutable SDK workflow runtime shared by storage adapters.
  final WorkflowRuntime _runtime;

  /// Database connection owned for this persistence lifetime.
  final RudraDatabase _database;

  /// Shared local notification channel for this persistence context.
  final LocalWorkflowCommitChannel _commit_channel =
      LocalWorkflowCommitChannel();

  /// Observes durable commits performed through this persistence context.
  ///
  /// The SDK application will consume this through its persistence contract.
  /// The caller must keep this persistence context alive while observing.
  @override
  WorkflowCommitSubscriber get workflow_commit_subscriber => _commit_channel;

  /// Durable submission contract consumed by the SDK.
  late final EventSubmissionStore event_submission_store =
      DriftEventSubmissionStore(
        database: _database,
        scope_id: _scope_id,
        codec: _runtime.codec,
      );

  /// Constructs a workflow inbox for a trusted OS-user identity.
  ///
  /// Submission scope and authenticated OS-user identity are
  /// deliberately separate inputs.
  ///
  /// The reader verifies the authoritative journal and
  /// unfinished-workflow projection before returning history.
  ///
  /// Creating the inbox performs no workflow mutations.
  WorkflowInbox workflow_inbox_for({required String os_user_id}) {
    return DriftWorkflowInbox(
      database: _database,
      scope_id: _scope_id,
      codec: _runtime.codec,
      state_reader: WorkflowStateReader(
        runtime: _runtime,
        history_store: workflow_history_store,
        os_user_id: os_user_id,
      ),
    );
  }

  /// Creates a transactional committer with post-commit notifications.
  ///
  /// [os_user_id] is supplied by trusted application composition.
  /// The committer publishes only when its delegate commits successfully.
  @override
  WorkflowCommitter workflow_committer_for({required String os_user_id}) {
    return PublishingWorkflowCommitter(
      delegate: DriftWorkflowCommitter(
        database: _database,
        scope_id: _scope_id,
        os_user_id: os_user_id,
        runtime: _runtime,
      ),
      publisher: _commit_channel,
      os_user_id: os_user_id,
    );
  }

  /// Read-only access to authoritative committed workflow history.
  ///
  /// Shares the existing database connection with submissions,
  /// processing, and workflow commitment.
  ///
  /// The caller supplies the trusted OS-user identity when
  /// requesting history. This identity must not be inferred
  /// from the submission scope.
  ///
  /// Decoding, replay, and lifecycle validation remain SDK
  /// responsibilities.
  late final WorkflowHistoryStore workflow_history_store =
      DriftWorkflowHistoryStore(database: _database);

  /// Records confirmed business rejections of pending commands.
  ///
  /// Shares the submission scope, codec, and database connection
  /// with the inbox and transaction committer.
  late final WorkflowSubmissionRejector workflow_rejector =
      DriftWorkflowRejectionStore(
        database: _database,
        scope_id: _scope_id,
        codec: _runtime.codec,
      );

  /// Durable quarantine boundary for unreadable submissions.
  ///
  /// Shares the trusted scope and database connection with
  /// the inbox and other submission persistence adapters.
  ///
  /// Quarantine never modifies workflow event history or
  /// unfinished-workflow ownership.
  late final WorkflowSubmissionQuarantiner workflow_quarantiner =
      DriftWorkflowQuarantineStore(database: _database, scope_id: _scope_id);

  /// Read-only, durable submission status lookup.
  ///
  /// Applications can query a previously accepted request
  /// without subscribing to transient processing events.
  late final WorkflowSubmissionStatusReader workflow_status_reader =
      DriftWorkflowStatusReader(database: _database, scope_id: _scope_id);

  /// Releases the database connection and its resources.
  ///
  /// Consumers must finish outstanding operations before closing.
  Future<void> close() async {
    try {
      await _database.close();
    } finally {
      await _commit_channel.close();
    }
  }

  /// Validates the trusted submission scope.
  static String _validate_scope(String scope_id) {
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
