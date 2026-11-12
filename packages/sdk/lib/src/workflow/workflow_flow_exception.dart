/// Typed reasons why a workflow flow configuration is invalid.
enum WorkflowFlowErrorCode {
  /// More than one transition claims the same state/event pair.
  duplicate_transition,
}

/// Indicates that a workflow transition graph is ambiguous.
///
/// Configuration errors are detected when the flow is assembled,
/// before any workflow event is processed.
///
/// They are separate from runtime transition rejections.
final class WorkflowFlowException implements Exception {
  /// Creates a typed invalid-flow configuration failure.
  const WorkflowFlowException({
    required this.code,
    required this.source_state_type,
    required this.trigger_event_type,
    required this.message,
  });

  /// Stable configuration failure category.
  final WorkflowFlowErrorCode code;

  /// State type involved in the rejected registration.
  final Type source_state_type;

  /// Event type involved in the rejected registration.
  final Type trigger_event_type;

  /// Human-readable diagnostic explanation.
  final String message;

  @override
  String toString() {
    return 'WorkflowFlowException('
        'code: ${code.name}, '
        'state: $source_state_type, '
        'event: $trigger_event_type): $message';
  }
}
