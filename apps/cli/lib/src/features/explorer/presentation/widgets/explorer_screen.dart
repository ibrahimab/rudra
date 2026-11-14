import '../../../../core/rendering/widgets/terminal_column.dart';
import '../../../../core/rendering/widgets/terminal_widget.dart';

import '../explorer_view_model.dart';

import 'directory/explorer_directory.dart';
import 'footer/explorer_footer.dart';
import 'header/explorer_header.dart';

/// Composes the complete Explorer terminal screen.
///
/// The screen delegates each presentation responsibility to
/// an independent, reusable widget.
///
/// It uses the shared [TerminalColumn] layout contract rather
/// than manually writing screen lines.
///
/// The layout consists of:
/// - [ExplorerHeader].
/// - [ExplorerDirectory].
/// - [ExplorerFooter].
///
/// The widget tree's height is the sum of its children.
///
/// [fixed_rows] derives from the component height contracts,
/// so the Explorer runner does not need to know the layout.
///
/// The additional terminal safety row belongs to the runner,
/// not to this widget.
///
/// No SDK access, navigation, persistence, or terminal I/O
/// occurs during construction or building.
///
/// Example:
/// ```dart
/// final screen = ExplorerScreen(view_model);
///
/// final reserved_rows = ExplorerScreen.fixed_rows;
/// final total_rows = screen.height;
/// ```
final class ExplorerScreen implements TerminalWidget {
  /// Composes the independently prepared component view models.
  ExplorerScreen(ExplorerViewModel view_model)
    : _layout = TerminalColumn(
        children: [
          ExplorerHeader(view_model.header),
          ExplorerDirectory(view_model.directory),
          ExplorerFooter(view_model.footer),
        ],
      );

  /// Root vertical layout containing the screen components.
  final TerminalColumn _layout;

  /// Fixed-height rows excluding the directory entry viewport.
  ///
  /// This value comes from the widgets that actually render
  /// the screen, rather than from independent runner constants.
  static int get fixed_rows =>
      ExplorerHeader.fixed_rows +
      ExplorerDirectory.heading_rows +
      ExplorerFooter.fixed_rows;

  @override
  int get height => _layout.height;

  @override
  Iterable<TerminalLine> build(TerminalConstraints constraints) {
    return _layout.build(constraints);
  }
}
