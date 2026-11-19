import 'package:drift/drift.dart';
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:uuid/uuid.dart';

import '../../../database/rudra_database.dart';

import 'drift_workflow_history_store.dart';

/// Atomically establishes a new workflow in SQLite.
///
/// This first implementation supports an initial workflow
/// transitioning to an active workflow at version 2.
///
/// It commits journal events, unfinished-workflow ownership,
/// and submission completion in a single transaction.
///
/// It does not generate identities, process commands,
/// or execute filesystem operations.
final class DriftWorkflowCommitter implements WorkflowCommitter {
  /// Creates a committer with explicitly configured workflow rules.
  ///
  /// [codec] serializes committed events and reads historical
  /// command representations.
  ///
  /// [flow] must be the same transition graph used by the
  /// processor that creates workflow processing plans.
  ///
  /// Production composition supplies both from one
  /// immutable WorkflowRuntime.
  DriftWorkflowCommitter({
    required RudraDatabase database,
    required String scope_id,
    required String os_user_id,
    required WorkflowRuntime runtime,
    WorkflowEventCodec? codec,
  }) : _database = database,
       _scope_id = _require_scope(scope_id),
       _os_user_id = _require_os_user_id(os_user_id),
       _runtime = runtime,
       _codec = codec ?? runtime.codec,
       _machine = WorkflowStateMachine(flow: runtime.flow);

  static final Uuid _uuid = Uuid();

  final RudraDatabase _database;
  final String _scope_id;

  /// Authenticated OS-user identity supplied by trusted composition.
  final String _os_user_id;

  final WorkflowEventCodec _codec;
  final WorkflowStateMachine _machine;

  /// Shared SDK runtime used for authoritative history validation.
  final WorkflowRuntime _runtime;

  /// Commits a validated lifecycle plan through its transactional path.
  ///
  /// Each supported command has its own persistence invariants.
  /// Unsupported commands fail without modifying storage.
  @override
  Future<void> commit(WorkflowProcessingPlan plan) async {
    final command = plan.submission.command;

    if (command is WorkflowStartEvent) {
      await _commit_start(plan);
      return;
    }

    if (command is WorkflowStopEvent) {
      await _commit_stop(plan);
      return;
    }

    throw const WorkflowCommitException(
      code: WorkflowCommitErrorCode.invalid_plan,
      message: 'Unsupported workflow command for commitment.',
    );
  }

