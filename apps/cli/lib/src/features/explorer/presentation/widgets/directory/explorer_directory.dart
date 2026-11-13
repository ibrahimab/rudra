import '../../../../../core/rendering/terminal_text.dart';
import '../../../../../core/rendering/theme.dart';
import '../../../../../core/rendering/widgets/terminal_widget.dart';

import '../../../../filesystem/directory_listing_view_model.dart';

import 'explorer_directory_view_model.dart';

/// Renders the Explorer's scrollable directory entry viewport.
///
/// The widget receives an already prepared [ExplorerViewModel].
///
/// It owns:
/// - Directory column headings.
/// - Display-column-aware entry formatting.
/// - Selection markers and semantic roles.
/// - Empty and incomplete directory placeholders.
/// - Blank rows preserving stable footer placement.
///
/// The widget does not:
/// - Read filesystem entries or construct paths.
/// - Sort or select entries.
/// - Calculate navigation viewport offsets.
/// - Write terminal output.
/// - Interpret keyboard input.
///
/// The output height equals one heading row plus the number
/// of entry rows allocated by the presenter.
///
/// Example:
/// ```dart
/// final directory = ExplorerDirectory(view_model);
///
/// print(directory.height);
/// // 1 + view_model.visible_row_limit
/// ```
final class ExplorerDirectory implements TerminalWidget {
  /// Creates a directory widget from its dedicated viewport model.
  const ExplorerDirectory(this.view_model);

  /// Directory-specific presentation data.
  final ExplorerDirectoryViewModel view_model;

  /// Fixed heading rows preceding the scrollable entries.
  static const int heading_rows = 1;

  /// Selection marker and following space.
  static const int _selection_columns = 2;

  /// Width of the filesystem entry type column.
  static const int _type_columns = 9;

  /// Width of the human-readable size column.
  static const int _size_columns = 9;

  /// Spaces between detailed entry columns.
  static const int _column_spacing = 2;

  /// Minimum width allocated to detailed entry names.
  static const int _minimum_name_columns = 8;

  /// Minimum terminal width permitting detailed columns.
  static const int _detailed_minimum_columns = _selection_columns +
      _type_columns +
      _size_columns +
      (_column_spacing * 2) +
      _minimum_name_columns;

  @override
  int get height => heading_rows + view_model.visible_row_limit;

  @override
  Iterable<TerminalLine> build(
    TerminalConstraints constraints,
  ) sync* {
    final columns = constraints.columns;

    yield TerminalLine(
      _column_header(columns),
      role: TerminalRole.heading,
    );

    for (var index = 0; index < view_model.visible_row_limit; index++) {
      if (index < view_model.visible_rows.length) {
        final row = view_model.visible_rows[index];

        final is_selected = view_model.selected_visible_index == index;

        yield TerminalLine(
          _entry_line(
            row,
            columns: columns,
            is_selected: is_selected,
          ),
          role: is_selected ? TerminalRole.selected : row.role,
        );
      } else if (index == 0 && view_model.total_entries == 0) {
        yield TerminalLine(
          view_model.is_empty
              ? '  (empty directory)'
              : '  (no entries observed; inspection incomplete)',
          role: TerminalRole.muted,
        );
      } else {
        yield const TerminalLine('');
      }
    }
  }

  /// Formats the entry-column heading for the terminal width.
  ///
  /// Narrow terminals display names only.
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

  /// Formats an observed entry without altering its identity.
  ///
  /// The output is plain presentation text. Sanitization,
  /// final truncation, and ANSI styling are performed by
  /// the shared terminal rendering backend.
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

  /// Computes the available detailed entry-name columns.
  ///
  /// Called only when the detailed layout is supported.
  int _name_columns(int columns) {
    return columns -
        _selection_columns -
        _type_columns -
        _size_columns -
        (_column_spacing * 2);
  }
}
