import 'package:rudra_target_contracts/rudra_target_contracts.dart';

import '../../../events/workflow_start_event.dart';
import '../../../serialization/workflow_event_serializer.dart';

/// Version 1 serializer for workflow start requests.
///
/// Preserves the original target identifier and target-native
/// filesystem path without normalization.
final class WorkflowStartSerializer
    extends WorkflowTypedEventSerializer<WorkflowStartEvent> {
  /// Creates the stateless serializer.
  const WorkflowStartSerializer();

  @override
  String get event_type => WorkflowStartEvent.type_id;

  @override
  int get schema_version => 1;

  /// Encodes the original workflow-start request.
  @override
  Map<String, Object?> encode(WorkflowStartEvent event) => {
    'target_id': event.target_id,
    'root': event.root.value,
  };

  /// Reconstructs a workflow-start request.
  @override
  WorkflowStartEvent decode(Map<String, dynamic> payload) {
    final target_id = payload['target_id'];
    final root = payload['root'];

    if (target_id is! String || root is! String) {
      throw const FormatException('Invalid workflow start payload.');
    }

    try {
      return WorkflowStartEvent(target_id: target_id, root: TargetPath(root));
    } on ArgumentError catch (error) {
      throw FormatException('Invalid workflow start payload: $error');
    }
  }
}
