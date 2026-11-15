import 'package:rudra_target_contracts/rudra_target_contracts.dart';

import '../../../events/workflow_started_event.dart';
import '../../../serialization/workflow_event_serializer.dart';
import '../../../workflow_identity.dart';

/// Version 1 serializer for established workflow outcomes.
///
/// Preserves the complete original workflow identity.
/// Trust in the owner identity is established by the processor
/// and commit boundary, not by deserialization.
final class WorkflowStartedSerializer
    extends WorkflowEventSerializer<WorkflowStartedEvent> {
  /// Creates the stateless serializer.
  const WorkflowStartedSerializer();

  @override
  String get event_type => WorkflowStartedEvent.type_id;

  @override
  int get schema_version => 1;

  /// Encodes the established workflow identity.
  @override
  Map<String, Object?> encode(WorkflowStartedEvent event) => {
    'workflow_id': event.identity.workflow_id,
    'os_user_id': event.identity.os_user_id,
    'target_id': event.identity.target_id,
    'root': event.identity.root.value,
  };

  /// Reconstructs a previously established workflow outcome.
  @override
  WorkflowStartedEvent decode(Map<String, dynamic> payload) {
    final workflow_id = payload['workflow_id'];
    final os_user_id = payload['os_user_id'];
    final target_id = payload['target_id'];
    final root = payload['root'];

    if (workflow_id is! String ||
        os_user_id is! String ||
        target_id is! String ||
        root is! String) {
      throw const FormatException('Invalid workflow started payload.');
    }

    try {
      return WorkflowStartedEvent(
        identity: WorkflowIdentity(
          workflow_id: workflow_id,
          os_user_id: os_user_id,
          target_id: target_id,
          root: TargetPath(root),
        ),
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid workflow started payload: $error');
    }
  }
}
