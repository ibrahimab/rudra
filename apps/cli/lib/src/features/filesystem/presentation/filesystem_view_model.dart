import 'widgets/directory_inspection_issues/directory_inspection_issues_view_model.dart';
import 'widgets/directory_listing/directory_listing_view_model.dart';

/// Immutable composition of a filesystem listing and its diagnostics.
///
/// This model represents one already observed SDK directory
/// listing prepared for CLI presentation.
///
/// Each component retains independent responsibility:
/// - DirectoryListingViewModel describes observed entries.
/// - DirectoryInspectionIssuesViewModel describes failures.
///
/// The two components must agree on inspection completeness.
///
/// A renderer may present them independently, for example
/// sending directory rows to stdout and diagnostics to stderr.
///
/// No SDK services, filesystem operations, or terminal I/O
/// are performed here.
///
/// Example:
/// ```dart
/// final model = FilesystemViewModel(
///   listing: listing_view_model,
///   inspection_issues: issues_view_model,
/// );
///
/// renderer.render(model);
/// ```
final class FilesystemViewModel {
  /// Creates a validated filesystem presentation composition.
  ///
  /// Throws [ArgumentError] when the two components disagree
  /// about whether the observation completed successfully.
  FilesystemViewModel({
    required this.listing,
    required this.inspection_issues,
  }) {
    if (listing.is_complete != inspection_issues.is_complete) {
      throw ArgumentError(
        'Filesystem presentation components disagree '
        'about inspection completeness.',
      );
    }
  }

  /// Directory entry and metadata presentation.
  final DirectoryListingViewModel listing;

  /// Typed inspection diagnostic presentation.
  final DirectoryInspectionIssuesViewModel inspection_issues;
}
