import '../../../core/rendering/bare/ansi_text.dart';
import '../../../core/rendering/bare/bare_widget_renderer.dart';
import '../../../core/rendering/renderer.dart';
import '../../../core/rendering/theme.dart';

import '../../filesystem/presentation/widgets/directory_inspection_issues/directory_inspection_issues_widget.dart';

import 'welcome_view_model.dart';
import 'widgets/welcome_screen.dart';

/// Renders the composable Welcome screen through the bare backend.
///
/// Main screen layout belongs to [WelcomeScreen].
///
/// Filesystem diagnostics are rendered separately using
/// [DirectoryInspectionIssuesWidget], allowing the application
/// to direct them to stderr without coupling the widget to an
/// output stream.
///
/// The shared [BareWidgetRenderer] owns:
/// - Untrusted text sanitization.
/// - Optional ANSI styling.
/// - Unbounded non-interactive output.
/// - Widget height validation.
/// - Final text encoding.
///
/// There is no nested filesystem renderer or feature-specific
/// line-writing implementation.
///
/// The renderer does not access SDK services, modify filesystem
/// state, handle input, or manage terminal lifecycle.
///
/// Example:
/// ```dart
/// final renderer = BareWelcomeRenderer(
///   output: stdout,
///   error_output: stderr,
/// );
///
/// renderer.render(welcome_view_model);
/// ```
final class BareWelcomeRenderer implements Renderer<WelcomeViewModel> {
  /// Creates rendering adapters for Welcome and optional diagnostics.
  ///
  /// [output] receives the full Welcome screen.
  ///
  /// [error_output], when provided, receives typed inspection
  /// diagnostics through an independent widget renderer.
  ///
  /// Both destinations use the same semantic theme and ANSI
  /// configuration. Output is unbounded by default.
  ///
  /// Construction performs no terminal I/O or filesystem access.
  BareWelcomeRenderer({
    required StringSink output,
    StringSink? error_output,
    TerminalTheme? theme,
    AnsiText ansi_text = const AnsiText(),
  })  : _screen_renderer = BareWidgetRenderer(
          output: output,
          theme: theme,
          ansi_text: ansi_text,
        ),
        _diagnostic_renderer = error_output == null
            ? null
            : BareWidgetRenderer(
                output: error_output,
                theme: theme,
                ansi_text: ansi_text,
              );

  /// Shared backend for the composed Welcome screen.
  final BareWidgetRenderer _screen_renderer;

  /// Optional independent diagnostics rendering backend.
  final BareWidgetRenderer? _diagnostic_renderer;

  /// Renders the Welcome screen and available inspection issues.
  ///
  /// Main output is emitted as one complete widget frame.
  ///
  /// When a filesystem observation exists, diagnostic data is
  /// delivered to the optional error sink after screen rendering.
  ///
  /// Incomplete observations remain visibly incomplete even
  /// when no diagnostic output sink is configured.
  ///
  /// Rendering exceptions propagate to the caller.
  @override
  void render(WelcomeViewModel view_model) {
    _screen_renderer.render(
      WelcomeScreen(view_model),
    );

    final diagnostics = view_model.filesystem?.inspection_issues;
    final renderer = _diagnostic_renderer;

    if (diagnostics != null && renderer != null) {
      renderer.render(
        DirectoryInspectionIssuesWidget(diagnostics),
      );
    }
  }
}
