
import '../../core/rendering/bare/ansi_text.dart';
import '../../core/rendering/bare/bare_widget_renderer.dart';
import '../../core/rendering/renderer.dart';
import '../../core/rendering/theme.dart';

import 'presentation/widgets/directory_listing/directory_listing_view_model.dart';
import 'presentation/widgets/directory_inspection_issues/directory_inspection_issues_widget.dart';
import 'presentation/widgets/directory_listing/directory_listing_widget.dart';

/// Bare rendering adapter for filesystem directory observations.
///
/// This class connects the existing backend-independent
/// [Renderer] contract to Rudra's shared widget renderer.
///
/// Directory layout belongs to [DirectoryListingWidget].
/// Diagnostic layout belongs to [DirectoryInspectionIssuesWidget].
///
/// Both widgets are independently composable by other CLI
/// features, including Welcome.
///
/// The renderer uses unbounded output by default, ensuring that
/// filesystem paths and diagnostic information are not silently
/// truncated by terminal-width assumptions.
///
/// Optional ANSI styling is delegated to [BareWidgetRenderer].
///
/// The renderer does not:
/// - Call SDK services or filesystem adapters.
/// - Format filesystem domain metadata.
/// - Implement application navigation or workflow behavior.
/// - Modify or authorize filesystem operations.
///
/// Example:
/// ```dart
/// final renderer = BareFilesystemRenderer(
///   output: stdout,
///   error_output: stderr,
/// );
///
/// renderer.render(listing_view_model);
/// ```
final class BareFilesystemRenderer
    implements Renderer<DirectoryListingViewModel> {
  /// Creates a directory-listing rendering adapter.
  ///
  /// [output] receives the listing presentation.
  ///
  /// [error_output], when provided, receives typed inspection
  /// diagnostics using the same theme and ANSI configuration.
  ///
  /// Output is unbounded to preserve meaningful directory data.
  ///
  /// Construction performs no terminal or filesystem I/O.
  BareFilesystemRenderer({
    required StringSink output,
    StringSink? error_output,
    TerminalTheme? theme,
    AnsiText ansi_text = const AnsiText(),
  })  : _listing_renderer = BareWidgetRenderer(
          output: output,
          theme: theme,
          ansi_text: ansi_text,
        ),
        _error_output = error_output,
        _theme = theme ?? TerminalTheme.plain,
        _ansi_text = ansi_text;

  /// Generic rendering backend used for listing content.
  final BareWidgetRenderer _listing_renderer;

  /// Optional destination for inspection diagnostics.
  final StringSink? _error_output;

  /// Semantic style configuration for diagnostic rendering.
  final TerminalTheme _theme;

  /// ANSI encoder shared with diagnostic rendering.
  final AnsiText _ansi_text;

  /// Renders one directory listing and its optional diagnostics.
  ///
  /// Directory data is passed to the reusable listing widget.
  ///
  /// If a diagnostic sink is configured, inspection issues are
  /// rendered separately after the listing completes.
  ///
  /// An incomplete listing without typed issues still produces
  /// an explicit fallback diagnostic.
  ///
  /// Rendering performs no SDK or filesystem operations.
  @override
  void render(DirectoryListingViewModel view_model) {
    _listing_renderer.render(
      DirectoryListingWidget(view_model),
    );

    final error_output = _error_output;

    if (error_output != null) {
      render_issues(
        view_model,
        output: error_output,
      );
    }
  }

  /// Renders inspection diagnostics to an explicit output sink.
  ///
  /// This method is useful when the caller wants diagnostics
  /// independently of directory contents.
  ///
  /// Formatting is delegated to the composable diagnostic
  /// widget rather than duplicated in this renderer.
  ///
  /// Complete observations without issues produce no output.
  ///
  /// Untrusted diagnostic text is sanitized before encoding.
  void render_issues(
    DirectoryListingViewModel view_model, {
    required StringSink output,
  }) {
    final renderer = BareWidgetRenderer(
      output: output,
      theme: _theme,
      ansi_text: _ansi_text,
    );

    renderer.render(
      DirectoryInspectionIssuesWidget(view_model),
    );
  }
}
