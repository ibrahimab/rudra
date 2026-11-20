import 'package:rudra_sdk/rudra_sdk.dart' show DirectoryListing;

import '../../../../filesystem/presentation/directory_listing_presenter.dart';
import '../../../../filesystem/presentation/widgets/directory_listing/directory_listing_view_model.dart';
import '../../../../filesystem/presentation/widgets/directory_inspection_issues/directory_inspection_issues_view_model.dart';

import '../../../application/explorer_model.dart';

/// Presentation state for the Explorer directory viewport.
///
/// Combines an existing navigation snapshot with formatted
/// filesystem observations and viewport dimensions.
///
/// Entry formatting uses [DirectoryListingPresenter], shared with
/// the filesystem feature. The selected entry remains visible
/// whenever the viewport has at least one entry row.
///
/// Example:
/// ```dart
/// final directory = ExplorerDirectoryViewModel(
///   explorer: explorer_model,
///   visible_row_limit: 12,
/// );
///
/// print(directory.visible_rows.length);
/// print(directory.first_visible_index);
/// ```
final class ExplorerDirectoryViewModel {
  /// Creates a directory viewport from the Explorer navigation state.
  ///
  /// [explorer] supplies the observed directory, ordered entries,
  /// and selected entry index.
  ///
  /// [visible_row_limit] is the number of terminal rows allocated
  /// to entries, excluding the directory heading.
  ///
  /// [first_visible_index] is the requested scroll position.
  /// It is clamped to the available entries and adjusted to keep
  /// the selected entry visible.
  ///
  /// Throws [RangeError] for a negative [visible_row_limit].
  factory ExplorerDirectoryViewModel({
    required ExplorerModel explorer,
    required int visible_row_limit,
    int first_visible_index = 0,
  }) {
    if (visible_row_limit < 0) {
      throw RangeError.value(
        visible_row_limit,
        'visible_row_limit',
        'The visible row limit cannot be negative.',
      );
    }

    // Use Explorer's established entry order rather than
    // sorting the SDK observation a second time.
    final ordered_listing = DirectoryListing(
      target_id: explorer.listing.target_id,
      directory: explorer.current_directory,
      entries: explorer.entries,
      is_complete: explorer.listing.is_complete,
      issues: explorer.listing.issues,
    );

    final presentation = const DirectoryListingPresenter().present(
      ordered_listing,
      layout: DirectoryListingLayout.compact,
    );

    final total_entries = presentation.listing.rows.length;

    final max_first_visible_index = total_entries > visible_row_limit
        ? total_entries - visible_row_limit
        : 0;

    var visible_start = first_visible_index
        .clamp(0, max_first_visible_index)
        .toInt();

    final selected_index = explorer.selected_index;

    // Scrolling follows the selected entry while preserving the
    // previous position when the selection remains visible.
    if (selected_index != null && visible_row_limit > 0) {
      if (selected_index < visible_start) {
        visible_start = selected_index;
      } else if (selected_index >= visible_start + visible_row_limit) {
        visible_start = selected_index - visible_row_limit + 1;
      }
    }

    return ExplorerDirectoryViewModel._(
      explorer: explorer,
      listing: presentation.listing,
      inspection_issues: presentation.inspection_issues,
      visible_row_limit: visible_row_limit,
      first_visible_index: visible_start,
    );
  }

  /// Constructs the validated viewport without recalculating it.
  ///
  /// [explorer] contains the navigation snapshot used for selection.
  ///
  /// [listing] contains formatted directory entries.
  ///
  /// [inspection_issues] contains the corresponding diagnostics.
  ///
  /// [visible_row_limit] is the allocated entry-row capacity.
  ///
  /// [first_visible_index] is the clamped viewport offset.
  const ExplorerDirectoryViewModel._({
    required this.explorer,
    required this.listing,
    required this.inspection_issues,
    required this.visible_row_limit,
    required this.first_visible_index,
  });

  /// Explorer navigation snapshot associated with this viewport.
  final ExplorerModel explorer;

  /// Formatted, immutable directory listing.
  final DirectoryListingViewModel listing;

  /// Inspection diagnostics associated with [listing].
  final DirectoryInspectionIssuesViewModel inspection_issues;

  /// Number of rows allocated to visible directory entries.
  final int visible_row_limit;

  /// Absolute index of the first displayed entry.
  final int first_visible_index;

  /// Total number of successfully observed entries.
  int get total_entries => listing.rows.length;

  /// Absolute index of the selected entry, if any.
  int? get selected_index => explorer.selected_index;

  /// Index immediately after the visible entry range.
  int get visible_end =>
      (first_visible_index + visible_row_limit).clamp(0, total_entries).toInt();

  /// Immutable entries within the current viewport.
  List<DirectoryEntryViewModel> get visible_rows =>
      List<DirectoryEntryViewModel>.unmodifiable(
        listing.rows.sublist(first_visible_index, visible_end),
      );

  /// Selected entry's index within the visible viewport.
  ///
  /// Returns null when no selected entry is visible.
  int? get selected_visible_index {
    final selected = selected_index;

    if (selected == null ||
        selected < first_visible_index ||
        selected >= visible_end) {
      return null;
    }

    return selected - first_visible_index;
  }

  /// Number of successfully observed entries.
  int get observed_count => total_entries;

  /// Whether the SDK directory observation completed.
  bool get is_complete => listing.is_complete;

  /// Whether the observation is incomplete.
  bool get is_incomplete => !is_complete;

  /// Whether the directory was completely observed as empty.
  bool get is_empty => is_complete && total_entries == 0;

  /// Whether entries exist before the visible viewport.
  bool get has_hidden_above => first_visible_index > 0;

  /// Whether entries exist beyond the visible viewport.
  bool get has_hidden_below => visible_end < total_entries;
}
