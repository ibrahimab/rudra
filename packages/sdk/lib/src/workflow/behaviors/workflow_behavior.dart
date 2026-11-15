import '../transitions/workflow_transition.dart';

/// A self-contained contribution to a workflow state machine.
///
/// Each behavior owns its transition definition and domain
/// validation. Registration does not execute the behavior.
///
/// Behaviors must not perform filesystem or persistence I/O.
abstract interface class WorkflowBehavior {
  /// Returns the typed transition defined by this behavior.
  WorkflowTransitionDefinition get transition;
}
