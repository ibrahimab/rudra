import 'package:drift/drift.dart';
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:uuid/uuid.dart';

import '../../../database/rudra_database.dart';
import 'drift_workflow_history_store.dart';

/// Transactional persistence of validated outcome-only workflow changes.
///
/// Every command remains in the durable submission inbox. Only committed
/// outcomes occupy workflow-local journal positions. A successful Start
/// creates version 1; a successful Stop creates version 2.
///
/// Submission completion, journal appends and unfinished ownership changes
/// share a single SQLite transaction. No filesystem operation occurs here.
final class DriftWorkflowCommitter implements WorkflowCommitter {
  /// Creates a committer with one shared immutable workflow runtime.
  ///
  /// The OS-user identity and scope originate from trusted composition.
  DriftWorkflowCommitter({
    required RudraDatabase database,
    required String scope_id,
    required String os_user_id,
    required WorkflowRuntime runtime,
    WorkflowEventCodec? codec,
  }) : _database = database,
       _scope_id = _require_nonblank(scope_id, 'scope_id'),
       _os_user_id = _require_nonblank(os_user_id, 'os_user_id'),
       _runtime = runtime,
       _codec = codec ?? runtime.codec,
       _machine = WorkflowStateMachine(runtime: runtime);

  /// Identifier generator for committed outcome events.
  static final Uuid _uuid = Uuid();

  /// Transaction owner supplying authoritative SQLite tables.
  final RudraDatabase _database;

  /// Trusted durable command-submission scope.
  final String _scope_id;

  /// Authenticated owner of all workflow operations through this instance.
  final String _os_user_id;

  /// Shared event codec for submitted commands and persisted outcomes.
  final WorkflowEventCodec _codec;

  /// Immutable workflow domain/command registration snapshot.
  final WorkflowRuntime _runtime;

  /// Side-effect-free outcome replay engine, never a command executor.
  final WorkflowStateMachine _machine;

  /// Commits a Start or Stop plan atomically or rejects it without writes.
  ///
  /// The accepted command is reloaded inside the transaction and compared
  /// against the proposal. Current ownership and expected history are also
  /// independently reloaded and validated before any journal mutation.
  @override
  Future<void> commit(WorkflowProcessingPlan plan) async {
    final command = plan.submission.command;
    if (command is WorkflowStartEvent) {
      await _commit_start(plan);
    } else if (command is WorkflowStopEvent) {
      await _commit_stop(plan);
    } else {
      throw const WorkflowCommitException(
        code: WorkflowCommitErrorCode.invalid_plan,
        message: 'No persistence operation supports this workflow command.',
      );
    }
  }

  /// Establishes a new owner-scoped workflow at journal version 1.
  ///
  /// No command event is copied into the journal. The original accepted
  /// submission remains independently queryable through its durable status.
  Future<void> _commit_start(WorkflowProcessingPlan plan) async {
    final pending = plan.submission;
    final command = pending.command;
    final events = plan.events_to_append;
    final result = plan.resulting_state;

    if (command is! WorkflowStartEvent ||
        plan.previous_state != null ||
        pending.committed_events.isNotEmpty ||
        events.length != 1 ||
        events.single is! WorkflowStartedEvent ||
        result.is_terminal ||
        result.version != 1) {
      throw const WorkflowCommitException(
        code: WorkflowCommitErrorCode.invalid_plan,
        message: 'Invalid workflow establishment proposal.',
      );
    }

    await _database.transaction(() async {
      final accepted = await _accepted_command(pending);
      if (accepted is! WorkflowStartEvent) {
        throw const WorkflowCommitException(
          code: WorkflowCommitErrorCode.stale_submission,
          message: 'The accepted submission is not a Start request.',
        );
      }

      final outcome = events.single as WorkflowStartedEvent;
      final identity = outcome.identity;

      if (identity.os_user_id != _os_user_id) {
        throw const WorkflowCommitException(
          code: WorkflowCommitErrorCode.invalid_plan,
          message: 'Proposed workflow owner differs from trusted OS user.',
        );
      }

      final current = await _reader().current();
      if (current != null) {
        throw const WorkflowCommitException(
          code: WorkflowCommitErrorCode.ownership_conflict,
          message: 'The OS user already owns an unfinished workflow.',
        );
      }

      final behavior = _runtime.command_behaviors[accepted.runtimeType];
      if (behavior == null) {
        throw const WorkflowCommitException(
          code: WorkflowCommitErrorCode.invalid_plan,
          message: 'Start command has no registered SDK behavior.',
        );
      }

      try {
        behavior.validate_submission(
          accepted,
          previous: null,
          identity: identity,
        );
      } on WorkflowCommandValidationException {
        throw const WorkflowCommitException(
          code: WorkflowCommitErrorCode.invalid_plan,
          message: 'Start command identity does not match accepted request.',
        );
      }

      final replayed = _machine.replay(events);
      if (replayed == null ||
          replayed.is_terminal ||
          !_same_snapshot_identity(replayed, result)) {
        throw const WorkflowCommitException(
          code: WorkflowCommitErrorCode.invalid_plan,
          message: 'Start outcomes do not reproduce the proposed snapshot.',
        );
      }

      // The owner index and unfinished projection provide complementary
      // defenses against duplicate or reused workflow identities.
      final owner =
          await (_database.select(_database.unfinishedWorkflows)
                ..where((row) => row.os_user_id.equals(identity.os_user_id)))
              .getSingleOrNull();
      if (owner != null) {
        throw const WorkflowCommitException(
          code: WorkflowCommitErrorCode.ownership_conflict,
          message: 'The OS user already has unfinished ownership.',
        );
      }

      final reused_id =
          await (_database.select(_database.workflowEvents)
                ..where((row) => row.workflow_id.equals(identity.workflow_id))
                ..limit(1))
              .getSingleOrNull();
      if (reused_id != null) {
        throw const WorkflowCommitException(
          code: WorkflowCommitErrorCode.invalid_plan,
          message: 'The proposed workflow identifier was previously used.',
        );
      }

      await _append_outcomes(
        pending: pending,
        identity: identity,
        events: events,
        previous_version: 0,
      );

      await _database
          .into(_database.unfinishedWorkflows)
          .insert(
            UnfinishedWorkflowsCompanion.insert(
              os_user_id: identity.os_user_id,
              workflow_id: identity.workflow_id,
              target_id: identity.target_id,
              root_path: identity.root.value,
              version: replayed.version,
            ),
          );
      await _complete_submission(pending);
    });
  }

