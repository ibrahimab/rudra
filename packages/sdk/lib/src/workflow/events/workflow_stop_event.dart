import 'workflow_event.dart';

/// Explicit request to stop an existing active workflow.
///
/// The workflow identifier binds the request to a specific
/// established workflow, preventing a stale request from
/// stopping a different workflow.
///
/// This command does not establish a terminal outcome.
/// Trusted SDK processing must validate and commit that
/// outcome before the workflow can be considered ended.
final class WorkflowStopEvent implements WorkflowCommandEvent {
  /// Creates a workflow-stop request.
  ///
  /// Throws [ArgumentError] if [workflow_id] is blank.
  WorkflowStopEvent({required this.workflow_id}) {
    if (workflow_id.trim().isEmpty) {
      throw ArgumentError.value(
        workflow_id,
        'workflow_id',
        'The workflow identifier must not be blank.',
      );
    }
  }

  /// Stable semantic event type.
  static const String type_id = 'workflow.stop';

  @override
  String get event_type => type_id;

  /// Identifier of the workflow to stop.
  final String workflow_id;
}
