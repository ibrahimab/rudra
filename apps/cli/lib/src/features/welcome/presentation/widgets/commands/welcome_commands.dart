import '../../../../../core/rendering/theme.dart';
import '../../../../../core/rendering/widgets/terminal_widget.dart';

import 'welcome_commands_view_model.dart';

/// Displays commands available from Rudra's welcome screen.
///
/// Filesystem-specific hints are shown only when a supported
/// target is configured.
///
/// This component is informational. Actual command availability
/// and execution belong to the CLI command registry.
final class WelcomeCommands implements TerminalWidget {
  /// Creates command hints from prepared presentation state.
  const WelcomeCommands(this.view_model);

  /// Command-hint presentation configuration.
  final WelcomeCommandsViewModel view_model;

  /// Rows always displayed by this component.
  static const int base_rows = 3;

  /// Additional rows for filesystem commands.
  static const int filesystem_rows = 2;

  @override
  int get height =>
      base_rows + (view_model.show_filesystem_commands ? filesystem_rows : 0);

  @override
  Iterable<TerminalLine> build(
    TerminalConstraints constraints,
  ) sync* {
    yield const TerminalLine(
      'Available commands:',
      role: TerminalRole.heading,
    );

    if (view_model.show_filesystem_commands) {
      yield const TerminalLine(
        '  rudra ls                  '
        'Inspect the starting directory',
      );

      yield const TerminalLine(
        '  rudra ls /absolute/path   '
        'Inspect another directory',
      );
    }

    yield const TerminalLine(
      '  rudra about               '
      'Show application information',
    );

    yield const TerminalLine(
      '  rudra --help              '
      'Show available commands',
    );
  }
}