  /// Commits the terminal outcome and releases the previous owner.
  ///
  /// Replay and business checks use the journal restored inside this
  /// transaction rather than trusting a snapshot supplied by the caller.
  Future<void> _commit_stop(WorkflowProcessingPlan plan) async {
    final pending = plan.submission;
    final command = pending.command;
    final previous = plan.previous_state;
    final result = plan.resulting_state;
    final events = plan.events_to_append;

    if (command is! WorkflowStopEvent ||
        previous == null ||
        previous.is_terminal ||
        previous.identity.os_user_id != _os_user_id ||
        command.workflow_id != previous.identity.workflow_id ||
        events.length != 1 ||
        events.single is! WorkflowEndedEvent ||
        !result.is_terminal ||
        result.version != previous.version + 1 ||
        pending.committed_events.length != previous.version ||
        !_same_identity(previous.identity, result.identity)) {
      throw const WorkflowCommitException(
        code: WorkflowCommitErrorCode.invalid_plan,
        message: 'Invalid workflow termination proposal.',
      );
    }

    await _database.transaction(() async {
      final accepted = await _accepted_command(pending);
      if (accepted is! WorkflowStopEvent) {
        throw const WorkflowCommitException(
          code: WorkflowCommitErrorCode.stale_submission,
          message: 'The accepted submission is not a Stop request.',
        );
      }

      final current = await _reader().current();
      if (current == null) {
        throw const WorkflowCommitException(
          code: WorkflowCommitErrorCode.workflow_not_active,
          message: 'No unfinished workflow remains to be stopped.',
        );
      }

      final actual = current.state;
      if (actual.identity.workflow_id != accepted.workflow_id) {
        throw const WorkflowCommitException(
          code: WorkflowCommitErrorCode.workflow_id_mismatch,
          message: 'The accepted Stop targets a different workflow.',
        );
      }

      if (actual.version != previous.version ||
          !_same_identity(actual.identity, previous.identity) ||
          current.events.length != pending.committed_events.length) {
        throw const WorkflowCommitException(
          code: WorkflowCommitErrorCode.invalid_plan,
          message: 'Stop proposal disagrees with the current journal.',
        );
      }

      // Canonical encoding compares decoded values rather than assuming
      // an event's object identity represents persisted equivalence.
      for (var index = 0; index < current.events.length; index++) {
        if (_codec.encode(current.events[index]) !=
            _codec.encode(pending.committed_events[index])) {
          throw const WorkflowCommitException(
            code: WorkflowCommitErrorCode.invalid_plan,
            message: 'The proposed previous history is not authoritative.',
          );
        }
      }

      final behavior = _runtime.command_behaviors[accepted.runtimeType];
      if (behavior == null) {
        throw const WorkflowCommitException(
          code: WorkflowCommitErrorCode.invalid_plan,
          message: 'Stop command has no registered SDK behavior.',
        );
      }
      try {
        behavior.validate_submission(
          accepted,
          previous: actual,
          identity: actual.identity,
        );
      } on WorkflowCommandValidationException {
        throw const WorkflowCommitException(
          code: WorkflowCommitErrorCode.invalid_plan,
          message: 'Accepted Stop failed trusted command validation.',
        );
      }

      final result_from_history = _machine.replay([
        ...current.events,
        ...events,
      ]);
      if (result_from_history == null ||
          !result_from_history.is_terminal ||
          !_same_snapshot_identity(result_from_history, result)) {
        throw const WorkflowCommitException(
          code: WorkflowCommitErrorCode.invalid_plan,
          message: 'Proposed Stop outcome does not reproduce terminal state.',
        );
      }

      await _append_outcomes(
        pending: pending,
        identity: actual.identity,
        events: events,
        previous_version: actual.version,
      );

      // The compare-and-delete checks every originally committed binding.
      final removed =
          await (_database.delete(_database.unfinishedWorkflows)..where(
                (row) =>
                    row.os_user_id.equals(_os_user_id) &
                    row.workflow_id.equals(actual.identity.workflow_id) &
                    row.target_id.equals(actual.identity.target_id) &
                    row.root_path.equals(actual.identity.root.value) &
                    row.version.equals(actual.version),
              ))
              .go();
      if (removed != 1) {
        throw const WorkflowCommitException(
          code: WorkflowCommitErrorCode.invalid_plan,
          message: 'Unfinished workflow ownership changed during Stop.',
        );
      }

      await _complete_submission(pending);
    });
  }

