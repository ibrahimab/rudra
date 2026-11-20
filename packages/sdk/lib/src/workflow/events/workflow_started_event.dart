import '../workflow_identity.dart';
import 'workflow_event.dart';

/// Confirms establishment of a workflow with a trusted identity.
///
/// This is the first committed domain outcome for a newly
/// established workflow. Replay constructs the initial immutable
/// snapshot directly from [identity], with workflow version 1.
///
/// The identity includes the workflow identifier, OS-user owner,
/// filesystem target, and original inspection root.
///
/// Before commitment, SDK processing and transactional persistence
/// must verify that the target and root match the accepted Start
/// command and that ownership matches the trusted OS-user identity.
///
/// A constructed event alone does not establish an authoritative
/// workflow. The outcome becomes authoritative only after its
/// successful durable commitment.
///
/// Example:
/// ```dart
/// final outcome = WorkflowStartedEvent(identity: identity);
///
/// print(outcome.identity.workflow_id);
/// // workflow-1
/// ```
final class WorkflowStartedEvent implements WorkflowEstablishmentOutcomeEvent {
  /// Creates a proposed workflow establishment outcome.
  ///
  /// [identity] contains all mandatory original workflow bindings.
  /// This constructor performs no persistence or authorization.
  const WorkflowStartedEvent({required this.identity});

  /// Stable semantic identifier of the establishment outcome.
  static const String type_id = 'workflow.started';

  /// Returns the registered semantic event identifier.
  @override
  String get event_type => type_id;

  /// Immutable identity of the newly established workflow.
  ///
  /// The identity must be preserved by all subsequent transitions.
  @override
  final WorkflowIdentity identity;
}
