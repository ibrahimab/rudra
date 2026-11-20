import 'events/workflow_event.dart';
import 'states/workflow_slice.dart';
import 'states/workflow_snapshot.dart';
import 'transitions/workflow_outcome_transition.dart';
import 'transitions/workflow_slice_reducer.dart';
import 'workflow_identity.dart';
import 'workflow_runtime.dart';
import 'workflow_transition_exception.dart';

/// Deterministic, outcome-only authoritative workflow state machine.
///
/// The first committed establishment outcome creates version 1. Each later
/// committed outcome advances exactly one version. Commands remain in the
/// submission inbox and never contribute to the workflow journal.
///
/// Domain lifecycle rules and slice reducers originate from one frozen
/// [WorkflowRuntime]; no I/O, persistence, or command handling happens here.
final class WorkflowStateMachine {
  /// Builds the authoritative machine from a completed runtime configuration.
  ///
  /// Omitting [runtime] uses the standard SDK module configuration.
  WorkflowStateMachine({WorkflowRuntime? runtime})
    : runtime = runtime ?? WorkflowRuntime.standard() {
    final transitions =
        <(String?, Type), WorkflowOutcomeTransitionDefinition>{};

    for (final definition in this.runtime.outcome_transitions) {
      final pair = (definition.source_lifecycle_id, definition.event_type);
      if (transitions.containsKey(pair)) {
        throw StateError('Duplicate workflow outcome transition: $pair');
      }
      transitions[pair] = definition;
    }
    _transitions = Map.unmodifiable(transitions);

    final reducers = <Type, List<WorkflowSliceReducerDefinition>>{};
    for (final reducer in this.runtime.slice_reducers) {
      reducers
          .putIfAbsent(
            reducer.event_type,
            () => <WorkflowSliceReducerDefinition>[],
          )
          .add(reducer);
    }
    _reducers = Map.unmodifiable({
      for (final entry in reducers.entries)
        entry.key: List<WorkflowSliceReducerDefinition>.unmodifiable(
          entry.value,
        ),
    });
  }

  /// Immutable shared runtime defining lifecycle and feature ownership.
  final WorkflowRuntime runtime;

  /// Exact source lifecycle and concrete outcome dispatch table.
  late final Map<(String?, Type), WorkflowOutcomeTransitionDefinition>
  _transitions;

  /// Typed slice reducers indexed by their exact outcome event type.
  late final Map<Type, List<WorkflowSliceReducerDefinition>> _reducers;

  /// Applies one outcome to an immutable prior state.
  ///
  /// [state] is null only before workflow establishment. A successful
  /// transition preserves established identity, runs all feature reducers
  /// against the *same previous snapshot*, and advances version by one.
  ///
  /// Throws [WorkflowTransitionException] without mutating [state].
  WorkflowSnapshot transition({
    required WorkflowSnapshot? state,
    required WorkflowOutcomeEvent event,
  }) {
    _validate_previous(state, event);
    if (state?.is_terminal ?? false) {
      throw _failure(
        WorkflowTransitionErrorCode.invalid_transition,
        state,
        event,
        'A terminal workflow cannot transition.',
      );
    }

    final event_type = event.runtimeType;
    if (!runtime.outcome_transitions.any(
      (definition) => definition.event_type == event_type,
    )) {
      throw _failure(
        WorkflowTransitionErrorCode.unsupported_event,
        state,
        event,
        'The concrete outcome type is not registered.',
      );
    }

    final rule = _transitions[(state?.lifecycle.id, event_type)];
    if (rule == null) {
      throw _failure(
        WorkflowTransitionErrorCode.invalid_transition,
        state,
        event,
        'No rule accepts this outcome from this lifecycle.',
      );
    }

    final WorkflowIdentity identity;
    if (state == null) {
      if (event is! WorkflowEstablishmentOutcomeEvent) {
        throw _failure(
          WorkflowTransitionErrorCode.invalid_transition,
          state,
          event,
          'First outcome must establish identity.',
        );
      }
      identity = event.identity;
    } else {
      if (event is WorkflowEstablishmentOutcomeEvent) {
        throw _failure(
          WorkflowTransitionErrorCode.invalid_transition,
          state,
          event,
          'Cannot establish an already established workflow.',
        );
      }
      identity = state.identity;
    }

    try {
      rule.validate(state, event);
    } on WorkflowTransitionException {
      rethrow;
    } catch (_) {
      throw _failure(
        WorkflowTransitionErrorCode.guard_rejected,
        state,
        event,
        'Registered outcome guard rejected the event.',
      );
    }

    final lifecycle = runtime.lifecycles[rule.destination_lifecycle_id];
    if (lifecycle == null) {
      throw _failure(
        WorkflowTransitionErrorCode.invalid_snapshot,
        state,
        event,
        'Outcome destination lifecycle is not registered.',
      );
    }

    final next_slices = _project_slices(state, event);
    return WorkflowSnapshot(
      identity: identity,
      lifecycle: lifecycle,
      version: (state?.version ?? 0) + 1,
      slices: next_slices,
    );
  }

