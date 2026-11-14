import '../../../../core/rendering/widgets/terminal_column.dart';
import '../../../../core/rendering/widgets/terminal_widget.dart';

import '../about_view_model.dart';
import 'information/about_information.dart';

/// Composes the complete About terminal screen.
///
/// The screen owns no application information directly.
/// It delegates to independently modeled presentation widgets.
///
/// Layout uses the shared [TerminalColumn] contract,
/// consistent with Explorer and Welcome.
///
/// Its height is derived from the child widgets rather than
/// maintained independently.
///
/// Construction and building perform no filesystem, SDK,
/// or terminal I/O.
///
/// Example:
/// ```dart
/// final screen = AboutScreen(about_view_model);
///
/// print(screen.height);
/// // 1
/// ```
final class AboutScreen implements TerminalWidget {
  /// Builds the current About screen composition.
  AboutScreen(AboutViewModel view_model)
    : _layout = TerminalColumn(
        children: [AboutInformation(view_model.information)],
      );

  /// Root vertical composition of About widgets.
  final TerminalColumn _layout;

  @override
  int get height => _layout.height;

  @override
  Iterable<TerminalLine> build(TerminalConstraints constraints) {
    return _layout.build(constraints);
  }
}
