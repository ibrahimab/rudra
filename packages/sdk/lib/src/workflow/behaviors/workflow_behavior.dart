import '../events/workflow_event.dart';
import '../states/workflow_snapshot.dart';
import '../workflow_identity.dart';

/// A typed SDK command behavior independent of domain outcome projection.
///
/// [C] identifies the supported concrete command type. Command validation
/// and outcome proposal are pure and never perform filesystem or database I/O.
abstract base class WorkflowCommandBehavior<C extends WorkflowCommandEvent> {
  /// Constructs a stateless command behavior.
  const WorkflowCommandBehavior();

  /// Exact Dart command type handled by this behavior.
  Type get command_type => C;

  /// Validates the submitted command against the current committed snapshot.
  ///
  /// [previous] is null only when no workflow was restored.
  /// [identity] comes from trusted processing, not frontend input.
  /// Throws [ArgumentError] for another concrete command type.
  void validate_submission(
    WorkflowCommandEvent command, {
    required WorkflowSnapshot? previous,
    required WorkflowIdentity identity,
  }) {
    if (command.runtimeType != C) {
      throw ArgumentError.value(command, 'command', 'Expected command $C.');
    }
    validate_command(command as C, previous: previous, identity: identity);
  }

  /// Implements domain-specific, side-effect-free command validation.
  void validate_command(
    C command, {
    required WorkflowSnapshot? previous,
    required WorkflowIdentity identity,
  });

  /// Returns immutable proposed outcomes without committing any of them.
  ///
  /// The processor must first call [validate_submission].
  List<WorkflowOutcomeEvent> propose_outcomes(
    WorkflowCommandEvent command, {
    required WorkflowIdentity identity,
  }) {
    if (command.runtimeType != C) {
      throw ArgumentError.value(command, 'command', 'Expected command $C.');
    }
    return List<WorkflowOutcomeEvent>.unmodifiable(
      handle_command(command as C, identity),
    );
  }

  /// Produces typed proposed outcomes for one validated command.
  List<WorkflowOutcomeEvent> handle_command(
    C command,
    WorkflowIdentity identity,
  );
}
