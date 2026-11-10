import '../../presentation/filesystem/directory_listing_view_model.dart';
import '../renderer.dart';
import '../terminal_text.dart';
import '../theme.dart';
import 'ansi_text.dart';

/// Renders filesystem view models using Rudra's bare backend.
///
/// Supports the existing compact and detailed directory layouts.
///
/// This renderer owns:
/// - Terminal column alignment.
/// - Table headers and separators.
/// - Semantic text styling.
/// - Incomplete-inspection notices.
/// - Inspection diagnostic output.
///
/// It receives presentation-ready data and never calls the SDK.
///
/// Compact listings preserve their established plain-text
/// format, regardless of the configured theme.
///
/// Detailed listings may use ANSI styling when explicitly
/// enabled through the injected [AnsiText].
///
/// No terminal modes are changed and no filesystem operations
/// are performed.
///
/// Example:
/// ```dart
/// final renderer = BareFilesystemRenderer(
///   output: stdout,
///   error_output: stderr,
/// );
///
/// renderer.render(view_model);
/// ```
final class BareFilesystemRenderer
    implements Renderer<DirectoryListingViewModel> {
  /// Creates a bare filesystem listing renderer.
  ///
  /// [output] receives listing content.
  ///
  /// [error_output], when supplied, receives inspection
  /// diagnostics during [render].
  ///
  /// [theme] controls semantic appearance.
  ///
  /// [ansi_text] encodes optional terminal styling.
  /// ANSI output is disabled by default.
  ///
  /// Construction performs no terminal or filesystem I/O.
  BareFilesystemRenderer({
    required StringSink output,
    StringSink? error_output,
    TerminalTheme? theme,
    AnsiText ansi_text = const AnsiText(),
  })  : _output = output,
        _error_output = error_output,
        _theme = theme ?? TerminalTheme.plain,
        _ansi_text = ansi_text;

  /// Destination for listing presentation.
  final StringSink _output;

  /// Optional destination for inspection diagnostics.
  final StringSink? _error_output;

  /// Semantic styling configuration.
  final TerminalTheme _theme;

  /// Bare-backend ANSI encoder.
  final AnsiText _ansi_text;

  /// Renders the requested directory presentation layout.
  ///
  /// Compact output preserves SDK observation ordering
  /// and the established column names.
  ///
  /// Detailed output uses the ordering prepared by the
  /// presenter and displays observed filesystem metadata.
  ///
  /// Inspection issues are written only when an error
  /// output sink was supplied.
  ///
  /// Errors from output sinks propagate to the caller.
  /// Terminal lifecycle cleanup belongs to the terminal host.
  ///
  /// This method does not inspect or modify the filesystem.
  @override
  void render(DirectoryListingViewModel view_model) {
    if (view_model.layout == DirectoryListingLayout.compact) {
      _render_compact(view_model);
    } else {
      _render_detailed(view_model);
    }

    final error_output = _error_output;

    if (error_output != null) {
      render_issues(
        view_model,
        output: error_output,
      );
    }
  }

  /// Renders the original compact filesystem layout.
  ///
  /// Compact output intentionally remains unstyled.
  /// It must be suitable for redirected output and scripts.
  ///
  /// The row order comes directly from the presenter.
  void _render_compact(DirectoryListingViewModel view_model) {
    const type_header = 'TYPE';
    const size_header = 'LOGICAL_BYTES';
    const path_header = 'PATH';
    const spacing = '  ';

    final type_width = view_model.rows.fold<int>(
      type_header.length,
      (width, row) {
        final length = TerminalText.estimated_columns(
          row.compact_type,
        );

        return length > width ? length : width;
      },
    );

    final size_width = view_model.rows.fold<int>(
      size_header.length,
      (width, row) {
        final length = TerminalText.estimated_columns(
          row.logical_bytes,
        );

        return length > width ? length : width;
      },
    );

    _output.writeln(
      '${TerminalText.pad_right(type_header, min_columns: type_width)}'
      '$spacing'
      '${TerminalText.pad_left(size_header, min_columns: size_width)}'
      '$spacing'
      '$path_header',
    );

    for (final row in view_model.rows) {
      _output.writeln(
        '${TerminalText.pad_right(row.compact_type, min_columns: type_width)}'
        '$spacing'
        '${TerminalText.pad_left(row.logical_bytes, min_columns: size_width)}'
        '$spacing'
        '${TerminalText.sanitize(row.path)}',
      );
    }
  }

  /// Renders a detailed, human-readable filesystem listing.
  ///
  /// Directory sizes are already marked as unavailable by
  /// the presenter. No recursive size calculation occurs.
  ///
  /// Column widths account for estimated Unicode display
  /// widths rather than Dart string lengths.
  ///
  /// Styling is applied only after text has been padded.
  void _render_detailed(
    DirectoryListingViewModel view_model,
  ) {
    const name_header = 'NAME';
    const type_header = 'TYPE';
    const size_header = 'SIZE';
    const permissions_header = 'PERMISSIONS';

    final name_width = view_model.rows.fold<int>(
      name_header.length,
      (width, row) {
        final length = TerminalText.estimated_columns(
          row.name,
        );

        return length > width ? length : width;
      },
    );

    _output.writeln(
      '  ${_style(
        TerminalText.pad_right(name_header, min_columns: name_width),
        TerminalRole.heading,
      )}  '
      '${_style(
        type_header.padRight(9),
        TerminalRole.heading,
      )}  '
      '${_style(
        size_header.padLeft(9),
        TerminalRole.heading,
      )}  '
      '${_style(
        permissions_header.padRight(11),
        TerminalRole.heading,
      )}  '
      '${_style('MODIFIED (UTC)', TerminalRole.heading)}',
    );

    _output.writeln(
      '  ${''.padRight(name_width, '─')}  '
      '${''.padRight(9, '─')}  '
      '${''.padRight(9, '─')}  '
      '${''.padRight(11, '─')}  '
      '${''.padRight(16, '─')}',
    );

    for (final row in view_model.rows) {
      final name = TerminalText.pad_right(
        row.name,
        min_columns: name_width,
      );

      _output.writeln(
        '  ${_style(name, row.role)}  '
        '${TerminalText.pad_right(row.type_label, min_columns: 9)}  '
        '${TerminalText.pad_left(row.size_label, min_columns: 9)}  '
        '${TerminalText.pad_right(row.permissions, min_columns: 11)}  '
        '${TerminalText.sanitize(row.modified_utc)}',
      );
    }

    _output.writeln();

    _output.writeln(
      '  ${view_model.observed_count} observed entries'
      ' · immediate children only',
    );

    if (view_model.is_incomplete) {
      _output.writeln(
        _style(
          '  WARNING: This directory listing is incomplete.',
          TerminalRole.warning,
        ),
      );
    }
  }

  /// Renders typed inspection issues to a supplied destination.
  ///
  /// This method is public so existing CLI presentation
  /// adapters can render diagnostics independently from
  /// directory content during the migration.
  ///
  /// It preserves the established diagnostic field order:
  /// operation, code, path, message.
  ///
  /// All diagnostic text is sanitized before terminal output.
  ///
  /// An incomplete result without issues produces an explicit
  /// fallback diagnostic rather than appearing successful.
  ///
  /// No SDK operations or filesystem mutations occur.
  void render_issues(
    DirectoryListingViewModel view_model, {
    required StringSink output,
  }) {
    for (final issue in view_model.issues) {
      output.writeln(
        _style(
          '${issue.operation}: '
          '${issue.code}: '
          '${issue.path}: '
          '${issue.message}',
          TerminalRole.error,
        ),
      );
    }

    if (view_model.is_incomplete && view_model.issues.isEmpty) {
      output.writeln(
        _style(
          'Filesystem inspection did not complete.',
          TerminalRole.error,
        ),
      );
    }
  }

  /// Applies semantic styling through the bare ANSI encoder.
  ///
  /// The encoder sanitizes text before inserting any ANSI
  /// escape sequences.
  ///
  /// Plain themes and disabled ANSI encoders produce safe
  /// unstyled output.
  String _style(
    String value,
    TerminalRole role,
  ) {
    return _ansi_text.format(
      value,
      style: _theme.style_for(role),
    );
  }
}
