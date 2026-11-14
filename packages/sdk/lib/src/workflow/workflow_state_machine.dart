import 'events/workflow_event.dart';
import 'states/workflow_initial_state.dart';
import 'states/workflow_state.dart';
import 'workflow_flow.dart';
import 'workflow_transition_exception.dart';

/// Deterministic, registry-driven workflow state machine.
///
/// The machine applies events using the immutable transition
/// definitions provided by [flow].
///
/// No concrete workflow event, state, or transition implementation
/// is hardcoded into this engine.
///
/// For every transition, the engine:
/// - Verifies that the event type is registered.
/// - Rejects transitions from terminal states.
/// - Finds the exact state/event transition.
/// - Executes its domain guard and state factory.
/// - Verifies the declared resulting state type.
/// - Verifies that the state version advanced exactly once.
///
/// Every successful transition produces a new immutable state.
///
/// A rejected transition preserves the original state.
///
/// Replay applies the same transition rules in event order.
///
/// The engine does not:
/// - Persist, publish, or submit events.
/// - Invoke asynchronous event handlers.
/// - Perform filesystem operations.
/// - Authenticate users or authorize cleanup.
/// - Enforce cross-process concurrency or uniqueness.
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
/// ]);
///
/// print(state is WorkflowActiveState);
/// // true
/// ```
final class WorkflowStateMachine {
  /// Creates a state machine with an immutable transition graph.
  ///
  /// If [flow] is omitted, the standard Rudra lifecycle is used.
  ///
  /// Construction performs no I/O or workflow processing.
  WorkflowStateMachine({WorkflowFlow? flow})
    : flow = flow ?? WorkflowFlow.standard();

  /// Transition graph used by this state-machine instance.
  ///
  /// The flow cannot be modified after construction.
  final WorkflowFlow flow;

  /// Applies one event according to the registered transition.
  ///
  /// Matching uses exact Dart state and event types.
  ///
  /// A valid transition produces a result with version equal
  /// to [state.version] plus one.
  ///
  /// Unknown event implementations are rejected with
  /// [WorkflowTransitionErrorCode.unsupported_event].
  ///
  /// Registered events without a valid transition from the
  /// current state are rejected with
  /// [WorkflowTransitionErrorCode.invalid_transition].
  ///
  /// Terminal states reject all transitions.
  ///
  /// The declared destination type and result version are
  /// checked independently of the transition factory.
  ///
  /// Throws [WorkflowTransitionException] for domain rejections
  /// and malformed transition results.
  ///
  /// The supplied state and event are never modified.
  ///
  /// Example:
  /// ```dart
  /// final next_state = machine.transition(
  ///   state: const WorkflowInitialState(),
  ///   event: WorkflowStartEvent(
  ///     target_id: 'local-macos',
  ///     root: TargetPath('/tmp'),
  ///   ),
  /// );
  /// ```
  WorkflowState transition({
    required WorkflowState state,
    required WorkflowEvent event,
  }) {
    final event_type = event.runtimeType;

    // Unknown event implementations cannot authorize transitions
    // by supplying a recognized string identifier.
    if (!flow.supports_event_type(event_type)) {
      throw WorkflowTransitionException(
        code: WorkflowTransitionErrorCode.unsupported_event,
        state: state,
        event: event,
        message: 'The workflow event type is not registered.',
      );
    }

    // Terminality is an invariant of the state itself.
    // A malformed custom flow cannot reopen a terminal state.
    if (state.is_terminal) {
      throw WorkflowTransitionException(
        code: WorkflowTransitionErrorCode.invalid_transition,
        state: state,
        event: event,
        message: 'A terminal workflow cannot transition.',
      );
    }

    final rule = flow.transition_for(
      state_type: state.runtimeType,
      event_type: event_type,
    );

    if (rule == null) {
      throw WorkflowTransitionException(
        code: WorkflowTransitionErrorCode.invalid_transition,
        state: state,
        event: event,
        message:
            'No transition is registered for this '
            'state and event combination.',
      );
    }

    final next_version = state.version + 1;

    // The rule performs domain validation and constructs the
    // proposed immutable next state.
    final next_state = rule.execute(state, event, next_version);

    // Even a incorrectly implemented rule must not produce a
    // different lifecycle state than its registration declares.
    if (next_state.runtimeType != rule.destination_state_type) {
      throw WorkflowTransitionException(
        code: WorkflowTransitionErrorCode.result_state_mismatch,
        state: state,
        event: event,
        message:
            'The transition produced a state type '
            'different from its declared destination.',
      );
    }

    // Reject malformed projections rather than allowing state
    // versions to skip or repeat committed event positions.
    if (next_state.version != next_version) {
      throw WorkflowTransitionException(
        code: WorkflowTransitionErrorCode.result_version_mismatch,
        state: state,
        event: event,
        message:
            'The transition did not advance the '
            'workflow version by exactly one.',
      );
    }

    return next_state;
  }

  /// Reconstructs state from ordered committed workflow events.
  ///
  /// Replay begins at [WorkflowInitialState] with version zero.
  ///
  /// Each event is passed to [transition], so reconstruction
  /// and individual event application share identical rules.
  ///
  /// Empty history produces the initial state.
  ///
  /// If any transition fails, replay throws
  /// [WorkflowReplayException] with the zero-based event index
  /// and the underlying typed transition error.
  ///
  /// A contradictory history must not be silently repaired or
  /// returned as partially reconstructed authoritative state.
  ///
  /// Replay performs no filesystem or persistence operations.
  ///
  /// Event-store sequence validation, idempotency, snapshots,
  /// and guarded durable appends are implemented separately.
  ///
  /// Example:
  /// ```dart
  /// final state = machine.replay(events);
  /// print(state.version);
  /// ```
  WorkflowState replay(Iterable<WorkflowEvent> events) {
    WorkflowState state = const WorkflowInitialState();

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
}
