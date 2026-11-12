import 'workflow_event.dart';

/// Confirms that an established workflow has ended.
///
/// This is a terminal outcome, not a request to cancel, purge,
/// or otherwise mutate filesystem content.
///
/// The state machine verifies that [workflow_id] identifies
/// the currently active workflow.
///
/// Future lifecycle rules will determine whether outstanding
/// operations permit a workflow to reach a terminal state.
final class WorkflowEndedEvent implements WorkflowEvent {
  /// Creates a confirmed workflow-ended outcome.
  ///
  /// Throws [ArgumentError] if [workflow_id] is blank.
  WorkflowEndedEvent({
    required this.workflow_id,
  }) {
    if (workflow_id.trim().isEmpty) {
      throw ArgumentError.value(
        workflow_id,
        'workflow_id',
        'The workflow identifier must not be blank.',
      );
    }
  }

  /// Stable semantic event type.
  static const String type_id = 'workflow.ended';

  @override
  String get event_type => type_id;

  /// Identifier of the workflow that ended.
  final String workflow_id;
}
