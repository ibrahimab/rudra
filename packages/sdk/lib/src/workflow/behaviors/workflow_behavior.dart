import '../events/workflow_event.dart';
import '../transitions/workflow_transition.dart';
import '../workflow_identity.dart';

/// A self-contained contribution to a workflow state machine.
///
/// Behaviors define pure state transitions. Registration never
/// executes them or performs persistence or filesystem I/O.
abstract interface class WorkflowBehavior {
  /// The transition owned by this behavior.
  WorkflowTransitionDefinition get transition;
}

/// A workflow behavior that also processes a command.
///
/// Command processing produces proposed outcome events.
/// The state machine must validate these outcomes before
/// the persistence layer commits anything.
///
/// C is the exact supported command type.
abstract base class WorkflowCommandBehavior<C extends WorkflowCommandEvent>
    implements WorkflowBehavior {
  /// Creates a command-capable workflow behavior.
  const WorkflowCommandBehavior();

  /// Exact command type handled by this behavior.
  Type get command_type => C;

  /// Produces immutable proposed outcome events.
  ///
  /// Rejects an unexpected concrete command type.
  /// Neither this method nor its returned events establish
  /// that a workflow has been committed.
  List<WorkflowEvent> propose_outcomes(
    WorkflowCommandEvent command, {
    required WorkflowIdentity identity,
  }) {
    if (command.runtimeType != C) {
      throw ArgumentError.value(
        command,
        'command',
        'Expected command type $C.',
      );
    }

    return List<WorkflowEvent>.unmodifiable(
      handle_command(command as C, identity),
    );
  }

  /// Implements the domain decision for a typed command.
  ///
  /// Must be deterministic and free of external side effects.
  List<WorkflowEvent> handle_command(C command, WorkflowIdentity identity);
}