  /// Reconstructs workflow state from an ordered outcome-only journal.
  ///
  /// Empty history produces null. Invalid nonempty history throws
  /// [WorkflowReplayException] at the first invalid journal position.
  WorkflowSnapshot? replay(Iterable<WorkflowOutcomeEvent> events) {
    WorkflowSnapshot? state;
    var event_index = 0;

    for (final event in events) {
      try {
        state = transition(state: state, event: event);
      } on WorkflowTransitionException catch (error) {
        throw WorkflowReplayException(event_index: event_index, cause: error);
      }
      event_index++;
    }
    return state;
  }

  /// Rejects snapshots whose lifecycle or slice ownership is unregistered.
  void _validate_previous(WorkflowSnapshot? state, WorkflowOutcomeEvent event) {
    if (state == null) return;
    final lifecycle = runtime.lifecycles[state.lifecycle.id];
    if (lifecycle == null ||
        lifecycle.is_terminal != state.lifecycle.is_terminal) {
      throw _failure(
        WorkflowTransitionErrorCode.invalid_snapshot,
        state,
        event,
        'Previous lifecycle is not registered.',
      );
    }

    for (final binding in state.slice_bindings) {
      final key = runtime.slice_keys[binding.key.id];
      if (key == null || key.slice_type != binding.key.slice_type) {
        throw _failure(
          WorkflowTransitionErrorCode.invalid_snapshot,
          state,
          event,
          'Previous workflow contains an unregistered slice.',
        );
      }
    }
  }

  /// Computes one coherent next set of independently owned slice bindings.
  ///
  /// Reducers receive the same [previous] rather than an intermediate result.
  /// A null reducer result removes only its own slice.
  List<WorkflowSliceBinding<WorkflowSlice>> _project_slices(
    WorkflowSnapshot? previous,
    WorkflowOutcomeEvent event,
  ) {
    final bindings = <String, WorkflowSliceBinding<WorkflowSlice>>{
      for (final binding
          in previous?.slice_bindings ??
              <WorkflowSliceBinding<WorkflowSlice>>[])
        binding.key.id: binding,
    };

    final reducers =
        _reducers[event.runtimeType] ??
        const <WorkflowSliceReducerDefinition>[];
    for (final reducer in reducers) {
      final WorkflowSlice? value;
      try {
        value = reducer.apply(previous, event);
      } catch (_) {
        throw _failure(
          WorkflowTransitionErrorCode.reducer_failure,
          previous,
          event,
          'Feature-owned slice reducer failed.',
        );
      }

      if (value == null) {
        bindings.remove(reducer.key.id);
      } else {
        bindings[reducer.key.id] = WorkflowSliceBinding<WorkflowSlice>(
          key: reducer.key,
          value: value,
        );
      }
    }

    final sorted_ids = bindings.keys.toList()..sort();
    return List<WorkflowSliceBinding<WorkflowSlice>>.unmodifiable([
      for (final id in sorted_ids) bindings[id]!,
    ]);
  }

  /// Builds a typed failure without modifying previous state.
  WorkflowTransitionException _failure(
    WorkflowTransitionErrorCode code,
    WorkflowSnapshot? state,
    WorkflowOutcomeEvent event,
    String message,
  ) => WorkflowTransitionException(
    code: code,
    state: state,
    event: event,
    message: message,
  );
}
