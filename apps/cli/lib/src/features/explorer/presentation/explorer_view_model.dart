import '../application/explorer_model.dart';
import '../../workflow/explorer/workflow_explorer_view_model.dart';

import 'widgets/actions/explorer_actions_view_model.dart';
import 'widgets/directory/explorer_directory_view_model.dart';
import 'widgets/footer/explorer_footer_view_model.dart';
import 'widgets/header/explorer_header_view_model.dart';

/// Immutable composition of Explorer's component view models.
///
/// Each component receives the navigation and application
/// information relevant to its own presentation.
///
/// The directory viewport is calculated once for the complete
/// screen snapshot. Header, Directory, and Footer therefore
/// describe the same navigation state.
///
/// Example:
/// ```dart
/// final view_model = ExplorerViewModel.from_navigation(
///   explorer: explorer_model,
///   workflows: workflow_view_model,
///   visible_row_limit: 12,
/// );
///
/// final screen = ExplorerScreen(view_model);
/// ```
final class ExplorerViewModel {
  /// Creates a complete presentation snapshot from navigation state.
  ///
  /// [explorer] contains the current Explorer navigation snapshot.
  ///
  /// [workflows] contains the current workflow presentation state.
  /// Null indicates that workflow functionality is not configured.
  ///
  /// [visible_row_limit] is the number of rows available for
  /// directory entries after fixed screen rows are reserved.
  ///
  /// [first_visible_index] is the preferred directory scroll
  /// position. The directory view model clamps and adjusts it.
  ///
  /// Throws [RangeError] for a negative [visible_row_limit].
  factory ExplorerViewModel.from_navigation({
    required ExplorerModel explorer,
    required WorkflowExplorerViewModel? workflows,
    required int visible_row_limit,
    int first_visible_index = 0,
  }) {
    final directory = ExplorerDirectoryViewModel(
      explorer: explorer,
      visible_row_limit: visible_row_limit,
      first_visible_index: first_visible_index,
    );

    final actions = ExplorerActionsViewModel(
      explorer: explorer,
      workflow: workflows,
    );

    return ExplorerViewModel._(
      header: ExplorerHeaderViewModel(explorer: explorer, workflow: workflows),
      directory: directory,
      footer: ExplorerFooterViewModel(directory: directory, actions: actions),
    );
  }

  /// Creates a screen composition from its component models.
  ///
  /// [header] contains the title, directory and workflow data.
  ///
  /// [directory] contains the formatted directory viewport.
  ///
  /// [footer] contains the summary and keyboard instructions.
  const ExplorerViewModel._({
    required this.header,
    required this.directory,
    required this.footer,
  });

  /// Presentation state consumed by ExplorerHeader.
  final ExplorerHeaderViewModel header;

  /// Presentation state consumed by ExplorerDirectory.
  final ExplorerDirectoryViewModel directory;

  /// Presentation state consumed by ExplorerFooter.
  final ExplorerFooterViewModel footer;
}
