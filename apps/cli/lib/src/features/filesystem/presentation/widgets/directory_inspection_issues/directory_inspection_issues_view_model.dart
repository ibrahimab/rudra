/// Immutable presentation of one typed filesystem inspection issue.
///
/// These values originate from SDK inspection diagnostics.
/// They are display data, not authoritative filesystem identity.
///
/// The rendering backend must sanitize all text before output.
///
/// Example:
/// ```dart
/// const issue = DirectoryInspectionIssueViewModel(
///   operation: 'inspect',
///   code: 'permissionDenied',
///   path: '/workspace/private',
///   message: 'Permission denied.',
/// );
/// ```
final class DirectoryInspectionIssueViewModel {
  /// Creates one prepared inspection diagnostic.
  const DirectoryInspectionIssueViewModel({
    required this.operation,
    required this.code,
    required this.path,
    required this.message,
  });

  /// Inspection operation that failed.
  final String operation;

  /// Typed inspection error classification.
  final String code;

  /// Target-native path associated with the failure.
  final String path;

  /// Human-readable diagnostic information.
  final String message;
}

/// Immutable presentation model for the inspection-issues widget.
///
/// This component owns only inspection completeness and
/// display-ready diagnostic information.
///
/// It does not contain directory entries, listing layout,
/// target configuration, or navigation state.
///
/// An incomplete inspection without specific issues remains
/// explicitly incomplete, allowing the widget to display a
/// fallback diagnostic.
///
/// The issues collection is defensively copied.
///
/// Example:
/// ```dart
/// final model = DirectoryInspectionIssuesViewModel(
///   is_complete: false,
///   issues: const [],
/// );
///
/// print(model.is_incomplete);
/// // true
/// ```
final class DirectoryInspectionIssuesViewModel {
  /// Creates an immutable diagnostics presentation.
  ///
  /// A complete inspection cannot contain inspection failures.
  ///
  /// Throws [ArgumentError] for inconsistent completeness
  /// and diagnostic information.
  DirectoryInspectionIssuesViewModel({
    required this.is_complete,
    required List<DirectoryInspectionIssueViewModel> issues,
  }) : issues = List<DirectoryInspectionIssueViewModel>.unmodifiable(issues) {
    if (is_complete && this.issues.isNotEmpty) {
      throw ArgumentError(
        'A complete inspection cannot contain inspection issues.',
      );
    }
  }

  /// Whether the underlying directory inspection completed.
  final bool is_complete;

  /// Immutable collection of prepared inspection diagnostics.
  final List<DirectoryInspectionIssueViewModel> issues;

  /// Whether the inspection result is incomplete.
  bool get is_incomplete => !is_complete;
}
