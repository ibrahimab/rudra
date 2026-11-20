import '../../../application/explorer_model.dart';
import '../../../../workflow/explorer/workflow_explorer_view_model.dart';

/// Presentation state for Explorer's keyboard instructions.
///
/// Combines navigation state with the workflow snapshot used
/// to determine which action instructions are visible.
///
/// Example:
/// ```dart
/// final view_model = ExplorerActionsViewModel(
///   explorer: explorer_model,
///   workflow: workflow_view_model,
/// );
///
/// print(view_model.show_start);
/// ```
final class ExplorerActionsViewModel {
  /// Creates the keyboard-instruction view model.
  ///
  /// [explorer] supplies the current navigation and closed state.
  ///
  /// [workflow] supplies the current workflow presentation state.
  /// Null indicates that workflow actions are not configured
  /// for this Explorer instance.
  const ExplorerActionsViewModel({
    required this.explorer,
    required this.workflow,
  });

  /// Navigation state associated with the rendered instructions.
  final ExplorerModel explorer;

  /// Workflow state used to determine action visibility.
  ///
  /// Null indicates that workflow actions are not configured.
  final WorkflowExplorerViewModel? workflow;

  /// Whether Explorer should show the Start instruction.
  bool get show_start => !explorer.is_closed && (workflow?.show_start ?? false);

  /// Whether Explorer should show the Stop instruction.
  bool get show_stop => !explorer.is_closed && (workflow?.show_stop ?? false);
}
