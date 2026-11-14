import '../workflow_identity.dart';
import 'workflow_state.dart';

/// Terminal state of a completed workflow lifecycle.
///
/// The original workflow identity remains available for
/// historical reconstruction and diagnostics.
///
/// Terminal states cannot be advanced by the state machine.
///
/// This model does not imply that any filesystem object was
/// deleted, quarantined, or restored.
final class WorkflowEndedState extends WorkflowState {
  /// Creates an immutable terminal workflow state.
  ///
  /// Throws [ArgumentError] for nonpositive versions.
  WorkflowEndedState({required this.identity, required int version})
    : version = WorkflowState.require_positive_version(version);

  /// Original workflow identity and immutable bindings.
  final WorkflowIdentity identity;

  @override
  final int version;

  @override
  bool get is_terminal => true;
}
