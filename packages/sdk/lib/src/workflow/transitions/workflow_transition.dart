import '../events/workflow_event.dart';
import '../states/workflow_state.dart';
import '../workflow_transition_exception.dart';

/// A transition rule understood by the workflow engine.
///
/// This non-generic base enables a single registry to contain
/// differently typed transitions.
///
/// Concrete registrations use [WorkflowTransition] to retain
/// compile-time typing for their guards and state factories.
///
/// Only the generic registration implementation is permitted
/// to extend this definition.
sealed class WorkflowTransitionDefinition {
  /// Creates a transition definition.
  const WorkflowTransitionDefinition();

  /// Exact source-state type accepted by the transition.
  Type get source_state_type;

  /// Exact event type that triggers the transition.
  Type get trigger_event_type;

  /// Exact state type produced by the transition.
  Type get destination_state_type;

  /// Applies the typed rule to its matching state and event.
  ///
  /// The engine must select this rule using exact type matching
  /// before invoking it.
  ///
  /// Any domain guard rejection is propagated to the caller.
  WorkflowState execute(
    WorkflowState state,
    WorkflowEvent event,
    int next_version,
  );
}

/// Strongly typed, declarative workflow transition.
///
/// Type parameters:
/// - [S]: concrete source-state type.
/// - [E]: concrete trigger-event type.
/// - [N]: concrete destination-state type.
///
/// [guard] optionally validates domain invariants.
/// [apply] constructs the next immutable state.
///
/// Guards must throw typed [WorkflowTransitionException] values
/// for rejected domain transitions.
///
/// Guards and factories must be deterministic and side-effect-free.
/// The type system cannot independently enforce callback purity.
///
/// The state-machine engine validates that [apply] produces the
/// declared destination type with exactly [next_version].
///
/// Example:
/// ```dart
/// final rule = WorkflowTransition<
///   WorkflowInitialState,
///   WorkflowStartEvent,
///   WorkflowStartRequestedState
/// >(
///   apply: (state, event, next_version) {
///     return WorkflowStartRequestedState(
///       target_id: event.target_id,
///       root: event.root,
///       version: next_version,
///     );
///   },
/// );
/// ```
final class WorkflowTransition<
  S extends WorkflowState,
  E extends WorkflowEvent,
  N extends WorkflowState
>
    extends WorkflowTransitionDefinition {
  /// Creates an immutable typed transition definition.
  ///
  /// Neither [guard] nor [apply] executes during construction.
  const WorkflowTransition({required this.apply, this.guard});

  /// Optional domain-invariant validation callback.
  final void Function(S state, E event)? guard;

  /// Factory for the next immutable workflow state.
  final N Function(S state, E event, int next_version) apply;

  @override
  Type get source_state_type => S;

  @override
  Type get trigger_event_type => E;

  @override
  Type get destination_state_type => N;

  @override
  WorkflowState execute(
    WorkflowState state,
    WorkflowEvent event,
    int next_version,
  ) {
    // Exact type matching is enforced by the registry lookup.
    // These casts reconnect the erased registry interface to
    // the concrete types of the registered transition.
    final typed_state = state as S;
    final typed_event = event as E;

    guard?.call(typed_state, typed_event);

    return apply(typed_state, typed_event, next_version);
  }
}
