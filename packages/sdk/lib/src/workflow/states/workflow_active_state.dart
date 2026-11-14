import '../workflow_identity.dart';
import 'workflow_state.dart';

/// State of a successfully established, unfinished workflow.
///
/// [identity] retains the workflow ID, trusted OS-user owner
/// reference, original target, and original inspection root.
///
/// These bindings must remain unchanged in future states.
///
/// An active workflow is not itself authorization for cleanup.
final class WorkflowActiveState extends WorkflowState {
  /// Creates an immutable active workflow state.
  ///
  /// Throws [ArgumentError] if [version] is nonpositive.
  WorkflowActiveState({required this.identity, required int version})
    : version = WorkflowState.require_positive_version(version);

  /// Authoritative workflow identity and original bindings.
  final WorkflowIdentity identity;

  @override
  final int version;
}
