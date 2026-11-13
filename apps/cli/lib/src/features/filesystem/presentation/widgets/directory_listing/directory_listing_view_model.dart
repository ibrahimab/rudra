import '../../../../../core/rendering/theme.dart';

import '../directory_inspection_issues/directory_inspection_issues_view_model.dart';

/// Identifies the presentation layout for a directory listing.
///
/// The layout describes the intended CLI presentation, not
/// a particular terminal rendering technology.
///
/// The compact layout preserves the established `rudra ls`
/// output contract.
///
/// The detailed layout is used by the welcome screen and
/// may be reused by other CLI presentation components.
enum DirectoryListingLayout {
  /// Compact TYPE, LOGICAL_BYTES, PATH listing.
  compact,

  /// Human-readable listing with observed metadata.
  detailed,
}

/// Immutable presentation data for one filesystem entry.
///
/// All strings are prepared by the filesystem presenter.
/// They are observations, not live filesystem metadata.
///
/// Unknown sizes and metadata remain explicitly unknown.
///
/// The [role] describes semantic styling and does not contain
/// ANSI escape sequences or rendering-backend objects.
///
/// No filesystem operations occur during construction.
final class DirectoryEntryViewModel {
  /// Creates a presentation row for an observed entry.
  ///
  /// [path] preserves the target-native path spelling.
  /// [name] is the directory-relative display name.
  ///
  /// Compact and detailed fields are kept separately because
  /// both existing CLI layouts have distinct output contracts.
  const DirectoryEntryViewModel({
    required this.path,
    required this.name,
    required this.compact_type,
    required this.type_label,
    required this.logical_bytes,
    required this.size_label,
    required this.permissions,
    required this.modified_utc,
    required this.role,
  });

  /// Full target-native path of the observed entry.
  final String path;

  /// Display name, including '/' for directories.
  final String name;

  /// Existing compact type identifier, such as `regularFile`.
  final String compact_type;

  /// Human-readable kind, such as `File` or `Directory`.
  final String type_label;

  /// Logical size in raw bytes, or '?' when unavailable.
  final String logical_bytes;

  /// Human-readable size, or an explicit unknown marker.
  final String size_label;

  /// Observed POSIX permission display, or unknown bits.
  final String permissions;

  /// Observed modification timestamp in UTC, or '?'.
  final String modified_utc;

  /// Semantic styling role for this entry kind.
  final TerminalRole role;
}

/// Immutable presentation model for a CLI directory listing.
///
/// This model is constructed by `DirectoryListingPresenter`
/// from a Rudra SDK directory observation.
///
/// It contains no filesystem adapters, services, or mutable
/// navigation state.
///
/// The model supports both existing CLI listing layouts.
///
/// An incomplete listing is explicitly marked by [is_complete].
/// Successfully inspected rows remain available even when
/// other entries could not be inspected.
///
/// The collections are defensively copied and cannot be
/// modified through this model.
///
/// Rendering implementations consume this model without
/// contacting the SDK or changing filesystem state.
///
/// Example:
/// ```dart
/// final view_model = presenter.present(
///   listing,
///   layout: DirectoryListingLayout.compact,
/// );
///
/// renderer.render(view_model);
/// ```
final class DirectoryListingViewModel {
  /// Creates an immutable filesystem listing presentation.
  ///
  /// Entry rows remain owned by the listing component.
  /// Diagnostics are represented by their dedicated
  /// [DirectoryInspectionIssuesViewModel].
  ///
  /// Both components describe the same inspection result.
  DirectoryListingViewModel({
    required this.layout,
    required this.directory_path,
    required this.target_id,
    required this.is_complete,
    required List<DirectoryEntryViewModel> rows,
    required List<DirectoryInspectionIssueViewModel> issues,
  })  : rows = List<DirectoryEntryViewModel>.unmodifiable(rows),
        inspection_issues = DirectoryInspectionIssuesViewModel(
          is_complete: is_complete,
          issues: issues,
        );

  /// Requested CLI presentation layout.
  final DirectoryListingLayout layout;

  /// Directory described by the SDK observation.
  final String directory_path;

  /// Identifier of the inspected target.
  final String target_id;

  /// Whether the underlying SDK listing completed.
  ///
  /// False means the listing cannot be treated as an
  /// authoritative inventory of the directory.
  final bool is_complete;

  /// Immutable collection of observed entry rows.
  final List<DirectoryEntryViewModel> rows;

  /// Independent presentation of inspection diagnostics.
  ///
  /// This component can be rendered separately from entry rows,
  /// including to a diagnostic output stream.
  final DirectoryInspectionIssuesViewModel inspection_issues;

  /// Number of successfully observed entries.
  int get observed_count => rows.length;

  /// Whether the SDK reported an incomplete observation.
  bool get is_incomplete => !is_complete;
}
