import '../../../../../core/rendering/theme.dart';
import '../../../../../core/rendering/widgets/terminal_widget.dart';

import 'welcome_header_view_model.dart';

/// Presents the application title and read-only introduction.
///
/// This widget owns only Welcome's header layout.
/// It never writes directly to a terminal.
final class WelcomeHeader implements TerminalWidget {
  /// Creates a header from prepared presentation data.
  const WelcomeHeader(this.view_model);

  /// Header-specific presentation data.
  final WelcomeHeaderViewModel view_model;

  /// Number of header rows, including surrounding spacing.
  static const int fixed_rows = 4;

  @override
  int get height => fixed_rows;

  @override
  Iterable<TerminalLine> build(TerminalConstraints constraints) sync* {
    yield const TerminalLine('');

    yield TerminalLine(
      '${view_model.product_title}  |  READ ONLY',
      role: TerminalRole.title,
    );

    yield const TerminalLine('Read-only filesystem exploration.');

    yield const TerminalLine('');
  }
}
