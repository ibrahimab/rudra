import '../workflow/workflow/states/workflows_state.dart';

/// Immutable composite application state exposed by Rudra's SDK.
///
/// [workflows] provides the owner-scoped workflow state.
///
/// Additional independently owned SDK domain-state collections
/// may be introduced as their capabilities are implemented.
/// Frontends consume this composite state rather than maintaining
/// separate authoritative domain-state representations.
///
/// An instance represents a coherent application state only when
/// its constituent values have been obtained from validated SDK
/// state restoration or committed state processing.
///
/// Construction does not load persistence, replay events, or
/// subscribe to state changes. Those operations belong to the
/// SDK application and observation contracts.
///
/// Example:
/// ```dart
/// final state = RudraState(
///   workflows: WorkflowsState(
///     current_workflow: restored_workflow,
///   ),
/// );
///
/// final current = state.workflows.current_workflow;
/// ```
final class RudraState {
  /// Constructs an immutable composite SDK state.
  ///
  /// [workflows] must be supplied explicitly and cannot be null.
  ///
  /// The caller is responsible for supplying validated domain
  /// state. Construction does not establish authoritative status.
  const RudraState({required this.workflows});

  /// Non-null workflow collection belonging to this application state.
  ///
  /// Its nullable current-workflow selector distinguishes verified
  /// absence from an established unfinished workflow.
  final WorkflowsState workflows;
}
