import '../filesystem/directory_listing_view_model.dart';

/// Immutable presentation data for one Explorer screen.
///
/// This model represents a viewport into an observed directory.
///
/// It contains:
/// - Target and navigation context.
/// - Visible filesystem entry rows.
/// - Selection and viewport positions.
/// - Inspection completeness and diagnostics.
///
/// Filesystem entry formatting is reused from the filesystem
/// feature's established presentation contracts.
///
/// All indices refer to presentation ordering rather than
/// the original SDK enumeration order.
///
/// The model does not:
/// - Access filesystem services.
/// - Resolve or construct filesystem paths.
/// - Decode terminal input.
/// - Generate terminal escape sequences.
/// - Manage persistent sessions.
/// - Authorize filesystem modifications.
///
/// Untrusted display text is not sanitized here.
/// Renderers must sanitize it before terminal output.
///
/// Example:
/// ```dart
/// final view_model = presenter.present(
///   explorer_model,
///   visible_row_limit: 10,
/// );
///
/// print(view_model.observed_count);
/// print(view_model.has_hidden_below);
/// ```
final class ExplorerViewModel {
  /// Creates a validated, immutable Explorer presentation.
  ///
  /// [target_id] identifies the inspected SDK target.
  ///
  /// [root_directory] and [current_directory] preserve
  /// their original target-native path spelling.
  ///
  /// [total_entries] counts successfully observed entries.
  /// It does not imply a complete directory inventory.
  ///
  /// [visible_row_limit] is the maximum number of filesystem
  /// rows available in the current viewport.
  ///
  /// [first_visible_index] identifies the first visible row
  /// within the complete presentation ordering.
  ///
  /// [selected_index] is the absolute presentation index
  /// of the selected entry, or null when none exists.
  ///
  /// [selected_visible_index] identifies the selection within
  /// [visible_rows], or null when it is outside the viewport.
  ///
  /// [visible_rows] and [issues] are defensively copied.
  ///
  /// Throws [ArgumentError] or [RangeError] when the supplied
  /// presentation state is inconsistent.
  ///
  /// Construction performs no filesystem or terminal I/O.
  ExplorerViewModel({
    required this.target_id,
    required this.root_directory,
    required this.current_directory,
    required this.can_go_back,
    required this.is_closed,
    required this.is_complete,
    required this.total_entries,
    required this.visible_row_limit,
    required this.first_visible_index,
    required this.selected_index,
    required this.selected_visible_index,
    required List<DirectoryEntryViewModel> visible_rows,
    required List<DirectoryInspectionIssueViewModel> issues,
  })  : visible_rows = List<DirectoryEntryViewModel>.unmodifiable(
          visible_rows,
        ),
        issues = List<DirectoryInspectionIssueViewModel>.unmodifiable(
          issues,
        ) {
    if (target_id.trim().isEmpty ||
        root_directory.isEmpty ||
        current_directory.isEmpty) {
      throw ArgumentError(
        'Explorer target and directory values must not be empty.',
      );
    }

    if (total_entries < 0 ||
        visible_row_limit < 0 ||
        first_visible_index < 0 ||
        first_visible_index > total_entries) {
      throw RangeError(
        'Invalid Explorer viewport dimensions or position.',
      );
    }

    final remaining_entries = total_entries - first_visible_index;

    final expected_visible_count = remaining_entries < visible_row_limit
        ? remaining_entries
        : visible_row_limit;

    if (this.visible_rows.length != expected_visible_count) {
      throw ArgumentError(
        'Visible rows do not match the configured viewport.',
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

    if (is_complete && this.issues.isNotEmpty) {
      throw ArgumentError(
        'A complete inspection cannot contain inspection issues.',
      );
    }
  }

  /// Identifier of the inspected filesystem target.
  final String target_id;

  /// Original target-native navigation root.
  final String root_directory;

  /// Currently displayed target-native directory.
  final String current_directory;

  /// Whether a previously visited directory is available.
  final bool can_go_back;

  /// Whether the interactive navigation model has closed.
  final bool is_closed;

  /// Whether the SDK directory observation completed.
  final bool is_complete;

  /// Number of successfully observed filesystem entries.
  final int total_entries;

  /// Maximum number of entry rows available for display.
  final int visible_row_limit;

  /// Absolute index of the first visible entry.
  final int first_visible_index;

  /// Absolute index of the selected entry, when available.
  final int? selected_index;

  /// Selected row's index inside [visible_rows], when visible.
  final int? selected_visible_index;

  /// Visible entry rows in Explorer navigation order.
  ///
  /// The collection is immutable.
  ///
  /// Rows contain display data only. Their paths must never
  /// be used by a renderer to initiate filesystem operations.
  final List<DirectoryEntryViewModel> visible_rows;

  /// Typed inspection diagnostics prepared for presentation.
  ///
  /// The collection is immutable.
  ///
  /// An incomplete inspection can legitimately have no issues.
  final List<DirectoryInspectionIssueViewModel> issues;

  /// Number of successfully observed entries.
  int get observed_count => total_entries;

  /// Whether the SDK observation is incomplete.
  bool get is_incomplete => !is_complete;

  /// Whether the directory was completely observed as empty.
  ///
  /// An incomplete observation containing zero entries is
  /// not considered an empty directory.
  bool get is_empty => is_complete && total_entries == 0;

  /// Whether some observed entries precede the viewport.
  bool get has_hidden_above => first_visible_index > 0;

  /// Whether some observed entries follow the viewport.
  bool get has_hidden_below =>
      first_visible_index + visible_rows.length < total_entries;
}
