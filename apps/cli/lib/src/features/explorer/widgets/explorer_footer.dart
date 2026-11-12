import '../../../core/rendering/theme.dart';
import '../../../core/rendering/widgets/terminal_widget.dart';

import '../explorer_view_model.dart';

/// Displays directory observations, inspection status, and key hints.
///
/// This footer presents information from the existing immutable
/// Explorer view model. It does not query the filesystem or SDK.
///
/// The widget always occupies three rows:
/// - Observed-entry and selection summary.
/// - Inspection completeness or diagnostic warning.
/// - Keyboard instructions or closed status.
///
/// The exact height keeps the footer stable while entries scroll.
///
/// Example:
/// ```dart
/// final footer = ExplorerFooter(view_model);
/// print(footer.height);
/// // 3
/// ```
final class ExplorerFooter implements TerminalWidget {
  /// Creates a footer from an Explorer presentation snapshot.
  const ExplorerFooter(this.view_model);

  /// Immutable Explorer presentation.
  final ExplorerViewModel view_model;

  /// Number of footer rows.
  static const int fixed_rows = 3;

  @override
  int get height => fixed_rows;

  @override
  Iterable<TerminalLine> build(
    TerminalConstraints constraints,
  ) sync* {
    final selected_label = view_model.selected_index == null
        ? 'none'
        : '${view_model.selected_index! + 1}/${view_model.total_entries}';

    final scroll_label =
        switch ((view_model.has_hidden_above, view_model.has_hidden_below)) {
      (true, true) => 'more above and below',
      (true, false) => 'more above',
      (false, true) => 'more below',
      (false, false) => 'all observed entries visible',
    };

    yield TerminalLine(
      '${view_model.observed_count} observed entries'
      '  |  Selected: $selected_label'
      '  |  $scroll_label',
      role: TerminalRole.muted,
    );

    yield TerminalLine(
      _inspection_status(),
      role:
          view_model.is_incomplete ? TerminalRole.warning : TerminalRole.muted,
    );

    yield TerminalLine(
      view_model.is_closed
          ? 'Explorer closed.'
          : 'Up/Down Select  Enter Open  Left/Backspace Back  Q Quit',
      role: TerminalRole.muted,
    );
  }

  /// Describes the completeness of the current SDK observation.
  ///
  /// An incomplete inspection must never appear successful
  /// simply because it returned zero observable entries.
  ///
  /// The first available diagnostic is included for context.
  /// Remaining diagnostics stay in the view model.
  ///
  /// The terminal backend sanitizes all untrusted text.
  String _inspection_status() {
    if (view_model.is_complete) {
      return 'Read-only exploration. No filesystem changes.';
    }

    if (view_model.issues.isEmpty) {
      return 'WARNING: Directory inspection incomplete.';
    }

    final issue = view_model.issues.first;

    return 'WARNING: ${view_model.issues.length} inspection issue(s)'
        '  |  ${issue.operation}: ${issue.code}:'
        ' ${issue.path}: ${issue.message}';
  }
}
