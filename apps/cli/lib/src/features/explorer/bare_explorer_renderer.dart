import '../../core/rendering/bare/ansi_text.dart';
import '../../core/rendering/renderer.dart';
import '../../core/rendering/terminal_text.dart';
import '../../core/rendering/theme.dart';

import '../filesystem/directory_listing_view_model.dart';

import 'explorer_view_model.dart';

/// Renders interactive Explorer screens using the bare terminal backend.
///
/// The renderer consumes immutable [ExplorerViewModel] snapshots.
///
/// It owns:
/// - The Explorer screen layout.
/// - Display-column-aware truncation and alignment.
/// - Visible entry rows and selection highlighting.
/// - Inspection warnings and navigation instructions.
/// - Optional ANSI screen clearing before redrawing.
///
/// Terminal dimensions are obtained through an injected callback.
/// The callback is evaluated on every render, allowing a later
/// interactive runner to respond to terminal resizing.
///
/// All presentation text is sanitized before ANSI styling.
/// Filesystem names and diagnostic messages cannot introduce
/// terminal control sequences.
///
/// This renderer does not:
/// - Inspect or modify the filesystem.
/// - Decode keyboard input.
/// - Manage navigation state.
/// - Configure terminal input modes.
/// - Enter or leave the alternate screen.
/// - Change cursor visibility.
/// - Manage persistent sessions or cleanup operations.
///
/// Terminal lifecycle management belongs to [ExplorerTerminalHost]
/// and its eventual concrete implementation.
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
final class BareExplorerRenderer implements Renderer<ExplorerViewModel> {
  /// Creates an Explorer renderer with injected output dependencies.
  ///
  /// [output] receives the completed screen frame.
  ///
  /// [terminal_columns] supplies the current terminal width.
  /// It must return a nonnegative number of display columns.
  ///
  /// [theme] selects semantic presentation styles.
  /// The default theme produces plain text.
  ///
  /// [ansi_text] enables optional ANSI styling.
  /// Styling is disabled by default.
  ///
  /// [redraw_screen] adds a fixed, renderer-owned ANSI sequence
  /// that clears the screen and moves the cursor to its origin.
  ///
  /// Screen redrawing requires ANSI output to be enabled.
  ///
  /// Throws [ArgumentError] if screen redrawing is requested
  /// while ANSI output is disabled.
  ///
  /// Construction performs no terminal or filesystem I/O.
  BareExplorerRenderer({
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

  /// Destination for completed screen frames.
  final StringSink _output;

  /// Supplies the current terminal width.
  final int Function() _terminal_columns;

  /// Semantic terminal styling configuration.
  final TerminalTheme _theme;

  /// Safe ANSI text encoder.
  final AnsiText _ansi_text;

  /// Whether each frame clears the previous screen.
  final bool _redraw_screen;

  /// Width of the selection marker and following space.
  static const int _selection_columns = 2;

  /// Width allocated to the entry type column.
  static const int _type_columns = 9;

  /// Width allocated to the human-readable size column.
  static const int _size_columns = 9;

  /// Separation between detailed entry columns.
  static const int _column_spacing = 2;

  /// Minimum useful width of the entry-name column.
  static const int _minimum_name_columns = 8;

  /// Minimum terminal width for the detailed row layout.
  static const int _detailed_minimum_columns = _selection_columns +
      _type_columns +
      _size_columns +
      (_column_spacing * 2) +
      _minimum_name_columns;

  /// Renders one complete Explorer screen.
  ///
  /// The number of entry lines equals
  /// [ExplorerViewModel.visible_row_limit].
  ///
  /// Unused entry lines are left blank so the footer occupies
  /// a stable position as selection and navigation change.
  ///
  /// The screen contains:
  /// - Application title and read-only status.
  /// - Current directory.
  /// - Entry column headers.
  /// - Visible filesystem rows.
  /// - Observation and selection summary.
  /// - Inspection status or diagnostic information.
  /// - Keyboard navigation instructions.
  ///
  /// The terminal width is read once per frame.
  ///
  /// When the terminal is too narrow for detailed columns,
  /// only the entry names and selection markers are displayed.
  ///
  /// Zero-width terminals produce empty display lines.
  /// The terminal host determines whether interaction is viable.
  ///
  /// All untrusted text is sanitized and truncated before
  /// ANSI styling is applied.
  ///
  /// Throws [RangeError] if the width callback returns a
  /// negative value.
  ///
  /// Output sink failures propagate to the caller.
  /// Restoration of terminal state is the host's responsibility.
  ///
  /// This method performs no filesystem operations.
  @override
  void render(ExplorerViewModel view_model) {
    final columns = _terminal_columns();

    if (columns < 0) {
      throw RangeError.value(
        columns,
        'terminal_columns',
        'Terminal width cannot be negative.',
      );
    }

    final frame = StringBuffer();

    if (_redraw_screen) {
      // This is a trusted, fixed renderer control sequence.
      // Untrusted presentation strings never reach this path.
      frame.write('\x1B[H\x1B[2J');
    }

    _write_line(
      frame,
      'RUDRA / EXPLORER  |  READ ONLY',
      columns: columns,
      role: TerminalRole.title,
    );

    _write_line(
      frame,
      'Directory: ${view_model.current_directory}',
      columns: columns,
      role: TerminalRole.path,
    );

    _write_line(
      frame,
      _column_header(columns),
      columns: columns,
      role: TerminalRole.heading,
    );

    for (var index = 0; index < view_model.visible_row_limit; index++) {
      if (index < view_model.visible_rows.length) {
        final row = view_model.visible_rows[index];

        final is_selected = view_model.selected_visible_index == index;

        _write_line(
          frame,
          _entry_line(
            row,
            columns: columns,
            is_selected: is_selected,
          ),
          columns: columns,
          role: is_selected ? TerminalRole.selected : row.role,
        );
      } else if (index == 0 && view_model.total_entries == 0) {
        final message = view_model.is_empty
            ? '  (empty directory)'
            : '  (no entries observed; inspection incomplete)';

        _write_line(
          frame,
          message,
          columns: columns,
          role: TerminalRole.muted,
        );
      } else {
        _write_line(
          frame,
          '',
          columns: columns,
        );
      }
    }

    final selected_label = view_model.selected_index == null
        ? 'none'
        : '${view_model.selected_index! + 1}/${view_model.total_entries}';

    final scroll_label =
        switch ((view_model.has_hidden_above, view_model.has_hidden_below)) {
      (true, true) => 'more above and below',
      (true, false) => 'more above',
      (false, true) => 'more below',
      (false, false) => 'all observed entries visible',
    };

    _write_line(
      frame,
      '${view_model.observed_count} observed entries'
      '  |  Selected: $selected_label'
      '  |  $scroll_label',
      columns: columns,
      role: TerminalRole.muted,
    );

    _write_line(
      frame,
      _inspection_status(view_model),
      columns: columns,
      role:
          view_model.is_incomplete ? TerminalRole.warning : TerminalRole.muted,
    );

    _write_line(
      frame,
      view_model.is_closed
          ? 'Explorer closed.'
          : 'Up/Down Select  Enter Open  Left/Backspace Back  Q Quit',
      columns: columns,
      role: TerminalRole.muted,
    );

    // Build the complete frame before writing to the output sink.
    // This avoids emitting partially formatted frames when
    // presentation processing itself fails.
    _output.write(frame.toString());
  }

  /// Produces the appropriate entry-column header.
  ///
  /// Narrow terminals use the name-only layout.
  String _column_header(int columns) {
    if (columns < _detailed_minimum_columns) {
      return '  NAME';
    }

    final name_columns = _name_columns(columns);

    return '  '
        '${TerminalText.pad_right('NAME', min_columns: name_columns)}'
        '  ${TerminalText.pad_right('TYPE', min_columns: _type_columns)}'
        '  ${TerminalText.pad_left('SIZE', min_columns: _size_columns)}';
  }

  /// Formats one observed entry for the current terminal width.
  ///
  /// The marker remains visible even when ANSI styling is off.
  ///
  /// The supplied row contains display data only. Its path
  /// is never used to determine navigation behavior.
  String _entry_line(
    DirectoryEntryViewModel row, {
    required int columns,
    required bool is_selected,
  }) {
    final marker = is_selected ? '>' : ' ';

    if (columns < _detailed_minimum_columns) {
      final available_name_columns =
          columns > _selection_columns ? columns - _selection_columns : 0;

      final name = TerminalText.truncate(
        row.name,
        max_columns: available_name_columns,
      );

      return '$marker $name';
    }

    final name_columns = _name_columns(columns);

    final name = TerminalText.pad_right(
      TerminalText.truncate(
        row.name,
        max_columns: name_columns,
      ),
      min_columns: name_columns,
    );

    final type = TerminalText.pad_right(
      TerminalText.truncate(
        row.type_label,
        max_columns: _type_columns,
      ),
      min_columns: _type_columns,
    );

    final size = TerminalText.pad_left(
      TerminalText.truncate(
        row.size_label,
        max_columns: _size_columns,
      ),
      min_columns: _size_columns,
    );

    return '$marker $name  $type  $size';
  }

  /// Determines the available entry-name display width.
  ///
  /// The caller must have selected the detailed layout.
  int _name_columns(int columns) {
    return columns -
        _selection_columns -
        _type_columns -
        _size_columns -
        (_column_spacing * 2);
  }

  /// Formats the current inspection status.
  ///
  /// An incomplete observation is never presented as an
  /// authoritative inventory.
  ///
  /// The first available typed issue is included for context.
  /// Additional issues remain in the view model.
  ///
  /// Untrusted diagnostics are sanitized by [_write_line].
  String _inspection_status(ExplorerViewModel view_model) {
    if (view_model.is_complete) {
      return 'Read-only exploration. No filesystem changes.';
    }

    if (view_model.issues.isEmpty) {
      return 'WARNING: Directory inspection incomplete.';
    }

    final issue = view_model.issues.first;

    return 'WARNING: ${view_model.issues.length} inspection issue(s)'
        '  |  ${issue.operation}: ${issue.code}:'
        ' ${issue.path}: ${issue.message}';
  }

  /// Appends one safely formatted display line.
  ///
  /// Untrusted content is sanitized and width-limited before
  /// terminal styling introduces any trusted ANSI sequences.
  ///
  /// The line terminator is renderer-owned.
  ///
  /// No filesystem or terminal-mode operations occur.
  void _write_line(
    StringBuffer frame,
    String value, {
    required int columns,
    TerminalRole role = TerminalRole.text,
  }) {
    final safe_text = TerminalText.truncate(
      value,
      max_columns: columns,
    );

    frame.writeln(
      _ansi_text.format(
        safe_text,
        style: _theme.style_for(role),
      ),
    );
  }
}
