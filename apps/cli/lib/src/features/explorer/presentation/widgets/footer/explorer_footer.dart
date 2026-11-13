import '../../../../../core/rendering/theme.dart';
import '../../../../../core/rendering/widgets/terminal_widget.dart';

import 'explorer_footer_view_model.dart';

/// Displays the Explorer's prepared summary, status, and key hints.
///
/// The footer is a pure presentation widget.
///
/// Its view model contains three display lines and the semantic
/// severity of the inspection-status line.
///
/// The footer does not need the directory viewport, selection
/// indices, filesystem observations, or navigation state.
///
/// It performs no formatting of domain information, SDK calls,
/// filesystem operations, or terminal I/O.
///
/// Example:
/// ```dart
/// final footer = ExplorerFooter(footer_view_model);
///
/// print(footer.height);
/// // 3
/// ```
final class ExplorerFooter implements TerminalWidget {
  /// Creates a footer from its dedicated presentation model.
  const ExplorerFooter(this.view_model);

  /// Footer-specific display information.
  final ExplorerFooterViewModel view_model;

  /// Number of fixed footer rows.
  static const int fixed_rows = 3;

  @override
  int get height => fixed_rows;

  @override
  Iterable<TerminalLine> build(
    TerminalConstraints constraints,
  ) sync* {
    yield TerminalLine(
      view_model.summary,
      role: TerminalRole.muted,
    );

    yield TerminalLine(
      view_model.inspection_status,
      role: view_model.is_warning ? TerminalRole.warning : TerminalRole.muted,
    );

    yield TerminalLine(
      view_model.navigation_hints,
      role: TerminalRole.muted,
    );
  }
}