  /// Atomically establishes a new active workflow.
  ///
  /// Retains the existing start validation and persistence
  /// transaction without changing its event representation.
  Future<void> _commit_start(WorkflowProcessingPlan plan) async {
    final state = plan.resulting_state;
    final pending = plan.submission;
    final receipt = pending.receipt;
    final events = plan.events_to_append;

    // The current persistence implementation establishes
    // new workflows only. Do not silently treat later
    // lifecycle transitions as workflow creation.
    if (plan.previous_state is! WorkflowInitialState ||
        pending.committed_events.isNotEmpty ||
        state is! WorkflowActiveState ||
        state.version != 2 ||
        events.length != 2 ||
        !identical(events.first, pending.command) ||
        events.skip(1).any((event) => event is WorkflowCommandEvent)) {
      throw const WorkflowCommitException(
        code: WorkflowCommitErrorCode.invalid_plan,
        message: 'Unsupported or invalid workflow establishment plan.',
      );
    }

    await _database.transaction(() async {
      // Re-read the submission inside the transaction.
      // The earlier inbox read was not a lock.
      final stored =
          await (_database.select(_database.workflowSubmissions)
                ..where((row) => row.event_id.equals(receipt.event_id)))
              .getSingleOrNull();

      if (stored == null ||
          stored.processing_state != 'pending' ||
          stored.scope_id != _scope_id ||
          stored.scope_id != pending.scope_id ||
          stored.correlation_id != receipt.correlation_id ||
          stored.event_type != pending.command.event_type) {
        throw const WorkflowCommitException(
          code: WorkflowCommitErrorCode.stale_submission,
          message: 'The accepted submission is no longer eligible.',
        );
      }

      // Reconstruct the actual persisted command. Comparing
      // current canonical encodings avoids assuming old JSON
      // envelopes always use the newest schema version.
      final persisted_event = _codec.decode(
        event_type: stored.event_type,
        payload_json: stored.payload_json,
      );

      if (persisted_event is! WorkflowCommandEvent ||
          _codec.encode(persisted_event) != _codec.encode(pending.command)) {
        throw const WorkflowCommitException(
          code: WorkflowCommitErrorCode.stale_submission,
          message: 'The persisted command differs from the proposal.',
        );
      }

      // Replay the real persisted command together with the
      // proposed outcomes. The commit boundary must not rely
      // only on a caller-supplied resulting state.
      final replayed = _machine.replay([persisted_event, ...events.skip(1)]);

      if (replayed is! WorkflowActiveState ||
          replayed.version != state.version ||
          !_same_identity(replayed.identity, state.identity)) {
        throw const WorkflowCommitException(
          code: WorkflowCommitErrorCode.invalid_plan,
          message: 'Proposed events do not reproduce the supplied state.',
        );
      }

      final identity = replayed.identity;

      // A proposed identity cannot override the authenticated
      // owner of this committer.
      if (identity.os_user_id != _os_user_id) {
        throw const WorkflowCommitException(
          code: WorkflowCommitErrorCode.invalid_plan,
          message: 'Proposed workflow owner differs from trusted OS user.',
        );
      }

      // Verify committed ownership within the same transaction
      // that will reserve and establish the new workflow.
      //
      // The unfinished-workflow projection alone is insufficient:
      // it could have been deleted or incorrectly reassigned.
      //
      // This SDK reader validates indexed journal histories through
      // the configured workflow state machine.
      //
      // A missing projection for an active workflow throws a typed
      // integrity failure. Do not convert that failure into a
      // business rejection or silently repair the database.
      final existing_workflow = await WorkflowStateReader(
        runtime: _runtime,
        history_store: DriftWorkflowHistoryStore(database: _database),
        os_user_id: identity.os_user_id,
      ).current();

      if (existing_workflow != null) {
        throw const WorkflowCommitException(
          code: WorkflowCommitErrorCode.ownership_conflict,
          message: 'The OS user already has an active workflow.',
        );
      }

      // Enforce one unfinished workflow per OS user.
      // The SQLite primary key independently enforces this
      // invariant against concurrent writers.
      final existing_owner =
          await (_database.select(_database.unfinishedWorkflows)
                ..where((row) => row.os_user_id.equals(identity.os_user_id)))
              .getSingleOrNull();

      if (existing_owner != null) {
        throw const WorkflowCommitException(
          code: WorkflowCommitErrorCode.ownership_conflict,
          message: 'The OS user already has an unfinished workflow.',
        );
      }

      // A workflow identifier must never be reused, including
      // after a previous workflow has ended and its unfinished
      // reservation has been removed.
      final existing_history =
          await (_database.select(_database.workflowEvents)
                ..where((row) => row.workflow_id.equals(identity.workflow_id))
                ..limit(1))
              .getSingleOrNull();

      if (existing_history != null) {
        throw const WorkflowCommitException(
          code: WorkflowCommitErrorCode.invalid_plan,
          message: 'The workflow identifier already exists.',
        );
      }

      // Reserve ownership in the same transaction as the
      // authoritative journal append and inbox completion.
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

      final recorded_at_unix_ms = DateTime.now().toUtc().millisecondsSinceEpoch;

      for (var index = 0; index < events.length; index++) {
        final event = events[index];

        // Preserve the original accepted command bytes.
        // Only newly generated outcomes receive new event IDs.
        final event_id = index == 0 ? receipt.event_id : _uuid.v4();

        final payload_json = index == 0
            ? stored.payload_json
            : _codec.encode(event);

        await _database
            .into(_database.workflowEvents)
            .insert(
              WorkflowEventsCompanion.insert(
                event_id: event_id,
                workflow_id: identity.workflow_id,
                os_user_id: event is WorkflowStartedEvent
                    ? Value(identity.os_user_id)
                    : const Value.absent(),
                version: plan.previous_state.version + index + 1,
                correlation_id: receipt.correlation_id,
                causation_id: Value(index == 0 ? null : receipt.event_id),
                event_type: event.event_type,
                payload_json: payload_json,
                recorded_at_unix_ms: recorded_at_unix_ms,
              ),
            );
      }

      // Compare-and-set completion. Even if another processor
      // observed the same pending command earlier, it cannot
      // complete an already processed submission.
      final updated =
          await (_database.update(_database.workflowSubmissions)..where(
                (row) =>
                    row.event_id.equals(receipt.event_id) &
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
    });
  }

  /// Atomically commits a stop request and its terminal outcome.
  ///
  /// Validates the proposed state against committed history
  /// under the authenticated OS-user identity.
  ///
  /// The terminal journal append, ownership release, and
  /// submission completion are one SQLite transaction.
  ///
  /// A failed transaction leaves the journal, projection,
  /// and submission resolution unchanged.
  Future<void> _commit_stop(WorkflowProcessingPlan plan) async {
    final pending = plan.submission;
    final receipt = pending.receipt;
    final command = pending.command;
    final previous = plan.previous_state;
    final result = plan.resulting_state;
    final events = plan.events_to_append;

    final outcome = events.length == 2 ? events.last : null;

    // Reject malformed processing plans before database writes.
    if (command is! WorkflowStopEvent ||
        previous is! WorkflowActiveState ||
        result is! WorkflowEndedState ||
        outcome is! WorkflowEndedEvent ||
        events.length != 2 ||
        !identical(events.first, command) ||
        previous.identity.os_user_id != _os_user_id ||
        command.workflow_id != previous.identity.workflow_id ||
        outcome.workflow_id != previous.identity.workflow_id ||
        !_same_identity(previous.identity, result.identity) ||
        result.version != previous.version + 2 ||
        pending.committed_events.length != previous.version) {
      throw const WorkflowCommitException(
        code: WorkflowCommitErrorCode.invalid_plan,
        message: 'Unsupported or invalid workflow stop plan.',
      );
    }

    // The plan must reproduce its own proposed previous state
    // and terminal outcome through the registered state machine.
    final proposed_previous = _machine.replay(pending.committed_events);

    final proposed_result = _machine.replay([
      ...pending.committed_events,
      ...events,
    ]);

    if (proposed_previous is! WorkflowActiveState ||
        proposed_previous.version != previous.version ||
        !_same_identity(proposed_previous.identity, previous.identity) ||
        proposed_result is! WorkflowEndedState ||
        proposed_result.version != result.version ||
        !_same_identity(proposed_result.identity, result.identity)) {
      throw const WorkflowCommitException(
        code: WorkflowCommitErrorCode.invalid_plan,
        message: 'Stop plan disagrees with its proposed event history.',
      );
    }

    await _database.transaction(() async {
      // Check that this exact accepted submission is still pending.
      final stored =
          await (_database.select(_database.workflowSubmissions)
                ..where((row) => row.event_id.equals(receipt.event_id)))
              .getSingleOrNull();

      if (stored == null ||
          stored.processing_state != 'pending' ||
          stored.scope_id != _scope_id ||
          stored.scope_id != pending.scope_id ||
          stored.correlation_id != receipt.correlation_id ||
          stored.event_type != command.event_type) {
        throw const WorkflowCommitException(
          code: WorkflowCommitErrorCode.stale_submission,
          message: 'Stop submission is no longer eligible.',
        );
      }

      // Compare against the actual accepted command, not the
      // event instance supplied in the processing plan.
      final persisted_event = _codec.decode(
        event_type: stored.event_type,
        payload_json: stored.payload_json,
      );

      if (persisted_event is! WorkflowStopEvent ||
          _codec.encode(persisted_event) != _codec.encode(command)) {
        throw const WorkflowCommitException(
          code: WorkflowCommitErrorCode.stale_submission,
          message: 'Persisted stop command differs from the proposal.',
        );
      }

      // Re-read the authoritative owner-scoped journal inside
      // the transaction. A previous inbox read is never a lock.
      //
      // This also detects missing or corrupt projections and
      // unrelated inconsistent histories belonging to this user.
      final current = await WorkflowStateReader(
        runtime: _runtime,
        history_store: DriftWorkflowHistoryStore(database: _database),
        os_user_id: _os_user_id,
      ).current();

      if (current == null) {
        throw const WorkflowCommitException(
          code: WorkflowCommitErrorCode.workflow_not_active,
          message: 'The workflow is no longer active.',
        );
      }

      final actual_state = current.state;
      final identity = actual_state.identity;

      if (identity.workflow_id != command.workflow_id) {
        throw const WorkflowCommitException(
          code: WorkflowCommitErrorCode.workflow_id_mismatch,
          message: 'Another workflow is now active.',
        );
      }

      // Reject stale or fabricated historical snapshots.
      if (actual_state.version != previous.version ||
          !_same_identity(identity, previous.identity) ||
          current.events.length != pending.committed_events.length) {
        throw const WorkflowCommitException(
          code: WorkflowCommitErrorCode.invalid_plan,
          message: 'Stop plan no longer matches committed workflow state.',
        );
      }

      // Compare each event using its canonical SDK representation.
      // Historical JSON envelope versions may differ from the
      // currently preferred serializer representation.
      for (var index = 0; index < current.events.length; index++) {
        if (_codec.encode(current.events[index]) !=
            _codec.encode(pending.committed_events[index])) {
          throw const WorkflowCommitException(
            code: WorkflowCommitErrorCode.invalid_plan,
            message: 'Stop plan differs from authoritative event history.',
          );
        }
      }

      // Recompute the terminal state from authoritative history
      // and the accepted command before performing any mutation.
      final committed_result = _machine.replay([
        ...current.events,
        persisted_event,
        outcome,
      ]);

      if (committed_result is! WorkflowEndedState ||
          committed_result.version != result.version ||
          !_same_identity(committed_result.identity, identity)) {
        throw const WorkflowCommitException(
          code: WorkflowCommitErrorCode.invalid_plan,
          message: 'Stop events do not produce the expected terminal state.',
        );
      }

      final recorded_at_unix_ms = DateTime.now().toUtc().millisecondsSinceEpoch;

      // Both events are appended to the existing journal.
      // The original accepted stop payload and event ID are
      // preserved; the outcome receives a new event ID.
      for (var index = 0; index < events.length; index++) {
        final event = index == 0 ? persisted_event : outcome;

        await _database
            .into(_database.workflowEvents)
            .insert(
              WorkflowEventsCompanion.insert(
                event_id: index == 0 ? receipt.event_id : _uuid.v4(),
                workflow_id: identity.workflow_id,
                version: actual_state.version + index + 1,
                correlation_id: receipt.correlation_id,
                causation_id: Value(index == 0 ? null : receipt.event_id),
                event_type: event.event_type,
                payload_json: index == 0
                    ? stored.payload_json
                    : _codec.encode(event),
                recorded_at_unix_ms: recorded_at_unix_ms,
              ),
            );
      }

      // Release ownership only after appending the terminal
      // outcome, still inside the same transaction.
      //
      // Compare-and-set guards the exact projected identity,
      // bindings, and last committed active version.
      final removed =
          await (_database.delete(_database.unfinishedWorkflows)..where(
                (row) =>
                    row.os_user_id.equals(_os_user_id) &
                    row.workflow_id.equals(identity.workflow_id) &
                    row.target_id.equals(identity.target_id) &
                    row.root_path.equals(identity.root.value) &
                    row.version.equals(actual_state.version),
              ))
              .go();

      if (removed != 1) {
        throw const WorkflowCommitException(
          code: WorkflowCommitErrorCode.invalid_plan,
          message: 'Unfinished-workflow ownership changed during stop.',
        );
      }

      // A failed inbox completion rolls back both journal
      // appends and the ownership release.
      final updated =
          await (_database.update(_database.workflowSubmissions)..where(
                (row) =>
                    row.event_id.equals(receipt.event_id) &
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
          message: 'Stop submission completion lost its pending status.',
        );
      }
    });
  }

  /// Compares established domain identities by value.
  ///
  /// WorkflowIdentity is immutable but currently does not
  /// implement value equality.
  static bool _same_identity(WorkflowIdentity first, WorkflowIdentity second) {
    return first.workflow_id == second.workflow_id &&
        first.os_user_id == second.os_user_id &&
        first.target_id == second.target_id &&
        first.root.value == second.root.value;
  }

  /// Validates independently trusted OS-user identity.
  static String _require_os_user_id(String os_user_id) {
    if (os_user_id.trim().isEmpty) {
      throw ArgumentError.value(
        os_user_id,
        'os_user_id',
        'Trusted OS-user identity must not be blank.',
      );
    }

    return os_user_id;
  }

  /// Validates the configured trusted submission scope.
  static String _require_scope(String scope_id) {
    if (scope_id.trim().isEmpty) {
      throw ArgumentError.value(scope_id, 'scope_id');
    }

    return scope_id;
  }
}
