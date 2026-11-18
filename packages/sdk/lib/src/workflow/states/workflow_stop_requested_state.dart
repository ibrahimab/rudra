import '../workflow_identity.dart';
import 'workflow_state.dart';

/// State after an active workflow receives a stop request.
///
/// Retains the established workflow identity while awaiting
/// the corresponding terminal outcome.
///
/// This is an intermediate lifecycle state. It does not
/// independently establish that the workflow has ended.
final class WorkflowStopRequestedState extends WorkflowState {
  /// Creates an immutable stop-requested state.
  ///
  /// Throws [ArgumentError] for nonpositive versions.
  WorkflowStopRequestedState({required this.identity, required int version})
    : version = WorkflowState.require_positive_version(version);

  /// Original established workflow identity.
  final WorkflowIdentity identity;

  @override
  final int version;
}
