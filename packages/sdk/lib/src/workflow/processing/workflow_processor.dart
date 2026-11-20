import '../behaviors/workflow_behavior.dart';
import '../behaviors/workflow_command_validation_exception.dart';

import '../events/workflow_stop_event.dart';

import '../states/workflow_snapshot.dart';

import '../workflow_identity.dart';
import '../workflow_runtime.dart';
import '../workflow_state_machine.dart';

import 'workflow_commit_exception.dart';
import 'workflow_committer.dart';
import 'workflow_identity_provider.dart';
import 'workflow_inbox.dart';
import 'workflow_processing_models.dart';
import 'workflow_processing_result.dart';
import 'workflow_quarantine.dart';
import 'workflow_submission_resolution.dart';

/// Orchestrates durable workflow command processing.
///
/// The processor consumes accepted commands from the inbox,
/// restores committed workflow state, resolves registered SDK
/// command behaviors, and validates proposed domain outcomes.
///
/// Commands are validated by their owning behaviors. Only
/// established domain outcomes are applied by the workflow
/// state machine and proposed for journal commitment.
///
/// The processor delegates trusted identity acquisition to
/// [WorkflowIdentityProvider] and atomic persistence to
/// [WorkflowCommitter].
///
/// Business rejections and unreadable submissions have separate
/// durable resolution paths. Unexpected domain or infrastructure
/// failures propagate without claiming successful commitment.
///
/// This class performs no filesystem operations and contains
/// no SQL or frontend-specific behavior.
final class WorkflowProcessor {
  /// Creates a processor sharing one authoritative workflow runtime.
  ///
  /// [runtime] supplies registered command handlers, lifecycle
  /// transitions, and feature-owned domain-slice reducers.
  ///
  /// [inbox] supplies accepted pending commands and validated
  /// committed outcome histories.
  ///
  /// [identity_provider] supplies proposed trusted identities
  /// when establishing workflows.
  ///
  /// [committer] independently revalidates and persists proposals.
  /// [rejector] persists recognized business rejections.
  /// [quarantiner] durably resolves unreadable submissions.
  ///
  /// Construction performs no I/O or command processing.
  WorkflowProcessor({
    required WorkflowRuntime runtime,
    required WorkflowInbox inbox,
    required WorkflowIdentityProvider identity_provider,
    required WorkflowCommitter committer,
    required WorkflowSubmissionRejector rejector,
    required WorkflowSubmissionQuarantiner quarantiner,
  }) : _inbox = inbox,
       _identity_provider = identity_provider,
       _committer = committer,
       _rejector = rejector,
       _quarantiner = quarantiner,
       _handlers = runtime.command_behaviors,
       _machine = WorkflowStateMachine(runtime: runtime);

  /// Durable source of pending accepted commands.
  final WorkflowInbox _inbox;

  /// Trusted identity provider used during workflow establishment.
  final WorkflowIdentityProvider _identity_provider;

  /// Atomic authoritative workflow persistence boundary.
  final WorkflowCommitter _committer;

  /// Durable resolution boundary for recognized business rejections.
  final WorkflowSubmissionRejector _rejector;

  /// Durable quarantine boundary for unreadable accepted commands.
  final WorkflowSubmissionQuarantiner _quarantiner;

  /// Registered command behaviors indexed by exact Dart command type.
  final Map<Type, WorkflowCommandBehavior<dynamic>> _handlers;

  /// Single authoritative outcome-driven domain state machine.
  final WorkflowStateMachine _machine;

