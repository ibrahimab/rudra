import 'workflow_event.dart';
import 'workflow_state.dart';
import 'workflow_transition_exception.dart';

/// Deterministic state machine for Rudra workflow lifecycles.
///
/// The machine applies committed workflow events to immutable
/// states according to explicit transition rules.
///
/// Supported transitions:
///
/// - Initial + WorkflowStartEvent = StartRequested.
/// - StartRequested + WorkflowStartedEvent = Active.
/// - Active + WorkflowEndedEvent = Ended.
///
/// Every other transition is rejected.
///
/// Successful transitions produce new immutable state objects.
/// Previous states and events are never modified.
///
/// The original filesystem target and inspection root must match
/// between the start request and successful start outcome.
///
/// An ended workflow cannot transition further.
///
/// The machine does not:
/// - Persist or publish events.
/// - Invoke event handlers.
/// - Inspect or modify filesystem content.
/// - Authenticate operating-system users.
/// - Enforce global workflow uniqueness.
/// - Authorize cleanup or execution.
///
/// Those responsibilities belong to separate SDK components
/// and trusted infrastructure.
///
/// Example:
/// ```dart
/// final machine = WorkflowStateMachine();
///
/// final state = machine.replay([
///   WorkflowStartEvent(
///     target_id: 'local-macos',
///     root: TargetPath('/tmp'),
///   ),
///   WorkflowStartedEvent(
///     identity: WorkflowIdentity(
///       workflow_id: 'workflow-1',
///       os_user_id: 'user-1',
///       target_id: 'local-macos',
///       root: TargetPath('/tmp'),
///     ),
///   ),
///   WorkflowEndedEvent(workflow_id: 'workflow-1'),
/// ]);
///
/// print(state is WorkflowEndedState);
/// // true
///
/// print(state.version);
/// // 3
/// ```
final class WorkflowStateMachine {
  /// Creates a stateless workflow state machine.
  ///
  /// Construction performs no I/O and creates no workflow.
  const WorkflowStateMachine();

  /// Applies a single event to the supplied workflow state.
  ///
  /// The transition must be permitted for the current state.
  ///
  /// On success, returns a new immutable [WorkflowState] with
  /// its version increased by exactly one.
  ///
  /// On failure, throws [WorkflowTransitionException] and leaves
  /// the supplied state unchanged.
  ///
  /// A start request creates a pending request state only.
  /// A workflow becomes active exclusively when a matching
  /// [WorkflowStartedEvent] is applied.
  ///
  /// Original path bindings are compared using their exact
  /// target-native string values. This verifies preservation
  /// of the requested binding; it does not establish that two
  /// paths identify the same filesystem object.
  ///
  /// Unknown event implementations are rejected explicitly.
  ///
  /// This method assumes the caller is applying an appropriate
  /// committed event. It does not authenticate the event source,
  /// verify persistence, or enforce concurrency constraints.
  ///
  /// Example:
  /// ```dart
  /// final requested = machine.transition(
  ///   state: const WorkflowInitialState(),
  ///   event: WorkflowStartEvent(
  ///     target_id: 'local-macos',
  ///     root: TargetPath('/tmp'),
  ///   ),
  /// );
  ///
  /// print(requested is WorkflowStartRequestedState);
  /// // true
  /// ```
  WorkflowState transition({
    required WorkflowState state,
    required WorkflowEvent event,
  }) {
    // Only explicitly implemented event types can modify state.
    //
    // The semantic event type string is not used for dispatch:
    // an unrelated event implementation must never gain domain
    // authority merely by supplying a recognized string.
    if (event is! WorkflowStartEvent &&
        event is! WorkflowStartedEvent &&
        event is! WorkflowEndedEvent) {
      throw WorkflowTransitionException(
        code: WorkflowTransitionErrorCode.unsupported_event,
        state: state,
        event: event,
        message: 'The workflow event type is not supported.',
      );
    }

    return switch ((state, event)) {
      // Recording a request does not establish an active workflow.
      (
        WorkflowInitialState(),
        WorkflowStartEvent requested,
      ) =>
        WorkflowStartRequestedState(
          target_id: requested.target_id,
          root: requested.root,
          version: state.version + 1,
        ),

      // A successful start must preserve the original request.
      (
        WorkflowStartRequestedState requested,
        WorkflowStartedEvent started,
      ) =>
        _apply_started(
          requested,
          started,
        ),

      // Only an established active workflow may end.
      (
        WorkflowActiveState active,
        WorkflowEndedEvent ended,
      ) =>
        _apply_ended(
          active,
          ended,
        ),

      // All unspecified transitions fail closed.
      _ => throw WorkflowTransitionException(
          code: WorkflowTransitionErrorCode.invalid_transition,
          state: state,
          event: event,
          message: 'The event is not valid in the current state.',
        ),
    };
  }

