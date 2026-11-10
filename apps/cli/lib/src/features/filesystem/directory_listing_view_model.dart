import '../../core/rendering/theme.dart';

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

/// Immutable presentation data for one inspection issue.
///
/// These fields originate from typed SDK inspection issues.
///
/// The view model preserves the error classification, operation,
/// target-native path, and diagnostic text without interpreting
/// native exceptions.
///
/// A renderer must sanitize the fields before terminal output.
final class DirectoryInspectionIssueViewModel {
  /// Creates a display-ready inspection diagnostic.
  const DirectoryInspectionIssueViewModel({
    required this.operation,
    required this.code,
    required this.path,
    required this.message,
  });

  /// Name of the failed inspection operation.
  final String operation;

  /// Name of the typed inspection error category.
  final String code;

  /// Target-native path associated with the issue.
  final String path;

  /// Human-readable diagnostic information.
  final String message;
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
  /// Creates an immutable directory listing presentation.
  ///
  /// [directory_path] retains the observed target-native path.
  /// [target_id] identifies the inspected SDK target.
  ///
  /// [rows] contains display-ready entry values.
  /// [issues] contains display-ready inspection diagnostics.
  ///
  /// The supplied lists are copied before being stored.
  ///
  /// Construction performs no filesystem or terminal I/O.
  DirectoryListingViewModel({
    required this.layout,
    required this.directory_path,
    required this.target_id,
    required this.is_complete,
    required List<DirectoryEntryViewModel> rows,
    required List<DirectoryInspectionIssueViewModel> issues,
  })  : rows = List<DirectoryEntryViewModel>.unmodifiable(rows),
        issues = List<DirectoryInspectionIssueViewModel>.unmodifiable(
          issues,
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

  /// Immutable collection of inspection diagnostics.
  final List<DirectoryInspectionIssueViewModel> issues;

  /// Number of successfully observed entries.
  int get observed_count => rows.length;

  /// Whether the SDK reported an incomplete observation.
  bool get is_incomplete => !is_complete;
}