  /// Processes at most one accepted pending workflow command.
  ///
  /// Returns [WorkflowProcessingIdle] when no command is pending.
  ///
  /// Returns [WorkflowProcessingCommitted] only after the
  /// proposed outcomes are atomically persisted.
  ///
  /// Returns [WorkflowProcessingRejected] only after a recognized
  /// business rejection has been durably recorded.
  ///
  /// Returns [WorkflowProcessingQuarantined] only after an
  /// unreadable accepted command is durably quarantined.
  ///
  /// Invalid histories, unrecognized commands, invalid domain
  /// outcomes, and infrastructure failures propagate.
  ///
  /// Reading or validating a command does not commit a workflow.
  Future<WorkflowProcessingResult> process_next() async {
    final PendingWorkflowCommand? pending;

    try {
      pending = await _inbox.next_pending();
    } on WorkflowInboxDecodingException catch (issue) {
      // Quarantine must commit before we report a resolution.
      // The unreadable submission must never be interpreted
      // as an ordinary business rejection.
      await _quarantiner.quarantine(issue);

      return WorkflowProcessingQuarantined(
        receipt: issue.receipt,
        code: issue.code,
      );
    }

    if (pending == null) {
      return const WorkflowProcessingIdle();
    }

    final behavior = _handlers[pending.command.runtimeType];

    if (behavior == null) {
      throw StateError(
        'No workflow command behavior registered for '
        '${pending.command.runtimeType}.',
      );
    }

    // Replay only previously committed domain outcomes.
    // Invalid histories propagate and never become absence.
    final previous_state = _machine.replay(pending.committed_events);

    // A Stop command with no established workflow is a known
    // business rejection. No identity may be fabricated from
    // the untrusted workflow ID supplied by the command.
    if (pending.command is WorkflowStopEvent && previous_state == null) {
      const rejection_code = WorkflowRejectionCode.workflow_not_active;

      await _rejector.reject(submission: pending, code: rejection_code);

      return WorkflowProcessingRejected(
        receipt: pending.receipt,
        code: rejection_code,
      );
    }

    // New workflows require a proposed trusted identity.
    // Existing workflows always retain their committed identity.
    //
    // The command behavior validates these bindings before
    // proposing domain outcomes.
    final WorkflowIdentity identity;

    if (previous_state == null) {
      identity = await _identity_provider.propose_identity(pending);
    } else {
      identity = previous_state.identity;
    }

    try {
      behavior.validate_submission(
        pending.command,
        previous: previous_state,
        identity: identity,
      );
    } on WorkflowCommandValidationException catch (error) {
      final rejection_code = switch (error.code) {
        WorkflowCommandValidationErrorCode.workflow_already_active =>
          WorkflowRejectionCode.ownership_conflict,
        WorkflowCommandValidationErrorCode.workflow_not_active =>
          WorkflowRejectionCode.workflow_not_active,
        WorkflowCommandValidationErrorCode.workflow_id_mismatch =>
          WorkflowRejectionCode.workflow_id_mismatch,
        _ => null,
      };

      // Identity and original-request mismatches indicate invalid
      // processing proposals. They must fail closed rather than
      // becoming ordinary business rejections.
      if (rejection_code == null) {
        rethrow;
      }

      await _rejector.reject(submission: pending, code: rejection_code);

      return WorkflowProcessingRejected(
        receipt: pending.receipt,
        code: rejection_code,
      );
    }

    // The behavior proposes domain outcomes but cannot commit them.
    // The typed behavior contract prevents commands and non-outcomes
    // from entering authoritative domain replay.
    final outcomes = behavior.propose_outcomes(
      pending.command,
      identity: identity,
    );

    if (outcomes.isEmpty) {
      throw StateError(
        'A workflow command must propose at least one domain outcome.',
      );
    }

    // Every outcome is validated against the immutable result
    // of the preceding transition. No domain state is persisted
    // during this evaluation.
    WorkflowSnapshot? resulting_state = previous_state;

    for (final outcome in outcomes) {
      resulting_state = _machine.transition(
        state: resulting_state,
        event: outcome,
      );
    }

    if (resulting_state == null) {
      throw StateError(
        'Outcome processing did not establish a workflow snapshot.',
      );
    }

    final plan = WorkflowProcessingPlan(
      submission: pending,
      previous_state: previous_state,
      resulting_state: resulting_state,
      events_to_append: outcomes,
    );

    try {
      // The persistence adapter must repeat its critical checks
      // against current transactional state. This processor's
      // validated snapshot alone cannot authorize a commit.
      await _committer.commit(plan);
    } on WorkflowCommitException catch (error) {
      final rejection_code = switch (error.code) {
        WorkflowCommitErrorCode.ownership_conflict =>
          WorkflowRejectionCode.ownership_conflict,
        WorkflowCommitErrorCode.workflow_not_active =>
          WorkflowRejectionCode.workflow_not_active,
        WorkflowCommitErrorCode.workflow_id_mismatch =>
          WorkflowRejectionCode.workflow_id_mismatch,
        _ => null,
      };

      // Integrity, invalid-plan, and infrastructure failures
      // must propagate without claiming a durable rejection.
      if (rejection_code == null) {
        rethrow;
      }

      await _rejector.reject(submission: pending, code: rejection_code);

      return WorkflowProcessingRejected(
        receipt: pending.receipt,
        code: rejection_code,
      );
    }

    // Authoritative success is reported only after commitment.
    return WorkflowProcessingCommitted(plan: plan);
  }
}
