import '../../../../../core/rendering/theme.dart';
import '../../../../../core/rendering/widgets/terminal_widget.dart';

import 'welcome_target_view_model.dart';

/// Displays configured target information or unsupported status.
///
/// This widget does not request an inspection or interpret
/// target-native paths.
///
/// An unsupported target is represented by an explicit warning.
final class WelcomeTarget implements TerminalWidget {
  /// Creates a target presentation component.
  const WelcomeTarget(this.view_model);

  /// Target-specific presentation data.
  final WelcomeTargetViewModel view_model;

  /// Rows used when a target is configured.
  static const int configured_rows = 3;

  /// Rows used when no target is available.
  static const int unsupported_rows = 2;

  @override
  int get height => view_model.can_inspect ? configured_rows : unsupported_rows;

  @override
  Iterable<TerminalLine> build(
    TerminalConstraints constraints,
  ) sync* {
    if (view_model.can_inspect) {
      yield TerminalLine(
        'Target: ${view_model.target_id}',
      );

      yield TerminalLine(
        'Starting directory: ${view_model.starting_directory}',
        role: TerminalRole.path,
      );
    } else {
      yield const TerminalLine(
        'Filesystem inspection is not available '
        'for the current target.',
        role: TerminalRole.warning,
      );
    }

    yield const TerminalLine('');
  }
}
