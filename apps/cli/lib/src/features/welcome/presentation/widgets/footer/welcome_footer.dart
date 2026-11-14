import '../../../../../core/rendering/theme.dart';
import '../../../../../core/rendering/widgets/terminal_widget.dart';

import 'welcome_footer_view_model.dart';

/// Presents Welcome's informational filesystem safety statement.
///
/// The footer performs no authorization, filesystem operations,
/// or terminal I/O.
final class WelcomeFooter implements TerminalWidget {
  /// Creates a safety footer from its own presentation model.
  const WelcomeFooter(this.view_model);

  /// Footer-specific presentation data.
  final WelcomeFooterViewModel view_model;

  /// Spacer and safety statement.
  static const int fixed_rows = 2;

  @override
  int get height => fixed_rows;

  @override
  Iterable<TerminalLine> build(
    TerminalConstraints constraints,
  ) sync* {
    yield const TerminalLine('');

    yield TerminalLine(
      view_model.safety_statement,
      role: TerminalRole.muted,
    );
  }
}
