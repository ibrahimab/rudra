import '../../../../../core/rendering/theme.dart';
import '../../../../../core/rendering/widgets/terminal_widget.dart';

import '../actions/explorer_actions.dart';
import 'explorer_footer_view_model.dart';

/// Renders Explorer's directory summary, inspection status,
/// and keyboard instructions.
///
/// The footer occupies three rows, with the final row supplied
/// by [ExplorerActions].
///
/// Example:
/// ```dart
/// final footer = ExplorerFooter(footer_view_model);
///
/// print(footer.height);
/// // 3
/// ```
final class ExplorerFooter implements TerminalWidget {
  /// Creates a footer from its presentation state.
  ///
  /// [view_model] supplies directory and action information.
  const ExplorerFooter(this.view_model);

  /// Current footer presentation state.
  final ExplorerFooterViewModel view_model;

  /// Number of rows occupied by the complete footer.
  static const int fixed_rows = 2 + ExplorerActions.fixed_rows;

  /// Returns the footer's fixed terminal height.
  @override
  int get height => fixed_rows;

  /// Builds the footer within the supplied terminal constraints.
  ///
  /// [constraints] provides the available layout dimensions.
  ///
  /// Returns a summary line, an inspection-status line,
  /// and the composed Actions widget's instruction line.
  @override
  Iterable<TerminalLine> build(TerminalConstraints constraints) sync* {
    final directory = view_model.directory;

    yield TerminalLine(
      '${directory.observed_count} observed entries'
      '  |  Selected: ${view_model.selected_label}'
      '  |  ${view_model.scroll_label}',
      role: TerminalRole.muted,
    );

    if (directory.is_complete) {
      yield const TerminalLine(
        'Read-only exploration. No filesystem changes.',
        role: TerminalRole.muted,
      );
    } else {
      final issues = directory.inspection_issues.issues;

      if (issues.isEmpty) {
        yield const TerminalLine(
          'WARNING: Directory inspection incomplete.',
          role: TerminalRole.warning,
        );
      } else {
        final issue = issues.first;

        yield TerminalLine(
          'WARNING: ${issues.length} inspection issue(s)'
          '  |  ${issue.operation}: ${issue.code}:'
          ' ${issue.path}: ${issue.message}',
          role: TerminalRole.warning,
        );
      }
    }

    // Compose the action instructions as the footer's final row.
    yield* ExplorerActions(view_model.actions).build(constraints);
  }
}
