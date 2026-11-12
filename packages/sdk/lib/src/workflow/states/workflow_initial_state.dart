import 'workflow_state.dart';

/// State before any workflow-start request has been recorded.
///
/// No workflow identifier, owner, or filesystem bindings have
/// been established.
///
/// This is the only valid state with version zero.
final class WorkflowInitialState extends WorkflowState {
  /// Creates the initial workflow state.
  const WorkflowInitialState();

  @override
  int get version => 0;
}
