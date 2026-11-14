import 'package:rudra_sdk/rudra_sdk.dart';

import '../../filesystem/presentation/directory_listing_presenter.dart';
import '../../filesystem/presentation/widgets/directory_listing/directory_listing_view_model.dart';
import '../../filesystem/presentation/widgets/directory_inspection_issues/directory_inspection_issues_view_model.dart';

import '../application/explorer_model.dart';
import 'explorer_view_model.dart';

import 'widgets/directory/explorer_directory_view_model.dart';
import 'widgets/footer/explorer_footer_view_model.dart';
import 'widgets/header/explorer_header_view_model.dart';

/// Builds a composable Explorer presentation from navigation state.
///
/// ExplorerModel remains the authoritative in-memory navigation
/// model for the CLI. Filesystem observations originate in the SDK.
///
/// This presenter:
/// - Prepares a header model from the current directory.
/// - Calculates the directory viewport and selection.
/// - Reuses the established filesystem metadata presenter.
/// - Prepares footer summaries and inspection diagnostics.
/// - Composes the three results into ExplorerViewModel.
///
/// Widgets do not receive ExplorerModel or the SDK services.
///
/// The presenter performs no filesystem I/O, terminal I/O,
/// navigation changes, or workflow operations.
///
/// Example:
/// ```dart
/// final presentation = const ExplorerPresenter().present(
///   explorer_model,
///   visible_row_limit: 10,
/// );
///
/// print(presentation.header.current_directory);
/// print(presentation.directory.visible_row_limit);
/// ```
final class ExplorerPresenter {
  /// Creates a stateless Explorer presenter.
  ///
  /// The filesystem presenter is injected to reuse the
  /// existing entry metadata formatting implementation.
  const ExplorerPresenter({
    DirectoryListingPresenter directory_listing_presenter =
        const DirectoryListingPresenter(),
  }) : _directory_listing_presenter = directory_listing_presenter;

  /// Shared filesystem entry metadata presenter.
  final DirectoryListingPresenter _directory_listing_presenter;

  /// Creates a complete immutable Explorer screen presentation.
  ///
  /// [visible_row_limit] specifies the number of available
  /// directory-entry rows, excluding fixed screen components.
  ///
  /// [first_visible_index] is the preferred viewport position.
  /// It is clamped to the available entry range.
  ///
  /// The selected row remains visible when at least one entry
  /// row is available.
  ///
  /// Throws [RangeError] for a negative viewport height.
  ///
  /// The source navigation model is never modified.
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

    // Preserve the navigation ordering already established
    // by ExplorerModel. This is not a new filesystem inspection.
    final ordered_listing = DirectoryListing(
      target_id: model.listing.target_id,
      directory: model.current_directory,
      entries: model.entries,
      is_complete: model.listing.is_complete,
      issues: model.listing.issues,
    );

    final listing_view_model = _directory_listing_presenter.present(
      ordered_listing,
      layout: DirectoryListingLayout.compact,
    );

    final rows = listing_view_model.listing.rows;
    final total_entries = rows.length;
    final selected_index = model.selected_index;

    final max_first_visible_index = total_entries > visible_row_limit
        ? total_entries - visible_row_limit
        : 0;

    var visible_start = first_visible_index
        .clamp(0, max_first_visible_index)
        .toInt();

    if (selected_index != null && visible_row_limit > 0) {
      if (selected_index < visible_start) {
        visible_start = selected_index;
      } else if (selected_index >= visible_start + visible_row_limit) {
        visible_start = selected_index - visible_row_limit + 1;
      }
    }

    final visible_end = (visible_start + visible_row_limit)
        .clamp(0, total_entries)
        .toInt();

    final int? selected_visible_index =
        selected_index != null &&
            selected_index >= visible_start &&
            selected_index < visible_end
        ? selected_index - visible_start
        : null;

    final directory = ExplorerDirectoryViewModel(
      total_entries: total_entries,
      visible_row_limit: visible_row_limit,
      first_visible_index: visible_start,
      selected_index: selected_index,
      selected_visible_index: selected_visible_index,
      visible_rows: rows.sublist(visible_start, visible_end),
      is_complete: listing_view_model.listing.is_complete,
    );

    final header = ExplorerHeaderViewModel(
      current_directory: model.current_directory.value,
    );

    final selected_label = directory.selected_index == null
        ? 'none'
        : '${directory.selected_index! + 1}/${directory.total_entries}';

    final scroll_label = switch ((
      directory.has_hidden_above,
      directory.has_hidden_below,
    )) {
      (true, true) => 'more above and below',
      (true, false) => 'more above',
      (false, true) => 'more below',
      (false, false) => 'all observed entries visible',
    };

    final footer = ExplorerFooterViewModel(
      summary:
          '${directory.observed_count} observed entries'
          '  |  Selected: $selected_label'
          '  |  $scroll_label',
      inspection_status: _inspection_status(
        is_complete: directory.is_complete,
        issues: listing_view_model.inspection_issues.issues,
      ),
      is_warning: directory.is_incomplete,
      navigation_hints: model.is_closed
          ? 'Explorer closed.'
          : 'Up/Down Select  Enter Open  Left/Backspace Back  Q Quit',
    );

    return ExplorerViewModel(
      header: header,
      directory: directory,
      footer: footer,
    );
  }

  /// Formats the status of an existing SDK directory observation.
  ///
  /// An incomplete observation is never described as complete.
  /// The first typed issue supplies context when available.
  ///
  /// This method does not sanitize terminal text. The shared
  /// rendering backend retains that responsibility.
  static String _inspection_status({
    required bool is_complete,
    required List<DirectoryInspectionIssueViewModel> issues,
  }) {
    if (is_complete) {
      return 'Read-only exploration. No filesystem changes.';
    }

    if (issues.isEmpty) {
      return 'WARNING: Directory inspection incomplete.';
    }

    final issue = issues.first;

    return 'WARNING: ${issues.length} inspection issue(s)'
        '  |  ${issue.operation}: ${issue.code}:'
        ' ${issue.path}: ${issue.message}';
  }
}
