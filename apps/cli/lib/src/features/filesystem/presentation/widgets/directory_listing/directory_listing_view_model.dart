import '../../../../../core/rendering/theme.dart';

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

/// Immutable presentation data for one observed directory listing.
///
/// This component owns directory-entry presentation only:
/// - The requested compact or detailed layout.
/// - The observed target and directory identifiers.
/// - Inspection completeness.
/// - Immutable, display-ready entry rows.
///
/// It does not own inspection diagnostics. Those are represented
/// independently by DirectoryInspectionIssuesViewModel.
///
/// DirectoryListingPresenter creates this component as part of
/// FilesystemViewModel, which associates both components with
/// the same SDK directory observation.
///
/// A directory with no rows is not necessarily empty.
/// Callers must also inspect [is_complete] before interpreting
/// the result as a complete directory inventory.
///
/// Entry rows are defensively copied. Construction performs
/// no filesystem operations or terminal I/O.
///
/// Example:
/// ```dart
/// final listing = DirectoryListingViewModel(
///   layout: DirectoryListingLayout.compact,
///   directory_path: '/workspace',
///   target_id: 'local-macos',
///   is_complete: true,
///   rows: [],
/// );
///
/// print(listing.observed_count);
/// // 0
/// ```
final class DirectoryListingViewModel {
  /// Creates an immutable directory listing presentation.
  ///
  /// The listing owns observed entry rows and their display
  /// layout, but not inspection diagnostic collections.
  ///
  /// A failed or incomplete observation remains explicitly
  /// identified by [is_complete].
  ///
  /// Entry rows are defensively copied.
  DirectoryListingViewModel({
    required this.layout,
    required this.directory_path,
    required this.target_id,
    required this.is_complete,
    required List<DirectoryEntryViewModel> rows,
  }) : rows = List<DirectoryEntryViewModel>.unmodifiable(rows);

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

  /// Number of successfully observed entries.
  int get observed_count => rows.length;

  /// Whether the SDK reported an incomplete observation.
  bool get is_incomplete => !is_complete;
}
