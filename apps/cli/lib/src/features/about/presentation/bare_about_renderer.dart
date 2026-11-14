import '../../../core/rendering/bare/ansi_text.dart';
import '../../../core/rendering/bare/bare_widget_renderer.dart';
import '../../../core/rendering/renderer.dart';
import '../../../core/rendering/theme.dart';

import 'about_view_model.dart';
import 'widgets/about_screen.dart';

/// Renders About through Rudra's shared bare terminal backend.
///
/// Feature layout is owned by [AboutScreen].
///
/// The [BareWidgetRenderer] handles:
/// - Text sanitization.
/// - Semantic theme styling.
/// - Optional ANSI encoding.
/// - Unbounded non-interactive output.
/// - Widget height validation.
///
/// This adapter contains no application formatting logic.
/// It does not access SDK services, read filesystem content,
/// or manage terminal modes.
///
/// Example:
/// ```dart
/// final renderer = BareAboutRenderer(
///   output: stdout,
/// );
///
/// renderer.render(about_view_model);
/// ```
final class BareAboutRenderer implements Renderer<AboutViewModel> {
  /// Creates a bare About renderer.
  ///
  /// [output] is selected by the application composition boundary.
  ///
  /// [theme] and [ansi_text] control optional styling.
  /// Output is unbounded by default.
  ///
  /// Construction performs no terminal I/O.
  BareAboutRenderer({
    required StringSink output,
    TerminalTheme? theme,
    AnsiText ansi_text = const AnsiText(),
  }) : _backend = BareWidgetRenderer(
          output: output,
          theme: theme,
          ansi_text: ansi_text,
        );

  /// Shared backend responsible for final output encoding.
  final BareWidgetRenderer _backend;

  /// Renders one complete About presentation snapshot.
  ///
  /// Layout and encoding errors propagate to the caller.
  ///
  /// No filesystem or terminal lifecycle operations occur.
  @override
  void render(AboutViewModel view_model) {
    _backend.render(
      AboutScreen(view_model),
    );
  }
}
