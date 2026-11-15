import 'package:drift/drift.dart';
import 'package:rudra_sdk/rudra_sdk.dart';
import 'package:uuid/uuid.dart';

import '../../../database/rudra_database.dart';

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
    required WorkflowEventCodec codec,
    required WorkflowFlow flow,
  }) : _database = database,
       _scope_id = _require_scope(scope_id),
       _codec = codec,
       _machine = WorkflowStateMachine(flow: flow);

  static final Uuid _uuid = Uuid();

  final RudraDatabase _database;
  final String _scope_id;
  final WorkflowEventCodec _codec;
  final WorkflowStateMachine _machine;

  /// Atomically commits the first two events of a workflow.
  ///
  /// A stale submission or ownership conflict produces a
  /// typed exception without partially committing changes.
  ///
  /// Unsupported lifecycle stages are deliberately rejected
  /// until their projection rules have been implemented.
  @override
  Future<void> commit(WorkflowProcessingPlan plan) async {
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

  /// Validates the configured trusted submission scope.
  static String _require_scope(String scope_id) {
    if (scope_id.trim().isEmpty) {
      throw ArgumentError.value(scope_id, 'scope_id');
    }

    return scope_id;
  }
}
