import 'workflow_event.dart';
import 'workflow_state.dart';

/// Identifies why a workflow transition was rejected.
///
/// Codes are independent of exception messages so callers can
/// handle failures without parsing diagnostic text.
///
/// Adding a new workflow event may introduce additional codes
/// without changing the existing error contract.
enum WorkflowTransitionErrorCode {
  /// The event is not permitted in the current lifecycle state.
  invalid_transition,

  /// The event type is not supported by this state machine.
  unsupported_event,

  /// A successful start refers to a different filesystem target.
  target_mismatch,

  /// A successful start changes the originally requested root.
  root_mismatch,

  /// An event refers to a different established workflow.
  workflow_id_mismatch,
}

/// Indicates that a workflow event cannot produce a valid transition.
///
/// The exception retains the previous state and rejected event.
///
/// Throwing this exception does not modify either object.
///
/// The [code] provides a stable, typed rejection reason.
/// [message] is intended for diagnostics.
///
/// Example:
/// ```dart
/// try {
///   machine.transition(state: state, event: event);
/// } on WorkflowTransitionException catch (error) {
///   print(error.code);
/// }
/// ```
final class WorkflowTransitionException implements Exception {
  /// Creates a typed transition failure.
  const WorkflowTransitionException({
    required this.code,
    required this.state,
    required this.event,
    required this.message,
  });

  /// Machine-readable reason for rejecting the event.
  final WorkflowTransitionErrorCode code;

  /// State that was supplied to the rejected transition.
  final WorkflowState state;

  /// Event that could not be applied.
  final WorkflowEvent event;

  /// Human-readable diagnostic explanation.
  final String message;

  @override
  String toString() {
    return 'WorkflowTransitionException('
        'code: ${code.name}, '
        'state: ${state.runtimeType}, '
        'version: ${state.version}, '
        'event: ${event.event_type}): $message';
  }
}

/// Indicates that committed event history cannot be replayed.
///
/// A replay failure means the supplied ordered history contains
/// an event that violates workflow transition rules.
///
/// Such a history must not be silently corrected or partially
/// accepted as an authoritative workflow state.
///
/// [event_index] is zero-based and identifies the failing event.
///
/// [cause] contains the underlying typed transition failure.
///
/// The event index is not a persisted event sequence number.
/// Persisted sequence metadata will be introduced separately.
///
/// Example:
/// ```dart
/// try {
///   final state = machine.replay(events);
///   print(state.version);
/// } on WorkflowReplayException catch (error) {
///   print(error.event_index);
///   print(error.cause.code);
/// }
/// ```
final class WorkflowReplayException implements Exception {
  /// Creates a replay integrity failure.
  ///
  /// [event_index] identifies the position of the rejected
  /// event in the supplied iterable.
  ///
  /// [cause] preserves the original transition rejection.
  const WorkflowReplayException({
    required this.event_index,
    required this.cause,
  });

  /// Zero-based position of the event that failed replay.
  final int event_index;

  /// Original transition failure, including its reason.
  final WorkflowTransitionException cause;

  @override
  String toString() {
    return 'WorkflowReplayException('
        'event_index: $event_index, '
        'applied_version: ${cause.state.version}): $cause';
  }
}
