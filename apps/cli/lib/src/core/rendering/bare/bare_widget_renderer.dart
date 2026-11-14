import '../terminal_text.dart';
import '../theme.dart';
import '../widgets/terminal_widget.dart';
import 'ansi_text.dart';

/// Renders composable terminal widgets using plain or ANSI text.
///
/// Feature-specific renderers supply widget trees. This shared
/// backend owns their final text encoding and output.
///
/// When [terminal_columns] is provided, the output is bounded
/// to the current terminal display width.
///
/// When omitted, output is unbounded. This is appropriate for
/// non-interactive commands and avoids truncating filenames,
/// paths, diagnostics, or other meaningful data.
///
/// Both modes sanitize untrusted display text before applying
/// any trusted ANSI styling.
///
/// The backend validates each widget tree's declared height
/// before writing the completed frame.
///
/// It does not:
/// - Read filesystem content or invoke SDK services.
/// - Modify presentation models.
/// - Handle input or application navigation.
/// - Manage terminal modes or lifecycle.
///
/// Example:
/// ```dart
/// final renderer = BareWidgetRenderer(
///   output: stdout,
/// );
///
/// renderer.render(
///   const TerminalLabel('RUDRA'),
/// );
/// ```
final class BareWidgetRenderer {
  /// Creates a shared bare terminal rendering backend.
  ///
  /// [terminal_columns] is optional.
  ///
  /// When supplied, it is evaluated on every render.
  /// Omitting it enables unbounded non-interactive output.
  ///
  /// [theme] maps semantic roles to styles.
  /// [ansi_text] controls trusted ANSI encoding.
  ///
  /// [redraw_screen] requires enabled ANSI output and must
  /// only be used in a suitable terminal-hosting context.
  ///
  /// Construction performs no terminal I/O.
  BareWidgetRenderer({
    required StringSink output,
    int Function()? terminal_columns,
    TerminalTheme? theme,
    AnsiText ansi_text = const AnsiText(),
    bool redraw_screen = false,
  }) : _output = output,
       _terminal_columns = terminal_columns,
       _theme = theme ?? TerminalTheme.plain,
       _ansi_text = ansi_text,
       _redraw_screen = redraw_screen {
    if (redraw_screen && !ansi_text.enabled) {
      throw ArgumentError('Screen redrawing requires ANSI-enabled output.');
    }
  }

  /// Destination for completed frames.
  final StringSink _output;

  /// Optional terminal width provider.
  final int Function()? _terminal_columns;

  /// Semantic styling configuration.
  final TerminalTheme _theme;

  /// Trusted ANSI styling encoder.
  final AnsiText _ansi_text;

  /// Whether a trusted screen redraw precedes each frame.
  final bool _redraw_screen;

  /// Renders one complete composable widget tree.
  ///
  /// The tree is built before any output is written.
  ///
  /// Each widget must produce exactly its declared height.
  /// Incorrect heights fail with [StateError].
  ///
  /// A bounded output is sanitized and truncated.
  /// An unbounded output is sanitized without truncation.
  ///
  /// Styling is applied after sanitization.
  ///
  /// Errors propagate to the caller. Terminal restoration
  /// remains the hosting application's responsibility.
  void render(TerminalWidget widget) {
    final constraints = TerminalConstraints(columns: _terminal_columns?.call());

    final expected_height = widget.height;

    if (expected_height < 0) {
      throw StateError('A widget cannot declare negative height.');
    }

    final frame = StringBuffer();

    if (_redraw_screen) {
      // Trusted renderer-owned terminal control sequence.
      frame.write('\x1B[H\x1B[2J');
    }

    var actual_height = 0;

    for (final line in widget.build(constraints)) {
      actual_height++;

      if (actual_height > expected_height) {
        throw StateError('The widget tree produced more rows than declared.');
      }

      final columns = constraints.columns;

      final safe_text = columns == null
          ? TerminalText.sanitize(line.text)
          : TerminalText.truncate(line.text, max_columns: columns);

      frame.writeln(
        _ansi_text.format(safe_text, style: _theme.style_for(line.role)),
      );
    }

    if (actual_height != expected_height) {
      throw StateError('The widget tree produced fewer rows than declared.');
    }

    // Layout and encoding finish before output begins.
    _output.write(frame.toString());
  }
}
