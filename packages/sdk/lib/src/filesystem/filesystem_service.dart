import 'package:rudra_target_contracts/rudra_target_contracts.dart';

import 'directory_listing.dart';
import 'inspection_issue.dart';

/// Provides platform-independent filesystem inspection operations.
///
/// FilesystemService is an application-level SDK service.
///
/// It coordinates filesystem observations through an injected
/// [TargetInspector] without depending on its implementation.
///
/// The service does not depend on CLI frameworks, Flutter,
/// native filesystem APIs, or persistence implementations.
///
/// Each instance operates against one configured filesystem
/// target, identified by [target_id].
///
/// All operations are read-only.
///
/// The service does not:
/// - Modify or delete filesystem entries.
/// - Decide whether filesystem entries are safe to remove.
/// - Follow symbolic links implicitly.
/// - Create or manage inspection sessions.
/// - Interpret paths using the frontend host's platform.
/// - Infer unavailable metadata.
/// - Treat incomplete observations as complete.
///
/// Example:
/// ```dart
/// final service = FilesystemService(
///   target_id: 'local-macos',
///   inspector: target_inspector,
/// );
///
/// final listing = await service.list(
///   directory: TargetPath('/Users/example'),
/// );
///
/// if (listing.is_complete) {
///   print('Directory inspection completed.');
/// }
///
/// for (final entry in listing.entries) {
///   print(entry.path.value);
/// }
/// ```
final class FilesystemService {
  /// Creates a filesystem service for one configured target.
  ///
  /// [target_id] identifies the target within the application's
  /// configured target registry.
  ///
  /// [inspector] implements the platform-independent filesystem
  /// inspection contract for that target.
  ///
  /// The caller must ensure that [target_id] identifies the same
  /// target environment represented by [inspector].
  ///
  /// Throws [ArgumentError] when [target_id] is blank.
  ///
  /// Construction does not inspect or modify filesystem content.
  FilesystemService({
    required String target_id,
    required TargetInspector inspector,
  })  : target_id = _validate_target_id(target_id),
        _inspector = inspector;

  /// Identifies the filesystem target served by this instance.
  ///
  /// The identifier is preserved without normalization.
  ///
  /// It is scoped to the application's configured targets and
  /// must not be assumed globally unique.
  final String target_id;

  /// Platform-independent filesystem inspection adapter.
  ///
  /// The concrete implementation is supplied by the application
  /// composition boundary.
  ///
  /// SDK services must not instantiate native adapters directly.
  final TargetInspector _inspector;

  /// Lists and inspects the immediate children of [directory].
  ///
  /// The directory must be expressed as an absolute path using
  /// the target platform's native filesystem syntax.
  ///
  /// Relative path resolution belongs to a separate, explicitly
  /// defined target-aware operation or application input boundary.
  ///
  /// Enumeration is performed through
  /// [TargetInspector.list_directory].
  ///
  /// Every discovered child is inspected through
  /// [TargetInspector.inspect].
  ///
  /// The resulting [DirectoryListing] contains:
  /// - The configured target identifier.
  /// - The originally requested directory.
  /// - Successfully inspected filesystem entries.
  /// - Typed inspection issues.
  /// - An explicit completion indicator.
  ///
  /// A failure while inspecting an individual child does not
  /// discard previously collected entries or prevent attempts
  /// to inspect subsequent children.
  ///
  /// A directory-enumeration failure terminates enumeration.
  /// Successfully collected entries are preserved, and the
  /// result is marked incomplete.
  ///
  /// The listing is complete only when enumeration and every
  /// required child inspection succeed without reported issues.
  ///
  /// Inspection failures represented by
  /// [TargetInspectionException] are converted into
  /// [InspectionIssue] response data.
  ///
  /// Unexpected exceptions are propagated rather than silently
  /// classified as filesystem failures.
  ///
  /// Entry ordering follows the target inspector's enumeration
  /// order and is not guaranteed to be sorted.
  ///
  /// The entire listing is collected in memory before returning.
  /// Streaming SDK results and cancellation of large listings
  /// will require separate API contracts.
  ///
  /// Filesystem observations are not atomic snapshots.
  /// Entries may change while the listing is being produced.
  ///
  /// This operation is strictly read-only and never authorizes
  /// cleanup or deletion.
  ///
  /// Example:
  /// ```dart
  /// final listing = await service.list(
  ///   directory: TargetPath('/Users/example/Downloads'),
  /// );
  ///
  /// for (final entry in listing.entries) {
  ///   print(entry.path.value);
  /// }
  ///
  /// for (final issue in listing.issues) {
  ///   print(issue.code);
  /// }
  ///
  /// if (!listing.is_complete) {
  ///   print('The directory listing is incomplete.');
  /// }
  /// ```
  Future<DirectoryListing> list({
    required TargetPath directory,
  }) async {
    final entries = <FilesystemEntry>[];
    final issues = <InspectionIssue>[];

    try {
      // Enumerate only immediate children. Recursive traversal
      // is a separate SDK responsibility.
      await for (final child_path in _inspector.list_directory(
        directory,
      )) {
        try {
          // Inspect each child without implicitly following its
          // final symbolic-link component.
          final entry = await _inspector.inspect(child_path);

          entries.add(entry);
        } on TargetInspectionException catch (error) {
          // Preserve the typed failure and continue inspecting
          // remaining directory entries.
          //
          // A failed entry must never be represented using
          // fabricated metadata or silently omitted.
          issues.add(
            InspectionIssue.from_target_exception(error),
          );
        }
      }
    } on TargetInspectionException catch (error) {
      // Enumeration failed or could not begin.
      //
      // Previously inspected entries remain useful observations,
      // but the directory inventory is now incomplete.
      issues.add(
        InspectionIssue.from_target_exception(error),
      );
    }

    // Completion depends on successful enumeration and inspection.
    // Any captured issue makes the result incomplete.
    return DirectoryListing(
      target_id: target_id,
      directory: directory,
      entries: entries,
      is_complete: issues.isEmpty,
      issues: issues,
    );
  }

  /// Validates a configured target identifier.
  ///
  /// The identifier must contain at least one non-whitespace
  /// character.
  ///
  /// The original spelling is preserved.
  ///
  /// Throws [ArgumentError] when [value] is blank.
  static String _validate_target_id(String value) {
    if (value.trim().isEmpty) {
      throw ArgumentError.value(
        value,
        'target_id',
        'The target identifier must not be blank.',
      );
    }

    return value;
  }
}
