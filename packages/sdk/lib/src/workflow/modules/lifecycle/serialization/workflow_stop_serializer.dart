import '../../../events/workflow_stop_event.dart';
import '../../../serialization/workflow_event_serializer.dart';

/// Version 1 serializer for explicit workflow-stop requests.
///
/// Preserves the original workflow identifier without
/// normalization or interpretation.
final class WorkflowStopSerializer
    extends WorkflowTypedEventSerializer<WorkflowStopEvent> {
  /// Creates the stateless serializer.
  const WorkflowStopSerializer();

  @override
  String get event_type => WorkflowStopEvent.type_id;

  @override
  int get schema_version => 1;

  /// Encodes the workflow targeted by the stop request.
  @override
  Map<String, Object?> encode(WorkflowStopEvent event) => {
    'workflow_id': event.workflow_id,
  };

  /// Reconstructs a workflow-stop request.
  @override
  WorkflowStopEvent decode(Map<String, dynamic> payload) {
    final workflow_id = payload['workflow_id'];

    if (workflow_id is! String) {
      throw const FormatException('Invalid workflow stop payload.');
    }

    try {
      return WorkflowStopEvent(workflow_id: workflow_id);
    } on ArgumentError catch (error) {
      throw FormatException('Invalid workflow stop payload: $error');
    }
  }
}
