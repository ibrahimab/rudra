import '../actions/explorer_actions_view_model.dart';
import '../directory/explorer_directory_view_model.dart';

/// Presentation state for the Explorer footer.
///
/// Combines the directory viewport with the current keyboard
/// instructions. Selection and scrolling information are
/// computed from the directory view model.
///
/// Example:
/// ```dart
/// final footer = ExplorerFooterViewModel(
///   directory: directory_view_model,
///   actions: actions_view_model,
/// );
///
/// print(footer.selected_label);
/// ```
final class ExplorerFooterViewModel {
  /// Creates the footer presentation state.
  ///
  /// [directory] supplies the observed entry count, selection,
  /// scroll position, and inspection diagnostics.
  ///
  /// [actions] supplies the current keyboard-instruction state.
  const ExplorerFooterViewModel({
    required this.directory,
    required this.actions,
  });

  /// Directory viewport represented by the footer.
  final ExplorerDirectoryViewModel directory;

  /// Presentation state for the footer's Actions widget.
  final ExplorerActionsViewModel actions;

  /// Human-readable selection position.
  ///
  /// Returns `none` when no entry is selected, or a
  /// one-based selection position such as `2/10`.
  String get selected_label {
    final selected = directory.selected_index;

    return selected == null
        ? 'none'
        : '${selected + 1}/${directory.total_entries}';
  }

  /// Description of the directory's current scroll position.
  String get scroll_label {
    return switch ((directory.has_hidden_above, directory.has_hidden_below)) {
      (true, true) => 'more above and below',
      (true, false) => 'more above',
      (false, true) => 'more below',
      (false, false) => 'all observed entries visible',
    };
  }
}
