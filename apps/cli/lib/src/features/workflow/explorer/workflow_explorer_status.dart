import '../../explorer/application/explorer_action_registry.dart';
import 'workflow_explorer_state.dart';

/// Projects workflow state into generic Explorer status data.
///
/// The Workflow feature owns the interpretation of its
/// lifecycle states and the formatting of its status.
///
/// Explorer itself receives only [ExplorerStatus].
///
/// A committed active workflow, an unresolved submission,
/// and the absence of a loaded workflow are represented
/// distinctly.
///
/// This function does not:
/// - Query persistence.
/// - Submit workflow commands.
/// - Replay the event journal.
/// - Change workflow state.
/// - Infer completion from submission acceptance.
///
/// The supplied [state] must already reflect the current
/// interaction-local application snapshot.
///
/// Example:
/// ```dart
/// final state = WorkflowExplorerState();
///
/// final status = workflow_explorer_status(state);
///
/// assert(status.text == 'Workflow: NOT LOADED');
/// ```
ExplorerStatus workflow_explorer_status(WorkflowExplorerState state) {
  final active = state.active_workflow;

  if (active != null) {
    return ExplorerStatus(
      'Workflow: ACTIVE'
      '  |  ID: ${active.identity.workflow_id}'
      '  |  Version: ${active.version}'
      '  |  Target: ${active.identity.target_id}',
      emphasized: true,
    );
  }

  final pending = state.pending_submission;

  if (pending != null) {
    return ExplorerStatus(
      'Workflow: PENDING'
      '  |  Submission: ${pending.event_id}',
    );
  }

  return const ExplorerStatus('Workflow: NOT LOADED');
}
