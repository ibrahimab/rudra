import '../events/workflow_event.dart';
import '../events/workflow_start_event.dart';
import '../events/workflow_started_event.dart';

import '../states/workflow_initial_state.dart';
import '../states/workflow_snapshot.dart';
import '../states/workflow_start_requested_state.dart';

import '../transitions/workflow_transition.dart';

import '../workflow_identity.dart';

import 'workflow_behavior.dart';
import 'workflow_command_validation_exception.dart';

/// Validates Start requests and proposes establishment outcomes.
///
/// A Start request may establish a workflow only when there is
/// no existing unfinished workflow for the trusted OS user.
///
/// The proposed identity must preserve the command's filesystem
/// target and original inspection root. These bindings are
/// compared using their target-native representations.
///
/// The authoritative outcome is [WorkflowStartedEvent], which
/// supplies the first immutable workflow snapshot's identity.
///
/// The legacy command transition remains during migration.
/// It is removed with the subclass-based state machine.
final class WorkflowStartBehavior
    extends WorkflowCommandBehavior<WorkflowStartEvent> {
  /// Creates the stateless workflow-start behavior.
  const WorkflowStartBehavior();

  /// Legacy transition from Initial to StartRequested.
  ///
  /// Retained until command events are removed from domain replay.
  @override
  WorkflowTransition<
    WorkflowInitialState,
    WorkflowStartEvent,
    WorkflowStartRequestedState
  >
  get transition =>
      WorkflowTransition<
        WorkflowInitialState,
        WorkflowStartEvent,
        WorkflowStartRequestedState
      >(
        apply: (state, event, next_version) {
          return WorkflowStartRequestedState(
            target_id: event.target_id,
            root: event.root,
            version: next_version,
          );
        },
      );

  /// Validates a workflow establishment request.
  ///
  /// [previous] must be null, indicating verified absence.
  /// [identity] must preserve the requested target and root.
  ///
  /// Throws [WorkflowCommandValidationException] when an
  /// unfinished workflow exists or a proposed binding differs
  /// from the submitted command.
  ///
  /// Transactional ownership uniqueness remains the
  /// responsibility of the persistence committer.
  @override
  void validate_command(
    WorkflowStartEvent command, {
    required WorkflowSnapshot? previous,
    required WorkflowIdentity identity,
  }) {
    if (previous != null) {
      throw const WorkflowCommandValidationException(
        code: WorkflowCommandValidationErrorCode.workflow_already_active,
        message: 'The OS user already has an unfinished workflow.',
      );
    }

    if (identity.target_id != command.target_id) {
      throw const WorkflowCommandValidationException(
        code: WorkflowCommandValidationErrorCode.target_mismatch,
        message: 'Proposed workflow target differs from the Start request.',
      );
    }

    if (identity.root.value != command.root.value) {
      throw const WorkflowCommandValidationException(
        code: WorkflowCommandValidationErrorCode.root_mismatch,
        message: 'Proposed workflow root differs from the Start request.',
      );
    }
  }

  /// Proposes the successful workflow establishment outcome.
  ///
  /// [identity] has been provided by trusted application processing
  /// and must already have passed command-binding validation.
  ///
  /// The returned event remains a proposal until committed.
  @override
  List<WorkflowEvent> handle_command(
    WorkflowStartEvent command,
    WorkflowIdentity identity,
  ) {
    return [WorkflowStartedEvent(identity: identity)];
  }
}
