import 'package:rudra_sdk/rudra_sdk.dart';

import '../filesystem/directory_listing_presenter.dart';
import '../filesystem/directory_listing_view_model.dart';

import 'explorer_model.dart';
import 'explorer_view_model.dart';

/// Converts Explorer navigation state into presentation data.
///
/// The presenter owns viewport calculations and translates
/// existing navigation state into immutable display data.
///
/// Filesystem metadata formatting is delegated to the
/// established [DirectoryListingPresenter].
///
/// The ordering established by [ExplorerModel] is preserved.
/// Consequently, navigation indices correspond exactly to
/// the rows prepared for rendering.
///
/// The presenter does not:
/// - Request new filesystem observations.
/// - Resolve or construct filesystem paths.
/// - Modify Explorer navigation state.
/// - Decode keyboard input.
/// - Write to terminal output.
/// - Manage persistent sessions or cleanup plans.
///
/// Example:
/// ```dart
/// const presenter = ExplorerPresenter();
///
/// final view_model = presenter.present(
///   model,
///   visible_row_limit: 15,
/// );
///
/// print(view_model.selected_visible_index);
/// ```
final class ExplorerPresenter {
  /// Creates a stateless Explorer presenter.
  ///
  /// [directory_listing_presenter] supplies the existing
  /// filesystem metadata presentation implementation.
  ///
  /// The default presenter can be replaced for composition
  /// without changing Explorer navigation behavior.
  ///
  /// Construction performs no filesystem or terminal I/O.
  const ExplorerPresenter({
    DirectoryListingPresenter directory_listing_presenter =
        const DirectoryListingPresenter(),
  }) : _directory_listing_presenter = directory_listing_presenter;

  /// Shared filesystem metadata presentation dependency.
  final DirectoryListingPresenter _directory_listing_presenter;

  /// Prepares an Explorer screen for the requested viewport.
  ///
  /// [model] contains an existing SDK directory observation,
  /// navigation history, and selection position.
  ///
  /// [visible_row_limit] is the number of terminal rows
  /// available for filesystem entries, excluding headers,
  /// diagnostics, and navigation instructions.
  ///
  /// Zero is permitted for terminals too small to display
  /// any entry rows.
  ///
  /// [first_visible_index] is the preferred viewport offset.
  /// It is clamped to the available entry range.
  ///
  /// The viewport is adjusted when necessary to keep the
  /// selected entry visible, provided at least one row fits.
  ///
  /// The returned view model retains:
  /// - The original target and directory.
  /// - Explorer ordering and selection.
  /// - Successfully inspected entry metadata.
  /// - Inspection completeness and typed issues.
  ///
  /// Throws [RangeError] for a negative [visible_row_limit].
  ///
  /// Does not mutate [model] or perform filesystem I/O.
  ExplorerViewModel present(
    ExplorerModel model, {
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

    // ExplorerModel already owns the navigation ordering.
    //
    // Build an in-memory presentation projection using that
    // ordering rather than changing the original SDK listing.
    //
    // This is not a new filesystem observation.
    final ordered_listing = DirectoryListing(
      target_id: model.listing.target_id,
      directory: model.current_directory,
      entries: model.entries,
      is_complete: model.listing.is_complete,
      issues: model.listing.issues,
    );

    // The compact presentation mode preserves supplied order.
    //
    // It still prepares all entry metadata fields, allowing
    // Explorer to reuse the established filesystem formatting
    // without implementing another metadata formatter.
    final listing_view_model = _directory_listing_presenter.present(
      ordered_listing,
      layout: DirectoryListingLayout.compact,
    );

    final rows = listing_view_model.rows;
    final total_entries = rows.length;
    final selected_index = model.selected_index;

    // The last possible viewport start must leave as many
    // visible rows as the available entry count permits.
    final max_first_visible_index = total_entries > visible_row_limit
        ? total_entries - visible_row_limit
        : 0;

    var visible_start =
        first_visible_index.clamp(0, max_first_visible_index).toInt();

    if (selected_index != null && visible_row_limit > 0) {
      if (selected_index < visible_start) {
        visible_start = selected_index;
      } else if (selected_index >= visible_start + visible_row_limit) {
        visible_start = selected_index - visible_row_limit + 1;
      }
    }

    final visible_end =
        (visible_start + visible_row_limit).clamp(0, total_entries).toInt();

    final visible_rows = rows.sublist(
      visible_start,
      visible_end,
    );

    final int? selected_visible_index = selected_index != null &&
            selected_index >= visible_start &&
            selected_index < visible_end
        ? selected_index - visible_start
        : null;

    return ExplorerViewModel(
      target_id: listing_view_model.target_id,
      root_directory: model.root_directory.value,
      current_directory: model.current_directory.value,
      can_go_back: model.can_go_back,
      is_closed: model.is_closed,
      is_complete: listing_view_model.is_complete,
      total_entries: total_entries,
      visible_row_limit: visible_row_limit,
      first_visible_index: visible_start,
      selected_index: selected_index,
      selected_visible_index: selected_visible_index,
      visible_rows: visible_rows,
      issues: listing_view_model.issues,
    );
  }
}
