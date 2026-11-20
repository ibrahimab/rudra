import '../events/workflow_event.dart';
import '../states/workflow_snapshot.dart';
import '../transitions/workflow_transition.dart';
import '../workflow_identity.dart';

/// A self-contained contribution to Rudra's workflow engine.
///
/// Workflow behaviors belong to SDK modules and are registered
/// without executing domain operations.
///
/// The legacy transition contract remains during the coordinated
/// state-machine migration. Command validation and outcome
/// proposal are separately defined by [WorkflowCommandBehavior].
abstract interface class WorkflowBehavior {
  /// Existing transition definition owned by the behavior.
  ///
  /// This contract is removed when the subclass-based workflow
  /// state machine is replaced by outcome-driven replay.
  WorkflowTransitionDefinition get transition;
}

/// SDK-owned behavior for one concrete workflow command type.
///
/// [C] identifies the supported command type.
///
/// A command behavior validates domain prerequisites against
/// the previous committed [WorkflowSnapshot] and proposes
/// immutable domain outcomes.
///
/// Command validation and outcome proposal are pure operations.
/// Neither establishes authoritative state or performs persistence.
///
/// The processor must validate a command before requesting its
/// proposed outcomes. The persistence committer must independently
/// revalidate transactional ownership and expected versions.
abstract base class WorkflowCommandBehavior<C extends WorkflowCommandEvent>
    implements WorkflowBehavior {
  /// Creates a stateless command behavior.
  const WorkflowCommandBehavior();

  /// Concrete command type supported by this behavior.
  ///
  /// Runtime dispatch uses exact Dart types.
  Type get command_type => C;

  /// Validates [command] against the prior committed state.
  ///
  /// [previous] is the current workflow snapshot, or null when
  /// validated restoration established that no workflow exists.
  ///
  /// [identity] is the trusted proposed identity for Start or
  /// the preserved committed identity for an existing workflow.
  ///
  /// The concrete behavior implements the domain-specific rules.
  ///
  /// Throws [ArgumentError] for an unexpected command type.
  /// Domain validation failures propagate to the processor.
  ///
  /// This method does not mutate the snapshot or propose events.
  void validate_submission(
    WorkflowCommandEvent command, {
    required WorkflowSnapshot? previous,
    required WorkflowIdentity identity,
  }) {
    if (command.runtimeType != C) {
      throw ArgumentError.value(
        command,
        'command',
        'Expected command type $C.',
      );
    }

    validate_command(command as C, previous: previous, identity: identity);
  }

  /// Validates the domain rules of a concrete [command].
  ///
  /// [previous] supplies the established workflow state, if any.
  /// [identity] supplies the identity bound to this processing
  /// operation.
  ///
  /// Implementations must be deterministic and side-effect-free.
  /// Violations must fail explicitly rather than being interpreted
  /// as successful command processing.
  void validate_command(
    C command, {
    required WorkflowSnapshot? previous,
    required WorkflowIdentity identity,
  });

  /// Proposes immutable outcomes for an exact command type.
  ///
  /// This method is called only after [validate_submission]
  /// succeeds. The processor supplies the trusted [identity].
  ///
  /// Throws [ArgumentError] when [command] is not of type [C].
  ///
  /// Returns an immutable list of proposed events. None of
  /// these events becomes authoritative before commitment.
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

  /// Computes proposed domain outcomes for the typed command.
  ///
  /// Implementations must be deterministic and free of I/O.
  ///
  /// The returned outcomes are independently validated through
  /// the authoritative state machine before persistence.
  List<WorkflowEvent> handle_command(C command, WorkflowIdentity identity);
}
