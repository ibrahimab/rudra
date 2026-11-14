import '../../../core/rendering/bare/ansi_text.dart';
import '../../../core/rendering/bare/bare_widget_renderer.dart';
import '../../../core/rendering/renderer.dart';
import '../../../core/rendering/theme.dart';

import 'filesystem_view_model.dart';
import 'widgets/directory_inspection_issues/directory_inspection_issues_widget.dart';
import 'widgets/directory_listing/directory_listing_widget.dart';

/// Bare rendering adapter for a complete filesystem presentation.
///
/// Consumes [FilesystemViewModel] through the generic Renderer contract.
///
/// The model contains two independently composable components:
/// - [DirectoryListingWidget] renders observed directory entries.
/// - [DirectoryInspectionIssuesWidget] renders typed diagnostics.
///
/// The directory listing is written to the configured output sink.
/// Diagnostics are written to the optional error sink.
///
/// Both components delegate terminal encoding to [BareWidgetRenderer].
/// Unbounded output preserves full paths, filenames, and diagnostics.
///
/// This adapter performs no SDK requests, filesystem mutations,
/// navigation operations, or cleanup authorization.
///
/// Example:
/// ```dart
/// final renderer = BareFilesystemRenderer(
///   output: stdout,
///   error_output: stderr,
/// );
///
/// renderer.render(filesystem_view_model);
/// ```
final class BareFilesystemRenderer implements Renderer<FilesystemViewModel> {
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

  /// Renders the two independently prepared components.
  ///
  /// The listing is sent to the presentation destination.
  /// Diagnostics are sent to the optional diagnostic sink.
  ///
  /// No SDK calls or filesystem mutations occur.
  @override
  void render(FilesystemViewModel view_model) {
    _listing_renderer.render(
      DirectoryListingWidget(view_model.listing),
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
    FilesystemViewModel view_model, {
    required StringSink output,
  }) {
    final renderer = BareWidgetRenderer(
      output: output,
      theme: _theme,
      ansi_text: _ansi_text,
    );

    renderer.render(
      DirectoryInspectionIssuesWidget(
        view_model.inspection_issues,
      ),
    );
  }
}
