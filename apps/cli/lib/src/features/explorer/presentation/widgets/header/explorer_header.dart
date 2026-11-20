import '../../../../../core/rendering/theme.dart';
import '../../../../../core/rendering/widgets/terminal_widget.dart';

import 'explorer_header_view_model.dart';

final class ExplorerHeader implements TerminalWidget {
  /// Creates a header from its prepared presentation model.
  ///
  /// Construction performs no application operations or
  /// terminal I/O.
  const ExplorerHeader(this.view_model);

  /// Immutable, feature-independent presentation snapshot.
  final ExplorerHeaderViewModel view_model;

  /// Fixed height of the generic Explorer header.
  ///
  /// The title, directory, and status each occupy one row.
  /// Keeping this value stable preserves viewport sizing.
  static const int fixed_rows = 3;

  /// Number of terminal rows occupied by this widget.
  @override
  int get height => fixed_rows;

  /// Builds exactly three terminal lines.
  ///
  /// The status is supplied as prepared presentation data.
  /// This widget does not interpret feature-specific states
  /// or determine whether application operations are allowed.
  ///
  /// Terminal text sanitization and truncation remain the
  /// responsibility of the shared rendering backend.
  @override
  Iterable<TerminalLine> build(TerminalConstraints constraints) sync* {
    yield const TerminalLine(
      'RUDRA / EXPLORER  |  FILESYSTEM READ ONLY',
      role: TerminalRole.title,
    );

    yield TerminalLine(
      'Directory: ${view_model.current_directory}',
      role: TerminalRole.path,
    );

    // The owning feature has already prepared the status.
    // The header selects only its presentation style.
    yield TerminalLine(
      view_model.status_line,
      role: view_model.emphasized ? TerminalRole.heading : TerminalRole.muted,
    );
  }
}
