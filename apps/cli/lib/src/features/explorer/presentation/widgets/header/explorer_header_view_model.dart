import '../../../application/explorer_model.dart';
import '../../../../workflow/explorer/workflow_explorer_view_model.dart';

/// Presentation state for the Explorer header.
///
/// Holds the current Explorer navigation snapshot and optional
/// workflow presentation state.
///
/// The header uses these objects to display the current directory
/// and workflow status.
///
/// Example:
/// ```dart
/// final view_model = ExplorerHeaderViewModel(
///   explorer: explorer_model,
///   workflow: workflow_view_model,
/// );
/// ```
final class ExplorerHeaderViewModel {
  /// Creates the header presentation state.
  ///
  /// [explorer] supplies the currently displayed directory.
  ///
  /// [workflow] supplies workflow status when workflow support
  /// is configured. Null indicates no workflow integration.
  const ExplorerHeaderViewModel({
    required this.explorer,
    required this.workflow,
  });

  /// Navigation snapshot associated with the displayed header.
  final ExplorerModel explorer;

  /// Workflow presentation state, if configured.
  final WorkflowExplorerViewModel? workflow;
}