  /// Reconstructs workflow state from ordered committed events.
  ///
  /// Replay always begins from [WorkflowInitialState].
  ///
  /// Events are consumed in the supplied iteration order.
  /// A valid empty history produces the initial state.
  ///
  /// Each event is passed through [transition], guaranteeing
  /// that live transitions and replay use identical domain rules.
  ///
  /// No snapshots or projections are trusted or required.
  ///
  /// If any event is invalid, throws [WorkflowReplayException]
  /// containing the zero-based failing event index and the
  /// underlying typed transition failure.
  ///
  /// Replay never skips invalid events or returns partially
  /// reconstructed authoritative state.
  ///
  /// Replay performs no filesystem operations, persistence
  /// writes, notifications, or event dispatch.
  ///
  /// The supplied history must already be in authoritative
  /// committed order. Verifying durable event identities,
  /// sequence numbers, and expected versions belongs to the
  /// future event-store implementation.
  ///
  /// Example:
  /// ```dart
  /// final state = machine.replay(events);
  ///
  /// print(state.version);
  /// // Number of successfully replayed committed events.
  /// ```
  WorkflowState replay(Iterable<WorkflowEvent> events) {
    WorkflowState state = const WorkflowInitialState();

    var event_index = 0;

    for (final event in events) {
      try {
        state = transition(
          state: state,
          event: event,
        );
      } on WorkflowTransitionException catch (error) {
        // A contradictory committed history is an integrity
        // failure, not a normal workflow transition rejection.
        throw WorkflowReplayException(
          event_index: event_index,
          cause: error,
        );
      }

      event_index++;
    }

    return state;
  }

  /// Applies an established workflow-start outcome.
  ///
  /// The successful outcome must preserve the originally
  /// requested target identifier and exact root path.
  ///
  /// The workflow identifier and trusted owner are introduced
  /// by the successful outcome's established identity.
  ///
  /// An incompatible outcome is rejected without modifying
  /// the pending request.
  WorkflowState _apply_started(
    WorkflowStartRequestedState requested,
    WorkflowStartedEvent started,
  ) {
    final identity = started.identity;

    if (identity.target_id != requested.target_id) {
      throw WorkflowTransitionException(
        code: WorkflowTransitionErrorCode.target_mismatch,
        state: requested,
        event: started,
        message: 'The workflow target differs from the '
            'original start request.',
      );
    }

    if (identity.root.value != requested.root.value) {
      throw WorkflowTransitionException(
        code: WorkflowTransitionErrorCode.root_mismatch,
        state: requested,
        event: started,
        message: 'The workflow root differs from the '
            'original start request.',
      );
    }

    return WorkflowActiveState(
      identity: identity,
      version: requested.version + 1,
    );
  }

  /// Applies a confirmed workflow-ended outcome.
  ///
  /// The event must identify the currently active workflow.
  ///
  /// A successful result retains the exact established
  /// [WorkflowIdentity] instance through the terminal state.
  ///
  /// This operation validates lifecycle consistency only.
  /// Whether ending is safe must have been established before
  /// the corresponding outcome event was committed.
  WorkflowState _apply_ended(
    WorkflowActiveState active,
    WorkflowEndedEvent ended,
  ) {
    if (ended.workflow_id != active.identity.workflow_id) {
      throw WorkflowTransitionException(
        code: WorkflowTransitionErrorCode.workflow_id_mismatch,
        state: active,
        event: ended,
        message: 'The end event refers to a different workflow.',
      );
    }

    return WorkflowEndedState(
      identity: active.identity,
      version: active.version + 1,
    );
  }
}
