import '../../../../../core/rendering/theme.dart';
import '../../../../../core/rendering/widgets/terminal_widget.dart';

import 'explorer_header_view_model.dart';

/// Renders Explorer's title, current directory and contributed status.
///
/// The header occupies three terminal rows.
///
/// Example:
/// ```dart
/// final header = ExplorerHeader(header_view_model);
///
/// print(header.height);
/// // 3
/// ```
final class ExplorerHeader implements TerminalWidget {
  /// Creates a header from its presentation state.
  ///
  /// [view_model] contains the navigation and status text
  /// represented by this header.
  const ExplorerHeader(this.view_model);

  /// Current header presentation state.
  final ExplorerHeaderViewModel view_model;

  /// Fixed number of rows occupied by the header.
  static const int fixed_rows = 3;

  /// Returns the header's fixed terminal height.
  @override
  int get height => fixed_rows;

  /// Renders the header for the supplied terminal constraints.
  ///
  /// [constraints] supplies the available layout dimensions.
  /// The renderer handles sanitization and final text fitting.
  ///
  /// Returns the title, directory and status lines. The first contribution
  /// supplies the styling role for the shared status row.
  @override
  Iterable<TerminalLine> build(TerminalConstraints constraints) sync* {
    yield const TerminalLine(
      'RUDRA / EXPLORER  |  FILESYSTEM READ ONLY',
      role: TerminalRole.title,
    );

    yield TerminalLine(
      'Directory: ${view_model.explorer.current_directory.value}',
      role: TerminalRole.path,
    );

    final statuses = view_model.statuses;
    if (statuses.isEmpty) {
      yield const TerminalLine('Explorer ready.', role: TerminalRole.muted);
    } else {
      yield TerminalLine(
        statuses.map((line) => line.text).join('  |  '),
        role: statuses.first.role,
      );
    }
  }
}
