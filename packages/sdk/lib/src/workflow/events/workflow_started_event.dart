import '../workflow_identity.dart';
import 'workflow_event.dart';
import 'workflow_start_event.dart';

/// Confirms that a workflow was successfully established.
///
/// [identity] contains the authoritative workflow ID, trusted
/// owner reference, filesystem target, and original root.
///
/// The state machine verifies that the target and root match
/// the preceding [WorkflowStartEvent] request.
///
/// This event is an outcome, not an instruction to create a
/// workflow or perform filesystem operations.
final class WorkflowStartedEvent implements WorkflowEvent {
  /// Creates an established workflow-start outcome.
  const WorkflowStartedEvent({required this.identity});

  /// Stable semantic event type.
  static const String type_id = 'workflow.started';

  @override
  String get event_type => type_id;

  /// Established workflow identity and immutable bindings.
  final WorkflowIdentity identity;
}
