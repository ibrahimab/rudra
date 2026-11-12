import '../../../../core/rendering/theme.dart';
import '../../../../core/rendering/widgets/terminal_widget.dart';

import 'explorer_header_view_model.dart';

/// Displays the Explorer screen title and current directory.
///
/// This widget owns only the header's presentation.
///
/// It does not inspect filesystem content, read workflow
/// state, modify navigation, or write to terminal output.
///
/// Both header rows are fixed-height. Terminal backends
/// must truncate long paths rather than wrap them.
///
/// Example:
/// ```dart
/// final header = ExplorerHeader(view_model);
/// print(header.height);
/// // 2
/// ```
final class ExplorerHeader implements TerminalWidget {
  /// Creates a header from its dedicated presentation model.
  const ExplorerHeader(this.view_model);

  /// Header-specific presentation data.
  final ExplorerHeaderViewModel view_model;

  /// Number of rows occupied by the header.
  static const int fixed_rows = 2;

  @override
  int get height => fixed_rows;

  @override
  Iterable<TerminalLine> build(
    TerminalConstraints constraints,
  ) sync* {
    yield const TerminalLine(
      'RUDRA / EXPLORER  |  READ ONLY',
      role: TerminalRole.title,
    );

    yield TerminalLine(
      'Directory: ${view_model.current_directory}',
      role: TerminalRole.path,
    );
  }
}
