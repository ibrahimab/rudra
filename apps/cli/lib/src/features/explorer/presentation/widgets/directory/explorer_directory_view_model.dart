import '../../../../filesystem/presentation/widgets/directory_listing/directory_listing_view_model.dart';

/// Immutable presentation model for ExplorerDirectory.
///
/// Contains only information needed to render the directory
/// heading, visible entries, selection, and empty-state message.
///
/// Indices refer to the presenter's entry ordering.
///
/// The model does not contain workflow state, terminal input,
/// navigation history, or footer diagnostics.
///
/// [visible_rows] is defensively copied and immutable.
///
/// Example:
/// ```dart
/// final model = ExplorerDirectoryViewModel(
///   total_entries: 0,
///   visible_row_limit: 5,
///   first_visible_index: 0,
///   selected_index: null,
///   selected_visible_index: null,
///   visible_rows: [],
///   is_complete: true,
/// );
///
/// print(model.is_empty);
/// // true
/// ```
final class ExplorerDirectoryViewModel {
  /// Creates a validated directory viewport.
  ///
  /// The visible row count must equal the number of available
  /// entries within the requested viewport.
  ///
  /// Selected indices must refer to the same entry.
  ///
  /// Throws [RangeError] for invalid dimensions or indices.
  /// Throws [ArgumentError] for inconsistent presentation data.
  ExplorerDirectoryViewModel({
    required this.total_entries,
    required this.visible_row_limit,
    required this.first_visible_index,
    required this.selected_index,
    required this.selected_visible_index,
    required List<DirectoryEntryViewModel> visible_rows,
    required this.is_complete,
  }) : visible_rows = List<DirectoryEntryViewModel>.unmodifiable(visible_rows) {
    if (total_entries < 0 ||
        visible_row_limit < 0 ||
        first_visible_index < 0 ||
        first_visible_index > total_entries) {
      throw RangeError('Invalid directory viewport dimensions.');
    }

    final remaining = total_entries - first_visible_index;
    final expected_count =
        remaining < visible_row_limit ? remaining : visible_row_limit;

    if (this.visible_rows.length != expected_count) {
      throw ArgumentError(
        'Visible entries do not match the directory viewport.',
      );
    }

    final selected = selected_index;

    if (selected != null && (selected < 0 || selected >= total_entries)) {
      throw RangeError.value(
        selected,
        'selected_index',
        'Selection must reference an observed entry.',
      );
    }

    final int? expected_visible_selection = selected != null &&
            selected >= first_visible_index &&
            selected < first_visible_index + this.visible_rows.length
        ? selected - first_visible_index
        : null;

    if (selected_visible_index != expected_visible_selection) {
      throw ArgumentError(
        'Visible selection does not match absolute selection.',
      );
    }
  }

  /// Number of successfully observed entries.
  final int total_entries;

  /// Entry rows allocated by the terminal viewport.
  final int visible_row_limit;

  /// Absolute index of the first visible entry.
  final int first_visible_index;

  /// Absolute index of the selected entry, if one exists.
  final int? selected_index;

  /// Selected entry's index within [visible_rows].
  final int? selected_visible_index;

  /// Immutable rows displayed in the current viewport.
  final List<DirectoryEntryViewModel> visible_rows;

  /// Whether the directory observation completed.
  final bool is_complete;

  /// Number of successfully observed entries.
  int get observed_count => total_entries;

  /// Whether observation was incomplete.
  bool get is_incomplete => !is_complete;

  /// Whether the directory was completely observed as empty.
  bool get is_empty => is_complete && total_entries == 0;

  /// Whether entries exist above the visible viewport.
  bool get has_hidden_above => first_visible_index > 0;

  /// Whether entries exist below the visible viewport.
  bool get has_hidden_below =>
      first_visible_index + visible_rows.length < total_entries;
}
