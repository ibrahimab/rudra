import '../../../core/rendering/widgets/terminal_widget.dart';

import '../application/explorer_action_registry.dart';
import '../application/explorer_model.dart';

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
///   contributions: [feature_presentation],
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
  /// [contributions] supplies projected status and shortcut text in
  /// registration order. Empty presentations contribute no text.
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
    Iterable<ExplorerFeaturePresentation> contributions = const [],
    required int visible_row_limit,
    int first_visible_index = 0,
  }) {
    final directory = ExplorerDirectoryViewModel(
      explorer: explorer,
      visible_row_limit: visible_row_limit,
      first_visible_index: first_visible_index,
    );

    final statuses = <TerminalLine>[];
    final instructions = <String>[];
    for (final (:status, :instruction) in contributions) {
      if (status != null) statuses.add(status);
      if (instruction != null) instructions.add(instruction);
    }

    final actions = ExplorerActionsViewModel(
      explorer: explorer,
      instructions: instructions,
    );

    return ExplorerViewModel._(
      header: ExplorerHeaderViewModel(explorer: explorer, statuses: statuses),
      directory: directory,
      footer: ExplorerFooterViewModel(directory: directory, actions: actions),
    );
  }

  /// Creates a screen composition from its component models.
  ///
  /// [header] contains the title, directory and contributed status text.
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
