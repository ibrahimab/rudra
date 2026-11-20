import 'events/workflow_event.dart';
import 'states/workflow_snapshot.dart';

/// Stable reasons a domain outcome cannot produce the next workflow snapshot.
enum WorkflowTransitionErrorCode {
  /// No transition accepts the outcome from the current lifecycle.
  invalid_transition,

  /// The concrete outcome type is not registered.
  unsupported_event,

  /// The previous snapshot is not valid for the configured runtime.
  invalid_snapshot,

  /// An outcome refers to an unrelated workflow identity.
  workflow_id_mismatch,

  /// A feature-owned lifecycle guard rejected the outcome.
  guard_rejected,

  /// A feature-owned slice reducer could not project a value.
  reducer_failure,
}

/// One outcome was rejected before constructing authoritative state.
///
/// [state] may be null only for initial establishment. A failure cannot
/// mutate the previous snapshot or authorize persistence.
final class WorkflowTransitionException implements Exception {
  /// Creates a classified transition failure.
  const WorkflowTransitionException({
    required this.code,
    required this.state,
    required this.event,
    required this.message,
  });

  /// Stable machine-readable failure reason.
  final WorkflowTransitionErrorCode code;

  /// Prior immutable snapshot, or null before establishment.
  final WorkflowSnapshot? state;

  /// Outcome that the state machine rejected.
  final WorkflowOutcomeEvent event;

  /// Human-readable diagnostic text, not suitable for code matching.
  final String message;

  @override
  String toString() =>
      'WorkflowTransitionException('
      '${code.name}, version: ${state?.version ?? 0}, '
      'event: ${event.event_type}): $message';
}

/// Indicates that a committed journal contains an invalid outcome.
///
/// Replay never returns a partially reconstructed authoritative state.
final class WorkflowReplayException implements Exception {
  /// Creates a failure at the zero-based [event_index].
  const WorkflowReplayException({
    required this.event_index,
    required this.cause,
  });

  /// Journal position of the first rejected outcome.
  final int event_index;

  /// Underlying typed domain transition failure.
  final WorkflowTransitionException cause;

  @override
  String toString() =>
      'WorkflowReplayException(event_index: $event_index): $cause';
}
