import '../../core/rendering/bare/ansi_text.dart';
import '../../core/rendering/renderer.dart';
import '../../core/rendering/theme.dart';

import '../filesystem/presentation/bare_filesystem_renderer.dart';

import 'welcome_view_model.dart';

/// Renders Rudra's welcome screen using the bare CLI backend.
///
/// The renderer consumes an immutable [WelcomeViewModel]
/// prepared by the welcome presenter.
///
/// It owns the layout of the welcome screen, including:
/// - Application title and read-only notice.
/// - Configured filesystem target information.
/// - Optional detailed directory listing.
/// - Available CLI commands.
/// - Safety information.
///
/// Nested filesystem presentation is delegated to
/// [BareFilesystemRenderer].
///
/// Both renderers use the same theme and ANSI encoder.
///
/// The renderer does not:
/// - Access Rudra SDK services.
/// - Inspect or modify the filesystem.
/// - Manage application navigation.
/// - Change terminal input or output modes.
/// - Create sessions or authorize cleanup.
///
/// Plain output preserves the established welcome-screen format.
///
/// ANSI styling is optional and must be enabled explicitly
/// by the application composition or terminal hosting layer.
///
/// Example:
/// ```dart
/// final renderer = BareWelcomeRenderer(
///   output: stdout,
///   error_output: stderr,
/// );
///
/// renderer.render(view_model);
/// ```
final class BareWelcomeRenderer implements Renderer<WelcomeViewModel> {
  /// Creates a bare welcome-screen renderer.
  ///
  /// [output] receives the main presentation.
  ///
  /// [error_output], when provided, receives nested filesystem
  /// inspection diagnostics.
  ///
  /// [theme] defines semantic presentation styles.
  /// The plain theme is used by default.
  ///
  /// [ansi_text] translates styles into ANSI sequences when
  /// explicitly enabled. ANSI output is disabled by default.
  ///
  /// The same theme and encoder are passed to the nested
  /// filesystem renderer.
  ///
  /// Construction performs no terminal or filesystem I/O.
  BareWelcomeRenderer({
    required StringSink output,
    StringSink? error_output,
    TerminalTheme? theme,
    AnsiText ansi_text = const AnsiText(),
  })  : _output = output,
        _error_output = error_output,
        _theme = theme ?? TerminalTheme.plain,
        _ansi_text = ansi_text;

  /// Destination for welcome-screen output.
  final StringSink _output;

  /// Optional destination for inspection diagnostics.
  final StringSink? _error_output;

  /// Shared semantic styling configuration.
  final TerminalTheme _theme;

  /// Shared bare-backend text encoder.
  final AnsiText _ansi_text;

  /// Renders a complete welcome-screen presentation.
  ///
  /// The output structure preserves the existing welcome
  /// layout when using the plain theme:
  ///
  /// - Blank line.
  /// - Application title and read-only notice.
  /// - Short application description.
  /// - Configured target information when available.
  /// - Optional detailed filesystem listing.
  /// - Available commands.
  /// - Filesystem safety information.
  ///
  /// When no target is configured, the renderer displays the
  /// existing unsupported-target message and omits filesystem
  /// commands.
  ///
  /// Nested directory listings may be incomplete.
  /// Warnings and typed issues are preserved through the
  /// shared filesystem renderer.
  ///
  /// Output sink exceptions propagate to the caller.
  /// Terminal lifecycle restoration is the caller's
  /// responsibility.
  ///
  /// This method never inspects or modifies the filesystem.
  @override
  void render(WelcomeViewModel view_model) {
    _output.writeln();

    _write_line(
      '${view_model.product_title}  |  READ ONLY',
      role: TerminalRole.title,
    );

    _write_line(
      'Read-only filesystem exploration.',
    );

    _output.writeln();

    if (view_model.can_inspect) {
      _render_target(view_model);
    } else {
      _render_unsupported_target();
    }

    _render_available_commands(view_model);

    _output.writeln();

    _write_line(
      'Inspection never authorizes '
      'file modification or deletion.',
      role: TerminalRole.muted,
    );
  }

  /// Renders configured filesystem target information.
  ///
  /// A target configured in [WelcomeViewModel] always
  /// includes its starting directory.
  ///
  /// When a listing is available, it is delegated to the
  /// shared filesystem renderer rather than formatted here.
  ///
  /// The view model is already validated, so this method
  /// does not perform another filesystem inspection.
  void _render_target(WelcomeViewModel view_model) {
    _write_line(
      'Target: ${view_model.target_id}',
    );

    _write_line(
      'Starting directory: ${view_model.starting_directory}',
      role: TerminalRole.path,
    );

    _output.writeln();

    final listing = view_model.listing;

    if (listing == null) {
      return;
    }

    // The filesystem template owns its own table layout,
    // metadata formatting, warnings, and diagnostics.
    //
    // No second SDK listing request occurs.
    final filesystem_renderer = BareFilesystemRenderer(
      output: _output,
      error_output: _error_output,
      theme: _theme,
      ansi_text: _ansi_text,
    );

    filesystem_renderer.render(listing);

    // Preserve the blank line separating the existing
    // detailed listing from the available command section.
    _output.writeln();
  }

  /// Renders the established unsupported-target message.
  ///
  /// The absence of a configured target does not imply
  /// that a filesystem inspection was attempted.
  void _render_unsupported_target() {
    _write_line(
      'Filesystem inspection is not available '
      'for the current target.',
      role: TerminalRole.warning,
    );

    _output.writeln();
  }

  /// Renders the commands available from the welcome screen.
  ///
  /// Filesystem listing commands are shown only when an
  /// inspection target is configured.
  ///
  /// This template preserves the existing command examples.
  ///
  /// Command registration and availability are still owned
  /// by RudraCli rather than by this renderer.
  void _render_available_commands(
    WelcomeViewModel view_model,
  ) {
    _write_line(
      'Available commands:',
      role: TerminalRole.heading,
    );

    if (view_model.can_inspect) {
      _write_line(
        '  rudra ls                  '
        'Inspect the starting directory',
      );

      _write_line(
        '  rudra ls /absolute/path   '
        'Inspect another directory',
      );
    }

    _write_line(
      '  rudra about               '
      'Show application information',
    );

    _write_line(
      '  rudra --help              '
      'Show available commands',
    );
  }

  /// Writes one sanitized and optionally styled text line.
  ///
  /// The semantic [role] is resolved through the injected
  /// theme before the bare ANSI encoder formats the text.
  ///
  /// Untrusted text is sanitized by [AnsiText] before any
  /// renderer-owned ANSI sequences are introduced.
  ///
  /// The method appends exactly one line terminator.
  void _write_line(
    String value, {
    TerminalRole role = TerminalRole.text,
  }) {
    final style = _theme.style_for(role);

    final formatted = _ansi_text.format(
      value,
      style: style,
    );

    _output.writeln(formatted);
  }
}
