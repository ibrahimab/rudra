import 'package:rudra_target_contracts/rudra_target_contracts.dart';

import 'inspection_issue.dart';

/// An immutable result of a directory listing operation.
///
/// DirectoryListing represents a filesystem observation produced
/// by Rudra's SDK.
///
/// The model is independent of operating-system implementations,
/// command-line presentation, Flutter, and persistence adapters.
///
/// Each listing belongs to exactly one configured target and
/// describes the immediate children of one directory.
///
/// Entries reuse the existing platform-independent
/// [FilesystemEntry] model.
///
/// Inspection failures are represented by [InspectionIssue].
/// Successfully collected entries remain available when a
/// listing cannot be completed.
///
/// A directory listing is not an atomic filesystem snapshot.
/// Entries may change after they have been inspected.
///
/// Invariants:
/// - Every listing belongs to one identified target.
/// - The target identifier must not be blank.
/// - The requested directory is preserved without modification.
/// - Entries and issues are immutable collections.
/// - A complete listing cannot contain inspection issues.
/// - An incomplete listing must never be interpreted as an
///   authoritative inventory of the directory.
/// - Constructing a listing performs no filesystem operations.
///
/// Example:
/// ```dart
/// final listing = DirectoryListing(
///   target_id: 'local-macos',
///   directory: TargetPath('/Users/example'),
///   entries: [
///     FilesystemEntry(
///       path: TargetPath('/Users/example/Documents'),
///       kind: FilesystemEntryKind.directory,
///       metadata: FilesystemMetadata(),
///     ),
///   ],
///   is_complete: true,
/// );
///
/// print(listing.entries.length);
/// // 1
///
/// print(listing.is_complete);
/// // true
/// ```
final class DirectoryListing {
  /// Creates an immutable directory listing.
  ///
  /// [target_id] identifies the configured filesystem target
  /// from which the observations originated.
  ///
  /// [directory] identifies the directory that was inspected,
  /// using the target platform's native path syntax.
  ///
  /// [entries] contains successfully inspected immediate children.
  ///
  /// [is_complete] indicates whether enumeration and all required
  /// entry inspections completed successfully.
  ///
  /// [issues] contains typed inspection failures encountered
  /// during the operation.
  ///
  /// The supplied collections are defensively copied.
  ///
  /// Throws [ArgumentError] when:
  /// - [target_id] is blank.
  /// - [is_complete] is true while [issues] is not empty.
  ///
  /// An incomplete listing may have no issues when collection
  /// was deliberately stopped before completion.
  ///
  /// The constructor does not verify filesystem state or
  /// determine whether entries are actually direct children.
  /// Those responsibilities belong to the inspection contracts
  /// and the SDK service producing this result.
  DirectoryListing({
    required String target_id,
    required this.directory,
    required List<FilesystemEntry> entries,
    required this.is_complete,
    List<InspectionIssue> issues = const [],
  }) : target_id = _require_target_id(target_id),
       entries = List<FilesystemEntry>.unmodifiable(entries),
       issues = List<InspectionIssue>.unmodifiable(issues) {
    if (is_complete && this.issues.isNotEmpty) {
      throw ArgumentError.value(
        is_complete,
        'is_complete',
        'A listing with inspection issues cannot be complete.',
      );
    }
  }

  /// Identifier of the filesystem target that produced the listing.
  ///
  /// The identifier is scoped to the configured target registry.
  /// It must not be assumed to be globally unique across unrelated
  /// Rudra installations.
  ///
  /// All entries in the listing belong to this target.
  final String target_id;

  /// The target-native directory path that was inspected.
  ///
  /// The path retains its original spelling.
  /// It must be interpreted using the target's path semantics,
  /// not those of the frontend's operating system.
  final TargetPath directory;

  /// Successfully inspected immediate children of [directory].
  ///
  /// The collection is immutable.
  ///
  /// Entry ordering is not guaranteed unless a consuming service
  /// explicitly documents an ordering policy.
  ///
  /// Entries must not be interpreted as a complete inventory
  /// when [is_complete] is false.
  final List<FilesystemEntry> entries;

  /// Whether the directory listing completed successfully.
  ///
  /// True means directory enumeration and all required entry
  /// inspections completed without reported failures.
  ///
  /// False means the result is incomplete.
  ///
  /// An incomplete result may still contain useful observations.
  ///
  /// This flag does not guarantee that the filesystem remained
  /// unchanged during or after inspection.
  final bool is_complete;

  /// Inspection failures encountered while producing the listing.
  ///
  /// Each issue identifies an affected path, failed operation,
  /// and platform-independent error category.
  ///
  /// This collection is immutable.
  ///
  /// An empty collection does not establish completeness.
  /// Consumers must inspect [is_complete] independently.
  final List<InspectionIssue> issues;

  /// Validates the target identifier.
  ///
  /// Preserves its original spelling without normalization.
  ///
  /// Throws [ArgumentError] if [value] is blank.
  static String _require_target_id(String value) {
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
