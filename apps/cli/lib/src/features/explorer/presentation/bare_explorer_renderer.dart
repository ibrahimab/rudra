import '../../../core/rendering/bare/ansi_text.dart';
import '../../../core/rendering/bare/bare_widget_renderer.dart';
import '../../../core/rendering/renderer.dart';
import '../../../core/rendering/theme.dart';

import 'explorer_view_model.dart';
import 'widgets/explorer_screen.dart';

/// Renders the composable Explorer screen using the bare backend.
///
/// This class adapts an [ExplorerViewModel] to an [ExplorerScreen]
/// and delegates terminal encoding to [BareWidgetRenderer].
///
/// Feature layout belongs to the composed widgets.
/// Text sanitization, truncation, semantic styling, and output
/// encoding belong to the shared bare rendering backend.
///
/// The renderer implements [ViewportRenderer] so the interactive
/// runner can reserve precisely the rows used by fixed widgets.
///
/// No filesystem access, navigation, SDK calls, or terminal
/// lifecycle operations occur here.
///
/// Example:
/// ```dart
/// final renderer = BareExplorerRenderer(
///   output: stdout,
///   terminal_columns: () => stdout.terminalColumns,
///   theme: TerminalTheme.ansi,
///   ansi_text: const AnsiText(enabled: true),
///   redraw_screen: true,
/// );
///
/// renderer.render(view_model);
/// ```
final class BareExplorerRenderer
    implements ViewportRenderer<ExplorerViewModel> {
  /// Creates a bare Explorer renderer.
  ///
  /// The shared backend validates ANSI redraw configuration.
  ///
  /// [terminal_columns] is evaluated on every render.
  /// No terminal I/O occurs during construction.
  BareExplorerRenderer({
    required StringSink output,
    required int Function() terminal_columns,
    TerminalTheme? theme,
    AnsiText ansi_text = const AnsiText(),
    bool redraw_screen = false,
  }) : _backend = BareWidgetRenderer(
          output: output,
          terminal_columns: terminal_columns,
          theme: theme,
          ansi_text: ansi_text,
          redraw_screen: redraw_screen,
        );

  /// Shared backend responsible for terminal output encoding.
  final BareWidgetRenderer _backend;

  @override
  int get fixed_rows => ExplorerScreen.fixed_rows;

  /// Builds and renders one complete Explorer screen.
  ///
  /// The screen composition is rebuilt on every render so
  /// navigation changes and terminal resizing are reflected.
  ///
  /// Errors from layout or output propagate to the runner,
  /// whose terminal host owns restoration.
  @override
  void render(ExplorerViewModel view_model) {
    _backend.render(
      ExplorerScreen(view_model),
    );
  }
}
