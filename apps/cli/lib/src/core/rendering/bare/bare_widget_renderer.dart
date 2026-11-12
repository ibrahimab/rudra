import '../terminal_text.dart';
import '../theme.dart';
import '../widgets/terminal_widget.dart';
import 'ansi_text.dart';

/// Renders any composable terminal widget tree using plain or ANSI text.
///
/// Feature-specific renderers construct widget trees and delegate
/// the actual output encoding to this shared backend.
///
/// The backend owns:
/// - Terminal width acquisition.
/// - Text sanitization and truncation.
/// - Semantic theme application.
/// - Optional trusted screen redraw sequences.
/// - Validation of widget height contracts.
/// - Writing the completed frame.
///
/// The widget tree is built completely before any frame content
/// reaches the output sink.
///
/// This renderer does not own terminal input, screen lifecycle,
/// application state, navigation, or SDK services.
///
/// Example:
/// ```dart
/// final renderer = BareWidgetRenderer(
///   output: stdout,
///   terminal_columns: () => stdout.terminalColumns,
/// );
///
/// renderer.render(
///   TerminalColumn(
///     children: [
///       TerminalLabel('RUDRA'),
///       TerminalLabel('Ready'),
///     ],
///   ),
/// );
/// ```
final class BareWidgetRenderer {
  /// Creates a backend for rendering composable widgets.
  ///
  /// [terminal_columns] is evaluated on every render.
  ///
  /// When [redraw_screen] is true, ANSI output must be enabled.
  ///
  /// Construction does not perform terminal I/O.
  BareWidgetRenderer({
    required StringSink output,
    required int Function() terminal_columns,
    TerminalTheme? theme,
    AnsiText ansi_text = const AnsiText(),
    bool redraw_screen = false,
  })  : _output = output,
        _terminal_columns = terminal_columns,
        _theme = theme ?? TerminalTheme.plain,
        _ansi_text = ansi_text,
        _redraw_screen = redraw_screen {
    if (redraw_screen && !ansi_text.enabled) {
      throw ArgumentError(
        'Screen redrawing requires ANSI-enabled output.',
      );
    }
  }

  /// Output destination for completed frames.
  final StringSink _output;

  /// Current terminal width provider.
  final int Function() _terminal_columns;

  /// Semantic styling configuration.
  final TerminalTheme _theme;

  /// Backend-specific ANSI text encoder.
  final AnsiText _ansi_text;

  /// Whether a trusted screen-clear sequence precedes each frame.
  final bool _redraw_screen;

  /// Renders one complete widget tree.
  ///
  /// Each widget must produce exactly its declared height.
  ///
  /// Malformed layouts raise [StateError] before writing output.
  ///
  /// Unsafe text is sanitized before ANSI styling is applied.
  /// No widget-provided escape sequence is interpreted.
  ///
  /// Output sink failures propagate to the caller.
  ///
  /// The terminal host remains responsible for restoring
  /// terminal modes if rendering fails.
  void render(TerminalWidget widget) {
    final constraints = TerminalConstraints(
      columns: _terminal_columns(),
    );

    final expected_height = widget.height;

    if (expected_height < 0) {
      throw StateError('A widget cannot declare negative height.');
    }

    final frame = StringBuffer();

    if (_redraw_screen) {
      frame.write('\x1B[H\x1B[2J');
    }

    var actual_height = 0;

    for (final line in widget.build(constraints)) {
      actual_height++;

      if (actual_height > expected_height) {
        throw StateError(
          'The widget tree produced more rows than declared.',
        );
      }

      final safe_text = TerminalText.truncate(
        line.text,
        max_columns: constraints.columns,
      );

      frame.writeln(
        _ansi_text.format(
          safe_text,
          style: _theme.style_for(line.role),
        ),
      );
    }

    if (actual_height != expected_height) {
      throw StateError(
        'The widget tree produced fewer rows than declared.',
      );
    }

    _output.write(frame.toString());
  }
}
