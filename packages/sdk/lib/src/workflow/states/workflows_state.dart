import 'workflow_snapshot.dart';

/// Immutable owner-scoped view of established workflow state.
///
/// [current_workflow] identifies the sole unfinished workflow
/// belonging to the trusted operating-system user, if one exists.
///
/// Historical workflows are queried independently. Constructing
/// this state does not require loading every workflow history.
///
/// The absence of an unfinished workflow must be established
/// through validated SDK restoration. A failed, incomplete, or
/// unavailable restoration must not be represented by a null
/// current workflow.
///
/// This object contains domain state only. Submission processing
/// status and observation availability have separate contracts.
///
/// Example:
/// ```dart
/// final workflows = WorkflowsState(
///   current_workflow: restored_workflow,
/// );
///
/// final current = workflows.current_workflow;
///
/// if (current != null) {
///   print(current.identity.workflow_id);
/// }
/// ```
final class WorkflowsState {
  /// Constructs an immutable workflow collection state.
  ///
  /// [current_workflow] is the validated unfinished workflow,
  /// or explicitly `null` when restoration has established absence.
  ///
  /// The supplied snapshot must have a nonterminal lifecycle.
  /// Paused and other nonterminal phases remain unfinished.
  ///
  /// Throws [ArgumentError] when a terminal snapshot is supplied.
  ///
  /// Construction does not verify journal evidence, authenticate
  /// ownership, or access persistence. These responsibilities
  /// belong to the SDK restoration boundary.
  WorkflowsState({required this.current_workflow}) {
    final current = current_workflow;

    if (current != null && current.is_terminal) {
      throw ArgumentError.value(
        current,
        'current_workflow',
        'The current unfinished workflow cannot be terminal.',
      );
    }
  }

  /// Current unfinished workflow, if validated restoration found one.
  ///
  /// Returns `null` only when the producer has established that no
  /// unfinished workflow exists for the trusted OS user.
  ///
  /// A missing value does not represent loading, unavailable
  /// persistence, or failed journal validation.
  final WorkflowSnapshot? current_workflow;
}
