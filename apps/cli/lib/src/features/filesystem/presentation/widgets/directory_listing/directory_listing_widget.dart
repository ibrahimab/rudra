import '../../../../../core/rendering/terminal_text.dart';
import '../../../../../core/rendering/theme.dart';
import '../../../../../core/rendering/widgets/terminal_widget.dart';

import 'directory_listing_view_model.dart';

/// Composable terminal presentation of a filesystem directory.
///
/// This widget renders an existing [DirectoryListingViewModel]
/// without querying the filesystem or mutating domain state.
///
/// The widget supports:
/// - Compact output for command-oriented listings.
/// - Detailed output with observed filesystem metadata.
/// - Dynamic column widths derived from display content.
/// - Explicit warnings for incomplete directory observations.
///
/// The owning presenter determines entry ordering and formats
/// metadata. This widget performs only layout operations.
///
/// It does not perform:
/// - SDK calls or native filesystem operations.
/// - Path normalization or symbolic-link resolution.
/// - Terminal I/O or ANSI encoding.
/// - Cleanup selection or authorization.
///
/// The widget can be embedded in any [TerminalWidget] composition.
///
/// Its row count is deterministic and independent of the terminal
/// width. Bounded backends truncate lines rather than wrap them.
/// Unbounded backends retain the complete sanitized content.
///
/// Example:
/// ```dart
/// final listing_widget = DirectoryListingWidget(
///   filesystem_view_model.listing,
/// );
///
/// final screen = TerminalColumn(
///   children: [
///     const TerminalLabel('Filesystem'),
///     listing_widget,
///   ],
/// );
/// ```
final class DirectoryListingWidget implements TerminalWidget {
  /// Creates a directory-listing widget from prepared data.
  const DirectoryListingWidget(this.view_model);

  /// Directory data and desired presentation layout.
  final DirectoryListingViewModel view_model;

  /// Number of fixed rows in the compact listing.
  static const int _compact_heading_rows = 1;

  /// Detailed listing heading and separator rows.
  static const int _detailed_heading_rows = 2;

  /// Detailed listing spacer and observation summary rows.
  static const int _detailed_summary_rows = 2;

  /// Detailed entry type column width.
  static const int _type_columns = 9;

  /// Detailed entry size column width.
  static const int _size_columns = 9;

  /// Detailed permission column width.
  static const int _permission_columns = 11;

  /// Visual separator width for the modification column.
  static const int _modified_columns = 16;

  /// Spacing between displayed columns.
  static const String _spacing = '  ';

  @override
  int get height {
    return switch (view_model.layout) {
      DirectoryListingLayout.compact =>
        _compact_heading_rows + view_model.rows.length,
      DirectoryListingLayout.detailed =>
        _detailed_heading_rows +
            view_model.rows.length +
            _detailed_summary_rows +
            (view_model.is_incomplete ? 1 : 0),
    };
  }

  /// Builds the selected directory-listing presentation.
  ///
  /// [constraints] determines whether the consuming backend
  /// imposes a terminal width. The shared backend applies
  /// final sanitization and truncation to each line.
  ///
  /// The widget itself never writes to an output stream.
  @override
  Iterable<TerminalLine> build(TerminalConstraints constraints) {
    return switch (view_model.layout) {
      DirectoryListingLayout.compact => _compact_lines(),
      DirectoryListingLayout.detailed => _detailed_lines(),
    };
  }

  /// Builds the compact TYPE, LOGICAL_BYTES, PATH layout.
  ///
  /// Original paths remain visible in full when the rendering
  /// backend uses unbounded output.
  ///
  /// Column widths account for Unicode display width rather
  /// than Dart string length.
  Iterable<TerminalLine> _compact_lines() sync* {
    const type_header = 'TYPE';
    const size_header = 'LOGICAL_BYTES';
    const path_header = 'PATH';

    final type_width = view_model.rows.fold<int>(type_header.length, (
      width,
      row,
    ) {
      final value_width = TerminalText.estimated_columns(row.compact_type);

      return value_width > width ? value_width : width;
    });

    final size_width = view_model.rows.fold<int>(size_header.length, (
      width,
      row,
    ) {
      final value_width = TerminalText.estimated_columns(row.logical_bytes);

      return value_width > width ? value_width : width;
    });

    yield TerminalLine(
      '${TerminalText.pad_right(type_header, min_columns: type_width)}'
      '$_spacing'
      '${TerminalText.pad_left(size_header, min_columns: size_width)}'
      '$_spacing'
      '$path_header',
    );

    for (final row in view_model.rows) {
      yield TerminalLine(
        '${TerminalText.pad_right(row.compact_type, min_columns: type_width)}'
        '$_spacing'
        '${TerminalText.pad_left(row.logical_bytes, min_columns: size_width)}'
        '$_spacing'
        '${row.path}',
      );
    }
  }

  /// Builds the human-readable detailed listing.
  ///
  /// The listing includes a heading, separator, observed entries,
  /// spacer, observation summary, and optional warning.
  ///
  /// Unknown metadata remains explicitly unknown.
  ///
  /// Only the backend introduces styling or output control.
  Iterable<TerminalLine> _detailed_lines() sync* {
    const name_header = 'NAME';
    const type_header = 'TYPE';
    const size_header = 'SIZE';
    const permission_header = 'PERMISSIONS';
    const modified_header = 'MODIFIED (UTC)';

    final name_width = view_model.rows.fold<int>(name_header.length, (
      width,
      row,
    ) {
      final value_width = TerminalText.estimated_columns(row.name);

      return value_width > width ? value_width : width;
    });

    yield TerminalLine(
      '  ${TerminalText.pad_right(name_header, min_columns: name_width)}'
      '$_spacing'
      '${TerminalText.pad_right(type_header, min_columns: _type_columns)}'
      '$_spacing'
      '${TerminalText.pad_left(size_header, min_columns: _size_columns)}'
      '$_spacing'
      '${TerminalText.pad_right(permission_header, min_columns: _permission_columns)}'
      '$_spacing'
      '$modified_header',
      role: TerminalRole.heading,
    );

    yield TerminalLine(
      '  ${''.padRight(name_width, '─')}'
      '$_spacing'
      '${''.padRight(_type_columns, '─')}'
      '$_spacing'
      '${''.padRight(_size_columns, '─')}'
      '$_spacing'
      '${''.padRight(_permission_columns, '─')}'
      '$_spacing'
      '${''.padRight(_modified_columns, '─')}',
      role: TerminalRole.muted,
    );

    for (final row in view_model.rows) {
      yield TerminalLine(
        '  ${TerminalText.pad_right(row.name, min_columns: name_width)}'
        '$_spacing'
        '${TerminalText.pad_right(row.type_label, min_columns: _type_columns)}'
        '$_spacing'
        '${TerminalText.pad_left(row.size_label, min_columns: _size_columns)}'
        '$_spacing'
        '${TerminalText.pad_right(row.permissions, min_columns: _permission_columns)}'
        '$_spacing'
        '${row.modified_utc}',
        role: row.role,
      );
    }

    yield const TerminalLine('');

    yield TerminalLine(
      '  ${view_model.observed_count} observed entries'
      ' · immediate children only',
      role: TerminalRole.muted,
    );

    if (view_model.is_incomplete) {
      yield const TerminalLine(
        '  WARNING: This directory listing is incomplete.',
        role: TerminalRole.warning,
      );
    }
  }
}