  /// Re-reads and checks the exact eligible inbox command.
  ///
  /// This function runs inside the caller's SQLite transaction.
  Future<WorkflowCommandEvent> _accepted_command(
    PendingWorkflowCommand pending,
  ) async {
    final receipt = pending.receipt;
    final stored = await (_database.select(
      _database.workflowSubmissions,
    )..where((row) => row.event_id.equals(receipt.event_id))).getSingleOrNull();

    if (stored == null ||
        stored.processing_state != 'pending' ||
        stored.scope_id != _scope_id ||
        stored.scope_id != pending.scope_id ||
        stored.correlation_id != receipt.correlation_id ||
        stored.event_type != pending.command.event_type) {
      throw const WorkflowCommitException(
        code: WorkflowCommitErrorCode.stale_submission,
        message: 'The accepted command is no longer eligible.',
      );
    }

    final decoded = _codec.decode(
      event_type: stored.event_type,
      payload_json: stored.payload_json,
    );
    if (decoded is! WorkflowCommandEvent ||
        decoded.runtimeType != pending.command.runtimeType ||
        _codec.encode(decoded) != _codec.encode(pending.command)) {
      throw const WorkflowCommitException(
        code: WorkflowCommitErrorCode.stale_submission,
        message: 'The persisted command differs from the submitted proposal.',
      );
    }
    return decoded;
  }

  /// Persists only domain outcomes with fresh journal event identities.
  ///
  /// The first establishment outcome records independent trusted owner
  /// metadata so restoration does not depend on a derived projection.
  Future<void> _append_outcomes({
    required PendingWorkflowCommand pending,
    required WorkflowIdentity identity,
    required List<WorkflowOutcomeEvent> events,
    required int previous_version,
  }) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    for (var index = 0; index < events.length; index++) {
      final event = events[index];
      await _database
          .into(_database.workflowEvents)
          .insert(
            WorkflowEventsCompanion.insert(
              event_id: _uuid.v4(),
              workflow_id: identity.workflow_id,
              os_user_id: event is WorkflowEstablishmentOutcomeEvent
                  ? Value(identity.os_user_id)
                  : const Value.absent(),
              version: previous_version + index + 1,
              correlation_id: pending.receipt.correlation_id,
              causation_id: Value(pending.receipt.event_id),
              event_type: event.event_type,
              payload_json: _codec.encode(event),
              recorded_at_unix_ms: now,
            ),
          );
    }
  }

  /// Completes an accepted submission with compare-and-set semantics.
  ///
  /// Failure rolls back all outcome appends and ownership changes.
  Future<void> _complete_submission(PendingWorkflowCommand pending) async {
    final updated =
        await (_database.update(_database.workflowSubmissions)..where(
              (row) =>
                  row.event_id.equals(pending.receipt.event_id) &
                  row.scope_id.equals(_scope_id) &
                  row.processing_state.equals('pending'),
            ))
            .write(
              const WorkflowSubmissionsCompanion(
                processing_state: Value('completed'),
              ),
            );
    if (updated != 1) {
      throw const WorkflowCommitException(
        code: WorkflowCommitErrorCode.stale_submission,
        message: 'Submission completion lost its pending status.',
      );
    }
  }

  /// Constructs the authoritative owner-scoped reader for this transaction.
  WorkflowStateReader _reader() => WorkflowStateReader(
    runtime: _runtime,
    history_store: DriftWorkflowHistoryStore(database: _database),
    os_user_id: _os_user_id,
  );

  /// Checks identity, lifecycle and version against a proposed snapshot.
  static bool _same_snapshot_identity(
    WorkflowSnapshot actual,
    WorkflowSnapshot expected,
  ) =>
      actual.version == expected.version &&
      actual.lifecycle.id == expected.lifecycle.id &&
      actual.is_terminal == expected.is_terminal &&
      _same_identity(actual.identity, expected.identity);

  /// Compares all immutable original workflow identity bindings by value.
  static bool _same_identity(WorkflowIdentity a, WorkflowIdentity b) =>
      a.workflow_id == b.workflow_id &&
      a.os_user_id == b.os_user_id &&
      a.target_id == b.target_id &&
      a.root.value == b.root.value;

  /// Validates configured trusted identifiers without rewriting them.
  static String _require_nonblank(String value, String name) {
    if (value.trim().isEmpty) throw ArgumentError.value(value, name);
    return value;
  }
}
