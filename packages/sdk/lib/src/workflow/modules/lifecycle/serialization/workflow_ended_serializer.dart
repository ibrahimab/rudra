import '../../../events/workflow_ended_event.dart';
import '../../../serialization/workflow_event_serializer.dart';

/// Version 1 serializer for terminal workflow outcomes.
final class WorkflowEndedSerializer
    extends WorkflowEventSerializer<WorkflowEndedEvent> {
  /// Creates the stateless serializer.
  const WorkflowEndedSerializer();

  @override
  String get event_type => WorkflowEndedEvent.type_id;

  @override
  int get schema_version => 1;

  /// Encodes the identity of the ended workflow.
  @override
  Map<String, Object?> encode(WorkflowEndedEvent event) => {
    'workflow_id': event.workflow_id,
  };

  /// Reconstructs a terminal workflow outcome.
  @override
  WorkflowEndedEvent decode(Map<String, dynamic> payload) {
    final workflow_id = payload['workflow_id'];

    if (workflow_id is! String) {
      throw const FormatException('Invalid workflow ended payload.');
    }

    try {
      return WorkflowEndedEvent(workflow_id: workflow_id);
    } on ArgumentError catch (error) {
      throw FormatException('Invalid workflow ended payload: $error');
    }
  }
}
