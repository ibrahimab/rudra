import '../../../../../core/rendering/theme.dart';
import '../../../../../core/rendering/widgets/terminal_widget.dart';

import 'explorer_actions_view_model.dart';

/// Renders Explorer's navigation and keyboard-action instructions.
///
/// Instructions reflect the navigation and contributed text supplied
/// through [ExplorerActionsViewModel].
///
/// The widget occupies one terminal row.
///
/// Example:
/// ```dart
/// final widget = ExplorerActions(actions_view_model);
///
/// final lines = widget.build(constraints);
/// ```
final class ExplorerActions implements TerminalWidget {
  /// Creates the action-instruction widget.
  ///
  /// [view_model] supplies navigation state and action visibility.
  const ExplorerActions(this.view_model);

  /// Presentation state for the current keyboard instructions.
  final ExplorerActionsViewModel view_model;

  /// Number of terminal rows occupied by the instructions.
  static const int fixed_rows = 1;

  /// Returns the fixed instruction-row height.
  @override
  int get height => fixed_rows;

  /// Builds the visible keyboard instructions.
  ///
  /// [constraints] contains the terminal layout constraints.
  /// Text fitting and sanitization are handled by the renderer.
  ///
  /// Returns one terminal line.
  @override
  Iterable<TerminalLine> build(TerminalConstraints constraints) sync* {
    if (view_model.explorer.is_closed) {
      yield const TerminalLine('Explorer closed.', role: TerminalRole.muted);
      return;
    }

    final instructions = [
      'Up/Down Select  Enter Open  Left/Backspace Back',
      ...view_model.instructions,
      'Q Quit',
    ];

    yield TerminalLine(instructions.join('  '), role: TerminalRole.muted);
  }
}
