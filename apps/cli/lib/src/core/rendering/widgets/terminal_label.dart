import '../theme.dart';
import 'terminal_widget.dart';

/// A single line of semantically styled terminal text.
///
/// This widget does not wrap its content. The rendering backend
/// sanitizes and truncates text to the available display width.
///
/// Example:
/// ```dart
/// final title = TerminalLabel(
///   'RUDRA / EXPLORER',
///   role: TerminalRole.title,
/// );
/// ```
final class TerminalLabel implements TerminalWidget {
  /// Creates an immutable single-line text widget.
  const TerminalLabel(this.text, {this.role = TerminalRole.text});

  /// Text to display.
  final String text;

  /// Semantic text role.
  final TerminalRole role;

  @override
  int get height => 1;

  @override
  Iterable<TerminalLine> build(TerminalConstraints constraints) sync* {
    yield TerminalLine(text, role: role);
  }
}
