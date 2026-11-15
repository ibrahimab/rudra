import '../behaviors/workflow_behavior.dart';
import '../events/workflow_event.dart';
import '../modules/workflow_module_registry.dart';
import '../workflow_flow.dart';
import '../workflow_state_machine.dart';

import 'workflow_committer.dart';
import 'workflow_identity_provider.dart';
import 'workflow_inbox.dart';
import 'workflow_processing_models.dart';
import 'workflow_commit_exception.dart';
import 'workflow_submission_resolution.dart';

/// Orchestrates durable workflow command processing.
///
/// Reads commands, resolves registered behaviors, obtains
/// proposed identities, and validates all state transitions.
///
/// Does not access SQLite, perform filesystem operations,
/// or commit changes itself.
final class WorkflowProcessor {
  /// Creates a processor from independently supplied services.
  ///
  /// Transition and command-handler registrations are
  /// snapshotted during construction.
  WorkflowProcessor({
    required WorkflowModuleRegistry registry,
    required WorkflowInbox inbox,
    required WorkflowIdentityProvider identity_provider,
    required WorkflowCommitter committer,
    required WorkflowSubmissionRejector rejector,
  }) : _inbox = inbox,
       _identity_provider = identity_provider,
       _committer = committer,
       _rejector = rejector,
       _handlers = Map.unmodifiable(registry.command_behaviors),
       _machine = WorkflowStateMachine(
         flow: WorkflowFlow(transitions: registry.transitions),
       );

  final WorkflowInbox _inbox;
  final WorkflowIdentityProvider _identity_provider;
  final WorkflowCommitter _committer;

  /// Persists confirmed business rejections independently
  /// of the authoritative workflow event journal.
  final WorkflowSubmissionRejector _rejector;

  final Map<Type, WorkflowCommandBehavior<dynamic>> _handlers;
  final WorkflowStateMachine _machine;

  /// Processes one pending workflow command, if available.
  ///
  /// Returns null when the inbox is empty.
  ///
  /// Domain validation runs before committing. Successful
  /// completion means the committer has durably persisted
  /// the resulting workflow changes.
  Future<WorkflowProcessingPlan?> process_next() async {
    final pending = await _inbox.next_pending();

    if (pending == null) {
      return null;
    }

    final behavior = _handlers[pending.command.runtimeType];

    if (behavior == null) {
      throw StateError(
        'No workflow command behavior registered for '
        '${pending.command.runtimeType}.',
      );
    }

    // Reconstruct the previously committed workflow state.
    final previous_state = _machine.replay(pending.committed_events);

    // Validate the submitted command before proposing outcomes.
    var resulting_state = _machine.transition(
      state: previous_state,
      event: pending.command,
    );

    // Identity creation belongs to a separate trusted service.
    final identity = await _identity_provider.propose_identity(pending);

    final outcomes = behavior.propose_outcomes(
      pending.command,
      identity: identity,
    );

    if (outcomes.isEmpty) {
      throw StateError('A workflow command must propose an outcome.');
    }

    if (outcomes.any((event) => event is WorkflowCommandEvent)) {
      throw StateError('A command handler cannot emit command events.');
    }

    // Validate all proposed outcomes before touching persistence.
    for (final outcome in outcomes) {
      resulting_state = _machine.transition(
        state: resulting_state,
        event: outcome,
      );
    }

    final plan = WorkflowProcessingPlan(
      submission: pending,
      previous_state: previous_state,
      resulting_state: resulting_state,
      events_to_append: [pending.command, ...outcomes],
    );

    // The committer rechecks transactional invariants.
    // Only its successful completion establishes the workflow.
    try {
      await _committer.commit(plan);
    } on WorkflowCommitException catch (error) {
      // Only a confirmed ownership conflict is a business
      // rejection in the currently implemented lifecycle.
      //
      // Stale plans and unexpected failures must not be
      // silently converted into rejected submissions.
      if (error.code != WorkflowCommitErrorCode.ownership_conflict) {
        rethrow;
      }

      const rejection_code = WorkflowRejectionCode.ownership_conflict;

      // This must finish successfully before we report that
      // the request was rejected.
      await _rejector.reject(submission: pending, code: rejection_code);

      throw WorkflowSubmissionRejectedException(
        receipt: pending.receipt,
        code: rejection_code,
      );
    }

    return plan;
  }
}
